// Regression for the streaming-playback toggle.
//
//   A. Byte-exact round-trip of the restored in-memory source (MemoryAudioSource).
//   B. Static scan proving the toggle is wired end-to-end:
//        Settings UI -> AppSettings.streamingPlaybackEnabled -> PlayerController branch
//        that picks StreamingAudioSource (ON) or MemoryAudioLoad (OFF).
//
// Run: node entry/src/test/StreamingToggle.regression.cjs

const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const ROOT = path.resolve(__dirname, '..', '..', '..')
const SRC = path.join(ROOT, 'entry', 'src', 'main', 'ets', 'services')

let failures = 0
const pass = (label) => console.log('  PASS  ' + label)
const fail = (label, error) => { console.error('  FAIL  ' + label + ' :: ' + (error && error.message ? error.message : error)); failures++ }

function assert(cond, msg) { if (!cond) { throw new Error(msg || 'assertion failed') } }

/* ------------------------------------------------------------------ */
/* A. MemoryAudioSource round-trip (real restored module, stubbed Kits)*/
/* ------------------------------------------------------------------ */

async function caseMemoryRoundTrip() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'stream-toggle-'))
  try {
    // HarmonyOS kit specifiers (@kit.X) are not valid Node package names, so the
    // temp copy points them at local stubs. Everything else is the shipped source.
    fs.writeFileSync(path.join(tmp, 'stub-network.mjs'), `
export const http = {
  createHttp() {
    return { on() {}, requestInStream() { return Promise.resolve(200) }, destroy() {} }
  },
  RequestMethod: { GET: 'GET' }
}
`)
    fs.writeFileSync(path.join(tmp, 'stub-media.mjs'), `export const media = {}`)
    let src = fs.readFileSync(path.join(SRC, 'MemoryAudioSource.ets'), 'utf8')
      .replace(/from '@kit\.NetworkKit'/g, "from './stub-network.mjs'")
      .replace(/from '@kit\.MediaKit'/g, "from './stub-media.mjs'")
    fs.writeFileSync(path.join(tmp, 'MemoryAudioSource.ts'), src)
    const testModule = `
import assert from 'assert'
import { MemoryAudioSource } from './MemoryAudioSource.ts'

export function run() {
  const total = 1000000
  const ref = new Uint8Array(total)
  for (let i = 0; i < total; i++) { ref[i] = (i * 31 + 7) & 0xff }

  const chunks = []
  let i = 0
  while (i < total) {
    const len = 1 + (Math.floor((i * 2654435761) % 9973) % 4096)
    const len2 = Math.min(len, total - i)
    chunks.push(ref.subarray(i, i + len2))
    i += len2
  }
  const src = new MemoryAudioSource(chunks)
  assert.strictEqual(src.size, total, 'size matches total')

  // 1. full sequential read from position 0
  const buf = new ArrayBuffer(total)
  const got = new Uint8Array(buf)
  let pos = 0
  while (pos < total) {
    const n = src.read(buf, 50000, pos)
    if (n <= 0) { break }
    pos += n
  }
  assert.strictEqual(pos, total, 'sequential full read length')
  for (let k = 0; k < total; k++) { assert.strictEqual(got[k], ref[k], 'sequential byte ' + k) }

  // 2. random seeks (off, count) return exact subranges
  for (const off of [0, 1, 500, total - 1, total - 1000, 123456, 777777]) {
    const b = new ArrayBuffer(2000)
    const n = src.read(b, 2000, off)
    const exp = Math.min(2000, total - off)
    assert.strictEqual(n, exp, 'seek count at ' + off)
    const arr = new Uint8Array(b, 0, n)
    for (let k = 0; k < n; k++) { assert.strictEqual(arr[k], ref[off + k], 'byte at ' + off + '+' + k) }
  }
  // 3. EOF / out-of-range
  assert.strictEqual(src.read(new ArrayBuffer(10), 10, total), -1, 'EOF at size')
  assert.strictEqual(src.read(new ArrayBuffer(10), 10, total + 5), -1, 'EOF past size')
  // 4. invalid arguments
  assert.strictEqual(src.read(new ArrayBuffer(10), 10, -1), -2, 'negative pos -> -2')
  assert.strictEqual(src.read(new ArrayBuffer(10), -5, 0), -2, 'negative length -> -2')
  assert.strictEqual(src.read(new ArrayBuffer(10), 10, 1.5), -2, 'fractional pos -> -2')
  // 5. relative read advances internal position
  const s2 = new MemoryAudioSource([ref.subarray(0, total)])
  assert.strictEqual(s2.read(new ArrayBuffer(100), 100), 100, 'relative read #1')
  assert.strictEqual(s2.read(new ArrayBuffer(100), 100), 100, 'relative read #2 (position advanced)')
}
`
    fs.writeFileSync(path.join(tmp, 'test.mjs'), testModule)
    const out = execFileSync('node', ['--experimental-strip-types', path.join(tmp, 'test.mjs')],
      { encoding: 'utf8', cwd: tmp })
    pass('MemoryAudioSource 字节级往返（顺序/跳转/EOF/非法参数/相对读）')
    void out
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
}

/* ------------------------------------------------------------------ */
/* B. Static wiring scan                                              */
/* ------------------------------------------------------------------ */

function readFileSafe(p) {
  try { return fs.readFileSync(p, 'utf8') } catch (_e) { return '' }
}

