import { http } from '@kit.NetworkKit'
import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'

// The playback / download URL endpoints return Netease CDN object URLs. Verified behaviour:
// Content-Length + Accept-Ranges: bytes + 206 Partial Content for head / middle / tail ranges,
// over both http and https, with a Referer header. That makes byte-range streaming possible.
//
// Both classes below keep a bounded amount of data in memory regardless of file size:
//  - StreamingAudioSource: <= 16 MB LRU block cache + <= 4 MB in-flight range for AVPlayer.dataSrc
//  - StreamingDownload: one network chunk at a time, written straight to the destination file

const BLOCK_SIZE: number = 128 * 1024
const WINDOW_BLOCKS: number = 32          // 4 MB per Range request
const MAX_BLOCKS: number = 128            // 16 MB resident ceiling
const PRELOAD_BLOCKS: number = 16         // 2 MB head before AVPlayer.prepare()
const TAIL_BLOCKS: number = 2             // 256 KB tail, some demuxers probe the end
const PREFETCH_MARGIN: number = 1024 * 1024
const STALL_LIMIT: number = 3
const REFERER: string = 'https://music.163.com/'

// Audio CDN URLs are handed out as http://. TLS works on the same object path and avoids
// cleartext restrictions in the media/network stacks; private or non-CDN URLs stay untouched.
export function secureAudioUrl(url: string): string {
  if (!url.startsWith('http://')) { return url }
  const rest = url.substring(7)
  const slash = rest.indexOf('/')
  const host = slash < 0 ? rest : rest.substring(0, slash)
  if (host === 'music.126.net' || host.endsWith('.music.126.net')) {
    return `https://${rest}`
  }
  return url
}

function streamHeaders(range?: string): Record<string, string> {
  const headers: Record<string, string> = {
    'Referer': REFERER,
    // Byte offsets must match the on-disk object exactly, so no transparent compression.
    'Accept-Encoding': 'identity'
  }
  if (range !== undefined) { headers['Range'] = range }
  return headers
}

interface InflightRange {
  from: number
  to: number
  cancel: () => void
}

/**
 * Range-backed data source for AVPlayer.dataSrc. The demuxer asks for arbitrary byte
 * windows via callback(buffer, length, pos); this class serves them from a bounded
 * block cache and fetches missing windows on demand with HTTP Range requests.
 * 0 is returned while a window is still downloading (AVPlayer retries the callback),
 * -1 at EOF and -2 on an unrecoverable error, per AVDataSrcDescriptor semantics.
 */
export class StreamingAudioSource {
  readonly size: number
  private url: string
  private blocks: Map<number, Uint8Array> = new Map()
  private order: number[] = []
  private fetched: Set<number> = new Set()
  private frontier: number = -1
  private inflight?: InflightRange
  private position: number = 0
  private cancelled: boolean = false
  private failed: boolean = false
  private lastError: string = ''
  private stalls: number = 0
  private totalFetched: number = 0
  private requests: number = 0

  constructor(url: string, size: number) {
    this.url = secureAudioUrl(url)
    this.size = Math.floor(size)
  }

  stats(): string {
    return `fileSize=${this.size} residentBytes=${this.blocks.size * BLOCK_SIZE} fetchedBytes=${this.totalFetched} ranges=${this.requests}`
  }

  private putBlock(index: number, data: Uint8Array): void {
    if (this.cancelled) { return }
    if (!this.blocks.has(index)) {
      this.blocks.set(index, data)
      this.order.push(index)
      while (this.order.length > MAX_BLOCKS) {
        const oldest: number = this.order[0]
        this.order.splice(0, 1)
        this.blocks.delete(oldest)
      }
    }
    this.fetched.add(index)
    // Only advance the sequential frontier across contiguous, already-fetched blocks.
    while (this.fetched.has(this.frontier + 1)) { this.frontier++ }
  }

