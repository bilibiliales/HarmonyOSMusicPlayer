// Run with Node. Execute production ArkTS services with mocked HarmonyOS boundaries.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function load(file, mocks = {}) {
  const exports = {};
  const code = fs.readFileSync(path.join(__dirname, '../main/ets', file), 'utf8');
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText, { exports, setTimeout, clearTimeout, console: { info() {}, error() {} },
    require: name => { assert.ok(name in mocks, name); return mocks[name]; } });
  return exports;
}
const music = load('models/music.ets');
const file = { br: 999000, sr: 96000, size: 20000000 };
let detail, calls = [], resolveUrl;
const api = { cookie: 'MUSIC_U=fake; __csrf=fake; os=android', get: async (endpoint, params) => {
  const args = Object.fromEntries(params.map(p => [p.key, p.value]));
  calls.push({ endpoint, args });
  assert.equal(args.id, '1');
  assert.ok(args.timestamp);
  assert.match(args.cookie, /MUSIC_U=fake/);
  assert.equal((args.cookie.match(/os=/g) || []).length, 1);
  assert.match(args.cookie, /os=pc/);
  if (endpoint === '/song/music/detail') return detail;
  assert.ok(['/song/url/v1', '/song/download/url/v1'].includes(endpoint));
  const value = resolveUrl(args.level);
  return { code: 200, data: endpoint === '/song/url/v1' ? [value] : value };
} };
const { SongQualityService: quality } = load('services/SongQualityService.ets', {
  '../models/music': music, './ApiClient': { ApiClient: api }
});
const { AudioFileFormat: format } = load('services/AudioFileFormat.ets');
const requests = [];
class HttpRequest {
  events = {}; destroyed = false;
  on(event, callback) { this.events[event] = callback; }
  emit(event, value) { this.events[event]?.(value); }
  requestInStream(url, options) {
    this.url = url;
    assert.equal(options.header['Accept-Encoding'], 'identity');
    return new Promise((resolve, reject) => { this.resolve = resolve; this.reject = reject; });
  }
  destroy() { this.destroyed = true; }
  chunk(values) { this.emit('dataReceive', Uint8Array.from(values).buffer); }
  complete(code = 200) { this.emit('dataEnd'); this.resolve(code); }
}
const memory = load('services/MemoryAudioSource.ets', {
  '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET' }, createHttp: () => {
    const client = new HttpRequest(); requests.push(client); return client;
  } } }
});
const flush = () => new Promise(resolve => setImmediate(resolve));
function fullResource(level, extra = {}) {
  return { id: 1, url: 'https://audio.invalid/track.flac', size: 8, level, type: 'flac', ...extra };
}

