import { common } from '@kit.AbilityKit'
import { ringtone } from '@kit.RingtoneKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { AudioFileFormat } from './AudioFileFormat'
import { AudioMetadata } from './AudioMetadata'
import { SongQualityService } from './SongQualityService'
import { StreamingDownload } from './StreamingAudio'
import { QualityOption, songItemType } from '../models/music'

/** 页面上的四种铃声类型顺序：闹钟、短信、通知、来电。 */
export const RINGTONE_TYPE_ORDER: number[] = [ringtone.RingtoneType.ALARM, ringtone.RingtoneType.MESSAGE,
  ringtone.RingtoneType.NOTIFICATION, ringtone.RingtoneType.CALL]
export const RINGTONE_TYPE_TITLES: string[] = ['闹钟铃声', '短信铃声', '通知铃声', '来电铃声']
/** 接口不可用时的兜底时长（秒），与系统约定一致。 */
const RINGTONE_FALLBACK_SECONDS: number[] = [300, 7, 7, 60]
/** 铃声对容器格式有要求，实际可裁剪的是 MP3 帧序列。 */
const SUPPORTED_LEVELS: string[] = ['standard', 'higher', 'exhigh']

export interface RingtoneAudio {
  path: string
  durationMs: number
}

export interface RingtoneClipResult {
  path: string
  durationMs: number
}

interface Mp3FrameHead {
  length: number
  sampleRate: number
  samples: number
}

const MP3_BITRATES_V1: number[] = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
const MP3_BITRATES_V2: number[] = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]
const MP3_RATES_V1: number[] = [44100, 48000, 32000, 0]
const MP3_RATES_V2: number[] = [22050, 24000, 16000, 0]
const MP3_RATES_V25: number[] = [11025, 12000, 8000, 0]

export class RingtoneService {
  /** 各铃声类型支持的 MP3 最大时长（秒），接口异常时退化为系统约定值。 */
  static maxSeconds(index: number): number {
    const clamped = Math.min(RINGTONE_TYPE_ORDER.length - 1, Math.max(0, index))
    const type = RINGTONE_TYPE_ORDER[clamped]
    try {
      let dataType: uniformTypeDescriptor.UniformDataType = uniformTypeDescriptor.UniformDataType.MP3
      const supported = ringtone.getSupportedDataTypes(type)
      if (supported.length > 0 && !supported.includes(dataType)) {
        dataType = supported[0]
      }
      const value = ringtone.getSupportedMaxDuration(type, dataType)
      if (value > 0) { return Math.round(value) }
    } catch (_error) {
    }
    return RINGTONE_FALLBACK_SECONDS[clamped]
  }

  /** 只保留能拿到 MP3 的音质档位：无损及以上是 FLAC，无法做帧级裁剪。 */
  static async availableQualities(song: songItemType): Promise<QualityOption[]> {
    if (song.localUri) {
      return [{ level: 'local', title: '本地文件', description: '使用本地音频原文件' }]
    }
    const all = await SongQualityService.available(song.id)
    const result: QualityOption[] = []
    for (let i = 0; i < all.length; i++) {
      if (SUPPORTED_LEVELS.includes(all[i].level)) { result.push(all[i]) }
    }
    return result.length > 0 ? result : all.slice(0, 1)
  }

  private static extensionOf(name: string): string {
    const dot = name.lastIndexOf('.')
    return dot >= 0 ? name.slice(dot + 1).toLowerCase() : ''
  }

  private static async ensureDirectory(context: common.UIAbilityContext): Promise<string> {
    const dir = `${context.cacheDir}/ringtone`
    try {
      fileIo.mkdirSync(dir, true)
    } catch (_error) {
    }
    return dir
  }

  private static async copyInto(srcFd: number, dstFd: number): Promise<number> {
    const chunk = new ArrayBuffer(256 * 1024)
    let total = 0
    while (true) {
      const count = fileIo.readSync(srcFd, chunk)
      if (count <= 0) { break }
      fileIo.writeSync(dstFd, chunk.slice(0, count))
      total += count
    }
    return total
  }

  private static toPath(value: string): string {
    return value.startsWith('file://') ? new fileUri.FileUri(value).path : value
  }