  private startFetch(startBlock: number, blockCount: number): void {
    if (this.cancelled || this.failed || this.inflight) { return }
    const from: number = startBlock * BLOCK_SIZE
    if (from >= this.size) { return }
    const to: number = Math.min(this.size, from + blockCount * BLOCK_SIZE) - 1
    if (to < from) { return }
    const client = http.createHttp()
    const pending: Map<number, Uint8Array> = new Map()
    let writePos: number = from
    let settled: boolean = false
    let timer: number = -1
    this.requests++

    const finish = (): void => {
      if (settled) { return }
      settled = true
      if (this.inflight && this.inflight.from === from && this.inflight.to === to) {
        this.inflight = undefined
      }
      if (timer !== -1) { clearTimeout(timer); timer = -1 }
      try { client.destroy() } catch (_error) {}
    }
    const fail = (message: string): void => {
      if (settled) { return }
      this.failed = true
      this.lastError = message
      pending.clear()
      finish()
    }

    this.inflight = { from: from, to: to, cancel: (): void => { finish() } }
    timer = setTimeout(() => fail('音频分段加载超时，请重试'), 60000)
    client.on('dataReceive', (data: ArrayBuffer) => {
      if (settled || this.cancelled || data.byteLength === 0) { return }
      const bytes = new Uint8Array(data)
      let cursor = 0
      while (cursor < bytes.length && writePos <= to) {
        const index = Math.floor(writePos / BLOCK_SIZE)
        const offset = writePos - index * BLOCK_SIZE
        const blockLength = Math.min(BLOCK_SIZE, this.size - index * BLOCK_SIZE)
        let target = pending.get(index)
        if (!target) {
          target = new Uint8Array(blockLength)
          pending.set(index, target)
        }
        const take = Math.min(blockLength - offset, bytes.length - cursor, to - writePos + 1)
        if (take <= 0) { break }
        target.set(bytes.subarray(cursor, cursor + take), offset)
        cursor += take
        writePos += take
      }
    })
    client.requestInStream(this.url, {
      method: http.RequestMethod.GET,
      header: streamHeaders(`bytes=${from}-${to}`),
      connectTimeout: 15000,
      readTimeout: 60000,
      usingCache: false
    }).then((code: number) => {
      if (settled || this.cancelled) { pending.clear(); return }
      // A 200 here means the server ignored Range. Only byte 0 ranges are still usable.
      if (code !== 206 && !(code === 200 && from === 0)) {
        fail(`音频分段加载失败 (${code})，服务器可能不支持 Range 请求`)
        return
      }
      if (writePos <= to) {
        this.stalls++
        if (this.stalls >= STALL_LIMIT) { fail('音频分段数据不完整，请重试'); return }
        pending.clear()
        finish()
        return
      }
      this.stalls = 0
      pending.forEach((block: Uint8Array, index: number) => {
        this.totalFetched += block.byteLength
        this.putBlock(index, block)
      })
      pending.clear()
      finish()
    }).catch((error: Error) => fail(error.message))
  }

  private async fetchAndWait(startBlock: number, blockCount: number): Promise<void> {
    this.startFetch(startBlock, blockCount)
    let guard = 0
    while (this.inflight && !this.cancelled && !this.failed && guard < 3000) {
      await StreamingAudioSource.sleep(10)
      guard++
    }
    if (this.cancelled) { throw new Error('音频加载已取消') }
    if (this.failed) { throw new Error(this.lastError || '音频分段加载失败') }
    if (guard >= 3000) { throw new Error('音频分段加载超时，请重试') }
  }

  private static sleep(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds)
    })
  }

  /** Pull the head (and tail) so AVPlayer.prepare() never has to wait on its first reads. */
  async preload(): Promise<void> {
    if (this.size <= 0) { throw new Error('音频文件大小未知，无法流式加载') }
    await this.fetchAndWait(0, PRELOAD_BLOCKS)
    const tailStart = Math.floor((this.size - 1) / BLOCK_SIZE) - TAIL_BLOCKS + 1
    if (tailStart > PRELOAD_BLOCKS) {
      await this.fetchAndWait(tailStart, TAIL_BLOCKS)
    }
  }

  private ensureFetch(blockIndex: number): void {
    if (this.cancelled || this.failed) { return }
    const active = this.inflight
    if (active) {
      const first = Math.floor(active.from / BLOCK_SIZE)
      const last = Math.floor(active.to / BLOCK_SIZE)
      if (blockIndex >= first && blockIndex <= last) { return }
      // A seek landed outside the current window: abandon it and fetch the new position.
      active.cancel()
    }
    this.startFetch(blockIndex, WINDOW_BLOCKS)
  }

  private prefetchAhead(pos: number): void {
    if (this.inflight || this.cancelled || this.failed) { return }
    let next = this.frontier + 1
    while (this.fetched.has(next) && next * BLOCK_SIZE < this.size) { next++ }
    const nextOffset = next * BLOCK_SIZE
    if (nextOffset >= this.size || nextOffset - pos >= PREFETCH_MARGIN) { return }
    this.startFetch(next, WINDOW_BLOCKS)
  }

  private read(buffer: ArrayBuffer, length: number, pos?: number): number {
    if (this.cancelled || this.failed) { return -2 }
    const start = pos === undefined ? this.position : pos
    if (!Number.isInteger(start) || start < 0 || !Number.isInteger(length) || length < 0) { return -2 }
    if (start >= this.size) { return -1 }
    const count = Math.min(length, buffer.byteLength, this.size - start)
    if (count <= 0) { return 0 }
    const first = Math.floor(start / BLOCK_SIZE)
    const last = Math.floor((start + count - 1) / BLOCK_SIZE)
    const target = new Uint8Array(buffer)
    let filled = 0
    // Serve the contiguous cached prefix. A short read is a normal streaming
    // result; AVPlayer asks for the remainder on the next callback. This avoids
    // returning 0 (no data) unless the very first block is still downloading.
    for (let i = first; i <= last; i++) {
      const block = this.blocks.get(i)
      if (!block) { this.ensureFetch(i); break }
      const blockStart = i * BLOCK_SIZE
      const offsetInBlock = Math.max(0, start - blockStart)
      const available = Math.min(block.length - offsetInBlock, count - filled)
      if (available <= 0) { break }
      target.set(block.subarray(offsetInBlock, offsetInBlock + available), filled)
      filled += available
    }
    if (filled === 0) { return 0 }
    this.position = start + filled
    this.prefetchAhead(this.position)
    return filled
  }

  descriptor(): media.AVDataSrcDescriptor {
    return {
      fileSize: this.size,
      callback: (buffer: ArrayBuffer, length: number, pos?: number): number => this.read(buffer, length, pos)
    }
  }

  cancel(): void {
    if (this.cancelled) { return }
    this.cancelled = true
    this.inflight?.cancel()
    this.inflight = undefined
    this.blocks.clear()
    this.order = []
    this.fetched.clear()
  }
}

