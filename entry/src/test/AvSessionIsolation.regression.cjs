#!/usr/bin/env node
/**
 * Regression suite for: "with the background playback switch off, the playback
 * module must ABSOLUTELY never load AVSession Kit".
 *
 * Three independent layers of proof:
 *   A. Static source / dependency-graph analysis of the shipped sources.
 *   B. Truth table of the single gate shouldLoadMediaSession(), executed from
 *      the real MediaSessionContract.ets (no Kit stubs involved).
 *   C. Runtime simulation that extracts the REAL mediaSessionAllowed /
 *      createSystemSession / ensureSystemSession methods from PlayerController.ets
 *      and executes them with a probe standing in for the AVSession bridge, so a
 *      module load is observable.
 *
 * Run: node entry/src/test/AvSessionIsolation.regression.cjs
 */
'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const assert = require('assert')

const ENTRY = path.resolve(__dirname, '../..')
const ETS = path.join(ENTRY, 'src/main/ets')
const SERVICES = path.join(ETS, 'services')
const CONTRACT = path.join(SERVICES, 'MediaSessionContract.ets')
const BRIDGE = path.join(SERVICES, 'MediaSessionBridge.ets')
const CONTROLLER = path.join(SERVICES, 'PlayerController.ets')
const SETTINGS = path.join(SERVICES, 'AppSettings.ets')

let failures = 0
function check(label, fn) {
  try { fn(); console.log('  PASS  ' + label) } catch (error) {
    failures++
    console.error('  FAIL  ' + label + ' :: ' + (error && error.message ? error.message : String(error)))
  }
}

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) { walk(full, out) } else if (/\.(ets|ts)$/.test(entry.name)) { out.push(full) }
  }
  return out
}

/** Remove comments (but keep string contents intact) so doc text cannot fool the scan. */
function stripComments(src) {
  let out = ''
  let state = 'code'
  let quote = ''
  for (let i = 0; i < src.length;) {
    const c = src[i]
    const n = src[i + 1]
    if (state === 'code') {
      if (c === '/' && n === '*') { state = 'block'; i += 2; continue }
      if (c === '/' && n === '/') { state = 'line'; i += 2; continue }
      if (c === "'" || c === '"' || c === '`') { quote = c; state = 'string'; out += c; i++; continue }
      out += c; i++; continue
    }
    if (state === 'block') {
      if (c === '*' && n === '/') { state = 'code'; i += 2 } else { i++ }
      continue
    }
    if (state === 'line') {
      if (c === '\n') { state = 'code'; out += '\n' }
      i++; continue
    }
    if (c === '\\') { out += c + (n || ''); i += 2; continue }
    if (c === quote) { state = 'code' }
    out += c; i++
  }
  return out
}

/** Only static `import ...` statements; `import()` expressions are not matched. */
function staticImports(src) {
  const out = []
  for (const line of stripComments(src).split('\n')) {
    if (!/^\s*import\s/.test(line)) { continue }
    const match = /['"]([^'"]+)['"]/.exec(line)
    if (match) { out.push(match[1]) }
  }
  return out
}

function resolveLocal(from, spec) {
  if (!spec.startsWith('.')) { return null }
  const base = path.resolve(path.dirname(from), spec)
  for (const suffix of ['', '.ets', '.ts', '/index.ets', '/index.ts']) {
    const candidate = base + suffix
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) { return candidate }
  }
  return null
}

function extractMethod(src, signature) {
  const start = src.indexOf(signature)
  if (start < 0) { throw new Error('找不到方法: ' + signature) }
  const open = src.indexOf('{', start)
  let depth = 0
  let end = open
  for (; end < src.length; end++) {
    if (src[end] === '{') { depth++ } else if (src[end] === '}') {
      depth--
      if (depth === 0) { end++; break }
    }
  }
  return src.slice(start, end).replace(/^private\s+/, '')
}

function methodBody(src, signature) {
  return extractMethod(src, signature)
}

/* ------------------------------------------------------------------ */
/* A. Static analysis                                                  */
/* ------------------------------------------------------------------ */

console.log('\n=== A. 静态依赖 / 源码隔离性 ===')
const files = walk(ETS, [])
const sources = new Map(files.map(f => [f, fs.readFileSync(f, 'utf8')]))
const clean = new Map([...sources].map(([f, s]) => [f, stripComments(s)]))
const rel = f => path.relative(ETS, f).replace(/\\/g, '/')

const KIT_RE = /@kit\.AVSessionKit|@ohos\.multimedia\.avsession/

