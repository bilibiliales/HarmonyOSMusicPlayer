import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { systemShare, harmonyShare } from '@kit.ShareKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { http } from '@kit.NetworkKit'
import { image } from '@kit.ImageKit'
import { SharePageParam } from '../models/api'
import { resizeImageUrl } from './ImageUrl'

export interface ShareLink {
  url: string
  title: string
  description: string
  label: string
  image?: string
}

export interface ShareText {
  content: string
  title: string
  description: string
  label: string
  image?: string
}

export class SystemShareService {
  static readonly MAX_RECORDS: number = 500
  static readonly MAX_BYTES: number = 200 * 1024
  private static abilityContext?: common.UIAbilityContext
  private static launching: boolean = false

  static bindAbility(context: common.UIAbilityContext): void {
    SystemShareService.abilityContext = context
  }

  static unbindAbility(): void {
    SystemShareService.abilityContext = undefined
  }

  // Count UTF-8 directly: platform TextEncoder implementations may return undefined
  // for an empty string. Optional share descriptions are commonly empty.
  static utf8ByteLength(value: string): number {
    let bytes = 0
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index)
      if (code <= 0x7f) { bytes += 1 }
      else if (code <= 0x7ff) { bytes += 2 }
      else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length &&
        value.charCodeAt(index + 1) >= 0xdc00 && value.charCodeAt(index + 1) <= 0xdfff) {
        bytes += 4
        index++
      } else { bytes += 3 }
    }
    return bytes
  }

  static validate(records: systemShare.SharedRecord[]): void {
    if (!records.length || records.length > SystemShareService.MAX_RECORDS) {
      throw new Error('单次分享需要 1 至 500 个条目')
    }
    let bytes = 0
    for (const record of records) {
      if (!record.utd || (!record.uri && !record.content)) { throw new Error('分享内容或 UTD 类型为空') }
      const fields: string[] = [record.utd, record.content || '', record.uri || '', record.title || '',
        record.label || '', record.description || '', record.thumbnailUri || '',
        JSON.stringify(record.extraData || {}), JSON.stringify(record.revisitShareRecordData || {})]
      // Include a small serialization allowance as well as all UTF-8 text and binary thumbnails.
      bytes += 64 + (record.thumbnail?.byteLength || 0)
      for (const field of fields) { bytes += SystemShareService.utf8ByteLength(field) }
      if (bytes > SystemShareService.MAX_BYTES) { throw new Error('分享数据描述总量不能超过 200KB，请减少分享条目') }
    }
  }

  static data(records: systemShare.SharedRecord[]): systemShare.SharedData {
    SystemShareService.validate(records)
    const data = new systemShare.SharedData(records[0])
    for (let index = 1; index < records.length; index++) { data.addRecord(records[index]) }
    return data
  }

  static musicLink(param: SharePageParam): ShareLink {
    const label = param.type === 'song' ? '歌曲' : param.type === 'playlist' ? '歌单' : param.type === 'event' ? '动态' : '专辑'
    return {
      url: `https://music.163.com/${param.type}?id=${encodeURIComponent(param.id)}` +
        (param.type === 'event' ? '&uid=' + encodeURIComponent(param.eventUserId || '') : ''),
      title: param.name,
      description: param.author ? `${label} · ${param.author}` : `分享${label}「${param.name}」`,
      label: label,
      image: param.img
    }
  }

  private static async thumbnail(url: string): Promise<Uint8Array | undefined> {
    if (!/^https?:\/\//i.test(url)) { return undefined }
    const request = http.createHttp()
    let source: image.ImageSource | undefined
    let pixel: image.PixelMap | undefined
    let packer: image.ImagePacker | undefined
    try {
      const response = await request.request(resizeImageUrl(url, 256, 256), {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 3000, readTimeout: 3000, maxLimit: 2 * 1024 * 1024
      })
      if (response.responseCode !== 200) { return undefined }
      source = image.createImageSource(response.result as ArrayBuffer)
      pixel = await source.createPixelMap({ desiredSize: { width: 256, height: 256 } })
      packer = image.createImagePacker()
      const buffer = await packer.packing(pixel, { format: 'image/jpeg', quality: 75 })
      return buffer && buffer.byteLength > 0 && buffer.byteLength < 32 * 1024 ? new Uint8Array(buffer) : undefined
    } catch (_error) {
      // A missing cover must not prevent sharing the link.
      return undefined
    } finally {
      request.destroy()
      try { await packer?.release() } catch (_error) {}
      try { await pixel?.release() } catch (_error) {}
      try { await source?.release() } catch (_error) {}
    }
  }

  static async linkRecords(link: ShareLink): Promise<systemShare.SharedRecord[]> {
    if (!/^https?:\/\//i.test(link.url)) { throw new Error('分享链接无效') }
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
      content: link.url, title: link.title, description: link.description, label: link.label
    }
    SystemShareService.validate([record])
    if (link.image) {
      const thumbnail = await SystemShareService.thumbnail(link.image)
      if (thumbnail) { record.thumbnail = thumbnail }
    }
    SystemShareService.validate([record])
    return [record]
  }

  static async show(context: common.UIAbilityContext, records: systemShare.SharedRecord[]): Promise<void> {
    if (SystemShareService.launching) { return }
    SystemShareService.launching = true
    try {
      await SystemShareService.present(context, records)
    } finally {
      SystemShareService.launching = false
    }
  }

  private static async present(context: common.UIAbilityContext, records: systemShare.SharedRecord[]): Promise<void> {
    try {
      const host = SystemShareService.abilityContext || context
      const controller = new systemShare.ShareController(SystemShareService.data(records))
      const isCard = records.every((record: systemShare.SharedRecord) =>
        record.utd === uniformTypeDescriptor.UniformDataType.HYPERLINK ||
          record.utd === uniformTypeDescriptor.UniformDataType.PLAIN_TEXT)
      await controller.show(host, {
        selectionMode: records.length > 1 ? systemShare.SelectionMode.BATCH : systemShare.SelectionMode.SINGLE,
        previewMode: isCard ? systemShare.SharePreviewMode.DEFAULT : systemShare.SharePreviewMode.DETAIL
      })
    } catch (error) {
      const err = error as BusinessError
      const code = err.code !== undefined ? err.code.toString() : 'unknown'
      const message = err.message || '系统未返回错误描述'
      console.error(`[SystemShare] launch failed: code=${code}, message=${message}`)
      throw new Error(`无法打开系统分享面板（${code}）：${message}`)
    }
  }

  static async showText(context: common.UIAbilityContext, text: ShareText): Promise<void> {
    if (SystemShareService.launching) { return }
    SystemShareService.launching = true
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT, content: text.content,
        title: text.title, description: text.description, label: text.label
      }
      SystemShareService.validate([record])
      if (text.image) {
        const thumbnail = await SystemShareService.thumbnail(text.image)
        if (thumbnail) { record.thumbnail = thumbnail }
      }
      await SystemShareService.present(context, [record])
    } finally { SystemShareService.launching = false }
  }

  static async showLink(context: common.UIAbilityContext, link: ShareLink): Promise<void> {
    if (SystemShareService.launching) { return }
    SystemShareService.launching = true
    try {
      await SystemShareService.present(context, await SystemShareService.linkRecords(link))
    } finally {
      SystemShareService.launching = false
    }
  }
}