  /** 把音频落到沙箱并读出真实时长。level 为 'local' 时直接用本地文件。 */
  static async prepare(context: common.UIAbilityContext, song: songItemType, level: string,
    onProgress?: (percent: number) => void): Promise<RingtoneAudio> {
    const dir = await RingtoneService.ensureDirectory(context)
    let path = ''
    if (level === 'local' || song.localUri) {
      const uri = song.localUri || ''
      if (!uri) { throw new Error('本地音频地址无效') }
      if (RingtoneService.extensionOf(uri) !== 'mp3') {
        throw new Error('铃声裁剪目前只支持 MP3 音频')
      }
      path = `${dir}/local_${Date.now()}.mp3`
      const src = fileIo.openSync(RingtoneService.toPath(uri), fileIo.OpenMode.READ_ONLY)
      const dst = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        await RingtoneService.copyInto(src.fd, dst.fd)
      } finally {
        fileIo.closeSync(src)
        fileIo.closeSync(dst)
      }
    } else {
      const resource = await SongQualityService.download(song.id, level)
      const header = await StreamingDownload.probe(resource.url, 64)
      const extension = AudioFileFormat.extension(resource.url, resource.type, resource.encodeType, header)
      if (extension !== 'mp3') {
        throw new Error('该音质不是 MP3，无法裁剪为铃声，请换一个音质')
      }
      const destPath = `${dir}/src_${song.id}_${level}_${Date.now()}.mp3`
      const file = fileIo.openSync(destPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        const task = new StreamingDownload()
        await task.run(resource.url, file.fd, resource.size, (received: number, total: number): void => {
          if (onProgress && total > 0) { onProgress(Math.min(99, Math.floor(received * 100 / total))) }
        })
      } finally {
        fileIo.closeSync(file)
      }
      if (onProgress) { onProgress(100) }
      path = destPath
    }
    const durationMs = await RingtoneService.durationOf(path)
    if (durationMs <= 0) { throw new Error('无法读取音频时长') }
    return { path: path, durationMs: durationMs }
  }

  private static async durationOf(path: string): Promise<number> {
    let fd = -1
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      fd = file.fd
      const stat = fileIo.statSync(path)
      const metadata = await AudioMetadata.read(fd, stat.size)
      const value = Number(metadata.duration || '0')
      return Number.isFinite(value) ? value : 0
    } catch (_error) {
      return 0
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd)
        } catch (_error) {
        }
      }
    }
  }

  /** 逐块统计压缩数据的能量包络，用于绘制可拖动的波形条。 */
  static async waveform(path: string, buckets: number): Promise<number[]> {
    const count = Math.max(8, buckets)
    const result: number[] = []
    for (let i = 0; i < count; i++) { result.push(0) }
    let fd = -1
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      fd = file.fd
      const stat = fileIo.statSync(path)
      const size = stat.size
      if (size <= 0) { return result }
      const chunk = new ArrayBuffer(512 * 1024)
      let position = 0
      while (true) {
        const read = fileIo.readSync(fd, chunk)
        if (read <= 0) { break }
        const bytes = new Uint8Array(chunk, 0, read)
        for (let i = 0; i < read; i++) {
          const index = Math.min(count - 1, Math.floor((position + i) * count / size))
          const energy = Math.abs(bytes[i] - 128)
          if (energy > result[index]) { result[index] = energy }
        }
        position += read
      }
    } catch (_error) {
      return result
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd)
        } catch (_error) {
        }
      }
    }
    const smoothed: number[] = []
    for (let i = 0; i < count; i++) {
      const left = result[Math.max(0, i - 1)]
      const right = result[Math.min(count - 1, i + 1)]
      smoothed.push(Math.round((result[i] * 2 + left + right) / 4))
    }
    let peak = 1
    for (let i = 0; i < smoothed.length; i++) {
      if (smoothed[i] > peak) { peak = smoothed[i] }
    }
    return smoothed.map((value: number) => Math.max(0.14, Math.min(1, value / peak)))
  }

  private static headAt(bytes: Uint8Array, pos: number): Mp3FrameHead {
    const head: Mp3FrameHead = { length: -1, sampleRate: 0, samples: 0 }
    if (pos + 4 > bytes.length) { return head }
    if (bytes[pos] !== 0xFF || (bytes[pos + 1] & 0xE0) !== 0xE0) { return head }
    const b1 = bytes[pos + 1]
    const b2 = bytes[pos + 2]
    const version = (b1 >> 3) & 0x03
    const layer = (b1 >> 1) & 0x03
    if (version === 0x01 || layer !== 0x01) { return head }
    const mpeg1 = version === 0x03
    const bitrateIndex = (b2 >> 4) & 0x0F
    const rateIndex = (b2 >> 2) & 0x03
    const padding = (b2 >> 1) & 0x01
    if (bitrateIndex === 0x0F || rateIndex === 0x03) { return head }
    const bitrate = (mpeg1 ? MP3_BITRATES_V1[bitrateIndex] : MP3_BITRATES_V2[bitrateIndex]) * 1000
    const sampleRate = mpeg1 ? MP3_RATES_V1[rateIndex] :
      (version === 0x02 ? MP3_RATES_V2[rateIndex] : MP3_RATES_V25[rateIndex])
    if (bitrate <= 0 || sampleRate <= 0) { return head }
    head.sampleRate = sampleRate
    head.samples = mpeg1 ? 1152 : 576
    head.length = Math.floor((mpeg1 ? 144 : 72) * bitrate / sampleRate) + padding
    return head
  }

  private static readAll(fd: number, size: number): Uint8Array {
    const buffer = new ArrayBuffer(size)
    let offset = 0
    while (offset < size) {
      const count = fileIo.readSync(fd, buffer, { offset: offset, length: size - offset })
      if (count <= 0) { break }
      offset += count
    }
    return new Uint8Array(buffer, 0, offset)
  }

  /**
   * 帧级裁剪：按整帧边界取出 [startMs, endMs) 的 MP3 字节，直接在内存里返回，
   * 不写文件。预览播放用这份数据（AVPlayer.dataSrc），保存/设铃声再落盘。
   */
  static clipBytes(srcPath: string, startMs: number, endMs: number): ArrayBuffer {
    let srcFd = -1
    try {
      const file = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY)
      srcFd = file.fd
      const size = fileIo.statSync(srcPath).size
      if (size <= 0) { return new ArrayBuffer(0) }
      const bytes = RingtoneService.readAll(srcFd, size)
      const read = bytes.length
      if (read <= 0) { return new ArrayBuffer(0) }

      // 跳过 ID3v2 标签（十年内所有主流编码器都会写）
      let pos = 0
      if (read > 10 && bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) {
        const tagSize = ((bytes[6] & 0x7F) << 21) | ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) | (bytes[9] & 0x7F)
        pos = 10 + tagSize
      }

      let elapsedSamples = 0
      let startOffset = -1
      let endOffset = -1
      while (pos + 4 <= read) {
        const head = RingtoneService.headAt(bytes, pos)
        if (head.length <= 0 || pos + head.length > read) { break }
        const timeMs = head.sampleRate > 0 ? elapsedSamples * 1000 / head.sampleRate : 0
        if (startOffset < 0 && timeMs >= startMs) { startOffset = pos }
        if (timeMs >= endMs) {
          endOffset = pos
          break
        }
        elapsedSamples += head.samples
        pos += head.length
      }
      if (startOffset < 0) { return new ArrayBuffer(0) }
      if (endOffset < 0 || endOffset <= startOffset) { endOffset = read }
      return bytes.buffer.slice(startOffset, endOffset)
    } catch (_error) {
      return new ArrayBuffer(0)
    } finally {
      if (srcFd >= 0) {
        try {
          fileIo.closeSync(srcFd)
        } catch (_error) {
        }
      }
    }
  }

  /** 把内存裁剪结果写成文件，供「保存音频 / 设为铃声」使用。 */
  static trim(srcPath: string, dstPath: string, startMs: number, endMs: number): boolean {
    const slice = RingtoneService.clipBytes(srcPath, startMs, endMs)
    if (slice.byteLength <= 0) { return false }
    try {
      const dst = fileIo.openSync(dstPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(dst.fd, slice)
      } finally {
        fileIo.closeSync(dst)
      }
      return true
    } catch (_error) {
      return false
    }
  }

  /** 生成裁剪结果文件，返回沙箱路径（file:// URI）。 */
  static async renderClip(context: common.UIAbilityContext, srcPath: string, startMs: number,
    endMs: number): Promise<RingtoneClipResult> {
    const dir = await RingtoneService.ensureDirectory(context)
    const destPath = `${dir}/clip_${Date.now()}.mp3`
    const ok = RingtoneService.trim(srcPath, destPath, startMs, endMs)
    if (!ok) { throw new Error('裁剪失败，请调整开始/结束位置后重试') }
    return { path: destPath, durationMs: Math.max(0, endMs - startMs) }
  }

  static safeName(value: string): string {
    return (value || '铃声').replace(/[\\/:*?"<>|]+/g, '_').replace(/\s+/g, '_').slice(0, 40)
  }

  /** 另存为：交给系统文件选择器，用户可存到下载目录或任意位置。 */
  static async saveCopy(context: common.UIAbilityContext, srcPath: string, fileName: string): Promise<string> {
    const options = new picker.DocumentSaveOptions()
    options.newFileNames = [fileName]
    const uris = await new picker.DocumentViewPicker(context).save(options)
    if (!uris.length) { return '' }
    const src = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY)
    const dst = fileIo.openSync(uris[0],
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      await RingtoneService.copyInto(src.fd, dst.fd)
    } finally {
      fileIo.closeSync(src)
      fileIo.closeSync(dst)
    }
    return fileName
  }

  /** 拉起系统铃声设置面板，返回用户在面板中选择的铃声类型。 */
  static async apply(context: common.UIAbilityContext, path: string, fileName: string): Promise<number> {
    try {
      const chosen = await ringtone.startRingtoneSetting(context, path, fileName)
      return chosen
    } catch (error) {
      const message = error instanceof Error ? error.message : '设置铃声失败'
      throw new Error(message)
    }
  }

  static typeTitle(value: number): string {
    const index = RINGTONE_TYPE_ORDER.indexOf(value)
    return index >= 0 ? RINGTONE_TYPE_TITLES[index] : '铃声'
  }
}
