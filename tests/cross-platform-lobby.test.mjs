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
const passwordInput = fs.readFileSync(
  new URL('../src/components/PasswordInput/PasswordInput.tsx', import.meta.url),
  'utf8'
);
const passwordPolicy = fs.readFileSync(
  new URL('../src/utils/passwordInputPolicy.ts', import.meta.url),
  'utf8'
);
const passwordCss = fs.readFileSync(
  new URL('../src/components/PasswordInput/PasswordInput.css', import.meta.url),
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
const androidSignaling = fs.readFileSync(
  new URL(
    '../MCTier-Android/app/src/main/java/top/pmh13/mctier/network/SignalingClient.kt',
    import.meta.url
  ),
  'utf8'
);
const appSource = fs.readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8');
const macInfoPlist = fs.readFileSync(new URL('../src-tauri/Info.plist', import.meta.url), 'utf8');

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
  assert.match(connectBlock, /isSafeChatToken\(message\.chatToken\)/);
  assert.match(connectBlock, /message\.chatTokenEpoch > 0/);
  assert.match(connectBlock, /const messageProcessing = this\.websocketMessageQueue\.then/);
  assert.match(connectBlock, /this\.chatToken === message\.chatToken/);
  assert.match(connectBlock, /信令服务器协议过旧，缺少大厅认证信息/);
  assert.match(connectBlock, /message\.type === 'register-error'/);
  assert.match(connectBlock, /rejectRegistration\(\s*new SignalingRegistrationError/);

  const openHandler =
    connectBlock.match(/this\.websocket\.onopen = \(\) => \{([\s\S]*?)\n\s*\};/)?.[1] ?? '';
  assert.doesNotMatch(
    openHandler,
    /\bresolve\s*\(/,
    'WebSocket open must not resolve before register-success'
  );
});

test('transient signaling failures preserve the virtual LAN and retry membership sync', () => {
  assert.match(appSource, /error instanceof SignalingRegistrationError/);
  assert.match(appSource, /setWebRtcRetryTick/);
  assert.match(appSource, /虚拟局域网仍在运行，正在自动恢复大厅成员同步/);

  const transientBranch = appSource.slice(
    appSource.indexOf('if (!(error instanceof SignalingRegistrationError))'),
    appSource.indexOf('// 后端 EasyTier 加入成功并不代表信令大厅注册成功')
  );
  assert.doesNotMatch(transientBranch, /leave_lobby|clearLobby|setAppState\('idle'\)/);
});

test('lobby success is announced only after signaling registration and initial metadata is retained', () => {
  const preRegistrationSuccess = lobbyForm.slice(
    lobbyForm.indexOf('setLobby({ ...lobby, serverNode, signalingServer })'),
    lobbyForm.indexOf(
      '} catch (error) {',
      lobbyForm.indexOf('setLobby({ ...lobby, serverNode, signalingServer })')
    )
  );

  assert.doesNotMatch(preRegistrationSuccess, /message\.success/);
  assert.match(appSource, /大厅连接成功/);
  assert.match(desktopRtc, /this\.pendingLobbyMeta = lobbyMeta/);
  assert.match(desktopRtc, /if \(this\.pendingLobbyMeta\)/);
});

test('Android normalizes shared credentials and rolls back a rejected registration', () => {
  assert.match(androidRepository, /val safeLobbyName = lobbyName\.trim\(\)/);
  assert.match(androidRepository, /val safePassword = password\.trim\(\)/);
  assert.match(androidRepository, /"register-error" ->/);
  assert.match(androidRepository, /leaveLobby\(\)/);
  assert.match(androidRepository, /state = AppConnectionState\.Error/);
});

test('Android publishes its lobby state before signaling can deliver the initial roster', () => {
  const joinBlock = androidRepository.slice(
    androidRepository.indexOf('fun createOrJoinLobby('),
    androidRepository.indexOf('fun leaveLobby()')
  );
  const inLobbyIndex = joinBlock.indexOf('state = AppConnectionState.InLobby');
  const connectIndex = joinBlock.indexOf('signalingClient.connect(');

  assert.ok(inLobbyIndex >= 0, 'join flow must publish InLobby state');
  assert.ok(connectIndex >= 0, 'join flow must open signaling');
  assert.ok(
    inLobbyIndex < connectIndex,
    'players-list must not be overwritten by a post-connect self-only roster'
  );
});

test('Android buffers initial signaling events until its single roster consumer is ready', () => {
  assert.match(androidSignaling, /Channel<SignalingEnvelope>/);
  assert.match(androidSignaling, /receiveAsFlow\(\)/);
  assert.doesNotMatch(androidSignaling, /MutableSharedFlow<SignalingEnvelope>/);
});

test('Android surfaces an initial signaling connection failure instead of showing a silent solo lobby', () => {
  assert.match(androidSignaling, /connectionFailureChannel/);
  assert.match(androidSignaling, /reportedFailureGeneration != generation/);
  assert.match(androidRepository, /signalingClient\.connectionFailures\.collect/);
  assert.match(androidRepository, /信令服务器连接失败/);
  assert.match(androidRepository, /reconnecting = true/);
});

test('macOS permits runtime private WebSocket signaling without disabling native ATS', () => {
  assert.match(macInfoPlist, /<key>NSAppTransportSecurity<\/key>/);
  assert.match(macInfoPlist, /<key>NSAllowsArbitraryLoadsInWebContent<\/key>\s*<true\/>/);
  assert.doesNotMatch(macInfoPlist, /<key>NSAllowsArbitraryLoads<\/key>/);
  assert.doesNotMatch(macInfoPlist, /floatawa\.top/);
});

test('tokenless legacy signaling cannot masquerade as a successful lobby join', () => {
  assert.match(androidRepository, /registeredId != _state.value.playerId/);
  assert.match(androidRepository, /sessionGeneration == null \|\| sessionGeneration <= 0L/);
  assert.match(androidRepository, /!isValidChatToken\(token\) \|\| epoch <= 0L/);

  const connectBlock = desktopRtc.slice(
    desktopRtc.indexOf('private async connectToSignalingServer()'),
    desktopRtc.indexOf('private sendRegistration()')
  );
  const validationIndex = connectBlock.indexOf('isSafeChatToken(message.chatToken)');
  const processingIndex = connectBlock.indexOf('const messageProcessing');
  const acceptIndex = connectBlock.lastIndexOf('acceptRegistration()');

  assert.ok(validationIndex >= 0, 'desktop must validate the lobby token');
  assert.ok(
    processingIndex > validationIndex,
    'legacy registration must be rejected before queuing'
  );
  assert.ok(
    acceptIndex > processingIndex,
    'registration succeeds only after authenticated processing'
  );
});

test('EasyTier IP parsing ignores unrelated private addresses from peer logs', () => {
  assert.match(networkService, /if is_virtual_ip_line && !is_excluded/);
  assert.match(networkService, /Self::is_mctier_virtual_ip\(&ip\)/);
});

test('macOS password editing avoids a native secure-field focus transition', () => {
  assert.match(lobbyForm, /<PasswordInput/);
  assert.match(passwordPolicy, /isMacUserAgent\(userAgent\)/);
  assert.match(passwordInput, /type="text"/);
  assert.match(passwordInput, /data-mctier-masked="true"/);
  assert.match(passwordCss, /-webkit-text-security: disc/);
});

test('frameless windows use the native Tauri drag API', () => {
  assert.match(windowDrag, /getCurrentWindow\(\)\s*\.startDragging\(\)/);
  assert.match(lobbyForm, /onMouseDown={startWindowDrag}/);
});
