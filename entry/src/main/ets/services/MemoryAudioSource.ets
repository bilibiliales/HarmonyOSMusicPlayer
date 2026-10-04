import { http } from '@kit.NetworkKit'
import { media } from '@kit.MediaKit'

// Retain the complete compressed file in chunks, avoiding a second full-size FLAC allocation.
export class MemoryAudioSource {
  private chunks: Uint8Array[]
  private offsets: number[] = []
  private position: number = 0
  readonly size: number

  constructor(chunks: Uint8Array[]) {
    this.chunks = chunks
    let size = 0
    for (let i = 0; i < chunks.length; i++) {
      this.offsets.push(size)
      size += chunks[i].byteLength
    }
    this.size = size
  }

  read(buffer: ArrayBuffer, length: number, pos?: number): number {
    const start = pos === undefined ? this.position : pos
    if (!Number.isInteger(start) || start < 0 || !Number.isInteger(length) || length < 0) { return -2 }
    if (start >= this.size) { return -1 }
    const count = Math.min(length, buffer.byteLength, this.size - start)
    const target = new Uint8Array(buffer)
    let low = 0
    let high = this.offsets.length - 1
    while (low < high) {
      const mid = Math.ceil((low + high) / 2)
      if (this.offsets[mid] <= start) { low = mid } else { high = mid - 1 }
    }
    let copied = 0
    for (let i = low; i < this.chunks.length && copied < count; i++) {
      const offset = Math.max(0, start - this.offsets[i])
      const take = Math.min(this.chunks[i].length - offset, count - copied)
      target.set(this.chunks[i].subarray(offset, offset + take), copied)
      copied += take
    }
    this.position = start + copied
    return copied
  }

  descriptor(): media.AVDataSrcDescriptor {
    return { fileSize: this.size,
      callback: (buffer: ArrayBuffer, length: number, pos?: number): number => this.read(buffer, length, pos) }
  }
}

export class MemoryAudioLoad {
  private cancelRequest?: () => void
  private cancelled: boolean = false

  cancel(): void {
    this.cancelled = true
    this.cancelRequest?.()
  }

  async load(url: string, expectedSize: number = 0): Promise<MemoryAudioSource> {
    if (this.cancelled) { throw new Error('音频加载已取消') }
    const client = http.createHttp()
    let timer: number = -1
    try {
      return await new Promise<MemoryAudioSource>((resolve, reject) => {
        let chunks: Uint8Array[] = []
        let received = 0
        let total = 0
        let status = 0
        let ended = false
        let settled = false
        const fail = (error: Error): void => {
          if (settled) { return }
          settled = true
          chunks = []
          reject(error)
        }
        const finish = (): void => {
          if (settled || !ended || status === 0) { return }
          const expected = total > 0 ? total : expectedSize
          if (received === 0 || (expected > 0 && received !== expected)) {
            fail(new Error('音频文件未完整加载，请重试'))
            return
          }
          settled = true
          resolve(new MemoryAudioSource(chunks))
          chunks = []
        }
        this.cancelRequest = (): void => fail(new Error('音频加载已取消'))
        timer = setTimeout(() => fail(new Error('音频加载超时，请重试')), 300000)
        client.on('dataReceive', (data: ArrayBuffer) => {
          if (settled || data.byteLength === 0) { return }
          chunks.push(new Uint8Array(data))
          received += data.byteLength
        })
        client.on('dataReceiveProgress', (progress: http.DataReceiveProgressInfo) => {
          if (progress.totalSize > 0) { total = progress.totalSize }
        })
        client.on('dataEnd', () => { ended = true; finish() })
        client.requestInStream(url, {
          method: http.RequestMethod.GET,
          header: { 'Referer': 'https://music.163.com/', 'Accept-Encoding': 'identity' },
          connectTimeout: 15000, readTimeout: 60000, usingCache: false
        }).then((code: number) => {
          if (code !== 200) { fail(new Error(`音频加载失败 (${code})`)); return }
          status = code
          finish()
        }).catch((error: Error) => fail(error))
      })
    } finally {
      if (timer !== -1) { clearTimeout(timer) }
      this.cancelRequest = undefined
      client.destroy()
    }
  }
}
