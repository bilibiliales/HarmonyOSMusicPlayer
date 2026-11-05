#!/usr/bin/env node
/*
 * 流式加载验证 / 回归测试
 *
 *   node entry/src/test/StreamingAudio.regression.cjs
 *
 * A. 联网实测（需要 curl + 可访问的 API 服务，失败时跳过而不是判红）：
 *    - /song/url/v1 与 /song/download/url/v1 是否返回可分段读取的 CDN 地址
 *    - CDN 是否支持 Accept-Ranges / 206 / Content-Range（首、中、尾）
 *    - http 与 https 两种口径
 * B. 本地回归（不依赖网络，必须全部通过）：
 *    - 用 120MB+ 的虚拟 FLAC 与 Range 服务器，直接加载 StreamingAudio.ets
 *    - 验证按需分段、顺序读、任意跳转、内存上界、取消语义
 *    - 验证下载是分块直接写盘，探测头只取 64 字节
 *
 * 可用环境变量：MUSIC_API_BASE、MUSIC_SONG_ID、SKIP_LIVE=1
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync, spawnSync } = require('child_process')

const ROOT = path.resolve(__dirname, '../../..')
const SOURCE = path.join(ROOT, 'entry/src/main/ets/services/StreamingAudio.ets')

let localFailures = 0

function pass(label) { console.log('  PASS  ' + label) }

// Live checks are informational: the project may be built offline, so a network
// failure is reported as SKIP and never fails the regression run.
async function liveCase(label, fn) {
  try { await fn(); pass(label) }
  catch (error) { console.log('  SKIP  ' + label + ' :: ' + error.message.split('\n')[0]) }
}

/* ------------------------------------------------------------------ */
/* A. 真实接口 / CDN 流式能力验证                                        */
/* ------------------------------------------------------------------ */

function curl(args) {
  return execFileSync('curl', ['-sS', '-m', '25', ...args], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 })
}

// A native Windows curl does not understand "/dev/null" when spawned from Node,
// so the response body is discarded into a real temp file instead.
function curlHeaders(args) {
  const sink = path.join(os.tmpdir(), 'hmos-curl-' + process.pid + '-' + Math.random().toString(36).slice(2))
  try { return curl(['-D', '-', '-o', sink, ...args]) }
  finally { try { fs.unlinkSync(sink) } catch (_error) {} }
}

function assertRangeHeaders(label, headers, from, to, total) {
  if (!/^HTTP\/[\d.]+ 206\b/m.test(headers)) { throw new Error(`${label}: 未返回 206 Partial Content`) }
  const range = new RegExp(`Content-Range:\\s*bytes\\s+${from}-${to}/${total}`, 'i')
  if (!range.test(headers)) { throw new Error(`${label}: Content-Range 不是 ${from}-${to}/${total}`) }
  const length = new RegExp(`Content-Length:\\s*${to - from + 1}\\b`, 'i')
  if (!length.test(headers)) { throw new Error(`${label}: 分段长度不等于 ${to - from + 1}`) }
}

async function verifyLive() {
  const base = (process.env.MUSIC_API_BASE || 'https://zm.wwoyun.cn').replace(/\/$/, '')
  const songId = process.env.MUSIC_SONG_ID || '33894312'
  const stamp = Date.now()
  const endpoints = [
    ['播放接口 /song/url/v1', '/song/url/v1'],
    ['下载接口 /song/download/url/v1', '/song/download/url/v1']
  ]
  for (const [label, endpoint] of endpoints) {
    await liveCase(label + ' 返回可流式读取的 CDN 地址', () => {
      let item
      // The upstream occasionally answers -460 (busy); retry with a fresh timestamp.
      for (let attempt = 0; attempt < 3 && !item; attempt++) {
        const body = curl([`${base}${endpoint}?id=${songId}&level=exhigh&timestamp=${stamp + attempt * 7919}`])
        const json = JSON.parse(body)
        const candidate = Array.isArray(json.data) ? json.data[0] : json.data
        if (candidate && candidate.url && candidate.size > 0) { item = candidate }
      }
      if (!item) { throw new Error('接口未返回有效 url / size（可能是 -460 限流或版权限制）') }
      verifyCdn(label, item.url, item.size)
    })
  }
}

