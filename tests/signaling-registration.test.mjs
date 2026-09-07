import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import ts from 'typescript';

function compile(path) {
  return ts.transpileModule(fs.readFileSync(new URL(path, import.meta.url), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
}
const source = compile('../src/services/webrtc/WebRTCClient.ts');
const boundary = compile('../src/security/trustBoundary.ts');
const identity = 'a'.repeat(64);
const token = 'b'.repeat(64);
const tick = () => new Promise((resolve) => setImmediate(resolve));

function harness() {
  const timers = new Map();
  let timerId = 0;
  let socket;
  class Socket {
    static OPEN = 1;
    readyState = 1;
    constructor() { socket = this; }
    close() { this.readyState = 3; this.onclose?.(); }
    message(message) { this.onmessage({ data: JSON.stringify(message) }); }
  }
  const boundaryExports = {};
  vm.runInNewContext(boundary, { exports: boundaryExports, URL });
  const exports = {};
  const timerApi = {
    setTimeout(callback, ms) { const id = ++timerId; timers.set(id, { callback, ms }); return id; },
    clearTimeout(id) { timers.delete(id); },
  };
  vm.runInNewContext(source, {
    exports,
    require(path) {
      if (path.endsWith('trustBoundary')) return boundaryExports;
      if (path.endsWith('signalingIdentity')) {
        return { isServerChallenge: (value) => /^[a-f0-9]{64}$/.test(value) };
      }
      if (path.endsWith('i18n')) return { tl: (zh) => zh };
      return {};
    },
    console: { log() {}, warn() {}, error() {} },
    WebSocket: Socket,
    window: timerApi,
    ...timerApi,
  });
  const client = new exports.WebRTCClient();
  client.localPlayerId = identity;
  client.startWebSocketHeartbeat = () => {};
  client.stopWebSocketHeartbeat = () => {};
  client.resetRemoteControlOnSignalingDisconnect = () => {};
  client.sendV3Registration = async () => {};
  client.handleWebSocketMessage = async (message) => {
    if (message.type === 'register-success') {
      client.chatToken = message.chatToken;
      client.chatTokenEpoch = message.chatTokenEpoch;
      client.serverSessionGeneration = String(message.sessionGeneration);
    }
  };
  const result = client.connectToSignalingServer();
  return { client, result, socket, timers, RegistrationError: exports.SignalingRegistrationError };
}

async function challenge(h) {
  h.socket.onopen();
  h.socket.message({ type: 'server-challenge', protocolVersion: 3, challenge: 'c'.repeat(64) });
  await tick();
}

function registration(overrides = {}) {
  return {
    type: 'register-success', clientId: identity, lobbyId: 'test-lobby',
    sessionGeneration: 7, chatToken: token, chatTokenEpoch: 1, ...overrides,
  };
}

test('v3 challenge and proof submission do not finish joining before authenticated registration', async () => {
  const h = harness();
  let settled = false;
  h.result.then(() => { settled = true; });
  await challenge(h);
  assert.equal(settled, false);
  h.socket.message(registration());
  await h.result;
  assert.equal(settled, true);
  await h.client.websocketMessageQueue;
  assert.equal(h.client.queuedWebSocketFrames, 0);
  h.client.isIntentionalDisconnect = true;
  h.socket.close();
  assert.equal(h.timers.size, 0);
});

for (const [name, message] of [
  ['wrong identity', registration({ clientId: 'd'.repeat(64) })],
  ['missing session generation', registration({ sessionGeneration: null })],
  ['legacy tokenless response', registration({ chatToken: undefined })],
  ['wrong lobby password', { type: 'register-error', message: 'wrong password' }],
]) {
  test(`registration rejects ${name} without scheduling automatic reconnect`, async () => {
    const h = harness();
    const rejected = assert.rejects(h.result, h.RegistrationError);
    await challenge(h);
    h.socket.message(message);
    await rejected;
    assert.equal(h.client.reconnectTimeout, null);
    assert.equal(h.client.queuedWebSocketFrames, 0);
  });
}

test('registration timeout covers a server that sends a challenge but never confirms the lobby', async () => {
  const h = harness();
  const rejected = assert.rejects(h.result, /15 秒/);
  await challenge(h);
  [...h.timers.values()].find(({ ms }) => ms === 15_000).callback();
  await rejected;
  assert.equal(h.socket.readyState, 3);
  assert.equal(h.timers.size, 0);
});