check('全工程只有 MediaSessionBridge.ets 静态导入 AVSession Kit', () => {
  const importers = [...clean].filter(([, text]) => {
    return /^\s*import\s[^\n]*(@kit\.AVSessionKit|@ohos\.multimedia\.avsession)/m.test(text)
  }).map(([f]) => rel(f))
  assert.deepStrictEqual(importers, ['services/MediaSessionBridge.ets'])
})

check('PlayerController.ets 完全不含 avSession / AVSession Kit 符号', () => {
  const text = clean.get(CONTROLLER)
  assert(!/avSession/i.test(text.replace(/AVSession/g, '')), '仍存在 avSession 引用')
  assert(!KIT_RE.test(text), '仍存在 AVSession Kit 路径')
})

check('中立契约 MediaSessionContract.ets 不含任何 AVSession 符号', () => {
  const text = clean.get(CONTRACT)
  assert(!/avSession/i.test(text.replace(/AVSession/g, '')), '仍存在 avSession 引用')
  assert(!KIT_RE.test(text), '仍存在 AVSession Kit 路径')
})

check('没有任何文件静态 import MediaSessionBridge', () => {
  const offenders = []
  for (const [f, text] of clean) {
    for (const spec of staticImports(text)) {
      if (/MediaSessionBridge/.test(spec)) { offenders.push(rel(f) + ' -> ' + spec) }
    }
  }
  assert.deepStrictEqual(offenders, [])
})

check('从所有冷启动入口做静态依赖 BFS，均不可达 MediaSessionBridge', () => {
  const roots = files.filter(f => {
    const r = rel(f)
    return r === 'entryability/EntryAbility.ets' ||
      r.startsWith('pages/') || r.startsWith('musiccard/') ||
      r.startsWith('entrybackupability/')
  })
  assert(roots.length > 0, '没有找到入口文件')
  const seen = new Set()
  const queue = roots.slice()
  while (queue.length) {
    const current = queue.shift()
    if (seen.has(current)) { continue }
    seen.add(current)
    for (const spec of staticImports(clean.get(current) || '')) {
      const target = resolveLocal(current, spec)
      if (target) { queue.push(target) }
    }
  }
  assert(!seen.has(BRIDGE), 'MediaSessionBridge 出现在冷启动静态依赖图中')
  assert(seen.has(CONTROLLER), 'PlayerController 应当出现在静态依赖图中')
  console.log('         ↳ 静态可达文件 ' + seen.size + ' 个，桥接模块不在其中')
})

