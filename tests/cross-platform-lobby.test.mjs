import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const desktopRtc = fs.readFileSync(
  new URL('../src/services/webrtc/WebRTCClient.ts', import.meta.url),
  'utf8'
);
const lobbyForm = fs.readFileSync(
  new URL('../src/components/LobbyForm/LobbyForm.tsx', import.meta.url),
  'utf8'
);
const lobbyCss = fs.readFileSync(
  new URL('../src/components/LobbyForm/LobbyForm.css', import.meta.url),
  'utf8'
);
const windowDrag = fs.readFileSync(new URL('../src/utils/windowDrag.ts', import.meta.url), 'utf8');
const networkService = fs.readFileSync(
  new URL('../src-tauri/src/modules/network_service.rs', import.meta.url),
  'utf8'
);
const androidRepository = fs.readFileSync(
  new URL(
    '../MCTier-Android/app/src/main/java/top/pmh13/mctier/MctierRepository.kt',
    import.meta.url
  ),
  'utf8'
);

test('lobby members are identified by player ID instead of a transient virtual IP', () => {
  assert.doesNotMatch(desktopRtc, /player\.virtualIp === this\.virtualIp/);
  assert.doesNotMatch(desktopRtc, /message\.virtualIp === this\.virtualIp/);
  assert.doesNotMatch(androidRepository, /player\.virtualIp != selfIp/);
  assert.doesNotMatch(androidRepository, /message\.virtualIp == selfIp/);
});

test('desktop waits for an authoritative signaling registration result', () => {
  const connectBlock = desktopRtc.slice(
    desktopRtc.indexOf('private async connectToSignalingServer()'),
    desktopRtc.indexOf('private sendRegistration()')
  );

  assert.match(connectBlock, /message\.type === 'register-success'/);
  assert.match(connectBlock, /acceptRegistration\(\)/);
  assert.match(connectBlock, /message\.type === 'register-error'/);
  assert.match(connectBlock, /rejectRegistration\(new SignalingRegistrationError/);
});

test('Android normalizes shared credentials and rolls back a rejected registration', () => {
  assert.match(androidRepository, /val normalizedLobbyName = lobbyName\.trim\(\)/);
  assert.match(androidRepository, /val normalizedPassword = password\.trim\(\)/);
  assert.match(androidRepository, /"register-error" ->/);
  assert.match(androidRepository, /leaveLobby\(\)/);
  assert.match(androidRepository, /state = AppConnectionState\.Error/);
});

test('EasyTier IP parsing ignores unrelated private addresses from peer logs', () => {
  assert.match(networkService, /if is_virtual_ip_line && !is_excluded/);
});

test('macOS password editing avoids a native secure-field focus transition', () => {
  assert.match(lobbyForm, /className={`lobby-password-native/);
  assert.match(lobbyForm, /type="text"/);
  assert.match(lobbyCss, /-webkit-text-security: disc/);
  assert.match(lobbyCss, /html\[data-theme='light'\] \.lobby-password-native/);
  assert.match(lobbyCss, /-webkit-text-fill-color: #18202b !important/);
});

test('frameless windows use the native Tauri drag API', () => {
  assert.match(windowDrag, /getCurrentWindow\(\)\s*\.startDragging\(\)/);
  assert.match(lobbyForm, /onMouseDown={startWindowDrag}/);
});