async function qualityTests() {
  detail = { code: 200, data: { songId: 1, l: file, h: file, sq: file, hr: file, jm: file, je: { size: 0 } } };
  resolveUrl = level => fullResource(level);
  const options = await quality.available('1');
  assert.deepEqual(Array.from(options, q => q.level), ['standard', 'exhigh', 'lossless', 'hires', 'jymaster']);
  assert.match(options[0].description, /96 kHz/);
  calls = [];
  let resource = await quality.playback('1', 'hires');
  assert.equal(resource.selectedLevel, 'hires'); assert.equal(resource.actualLevel, 'hires');
  assert.deepEqual(calls.map(c => c.endpoint), ['/song/music/detail', '/song/url/v1']);
  assert.equal(calls[1].args.level, 'hires');
  calls = [];
  delete detail.data.hr;
  resource = await quality.playback('1', 'hires');
  assert.equal(resource.requestedLevel, 'hires'); assert.equal(resource.selectedLevel, 'lossless');
  assert.equal(calls[1].args.level, 'lossless');
  assert.deepEqual(Array.from(quality.candidates('higher', options)), ['standard'], 'never upgrade to exhigh');
  calls = [];
  resolveUrl = level => fullResource(level, { url: level === 'lossless' ? '' : 'https://audio.invalid/a.mp3' });
  resource = await quality.playback('1', 'hires');
  assert.deepEqual(calls.slice(1).map(c => c.args.level), ['lossless', 'exhigh']);
  assert.equal(resource.actualLevel, 'exhigh');
  resolveUrl = () => fullResource('standard');
  resource = await quality.playback('1', 'jymaster');
  assert.equal(resource.selectedLevel, 'jymaster'); assert.equal(resource.actualLevel, 'standard');
  resolveUrl = () => fullResource(undefined);
  assert.equal((await quality.playback('1', 'jymaster')).actualLevel, '', 'unknown actual quality stays unknown');
  resolveUrl = () => fullResource('exhigh', { id: 999 });
  await assert.rejects(() => quality.playback('1', 'exhigh'), /不匹配/);
  detail = { code: 500 }; calls = [];
  await assert.rejects(() => quality.playback('1', 'hires'));
  assert.equal(calls.length, 1, 'failed inspection must not invent an available quality');
  detail = { code: 200, data: { songId: 999, l: file } };
  await assert.rejects(() => quality.available('1'), /不匹配/);
  detail = { code: 200, data: { songId: 1, hr: file } }; calls = [];
  await assert.rejects(() => quality.playback('1', 'standard'));
  assert.equal(calls.length, 1);
  detail.data.l = file; detail.data.sq = file;
  resolveUrl = level => fullResource(level, { type: 'mp3', encodeType: 'flac' }); calls = [];
  resource = await quality.download('1', 'hires');
  assert.deepEqual(calls.map(c => c.endpoint), ['/song/music/detail', '/song/download/url/v1']);
  assert.equal(calls[1].args.level, 'hires'); assert.equal(resource.actualLevel, 'hires');
  resolveUrl = level => fullResource(level, { freeTrialInfo: level === 'hires' ? { start: 0, end: 30 } : null });
  resource = await quality.download('1', 'hires'); assert.equal(resource.actualLevel, 'lossless');
  resolveUrl = level => fullResource(level, { freeTrialInfo: {} });
  await assert.rejects(() => quality.download('1', 'hires'), /完整/);
  assert.equal(api.cookie, 'MUSIC_U=fake; __csrf=fake; os=android', 'existing login cookie is unchanged');
}

function formatTests() {
  assert.equal(format.extension('https://a/track.mp3', 'mp3', '', Buffer.from('fLaC')), 'flac');
  assert.equal(format.extension('https://a/track.FLAC?token=1#x', 'mp3', '', new Uint8Array([1, 2])), 'flac');
  assert.equal(format.extension('https://a/stream', '', 'flac', new Uint8Array([1, 2])), 'flac');
  assert.equal(format.extension('https://a/track.flac', 'flac', '', Buffer.from('ID3')), 'mp3');
  assert.equal(format.extension('https://a/stream', '', '', new Uint8Array([0xff, 0xfb])), 'mp3');
  assert.equal(format.extension('https://a/stream', '', '', new Uint8Array([0xff, 0xf1])), 'aac');
  assert.equal(format.extension('https://a/stream', '', '', Buffer.from('RIFFxxxxWAVE')), 'wav');
  assert.equal(format.extension('https://a/track.m4a', '', '', Buffer.from('xxxxftypM4A ')), 'm4a');
  assert.throws(() => format.extension('https://a/file.mp3', 'mp3', '', Buffer.from('<html>')), /有效/);
  assert.throws(() => format.extension('https://a/stream', '', '', new Uint8Array([1, 2])), /识别/);
}

