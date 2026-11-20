import { webview } from '@kit.ArkWeb'
import { util } from '@kit.ArkTS'

/** 每次从 ArkTS 交给网页的 base64 分片长度，避免单次字符串过大。 */
const PCM_CHUNK_SIZE: number = 32000
/** 音频文件体积大，分片放宽到 64KB，减少往返次数。 */
const FILE_CHUNK_SIZE: number = 64000
/** 一次指纹计算的总超时（含引擎就绪等待）。 */
const GENERATE_TIMEOUT_MS: number = 15000
/** 音频文件还要额外解码，给更长的上限。 */
const FILE_TIMEOUT_MS: number = 30000
/** 等待引擎就绪的超时。 */
const READY_TIMEOUT_MS: number = 8000

/** 任务类型：引擎侧据此区分「已经是 8kHz PCM」和「需要自己解码的音频文件」。 */
const KIND_PCM: number = 0
const KIND_FILE: number = 1

/**
 * 音频指纹引擎（WebAssembly 版）。
 *
 * ArkTS 的 JS 运行时没有 WebAssembly，把官方 wasm 用 binaryen 转成纯 JS 后，
 * embind 的 std::string 类型注册在 ArkTS 引擎里会失败（调用时报 unbound types）。
 * 所以这里把官方的 afp.js + afp.wasm.js 原样内联成一个离线页面，放在隐藏的
 * Web 组件里跑 —— 与官方 demo 完全一致的执行环境，WebAssembly 可用。
 *
 * 数据通路：ArkTS 把 PCM 或音频文件转 base64 切片放进队列，网页每 10ms 轮询一次
 * 取走（poll 返回 S/C/E 或 F/G/H），算完通过 onFp 回传指纹。
 * 这样不需要 runJavaScript 传大字符串，也不受其签名差异影响。
 */
export class AudioFingerprintWeb {
  private ready: boolean = false
  private job: string[] = []
  private cursor: number = 0
  private started: boolean = false
  private kind: number = KIND_PCM
  private resolveFn?: (value: string) => void
  private rejectFn?: (error: Error) => void
  private timeoutId: number = -1

  /** 网页加载完成、且预热成功后由页面调用。 */
  onReady(): void {
    this.ready = true
  }

  /** 网页回传指纹（base64）。 */
  onFp(fp: string): void {
    const resolve = this.resolveFn
    this.clearPending()
    if (resolve) {
      resolve(fp)
    }
  }

  /** 网页报告错误。 */
  onError(message: string): void {
    const reject = this.rejectFn
    this.clearPending()
    if (reject) {
      reject(new Error(message.length > 0 ? message : '指纹引擎异常'))
    }
  }

  /**
   * 网页轮询取数据。
   * 返回 '' 表示空闲；S/C/E 为 PCM 通道（首片/续片/结束）；
   * F/G/H 为音频文件通道（首片/续片/结束）。
   */
  poll(): string {
    if (!this.started || this.job.length === 0) {
      return ''
    }
    const isFile = this.kind === KIND_FILE
    if (this.cursor === 0) {
      const first = this.job[0]
      this.cursor = 1
      return (isFile ? 'F' : 'S') + first
    }
    if (this.cursor < this.job.length) {
      const chunk = this.job[this.cursor]
      this.cursor = this.cursor + 1
      return (isFile ? 'G' : 'C') + chunk
    }
    this.started = false
    this.job = []
    this.cursor = 0
    return isFile ? 'H' : 'E'
  }

  isReady(): boolean {
    return this.ready
  }

  /** 用网页引擎对 8kHz 单声道 Float32 PCM 生成 base64 指纹。 */
  async generate(pcm: Float32Array): Promise<string> {
    if (this.isBusy()) {
      throw new Error('指纹引擎正忙，请稍后再试')
    }
    await this.waitReady()
    const samples = new Float32Array(pcm.length)
    samples.set(pcm)
    const bytes = new Uint8Array(samples.buffer)
    const encoded = new util.Base64Helper().encodeToStringSync(bytes)
    return this.enqueue(encoded, KIND_PCM, GENERATE_TIMEOUT_MS)
  }

  /**
   * 直接对一段音频文件（mp3 / aac / wav / flac / ogg）生成指纹：
   * 解码、混单声道、重采样到 8kHz、挑一段 3 秒，全部由网页里的浏览器能力完成。
   */
  async generateFromFile(bytes: Uint8Array): Promise<string> {
    if (this.isBusy()) {
      throw new Error('指纹引擎正忙，请稍后再试')
    }
    if (bytes.length === 0) {
      throw new Error('音频文件是空的')
    }
    await this.waitReady()
    const encoded = new util.Base64Helper().encodeToStringSync(bytes)
    return this.enqueue(encoded, KIND_FILE, FILE_TIMEOUT_MS)
  }

  private isBusy(): boolean {
    return this.started || this.resolveFn !== undefined
  }

  private enqueue(encoded: string, kind: number, timeoutMs: number): Promise<string> {
    const chunkSize = kind === KIND_FILE ? FILE_CHUNK_SIZE : PCM_CHUNK_SIZE
    const chunks: string[] = []
    let offset = 0
    while (offset < encoded.length) {
      chunks.push(encoded.substring(offset, offset + chunkSize))
      offset = offset + chunkSize
    }
    this.job = chunks
    this.cursor = 0
    this.kind = kind
    this.started = true
    return new Promise<string>((resolve, reject) => {
      this.resolveFn = resolve
      this.rejectFn = reject
      this.timeoutId = setTimeout(() => {
        this.clearPending()
        reject(new Error(kind === KIND_FILE ? '分析音频文件超时，请换一个更短的文件' : '指纹计算超时，请重试'))
      }, timeoutMs)
    })
  }

  /** 等网页引擎预热完成；超时抛错，由页面决定是否退回原生实现。 */
  private async waitReady(): Promise<void> {
    const deadline = Date.now() + READY_TIMEOUT_MS
    while (!this.ready) {
      if (Date.now() > deadline) {
        throw new Error('指纹引擎启动失败，请重试')
      }
      await new Promise<void>((resolve) => {
        setTimeout(() => resolve(), 50)
      })
    }
  }

  private clearPending(): void {
    if (this.timeoutId >= 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = -1
    }
    this.resolveFn = undefined
    this.rejectFn = undefined
    this.started = false
    this.job = []
    this.cursor = 0
  }
}

/** 隐藏 Web 组件与引擎实例的持有者，页面只依赖它。 */
export class AudioFingerprintHost {
  readonly controller: webview.WebviewController = new webview.WebviewController()
  readonly engine: AudioFingerprintWeb = new AudioFingerprintWeb()
}
