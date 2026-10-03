const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.join(__dirname, '../main/ets');
function compile(file, requireMock) {
  const exports = {};
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText, { exports, require: requireMock });
  return exports;
}
const api = compile('models/api.ets', () => ({}));
let response;
const calls = [];
const { ListeningPlaylistService: service } = compile('services/ListeningPlaylistService.ets', name => {
  if (name === '../models/api') return api;
  if (name === './ApiClient') return { ApiClient: { get: async (endpoint, params) => {
    calls.push({ endpoint, params: Object.fromEntries(params.map(p => [p.key, p.value])) });
    return response;
  } } };
  return {};
});
const song = (id, cover) => ({ id, name: `Song ${id}`, ar: [{ id: 9, name: 'Artist' }],
  al: { id: 8, name: 'Album', picUrl: cover }, dt: 60000, fee: 0 });
(async () => {
  response = { code: 200, data: { total: 3, list: [
    { data: song(2, 'first-cover') }, { data: song(1, 'second-cover') }, { data: song(2, 'old-cover') }
  ] } };
  const recent = await service.recent('123');
  assert.equal(calls.at(-1).endpoint, '/record/recent/song');
  assert.equal(calls.at(-1).params.limit, '300');
  assert.equal(calls.at(-1).params.timestamp, '123');
  assert.equal(recent.map(s => s.id).join(','), '2,1');
  assert.equal(recent[0].author, 'Artist');
  assert.equal(service.playlist('recent', 'me', 'Me', recent).cover, 'first-cover');
  response = { code: 200, weekData: [{ song: song(3, 'week') }], allData: [{ song: song(4, 'all') }] };
  const week = await service.record('other-user', 1);
  assert.equal(week[0].id, '3');
  assert.equal(calls.at(-1).endpoint, '/user/record');
  assert.equal(calls.at(-1).params.uid, 'other-user');
  assert.equal(calls.at(-1).params.type, '1');
  const all = await service.record('other-user', 0);
  assert.equal(all[0].id, '4');
  assert.equal(calls.at(-1).params.type, '0');
  const playlist = service.playlist('record', 'other-user', 'Other', all, 0);
  assert.equal(playlist.creatorId, 'other-user');
  assert.equal(playlist.recordType, 0);
  assert.equal(playlist.cover, 'all');
  response.allData = [];
  assert.equal((await service.record('other-user', 0)).length, 0);
  assert.equal(service.playlist('record', 'other-user', 'Other', []).cover, '');
  delete response.allData;
  await assert.rejects(() => service.record('other-user', 0));
  response = { code: 403, message: 'Private records' };
  await assert.rejects(() => service.record('other-user', 1), /Private records/);
  response = { code: 200 };
  await assert.rejects(() => service.recent());
  console.log('PASS: recent endpoint, song mapping/order, first cover, target uid, exact ranking period, empty/private data');
})().catch(error => { console.error(error); process.exitCode = 1; });