async function memoryTests() {
  const source = new memory.MemoryAudioSource([new Uint8Array([1, 2, 3]), new Uint8Array([4, 5]), new Uint8Array([6, 7, 8])]);
  const target = new ArrayBuffer(4);
  assert.equal(source.descriptor().fileSize, 8);
  assert.equal(source.read(target, 4, 2), 4); assert.deepEqual(Array.from(new Uint8Array(target)), [3, 4, 5, 6]);
  assert.equal(source.read(target, 4), 2); assert.deepEqual(Array.from(new Uint8Array(target).slice(0, 2)), [7, 8]);
  assert.equal(source.read(target, 4), -1);
  assert.equal(source.read(target, 999, 0), 4); assert.deepEqual(Array.from(new Uint8Array(target)), [1, 2, 3, 4]);
  assert.equal(source.read(target, 4, -1), -2);
  assert.equal(source.read(target, 4, NaN), -2);
  let loader = new memory.MemoryAudioLoad();
  let pending = loader.load('https://audio.invalid/a.flac', 8);
  let client = requests.at(-1), finished = false;
  pending.then(() => { finished = true; });
  client.resolve(200); client.chunk([1, 2, 3]); await flush();
  assert.equal(finished, false, 'do not play a partial file even when HTTP status is available');
  client.chunk([4, 5, 6, 7, 8]); client.emit('dataEnd');
  assert.equal((await pending).size, 8); assert.equal(client.destroyed, true);
  loader = new memory.MemoryAudioLoad(); pending = loader.load('https://audio.invalid/a.mp3', 3);
  client = requests.at(-1); client.chunk([1, 2, 3]); client.emit('dataEnd'); await flush();
  assert.equal(client.destroyed, false, 'wait for HTTP status even if dataEnd arrives first');
  client.resolve(200); assert.equal((await pending).size, 3);
  loader = new memory.MemoryAudioLoad(); pending = loader.load('https://audio.invalid/a.flac', 8);
  client = requests.at(-1); client.chunk([1, 2]); client.complete();
  await assert.rejects(pending, /完整/); assert.equal(client.destroyed, true);
  loader = new memory.MemoryAudioLoad(); pending = loader.load('https://audio.invalid/a.flac');
  client = requests.at(-1); client.emit('dataReceiveProgress', { totalSize: 10 }); client.chunk([1]); client.complete();
  await assert.rejects(pending, /完整/);
  loader = new memory.MemoryAudioLoad(); pending = loader.load('https://audio.invalid/a.mp3');
  client = requests.at(-1); client.resolve(403);
  await assert.rejects(pending, /403/); assert.equal(client.destroyed, true);
  loader = new memory.MemoryAudioLoad(); pending = loader.load('https://audio.invalid/a.flac');
  client = requests.at(-1); client.chunk([1, 2, 3]); loader.cancel();
  await assert.rejects(pending, /取消/); assert.equal(client.destroyed, true);
  client.complete(); // Late completion cannot resurrect a cancelled load.
  const before = requests.length; await assert.rejects(() => loader.load('https://audio.invalid/again'), /取消/);
  assert.equal(requests.length, before);
}

