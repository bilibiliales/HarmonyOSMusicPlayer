// Run with node; optional first argument is the installed SDK TypeScript module path.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function load(name, mocks) {
  const source = fs.readFileSync(path.join(__dirname, '../main/ets/services', name + '.ets'), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, Error, console: { info() {}, error() {} }, setTimeout, clearTimeout,
    require(name) { assert.ok(name in mocks, name); return mocks[name]; } });
  return exports;
}
const tick = () => new Promise(resolve => setImmediate(resolve));
async function playback() {
  let sessions = 0, destroyed = 0, players = 0, releases = 0, pauses = 0;
  const settings = { backgroundPlaybackEnabled: false, savePlayerState: async () => {},
    saveBackgroundPlayback: async (_ctx, enabled) => { settings.backgroundPlaybackEnabled = enabled; } };
  const session = { on() {}, activate: async () => {}, setBackgroundPlayMode: async () => {},
    setAVMetadata: async () => {}, setAVPlaybackState: async () => {}, destroy: async () => { destroyed++; } };
  const player = { state: 'playing', on() {}, pause: async () => { pauses++; player.state = 'paused'; },
    release: async () => { releases++; }, currentTime: 1234 };
  const { PlayerController } = load('PlayerController', {
    '@kit.AVSessionKit': { avSession: { createAVSession: async () => { sessions++; return session; },
      PlaybackState: {}, LoopMode: {}, BackgroundPlayMode: {} } },
    '@kit.MediaKit': { media: { createAVPlayer: async () => { players++; return player; } } },
    '../models/music': { PlayMode: {} }, './ApiClient': { ApiClient: {} }, './AppSettings': { AppSettings: settings },
    './LiveViewController': { LiveViewController: { sync() {}, refresh: async () => {}, stop: async () => {} } },
    './PlaybackControlBridge': { PlaybackControlBridge: { subscribe: async () => {}, unsubscribe() {} } }
    , './ListeningScrobble': load('ListeningScrobble', { './ApiClient': { ApiClient: { cookie: '' } } })
  });
  const store = { queue: [{ id: '1' }], currentSong: { id: '1' }, position: 1234, quality: 'hires', isPlaying: true };
  const c = new PlayerController(); c.bind(store, { getHostContext: () => ({}) });
  await tick(); assert.equal(sessions, 0);
  await c.ensurePlayer(); assert.equal(players, 1); assert.equal(sessions, 0);
  await c.setBackgroundPlayback({}, true); assert.equal(sessions, 1);
  await c.setBackgroundPlayback({}, false); assert.equal(destroyed, 1);
  assert.equal(releases, 0); assert.equal(store.quality, 'hires'); assert.equal(store.position, 1234);
  assert.equal(await c.ensureSystemSession(), undefined); assert.equal(sessions, 1);
  c.shouldAutoPlay = true; c.onAppBackground(); await tick();
  assert.equal(pauses, 1); assert.equal(c.shouldAutoPlay, false);
  player.state = 'playing'; c.sourceSongId = '1';
  c.handleStateChange(player, c.playerGeneration, 'playing'); await tick();
  assert.equal(pauses, 2, 'Late playing event must pause while background playback is off');
  c.onAppForeground(); assert.equal(player.state, 'paused');
  await c.release(); assert.equal(releases, 1);
}
async function sharing() {
  let calls = 0, receivedOptions, receivedData, fail = true, unblock;
  const host = { startAbility: () => { throw new Error('Sharing must not use startAbility'); } };
  let showPanel = async () => { if (fail) throw { code: 16000019, message: 'launch failed' }; };
  class ShareController {
    constructor(data) { receivedData = data; }
    async show(context, options) {
      assert.equal(context, host);
      calls++;
      receivedOptions = options;
      await showPanel();
    }
  }
  const { SystemShareService: s } = load('SystemShareService', {
    '@kit.ShareKit': { systemShare: { SharedData: class { constructor(record) { this.records = [record]; } addRecord(r) { this.records.push(r); } },
      ShareController,
      getWant: () => { throw new Error('Sharing must use ShareController.show'); },
      SelectionMode: { SINGLE: 0, BATCH: 1 }, SharePreviewMode: { DEFAULT: 0, DETAIL: 1 } }, harmonyShare: {} },
    '@kit.ArkData': { uniformTypeDescriptor: { UniformDataType: { HYPERLINK: 'general.hyperlink' } } },
    // Reproduce platforms where encoding an empty optional description returns undefined.
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(value) { return value ? Buffer.from(value) : undefined; } } } },
    '@kit.NetworkKit': { http: {} }, '@kit.ImageKit': { image: {} }, './ImageUrl': {}
  });
  s.bindAbility(host);
  for (const value of ['', 'ASCII', '分享歌手', 'é', '🎵', 'A中🎵', '\ud800', '\udc00', '\ud800x']) {
    assert.equal(s.utf8ByteLength(value), Buffer.byteLength(value, 'utf8'));
  }
  const artist = await s.linkRecords({ url: 'https://music.163.com/artist?id=1', title: '歌手',
    label: '歌手', description: '', image: 'unavailable' });
  assert.equal(artist[0].utd, 'general.hyperlink');
  assert.equal(Object.hasOwn(artist[0], 'thumbnail'), false);
  assert.doesNotThrow(() => s.validate(artist));
  const overhead = 64 + Buffer.byteLength('general.hyperlink') + 4;
  assert.doesNotThrow(() => s.validate([{ utd: 'general.hyperlink', content: 'a'.repeat(s.MAX_BYTES - overhead) }]));
  assert.throws(() => s.validate([{ utd: 'general.hyperlink', content: 'a'.repeat(s.MAX_BYTES - overhead + 1) }]), /200KB/);
  const wrongContext = { startAbility: () => { throw new Error('Must use EntryAbility context'); } };
  const records = [{ utd: 'general.hyperlink', content: 'https://example.test' }];
  await assert.rejects(s.show(wrongContext, records), /16000019.*launch failed/);
  fail = false; await s.show(wrongContext, records); assert.equal(calls, 2);
  assert.equal(receivedOptions.previewMode, 0); assert.equal(receivedOptions.selectionMode, 0);
  assert.equal(receivedData.records[0].content, records[0].content);
  await s.show(wrongContext, [{ utd: 'general.jpeg', uri: 'file://a' }, { utd: 'general.jpeg', uri: 'file://b' }]);
  assert.equal(receivedOptions.selectionMode, 1);
  assert.equal(receivedOptions.previewMode, 1);
  assert.equal(receivedData.records.length, 2);
  assert.throws(() => s.validate(Array(501).fill(records[0])), /500/);
  assert.throws(() => s.validate([{ ...records[0], content: '中'.repeat(70000) }]), /200KB/);
  showPanel = () => new Promise(resolve => { unblock = resolve; });
  const first = s.show(wrongContext, records); await tick(); const before = calls;
  await s.show(wrongContext, records); assert.equal(calls, before);
  unblock(); await first; assert.equal(s.launching, false);
  // Suppress repeated link actions during preparation, not only during panel launch.
  const prepare = s.linkRecords;
  let finishPreparing, preparations = 0;
  s.linkRecords = () => { preparations++; return new Promise(resolve => { finishPreparing = resolve; }); };
  showPanel = async () => {};
  const linkRequest = s.showLink(wrongContext, {});
  await s.showLink(wrongContext, {}); assert.equal(preparations, 1);
  finishPreparing(records); await linkRequest; assert.equal(s.launching, false);
  s.linkRecords = async () => { throw new Error('prepare failed'); };
  await assert.rejects(s.showLink(wrongContext, {}), /prepare failed/);
  assert.equal(s.launching, false);
  s.linkRecords = prepare;
}
(async () => { await playback(); await sharing(); console.log('PASS: AVPlayer-only mode, AVSession switching, background race, share context, retry and limits'); })()
  .catch(error => { console.error(error); process.exitCode = 1; });