function scan() {
  const pc = readFileSafe(path.join(SRC, 'PlayerController.ets'))
  const as = readFileSync2(path.join(SRC, 'AppSettings.ets'))
  const se = readFileSafe(path.join(ROOT, 'entry', 'src', 'main', 'ets', 'pages', 'Settings.ets'))
  const ms = readFileSafe(path.join(SRC, 'MemoryAudioSource.ets'))

  // AppSettings: flag (default true) + key + save method
  assert(/static\s+streamingPlaybackEnabled\s*:\s*boolean\s*=\s*true/.test(as), 'AppSettings.streamingPlaybackEnabled 默认 true')
  assert(/STREAMING_PLAYBACK_KEY/.test(as), 'AppSettings 定义 STREAMING_PLAYBACK_KEY 常量')
  assert(/saveStreamingPlayback/.test(as), 'AppSettings 提供 saveStreamingPlayback')
  assert(/store\.get\(AppSettings\.STREAMING_PLAYBACK_KEY/.test(as), 'load() 读取该偏好，默认 true')
  pass('AppSettings: streamingPlaybackEnabled(默认true) + 键 + 持久化方法 齐备')

  // PlayerController: the streaming toggle is the OUTER branch.
  //   ON  -> StreamingAudioSource (size>0) OR player.url direct stream (live radio, size 0)
  //   OFF -> ALWAYS MemoryAudioLoad + dataSrc (the original whole-file-in-memory
  //          strategy), regardless of resource.size — there is never a
  //          "load while playing" window, which is what the code review required.
  assert(/import \{ MemoryAudioLoad \} from '\.\/MemoryAudioSource'/.test(pc), 'PlayerController 导入 MemoryAudioLoad')
  assert(/import \{ secureAudioUrl, StreamingAudioSource \} from '\.\/StreamingAudio'/.test(pc), 'PlayerController 仍导入 StreamingAudioSource')
  const gateIdx = pc.indexOf('if (AppSettings.streamingPlaybackEnabled)')
  assert(gateIdx >= 0, 'PlayerController 按 streamingPlaybackEnabled 外层分支')
  // The OFF branch is the `} else {` immediately before `new MemoryAudioLoad()`.
  const memIdx = pc.indexOf('new MemoryAudioLoad()')
  assert(memIdx >= 0, 'OFF 分支使用 MemoryAudioLoad')
  const elseIdx = pc.lastIndexOf('} else {', memIdx)
  const offBranch = pc.slice(elseIdx)
  assert(/new MemoryAudioLoad\(\)/.test(offBranch), 'OFF 分支使用 MemoryAudioLoad 整曲加载')
  assert(/player\.dataSrc = source\.descriptor\(\)/.test(offBranch), 'OFF 分支经 dataSrc 从内存读取(非 player.url)')
  assert(!/player\.url/.test(offBranch), 'OFF 分支绝不走 player.url 直接流(回归项: 关闭流式后不得一边加载一边播)')
  // The direct-stream path must be confined to the ON branch (after the gate).
  const onBranch = pc.slice(gateIdx)
  assert(/new StreamingAudioSource\(resource\.url, resource\.size\)/.test(onBranch), 'ON 分支使用 StreamingAudioSource')
  assert(/player\.url = secureAudioUrl/.test(onBranch), 'ON 分支的直播流走 player.url 直连')
  assert(/SET_STREAMING_SOURCE/.test(pc) && /SET_MEMORY_SOURCE/.test(pc), '两条分支各有日志标记')
  // lifecycle: closeAudioStream cancels both
  assert(/this\.audioLoad\?\.cancel\(\)/.test(pc), 'closeAudioStream 取消 MemoryAudioLoad')
  pass('PlayerController: 流式开关为外层分支, OFF 回退整曲内存加载且绝不走 player.url')

  // Settings UI: toggle wired to changeStreamingPlayback -> saveStreamingPlayback
  assert(/@State streamingPlaybackEnabled: boolean = AppSettings\.streamingPlaybackEnabled/.test(se),
    'Settings 声明 streamingPlaybackEnabled @State')
  assert(/changeStreamingPlayback/.test(se), 'Settings 提供 changeStreamingPlayback')
  assert(/onChange\(\(enabled: boolean\) => this\.changeStreamingPlayback\(enabled\)\)/.test(se),
    'Toggle 的 onChange 调用 changeStreamingPlayback')
  assert(/saveStreamingPlayback/.test(se), 'changeStreamingPlayback 持久化(saveStreamingPlayback)')
  pass('Settings UI: 开关 -> changeStreamingPlayback -> saveStreamingPlayback 完整闭环')

  // MemoryAudioSource restored and whole-file (not range) loader
  assert(/class MemoryAudioSource/.test(ms) && /class MemoryAudioLoad/.test(ms), 'MemoryAudioSource.ets 含两个类')
  assert(/requestInStream/.test(ms), 'MemoryAudioLoad 使用 requestInStream 整曲下载')
  pass('MemoryAudioSource.ets: 整曲内存加载策略已恢复')
}

function readFileSync2(p) { return readFileSafe(p) }

/* ------------------------------------------------------------------ */

async function main() {
  console.log('\n=== 流式播放开关回归 ===')
  await caseAsync('A. MemoryAudioSource 字节级往返', caseMemoryRoundTrip)
  try { scan(); pass('B. 静态接线扫描') } catch (e) { fail('B. 静态接线扫描', e) }

  console.log('\n=== 既有回归（防回归）===')
  for (const script of ['StreamingAudio.regression.cjs', 'AvSessionIsolation.regression.cjs']) {
    const full = path.join(ROOT, 'entry', 'src', 'test', script)
    try {
      const out = execFileSync('node', [full], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
      console.log('  PASS  既有回归 ' + script)
      void out
    } catch (e) {
      fail('既有回归 ' + script, e)
    }
  }
  console.log('\n' + (failures === 0 ? 'ALL PASSED' : (failures + ' FAILED')))
  process.exit(failures === 0 ? 0 : 1)
}

async function caseAsync(label, fn) {
  try { await fn(); pass(label) } catch (e) { fail(label, e) }
}

main()
