const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.join(__dirname, '../main/ets');
function load(file, mocks = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, require: name => mocks[name] || {} });
  return exports;
}
const calls = [];
let response;
const client = { cookie: 'logged-in-user', get: async (url, params) => {
  calls.push({ url, params: Object.fromEntries((params || []).map(p => [p.key, p.value])) });
  return response || { code: 200 };
} };
const { ListeningScrobble } = load('services/ListeningScrobble.ets', { './ApiClient': { ApiClient: client } });
const api = load('models/api.ets');
const { RecentPlaybackService } = load('services/RecentPlaybackService.ets', {
  './ApiClient': { ApiClient: client }, '../models/api': api
});
const { DiscoveryPlaylistsService } = load('services/DiscoveryPlaylistsService.ets', {
  './ApiClient': { ApiClient: client }, '../models/api': api
});
const song = { id: '123', albumId: '456', duration: 60000, name: 'Song' };
function listen(tracker, end = 60000) {
  for (let time = 0; time <= end; time += 250) tracker.update(time, true, time + 10000);
}
(async () => {
  const tracker = new ListeningScrobble();
  tracker.reset(); listen(tracker);
  assert.equal(calls.length, 0, 'no reporting before completion');
  await tracker.completed(song, 60000);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, '/scrobble');
  assert.equal(calls[0].params.sourceid, '456');
  assert.equal(calls[0].params.time, '60');
  await tracker.completed(song, 60000);
  assert.equal(calls.length, 1, 'duplicate completion must not report twice');
  tracker.reset(); listen(tracker, 10000); tracker.discontinuity(); tracker.update(60000, true, 21000);
  await tracker.completed(song, 60000);
  assert.equal(calls.length, 1, 'seeking to the end must not count as a complete listen');
  tracker.reset(true); listen(tracker); await tracker.completed(song, 60000);
  assert.equal(calls.length, 1, 'trial resources must not report');
  tracker.reset(); listen(tracker); client.cookie = 'different-user'; await tracker.completed(song, 60000);
  assert.equal(calls.length, 1, 'account switches must not report to another account');
  tracker.reset(); listen(tracker); await tracker.completed({ ...song, isVoice: true }, 60000);
  assert.equal(calls.length, 1, 'podcasts are not song scrobbles');
  tracker.reset(); listen(tracker, 30000); await tracker.completed(song, 30000);
  assert.equal(calls.length, 1, 'shortened resources must not count');
  tracker.reset(); listen(tracker); await tracker.completed({ ...song, sourceId: '789' }, 60000);
  assert.equal(calls.at(-1).params.sourceid, '789');

  response = { code: 200, data: { list: [{ resourceId: 7, data: { id: 7, name: 'Voice', mainSong: {
    id: 8, name: 'Voice', ar: [], al: { id: 9, name: 'Podcast', picUrl: 'cover' }
  } } }] } };
  for (const kind of ['video', 'voice', 'playlist', 'album', 'dj']) {
    const result = await RecentPlaybackService.load(kind);
    assert.equal(calls.at(-1).url, `/record/recent/${kind}`);
    assert.equal(calls.at(-1).params.limit, '100');
    assert.equal(result[0].song.id, '8');
    assert.equal(result[0].song.isVoice, true);
  }
  response = { code: 200, data: { list: [{ resourceId: 'video-id', data: { vid: 'video-id', title: 'Video' } }] } };
  const videos = await RecentPlaybackService.load('video');
  assert.equal(videos[0].video, true);
  assert.equal(videos[0].id, 'video-id');
  client.cookie = '';
  await assert.rejects(() => RecentPlaybackService.load('playlist'));
  assert.equal(DiscoveryPlaylistsService.isRadar({ blockCode: 'HOMEPAGE_BLOCK_PLAYLIST_RADAR' }), true);
  assert.equal(DiscoveryPlaylistsService.isRadar({ uiElement: { mainTitle: { title: '雷达歌单' } } }), true);
  console.log('PASS: completion-only scrobble, seek/trial/account guards, source IDs, recent categories and limits, video mapping, radar detection');
})().catch(error => { console.error(error); process.exitCode = 1; });