async function playerTests() {
  const players = [];
  class FakePlayer {
    state = 'idle'; events = {}; duration = 180000; currentTime = 0; assignmentCount = 0;
    on(event, handler) { this.events[event] = handler; }
    transition(state) { this.state = state; this.events.stateChange?.(state); }
    set url(value) { assert.fail('audio must use the complete memory source'); }
    set dataSrc(source) { this.source = source; this.assignmentCount++; this.transition('initialized'); }
    async prepare() { this.transition('prepared'); }
    async play() { this.transition('playing'); }
    async pause() { this.transition('paused'); }
    seek(position) { this.currentTime = position; }
    async release() { this.source = undefined; this.transition('released'); }
  }
  const settings = { backgroundPlaybackEnabled: false, savePlayerState: async () => {} };
  let resourceResolver = async (id, level) => ({ url: `https://audio.invalid/${id}.flac`, requestedLevel: level,
    selectedLevel: level, actualLevel: 'hires', size: 8, type: 'flac', trial: false });
  const { PlayerController } = load('services/PlayerController.ets', {
    '@kit.MediaKit': { media: { createAVPlayer: async () => { const player = new FakePlayer(); players.push(player); return player; } } },
    '@kit.AVSessionKit': { avSession: { PlaybackState: {} } }, '../models/music': music,
    './AppSettings': { AppSettings: settings },
    './LiveViewController': { LiveViewController: { sync() {}, stop: async () => {} } },
    './PlaybackControlBridge': { PlaybackControlBridge: { unsubscribe() {} } },
    './ListeningScrobble': { ListeningScrobble: class { reset() {} setTrial() {} update() {} discontinuity() {} } },
    './SongQualityService': { SongQualityService: { playback: (...args) => resourceResolver(...args) } },
    './MemoryAudioSource': memory
  });
  const store = { queue: [{ id: '1', name: 'one' }, { id: '2', name: 'two' }], currentSong: {}, currentIndex: 0,
    quality: 'hires', position: 0, selectAt(index) { this.currentIndex = index; this.currentSong = this.queue[index]; } };
  const controller = new PlayerController(); controller.bind(store);
  let first = controller.playAt(0); await flush();
  const firstRequest = requests.at(-1), firstPlayer = players.at(-1);
  firstRequest.chunk([1, 2]); assert.equal(firstPlayer.assignmentCount, 0);
  let second = controller.playAt(1); await flush();
  const secondRequest = requests.at(-1), secondPlayer = players.at(-1);
  assert.equal(firstRequest.destroyed, true);
  firstRequest.complete(); await first; assert.equal(firstPlayer.assignmentCount, 0);
  secondRequest.chunk([1, 2, 3, 4, 5, 6, 7, 8]); secondRequest.complete(); await second; await flush();
  assert.equal(secondPlayer.assignmentCount, 1); assert.equal(secondPlayer.state, 'playing');
  assert.equal(store.actualQuality, 'hires'); assert.equal(store.currentSong.id, '2');
  const buffer = new ArrayBuffer(8); assert.equal(secondPlayer.source.callback(buffer, 8, 0), 8);
  assert.deepEqual(Array.from(new Uint8Array(buffer)), [1, 2, 3, 4, 5, 6, 7, 8]);
  controller.onAppBackground(); await flush(); assert.equal(secondPlayer.state, 'paused');
  assert.equal(secondPlayer.source.callback(buffer, 8, 0), 8, 'foreground-only pause retains the full source for resume');
  controller.onAppForeground(); store.position = 60000; store.isPlaying = true;
  let change = controller.changeQuality('lossless'); await flush();
  const changedRequest = requests.at(-1), changedPlayer = players.at(-1);
  changedRequest.chunk([1, 2, 3, 4, 5, 6, 7, 8]); changedRequest.complete(); await change; await flush();
  assert.equal(changedPlayer.currentTime, 60000, 'quality switch preserves position');
  store.actualQuality = 'standard'; // Server previously downgraded the selected lossless level.
  const retry = controller.changeQuality('lossless'); await flush();
  const retryRequest = requests.at(-1);
  assert.notEqual(retryRequest, changedRequest, 'selecting a downgraded preference again must retry v1');
  retryRequest.chunk([1, 2, 3, 4, 5, 6, 7, 8]); retryRequest.complete(); await retry; await flush();
  let backgroundLoad = controller.playAt(0); await flush();
  const backgroundRequest = requests.at(-1), backgroundPlayer = players.at(-1);
  controller.onAppBackground(); await backgroundLoad;
  assert.equal(backgroundRequest.destroyed, true); assert.equal(backgroundPlayer.assignmentCount, 0);
  controller.onAppForeground();
  let pendingResolve;
  resourceResolver = () => new Promise(resolve => { pendingResolve = resolve; });
  const old = controller.playAt(1); await flush();
  const count = requests.length; await controller.release();
  pendingResolve({ url: 'https://audio.invalid/late.flac', size: 8 }); await old;
  assert.equal(requests.length, count, 'late quality/URL response after release must not load audio');
}

(async () => {
  await qualityTests(); formatTests(); await memoryTests(); await playerTests();
  console.log('PASS: quality discovery/fallback, v1 endpoints, original formats, complete memory loading, cancellation and player lifecycle');
})().catch(error => { console.error(error); process.exitCode = 1; });