/** Chunked HTTP download that writes straight into an already-open destination fd. */
export class StreamingDownload {
  private cancelRequest?: () => void
  private cancelled: boolean = false

  cancel(): void {
    this.cancelled = true
    this.cancelRequest?.()
    this.cancelRequest = undefined
  }

  /** Read only the first bytes via Range, so the container can be sniffed without a full download. */
  static async probe(url: string, bytes: number = 64): Promise<Uint8Array> {
    const client = http.createHttp()
    let timer: number = -1
    try {
      return await new Promise<Uint8Array>((resolve, reject) => {
        const chunks: Uint8Array[] = []
        let received = 0
        let settled = false
        const fail = (error: Error): void => {
          if (settled) { return }
          settled = true
          reject(error)
        }
        timer = setTimeout(() => fail(new Error('音频头探测超时，请重试')), 20000)
        client.on('dataReceive', (data: ArrayBuffer) => {
          if (settled || received >= bytes || data.byteLength === 0) { return }
          const take = Math.min(bytes - received, data.byteLength)
          chunks.push(new Uint8Array(data, 0, take))
          received += take
        })
        client.requestInStream(secureAudioUrl(url), {
          method: http.RequestMethod.GET,
          header: streamHeaders(`bytes=0-${bytes - 1}`),
          connectTimeout: 15000,
          readTimeout: 30000,
          usingCache: false
        }).then((code: number) => {
          if (settled) { return }
          if (code !== 206) { fail(new Error(`音频头探测失败 (${code})`)); return }
          const result = new Uint8Array(received)
          let offset = 0
          for (let i = 0; i < chunks.length; i++) {
            result.set(chunks[i], offset)
            offset += chunks[i].byteLength
          }
          settled = true
          resolve(result)
        }).catch((error: Error) => fail(error))
      })
    } finally {
      if (timer !== -1) { clearTimeout(timer) }
      client.destroy()
    }
  }

  /** Streams the full body into fd, one chunk at a time. Resolves with the byte count. */
  async run(url: string, fd: number, expectedSize: number,
    onProgress?: (received: number, total: number) => void): Promise<number> {
    if (this.cancelled) { throw new Error('下载已取消') }
    const client = http.createHttp()
    let timer: number = -1
    try {
      return await new Promise<number>((resolve, reject) => {
        let received = 0
        let settled = false
        const fail = (error: Error): void => {
          if (settled) { return }
          settled = true
          reject(error)
        }
        this.cancelRequest = (): void => fail(new Error('下载已取消'))
        timer = setTimeout(() => fail(new Error('下载超时，请重试')), 300000)
        client.on('dataReceive', (data: ArrayBuffer) => {
          if (settled || this.cancelled || data.byteLength === 0) { return }
          try {
            // Explicit absolute file offset: no dependency on the fd's implicit cursor.
            const written = fileIo.writeSync(fd, data, { offset: received, length: data.byteLength })
            received += written
            if (onProgress) { onProgress(received, expectedSize) }
          } catch (error) {
            fail(new Error(`写入音频文件失败：${error instanceof Error ? error.message : '未知错误'}`))
          }
        })
        client.requestInStream(secureAudioUrl(url), {
          method: http.RequestMethod.GET,
          header: streamHeaders(),
          connectTimeout: 15000,
          readTimeout: 60000,
          usingCache: false
        }).then((code: number) => {
          if (settled) { return }
          if (code !== 200 && code !== 206) { fail(new Error(`音频下载失败 (${code})`)); return }
          if (received === 0 || (expectedSize > 0 && received !== expectedSize)) {
            fail(new Error('音频文件下载不完整，请重试'))
            return
          }
          settled = true
          resolve(received)
        }).catch((error: Error) => fail(error))
      })
    } finally {
      if (timer !== -1) { clearTimeout(timer) }
      this.cancelRequest = undefined
      client.destroy()
    }
  }
}
