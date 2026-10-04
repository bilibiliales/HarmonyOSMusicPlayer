// Node crypto is an independent test oracle only; production uses HarmonyOS CryptoArchitectureKit.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function load(file, mocks) {
  const exports = {};
  const code = fs.readFileSync(path.join(__dirname, '../main/ets', file), 'utf8');
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText, { exports, require: name => { assert.ok(name in mocks, name); return mocks[name]; } });
  return exports;
}
const sdk = {
  CryptoMode: { ENCRYPT_MODE: 1 },
  createRandom: () => ({ generateRandom: async size => ({ data: crypto.randomBytes(size) }) }),
  createSymKeyGenerator: name => {
    assert.equal(name, 'AES128');
    return { convertKey: async blob => Buffer.from(blob.data) };
  },
  createAsyKeyGenerator: name => {
    assert.equal(name, 'RSA1024');
    return { convertKey: async (pub, pri) => {
      assert.equal(pri, null);
      return { pubKey: crypto.createPublicKey({ key: Buffer.from(pub.data), format: 'der', type: 'spki' }) };
    } };
  },
  createCipher: name => {
    let key, iv;
    assert.ok(['AES128|CBC|PKCS7', 'RSA1024|NoPadding'].includes(name));
    return {
      init: async (mode, suppliedKey, params) => { assert.equal(mode, 1); key = suppliedKey; iv = params?.iv.data; },
      doFinal: async blob => {
        if (name.startsWith('RSA')) {
          assert.equal(blob.data.length, 128);
          return { data: crypto.publicEncrypt({ key, padding: crypto.constants.RSA_NO_PADDING }, Buffer.from(blob.data)) };
        }
        assert.equal(Buffer.from(iv).toString(), '0102030405060708');
        const cipher = crypto.createCipheriv('aes-128-cbc', key, iv);
        return { data: Buffer.concat([cipher.update(Buffer.from(blob.data)), cipher.final()]) };
      }
    };
  }
};
const { WeApiCrypto } = load('services/WeApiCrypto.ets', {
  '@kit.CryptoArchitectureKit': { cryptoFramework: sdk },
  '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(s) { return Buffer.from(s); } },
    Base64Helper: class { encodeToStringSync(b) { return Buffer.from(b).toString('base64'); } } } }
});
const standardModulus = BigInt('0xe0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7');
function pow(base, exponent, modulus) {
  let value = 1n;
  while (exponent) { if (exponent & 1n) value = value * base % modulus; base = base * base % modulus; exponent >>= 1n; }
  return value;
}
function aes(text, key) {
  const cipher = crypto.createCipheriv('aes-128-cbc', Buffer.from(key), Buffer.from('0102030405060708'));
  return Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]).toString('base64');
}
const cookie = 'MUSIC_U=test-session; __csrf=test-csrf; extra=a=b';
let captured, destroyed = 0, reply = { code: 200 }, networkFails = false;
const api = { cookie, baseUrl: 'https://configured-api.invalid' };
const { NeteaseDirectApi: direct } = load('services/NeteaseDirectApi.ets', {
  './ApiClient': { ApiClient: api }, './WeApiCrypto': { WeApiCrypto },
  '@kit.NetworkKit': { http: { RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 'string' }, createHttp: () => ({
    request: async (url, options) => { captured = { url, options }; if (networkFails) throw new Error('offline');
      return { responseCode: 200, result: JSON.stringify(reply) }; },
    destroy: () => destroyed++
  }) } }
});
const settingsModel = load('models/userSettings.ets', {});
let readCount = 0, writeCount = 0, readFails = false, writeFails = false;
let stored = { userId: 1, allowPeopleCanSeeMyPlayRecord: true, profileSetting: 0, commentSetting: 2, newSongDiskSetting: null };
const { UserSettingsService: settings } = load('services/UserSettingsService.ets', {
  './ApiClient': { ApiClient: { get cookie() { return api.cookie; }, get: async (url, params) => {
    readCount++; assert.equal(url, '/setting'); assert.ok(params.some(p => p.key === 'timestamp'));
    if (readFails) throw new Error('read failed'); return { code: 200, setting: stored };
  } } },
  './NeteaseDirectApi': { NeteaseDirectApi: { updateUserSettings: async patch => {
    writeCount++; assert.deepEqual(Object.keys(patch), ['allowPeopleCanSeeMyPlayRecord']);
    if (writeFails) throw new Error('write rejected'); return { code: 200 };
  } } }
});
(async () => {
  // Deterministic random bytes yield a known 16-character key without changing production code.
  sdk.createRandom = () => ({ generateRandom: async () => ({ data: Uint8Array.from({ length: 32 }, (_, i) => i) }) });
  const secret = 'abcdefghijklmnop';
  const text = JSON.stringify({ allowPeopleCanSeeMyPlayRecord: false, csrf_token: 'token', label: '中文' });
  const encrypted = await WeApiCrypto.encrypt(text);
  assert.equal(encrypted.params, aes(aes(text, '0CoJUm6Qyw8W8jud'), secret));
  const integer = BigInt('0x' + Buffer.from([...secret].reverse().join('')).toString('hex'));
  assert.equal(encrypted.encSecKey, pow(integer, 65537n, standardModulus).toString(16).padStart(256, '0'));
  assert.equal(encrypted.encSecKey.length, 256);
  const payload = direct.settingPayload({ allowPeopleCanSeeMyPlayRecord: false }, 'token');
  assert.equal(payload.allowPeopleCanSeeMyPlayRecord, false);
  assert.deepEqual(Object.keys(payload).sort(), ['allowPeopleCanSeeMyPlayRecord', 'csrf_token']);
  assert.throws(() => direct.settingPayload({ csrf_token: 'override' }, 'token'));
  assert.equal(direct.cookieValue(cookie, 'extra'), 'a=b');
  await direct.updateUserSettings({ allowPeopleCanSeeMyPlayRecord: false });
  assert.equal(new URL(captured.url).origin, 'https://music.163.com');
  assert.equal(new URL(captured.url).pathname, '/weapi/user/setting/update');
  assert.equal(captured.options.method, 'POST'); assert.equal(captured.options.header.Cookie, cookie);
  assert.equal(captured.options.maxRedirects, 0);
  const form = new URLSearchParams(captured.options.extraData);
  assert.deepEqual([...form.keys()], ['params', 'encSecKey']);
  assert.equal(form.get('params'), aes(aes(JSON.stringify({ allowPeopleCanSeeMyPlayRecord: false, csrf_token: 'test-csrf' }), '0CoJUm6Qyw8W8jud'), secret));
  assert.equal(destroyed, 1);
  reply = { code: 301, message: 'login expired' }; await assert.rejects(() => direct.updateUserSettings({ allowPeopleCanSeeMyPlayRecord: true }), /login expired/);
  assert.equal(destroyed, 2);
  networkFails = true; await assert.rejects(() => direct.updateUserSettings({ allowPeopleCanSeeMyPlayRecord: true }), /offline/);
  assert.equal(destroyed, 3);
  api.cookie = 'MUSIC_U=test'; await assert.rejects(() => direct.updateUserSettings({ allowPeopleCanSeeMyPlayRecord: true }));
  assert.equal(destroyed, 3); api.cookie = cookie;
  const patch = settingsModel.playRecordVisibilityPatch(false);
  const mismatch = await settings.updateAndRead('1', patch); assert.equal(mismatch.confirmed, false); assert.equal(mismatch.settings.allowPeopleCanSeeMyPlayRecord, true);
  stored.allowPeopleCanSeeMyPlayRecord = false;
  const success = await settings.updateAndRead('1', patch); assert.equal(success.confirmed, true); assert.equal(success.settings.commentSetting, 2); assert.equal(success.settings.newSongDiskSetting, null);
  writeFails = true; await settings.updateAndRead('1', patch); assert.equal(readCount, 3, 'read back even after ambiguous write failure');
  writeFails = false; readFails = true;
  const unconfirmed = await settings.updateAndRead('1', patch); assert.equal(unconfirmed.confirmed, false); assert.equal(unconfirmed.settings, undefined);
  assert.equal(writeCount, 4);
  readFails = false; await assert.rejects(() => settings.read('2'));
  let randomCalls = 0;
  sdk.createRandom = () => ({ generateRandom: async () => {
    const start = randomCalls++;
    return { data: Uint8Array.from({ length: 32 }, (_, i) => start + i) };
  } });
  const firstRandom = await WeApiCrypto.encrypt(text), nextRandom = await WeApiCrypto.encrypt(text);
  assert.equal(randomCalls, 2);
  assert.notEqual(firstRandom.params, nextRandom.params);
  assert.notEqual(firstRandom.encSecKey, nextRandom.encSecKey);
  const encrypt = WeApiCrypto.encrypt;
  WeApiCrypto.encrypt = async text => { const result = await encrypt.call(WeApiCrypto, text); api.cookie = 'another-account'; return result; };
  await assert.rejects(() => direct.updateUserSettings({ allowPeopleCanSeeMyPlayRecord: true }));
  assert.equal(destroyed, 3, 'account changes during encryption must not send a request');
  console.log('PASS: double AES/Base64, raw RSA/reversed key/zero padding, official URL, cookies/CSRF/form encoding, cleanup, boolean-only patch, canonical readback and failure states');
})().catch(error => { console.error(error); process.exitCode = 1; });
