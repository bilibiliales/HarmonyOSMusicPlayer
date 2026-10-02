import { common } from '@kit.AbilityKit'
import { systemShare, harmonyShare } from '@kit.ShareKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { util } from '@kit.ArkTS'
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

export class SystemShareService {
  static readonly MAX_RECORDS: number = 500
  static readonly MAX_BYTES: number = 200 * 1024
  private static controller?: systemShare.ShareController

  static validate(records: systemShare.SharedRecord[]): void {
    if (!records.length || records.length > SystemShareService.MAX_RECORDS) {
      throw new Error('单次分享需要 1 至 500 个条目')
    }
    const encoder = new util.TextEncoder()
    let bytes = 0
    for (const record of records) {
      if (!record.utd || (!record.uri && !record.content)) { throw new Error('分享内容或 UTD 类型为空') }
      const fields: string[] = [record.utd, record.content || '', record.uri || '', record.title || '',
        record.label || '', record.description || '', record.thumbnailUri || '',
        JSON.stringify(record.extraData || {}), JSON.stringify(record.revisitShareRecordData || {})]
      // Include a small serialization allowance as well as all UTF-8 text and binary thumbnails.
      bytes += 64 + (record.thumbnail?.byteLength || 0)
      for (const field of fields) { bytes += encoder.encodeInto(field).byteLength }
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
    const label = param.type === 'song' ? '歌曲' : param.type === 'playlist' ? '歌单' : '专辑'
    return {
      url: `https://music.163.com/${param.type}?id=${encodeURIComponent(param.id)}`,
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
      return buffer.byteLength <= 48 * 1024 ? new Uint8Array(buffer) : undefined
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
    if (link.image) { record.thumbnail = await SystemShareService.thumbnail(link.image) }
    SystemShareService.validate([record])
    return [record]
  }

  static async show(context: common.UIAbilityContext, records: systemShare.SharedRecord[]): Promise<void> {
    if (SystemShareService.controller) { return }
    const controller = new systemShare.ShareController(SystemShareService.data(records))
    SystemShareService.controller = controller
    const dismiss = (): void => {
      controller.off('dismiss', dismiss)
      if (SystemShareService.controller === controller) { SystemShareService.controller = undefined }
    }
    controller.on('dismiss', dismiss)
    try {
      await controller.show(context, {
        selectionMode: records.length > 1 ? systemShare.SelectionMode.BATCH : systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      })
    } catch (error) {
      dismiss()
      throw new Error(error instanceof Error ? error.message : '无法打开系统分享面板')
    }
  }

  static async showLink(context: common.UIAbilityContext, link: ShareLink): Promise<void> {
    await SystemShareService.show(context, await SystemShareService.linkRecords(link))
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