// Each visible share surface owns its registrations; leaving it invalidates pending preparation.
export class NearbyShareSession {
  private static foreground: boolean = true
  static setForeground(foreground: boolean): void { NearbyShareSession.foreground = foreground }
  private active: boolean = false
  private revision: number = 0
  private knockRegistered: boolean = false
  private gestureRegistered: boolean = false
  private provider?: () => Promise<systemShare.SharedRecord[]>
  private callback: (target: harmonyShare.SharableTarget) => void = (target: harmonyShare.SharableTarget) => {
    this.send(target).catch((error: Error) => console.error(`[NearbyShare] ${error.message}`))
  }

  activate(provider: () => Promise<systemShare.SharedRecord[]>): void {
    this.deactivate()
    this.active = true
    this.provider = provider
    try { harmonyShare.on('knockShare', this.callback); this.knockRegistered = true } catch (_error) {}
    try { harmonyShare.on('gesturesShare', this.callback); this.gestureRegistered = true } catch (_error) {}
  }

  deactivate(): void {
    this.active = false
    ++this.revision
    this.provider = undefined
    if (this.knockRegistered) { try { harmonyShare.off('knockShare', this.callback) } catch (_error) {} }
    if (this.gestureRegistered) { try { harmonyShare.off('gesturesShare', this.callback) } catch (_error) {} }
    this.knockRegistered = false
    this.gestureRegistered = false
  }

  private async send(target: harmonyShare.SharableTarget): Promise<void> {
    const revision = this.revision
    try {
      if (!this.active || !this.provider || !NearbyShareSession.foreground) { throw new Error('No share content') }
      const records = await this.provider()
      if (!this.active || revision !== this.revision || !NearbyShareSession.foreground) { throw new Error('Share surface closed') }
      await target.share(SystemShareService.data(records))
    } catch (_error) { await target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR) }
  }
}