function verifyCdn(label, url, size) {
  const head = curlHeaders(['-I', url])
  if (!/Accept-Ranges:\s*bytes/i.test(head)) { throw new Error(`${label}: CDN 未声明 Accept-Ranges: bytes`) }
  const declared = /Content-Length:\s*(\d+)/i.exec(head)
  if (!declared || Number(declared[1]) !== size) { throw new Error(`${label}: Content-Length 与接口 size 不一致`) }

  const probes = [
    ['首部', 0, 1023],
    ['中部', Math.floor(size / 2), Math.floor(size / 2) + 1023],
    ['尾部', size - 1024, size - 1]
  ]
  for (const [name, from, to] of probes) {
    const headers = curlHeaders(['-H', `Range: bytes=${from}-${to}`, url])
    assertRangeHeaders(`${label} ${name} Range`, headers, from, to, size)
  }
  const httpsUrl = url.replace(/^http:\/\//, 'https://')
  if (httpsUrl !== url) {
    const headers = curlHeaders(['-H', 'Range: bytes=0-1023',
      '-H', 'Referer: https://music.163.com/', httpsUrl])
    assertRangeHeaders(`${label} HTTPS + Referer Range`, headers, 0, 1023, size)
  }
  console.log(`         ↳ ${label}: size=${size} bytes, 首/中/尾 206 均通过 (http/https)`)
}

/* ------------------------------------------------------------------ */
/* B. 本地 Range 服务器 + 真实 StreamingAudio.ets 逻辑回归               */
/* ------------------------------------------------------------------ */

const NETWORK_STUB = `
import nodeHttp from 'node:http'

export const http = {
  RequestMethod: { GET: 'GET' },
  createHttp() {
    const listeners = {}
    let request = null
    const api = {
      on(name, cb) {
        if (!listeners[name]) { listeners[name] = [] }
        listeners[name].push(cb)
        return api
      },
      emit(name, arg) {
        for (const cb of listeners[name] || []) { cb(arg) }
      },
      destroy() {
        if (request) { request.destroy(); request = null }
      },
      requestInStream(url, options) {
        return new Promise((resolve, reject) => {
          request = nodeHttp.get(url, { headers: options.header || {} }, (res) => {
            res.on('data', (chunk) => {
              const ab = chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength)
              api.emit('dataReceive', ab)
            })
            res.on('end', () => { api.emit('dataEnd'); resolve(res.statusCode) })
            res.on('error', reject)
          })
          request.on('error', reject)
        })
      }
    }
    return api
  }
}
export const connection = {}
`

const MEDIA_STUB = `export const media = {}\n`

const CORE_FILE_STUB = `
const files = new Map()
export const fileIo = {
  files,
  writeSync(fd, data, options) {
    const length = options && options.length !== undefined ? options.length : data.byteLength
    const bytes = Buffer.from(new Uint8Array(data, 0, length))
    let entry = files.get(fd)
    if (!entry) { entry = { chunks: [], size: 0 }; files.set(fd, entry) }
    entry.chunks.push(bytes)
    entry.size += bytes.length
    return bytes.length
  }
}
export const fileUri = {}
export const picker = {}
export const fileShare = {}
`

const TEST_MODULE = `
import nodeHttp from 'node:http'
import assert from 'node:assert/strict'
import { fileIo } from './stub-corefile.mjs'
import { StreamingAudioSource, StreamingDownload } from './StreamingAudio.ts'

const BIG = 120 * 1024 * 1024 + 12345   // 120 MB+ 非整块对齐的虚拟 FLAC
const SMALL = 3 * 1024 * 1024 + 77
const CHUNK = 64 * 1024
const byteAt = (i) => (i * 31 + 7) & 0xff
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

let servedBytes = 0
let bigFullGets = 0
let smallProbeBytes = 0

function writeBytes(res, from, to, size) {
  let pos = from
  while (pos <= to) {
    const end = Math.min(to, pos + CHUNK - 1)
    const buf = Buffer.allocUnsafe(end - pos + 1)
    for (let k = 0; k < buf.length; k++) { buf[k] = byteAt(pos + k) }
    res.write(buf)
    servedBytes += buf.length
    pos = end + 1
  }
}

const server = nodeHttp.createServer((req, res) => {
  const size = req.url.startsWith('/small') ? SMALL : BIG
  const range = req.headers.range
  if (!range) {
    if (!req.url.startsWith('/small')) { bigFullGets++ }
    res.writeHead(200, { 'Content-Type': 'audio/flac', 'Accept-Ranges': 'bytes', 'Content-Length': size })
    writeBytes(res, 0, size - 1, size)
    res.end()
    return
  }
  const match = /^bytes=(\\d+)-(\\d+)$/.exec(range)
  if (!match) { res.writeHead(416); res.end(); return }
  const from = Number(match[1])
  const to = Math.min(Number(match[2]), size - 1)
  if (from > to) { res.writeHead(416, { 'Content-Range': 'bytes */' + size }); res.end(); return }
  if (req.url.startsWith('/small')) { smallProbeBytes += to - from + 1 }
  res.writeHead(206, {
    'Content-Type': 'audio/flac',
    'Accept-Ranges': 'bytes',
    'Content-Range': 'bytes ' + from + '-' + to + '/' + size,
    'Content-Length': to - from + 1
  })
  writeBytes(res, from, to, size)
  res.end()
})

await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
const port = server.address().port
const bigUrl = 'http://127.0.0.1:' + port + '/big'
const smallUrl = 'http://127.0.0.1:' + port + '/small'

let failures = 0
async function check(label, fn) {
  try { await fn(); console.log('  PASS  ' + label) }
  catch (error) { failures++; console.error('  FAIL  ' + label + ' :: ' + error.message) }
}

function statValue(stats, key) {
  for (const part of stats.split(' ')) {
    if (part.startsWith(key + '=')) { return Number(part.slice(key.length + 1)) }
  }
  throw new Error('stats 缺少 ' + key + ' -> ' + stats)
}

async function readAt(desc, pos, length) {
  const buffer = new ArrayBuffer(length)
  const deadline = Date.now() + 8000
  let filled = 0
  while (Date.now() < deadline) {
    filled = desc.callback(buffer, length, pos)
    if (filled > 0) {
      const bytes = new Uint8Array(buffer, 0, filled)
      for (let k = 0; k < filled; k++) { assert.equal(bytes[k], byteAt(pos + k), 'wrong byte at ' + (pos + k)) }
      return filled
    }
    if (filled < 0) { throw new Error('callback returned ' + filled + ' at ' + pos) }
    await sleep(10)   // AVPlayer retries the callback when 0 bytes are available
  }
  throw new Error('timed out waiting for range at ' + pos)
}

await check('120MB+ FLAC: 起播只预取头部+尾部，不整曲加载', async () => {
  const before = servedBytes
  const src = new StreamingAudioSource(bigUrl, BIG)
  const desc = src.descriptor()
  assert.equal(desc.fileSize, BIG)
  await src.preload()
  const fetched = statValue(src.stats(), 'fetchedBytes')
  assert(fetched <= 3 * 1024 * 1024, '预取量过大: ' + fetched)
  assert(servedBytes - before <= 3 * 1024 * 1024, '实际网络流量过大: ' + (servedBytes - before))
  src.cancel()
})

await check('顺序播放 / 任意跳转读取字节正确，且内存与流量有界', async () => {
  const src = new StreamingAudioSource(bigUrl, BIG)
  const desc = src.descriptor()
  await src.preload()
  let pos = 0
  const playback = 6 * 1024 * 1024
  while (pos < playback) {
    pos += await readAt(desc, pos, Math.min(4096, playback - pos))
  }
  for (const seek of [100 * 1024 * 1024, 0, BIG - 4096]) {
    await readAt(desc, seek, 2048)
  }
  const stats = src.stats()
  const resident = statValue(stats, 'residentBytes')
  const fetched = statValue(stats, 'fetchedBytes')
  assert(resident <= 16 * 1024 * 1024, '常驻内存超过 16MB: ' + resident)
  assert(fetched <= 40 * 1024 * 1024, '累计取数接近整曲: ' + fetched)
  assert.equal(bigFullGets, 0, '出现了不带 Range 的整曲请求')
  src.cancel()
  assert.equal(desc.callback(new ArrayBuffer(16), 16, 0), -2, 'cancel 后应返回 -2')
})

await check('下载: 64 字节探测头 + 分块直写目标文件', async () => {
  const before = smallProbeBytes
  const header = await StreamingDownload.probe(smallUrl, 64)
  assert.equal(header.length, 64)
  for (let i = 0; i < 64; i++) { assert.equal(header[i], byteAt(i)) }
  assert.equal(smallProbeBytes - before, 64, '探测头只应取 64 字节')

  const fd = 7
  let lastProgress = 0
  const download = new StreamingDownload()
  const written = await download.run(smallUrl, fd, SMALL, (received) => { lastProgress = received })
  assert.equal(written, SMALL)
  assert.equal(lastProgress, SMALL)
  const data = Buffer.concat(fileIo.files.get(fd).chunks)
  assert.equal(data.length, SMALL)
  for (let i = 0; i < data.length; i += 997) { assert.equal(data[i], byteAt(i)) }
})

server.close()
console.log(failures ? '\\n本地回归 ' + failures + ' 项失败' : '\\n本地回归全部通过')
process.exit(failures ? 1 : 0)
`

function runLocalRegression() {
  if (!fs.existsSync(SOURCE)) { throw new Error('找不到 StreamingAudio.ets: ' + SOURCE) }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hmos-stream-'))
  try {
    fs.writeFileSync(path.join(tmp, 'package.json'), '{"type":"module"}\n')
    fs.writeFileSync(path.join(tmp, 'stub-network.mjs'), NETWORK_STUB)
    fs.writeFileSync(path.join(tmp, 'stub-media.mjs'), MEDIA_STUB)
    fs.writeFileSync(path.join(tmp, 'stub-corefile.mjs'), CORE_FILE_STUB)
    // HarmonyOS kit specifiers (@kit.X) are not valid Node package names, so the
    // temp copy points them at local stubs. Everything else is the shipped source.
    const source = fs.readFileSync(SOURCE, 'utf8')
      .replace(/from '@kit\.NetworkKit'/g, "from './stub-network.mjs'")
      .replace(/from '@kit\.MediaKit'/g, "from './stub-media.mjs'")
      .replace(/from '@kit\.CoreFileKit'/g, "from './stub-corefile.mjs'")
    fs.writeFileSync(path.join(tmp, 'StreamingAudio.ts'), source)
    fs.writeFileSync(path.join(tmp, 'test.mjs'), TEST_MODULE)
    const result = spawnSync(process.execPath,
      ['--no-warnings', '--experimental-strip-types', path.join(tmp, 'test.mjs')],
      { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
    if (result.stdout) { process.stdout.write(result.stdout) }
    if (result.stderr) { process.stdout.write(result.stderr) }
    if (result.status !== 0) {
      localFailures++
      console.error('  FAIL  本地回归进程退出码 ' + result.status +
        (result.error ? ' :: ' + result.error.message : ''))
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
}

/* ------------------------------------------------------------------ */

async function main() {
  console.log('\n=== A. 在线播放 / 下载接口流式能力实测 ===')
  if (process.env.SKIP_LIVE === '1') {
    console.log('  SKIP  已设置 SKIP_LIVE=1')
  } else {
    try { await verifyLive() }
    catch (error) { console.log('  SKIP  联网验证不可用：' + error.message.split('\n')[0]) }
  }
  console.log('\n=== B. 流式播放 / 下载逻辑本地回归 (120MB+ 虚拟 FLAC) ===')
  runLocalRegression()
  console.log('\n结果：' + (localFailures ? localFailures + ' 项失败' : '全部通过') + '\n')
  process.exit(localFailures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