check('全工程唯一一次 import(\'./MediaSessionBridge\') 且位于 PlayerController', () => {
  const hits = []
  for (const [f, text] of clean) {
    const count = (text.match(/import\(\s*['"]\.\/MediaSessionBridge['"]\s*\)/g) || []).length
    if (count) { hits.push(rel(f) + ' x' + count) }
  }
  assert.deepStrictEqual(hits, ['services/PlayerController.ets x1'])
})

check('动态导入只存在于 createSystemSession，且只被门控后的 ensureSystemSession 调用', () => {
  const text = clean.get(CONTROLLER)
  const createBody = methodBody(text, 'private async createSystemSession(context: common.Context): Promise<MediaSessionApi> {')
  const ensureBody = methodBody(text, 'private async ensureSystemSession(): Promise<MediaSessionApi | undefined> {')
  assert(/import\(\s*['"]\.\/MediaSessionBridge['"]\s*\)/.test(createBody), '动态导入不在 createSystemSession 内')
  const guardAt = ensureBody.indexOf('if (!this.mediaSessionAllowed()) { return undefined }')
  const callAt = ensureBody.indexOf('this.createSystemSession(context)')
  assert(guardAt >= 0, 'ensureSystemSession 缺少门控')
  assert(callAt > guardAt, '门控必须在调用 createSystemSession 之前')
  assert.strictEqual((text.match(/this\.createSystemSession\(/g) || []).length, 1,
    'createSystemSession 只有一个调用点')
})

check('所有会话读写入口都有 mediaSessionAllowed 前置门控', () => {
  const text = clean.get(CONTROLLER)
  const guarded = [
    'private async syncSystemPlayback(state: number, position?: number): Promise<void> {',
    'private async syncSystemMetadata(song: songItemType): Promise<void> {',
    'async refreshDesktopLyrics(): Promise<void> {',
    'async setDesktopLyrics(enabled: boolean, locked: boolean): Promise<void> {'
  ]
  for (const signature of guarded) {
    const body = methodBody(text, signature)
    assert(/mediaSessionAllowed\(\)/.test(body), signature.split('(')[0] + ' 缺少门控')
  }
})

check('桥接工厂自带二次开关校验（纵深防御）', () => {
  const text = clean.get(BRIDGE)
  const body = methodBody(text, 'export async function createMediaSession(context: common.Context, handlers: SessionHandlers,')
  assert(/shouldLoadMediaSession\(/.test(body), '桥接工厂缺少开关复核')
  assert(/createAVSession\(/.test(body), '桥接工厂没有创建会话')
})

check('AppSettings 默认 settingsLoaded=false，且显式读取/保存偏好后才置 true', () => {
  const text = clean.get(SETTINGS)
  assert(/static settingsLoaded: boolean = false/.test(text), '默认值不是 false')
  assert.strictEqual((text.match(/AppSettings\.settingsLoaded = true/g) || []).length, 2,
    'load() 与 saveBackgroundPlayback() 都应置 true')
})

/* ------------------------------------------------------------------ */
/* B/C. Runtime harness                                                */
/* ------------------------------------------------------------------ */

console.log('\n=== B/C. 门控真值表 + 真实门控代码运行时模拟 ===')

const STUB_ABILITY = 'export const common = {}\n'
const PROBE = 'export const marker = { loads: 0, destroyed: 0, beforeResolve: null }\n'
const BRIDGE_STUB = [
  "import { MediaSessionRegistry } from './MediaSessionContract.ts'",
  "import { marker } from './bridge-probe.mjs'",
  'marker.loads += 1',
  'MediaSessionRegistry.factory = async (context, handlers, initial) => {',
  '  if (marker.beforeResolve) { await marker.beforeResolve() }',
  '  return {',
  "    sessionId: () => 'stub-session',",
  '    destroy: async () => { marker.destroyed += 1 },',
  '    activate: async () => {},',
  '    setMetadata: async () => {},',
  '    setPlaybackState: async () => {},',
  '    configureDesktopLyrics: async () => {},',
  "    refreshDesktopLyrics: async () => ({ visible: false, locked: false }),",
  "    readLyricMetadata: async () => ({ assetId: '', lyric: '' })",
  '  }',
  '}',
  ''
].join('\n')

const HARNESS_HEAD = [
  "import { shouldLoadMediaSession, MediaSessionRegistry } from './MediaSessionContract.ts'",
  "import { marker } from './bridge-probe.mjs'",
  '',
  'const AppSettings: any = {',
  '  settingsLoaded: false,',
  '  backgroundPlaybackEnabled: false,',
  '  desktopLyricsEnabled: false,',
  '  desktopLyricsLocked: false',
  '}',
  '',
  'class Harness {',
  '  private systemSession: any = undefined',
  '  private systemSessionCreation: any = undefined',
  '  private desktopSessionEnabled: boolean = false',
  '  private desktopConfiguring: boolean = false',
  '  private released: boolean = false',
  '  private uiContext: any = { getHostContext: () => ({}) }',
  '  log(event: string, detail: string): void {}',
  '  sessionHandlers(): any { return {} }',
  '',
  '  configure(settingsLoaded: boolean, enabled: boolean, released: boolean): void {',
  '    AppSettings.settingsLoaded = settingsLoaded',
  '    AppSettings.backgroundPlaybackEnabled = enabled',
  '    this.released = released',
  '  }'
].join('\n')

const HARNESS_TAIL = [
  '',
  'const results: any[] = []',
  '',
  'async function scenario(name: string, s: boolean, e: boolean, r: boolean, flip: boolean): Promise<void> {',
  '  const h = new Harness()',
  '  h.configure(s, e, r)',
  '  const beforeLoads = marker.loads',
  '  const beforeDestroyed = marker.destroyed',
  '  marker.beforeResolve = flip ? async () => { AppSettings.backgroundPlaybackEnabled = false } : null',
  '  const session = await h.ensureSystemSession()',
  '  results.push({',
  '    name, session: !!session,',
  '    loadDelta: marker.loads - beforeLoads,',
  '    destroyDelta: marker.destroyed - beforeDestroyed',
  '  })',
  '}',
  '',
  '// Truth table of the real gate, executed from the shipped contract module.',
  'const truth: any[] = []',
  'for (const s of [false, true]) {',
  '  for (const e of [false, true]) {',
  '    for (const r of [false, true]) {',
  '      truth.push({ s, e, r, allowed: shouldLoadMediaSession(s, e, r) })',
  '    }',
  '  }',
  '}',
  '',
  'async function main(): Promise<void> {',
  "  await scenario('开关关闭', true, false, false, false)",
  "  await scenario('偏好尚未读取完成', false, true, false, false)",
  "  await scenario('已释放', true, true, true, false)",
  "  await scenario('开关打开', true, true, false, false)",
  "  await scenario('加载途中关闭开关', true, true, false, true)",
  "  console.log('__RESULT__' + JSON.stringify({ truth, results }))",
  '}',
  'main()',
  ''
].join('\n')

function runRuntimeHarness() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hmos-avsession-'))
  try {
    fs.writeFileSync(path.join(tmp, 'package.json'), '{"type":"module"}\n')
    fs.writeFileSync(path.join(tmp, 'stub-ability.mjs'), STUB_ABILITY)
    fs.writeFileSync(path.join(tmp, 'bridge-probe.mjs'), PROBE)
    fs.writeFileSync(path.join(tmp, 'MediaSessionBridge.mjs'), BRIDGE_STUB)

    // Real contract, with the type-only AbilityKit import pointed at a local stub.
    const contract = sources.get(CONTRACT).replace(/from '@kit\.AbilityKit'/g, "from './stub-ability.mjs'")
    fs.writeFileSync(path.join(tmp, 'MediaSessionContract.ts'), contract)

    // The three REAL methods from PlayerController. Only the Kit module specifier
    // is rewritten to the probe; all gating logic is the shipped source verbatim.
    const controller = sources.get(CONTROLLER)
    const methods = [
      'private mediaSessionAllowed(): boolean {',
      'private async createSystemSession(context: common.Context): Promise<MediaSessionApi> {',
      'private async ensureSystemSession(): Promise<MediaSessionApi | undefined> {'
    ].map(sig => extractMethod(controller, sig))
      .map(body => body.replace(/'\.\/MediaSessionBridge'/g, "'./MediaSessionBridge.mjs'"))
      .join('\n\n  ')

    fs.writeFileSync(path.join(tmp, 'harness.ts'),
      HARNESS_HEAD + '\n\n  ' + methods + '\n}\n' + HARNESS_TAIL)

    const result = spawnSync(process.execPath,
      ['--no-warnings', '--experimental-strip-types', path.join(tmp, 'harness.ts')],
      { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
    if (result.stdout && !result.stdout.includes('__RESULT__')) { process.stdout.write(result.stdout) }
    if (result.stderr) { process.stdout.write(result.stderr) }
    assert.strictEqual(result.status, 0, '运行时模拟进程退出码 ' + result.status)
    const line = result.stdout.split('\n').find(l => l.startsWith('__RESULT__'))
    assert(line, '运行时模拟没有输出结果')
    return JSON.parse(line.slice('__RESULT__'.length))
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
}

let runtime = null
try {
  runtime = runRuntimeHarness()
  console.log('  PASS  运行时模拟成功执行（真实门控代码 + 探针桥接模块）')
} catch (error) {
  failures++
  console.error('  FAIL  运行时模拟无法执行 :: ' + error.message)
}

if (runtime) {
  check('shouldLoadMediaSession 真值表：仅 (已读取, 开关开, 未释放) 允许加载', () => {
    const allowed = runtime.truth.filter(t => t.allowed)
    assert.strictEqual(allowed.length, 1, '允许加载的组合不唯一')
    assert.deepStrictEqual(allowed[0], { s: true, e: true, r: false, allowed: true })
  })

  const cases = {
    '开关关闭': { session: false, loadDelta: 0, destroyDelta: 0 },
    '偏好尚未读取完成': { session: false, loadDelta: 0, destroyDelta: 0 },
    '已释放': { session: false, loadDelta: 0, destroyDelta: 0 },
    '开关打开': { session: true, loadDelta: 1, destroyDelta: 0 },
    '加载途中关闭开关': { session: false, loadDelta: 0, destroyDelta: 1 }
  }
  for (const [name, expect] of Object.entries(cases)) {
    check('运行时 · ' + name + ' → ' + JSON.stringify(expect), () => {
      const actual = runtime.results.find(r => r.name === name)
      assert(actual, '缺少场景结果')
      assert.deepStrictEqual(
        { session: actual.session, loadDelta: actual.loadDelta, destroyDelta: actual.destroyDelta },
        expect)
    })
  }
}

console.log('\n' + (failures ? '隔离性回归 ' + failures + ' 项失败' : '隔离性回归全部通过'))
process.exit(failures ? 1 : 0)
