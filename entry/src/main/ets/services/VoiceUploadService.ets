import { fileIo } from '@kit.CoreFileKit'
import { ApiClient, ApiUploadFile } from './ApiClient'
import { ApiParam, OperationResponse } from '../models/api'

export interface VoiceList {
  voiceListId: string | number
  voiceListName: string
  coverUrl?: string
  coverImgId?: string | number
  categoryId?: string | number
  secondCategoryId?: string | number
  privacy?: boolean
  description?: string
  voiceCount?: number
}

interface VoiceListsResponse {
  code: number
  message?: string
  data?: VoiceListsData
}
interface VoiceListsData { data?: VoiceList[]; list?: VoiceList[] }
interface VoiceDetailResponse { code: number; message?: string; data?: VoiceList }

export interface VoiceUploadParam { voiceListId?: string; onUploaded?: () => void }

export interface VoicePublishOptions {
  coverUri?: string
  publishTime?: number
  autoPublish?: boolean
  autoPublishText?: string
}

export class VoiceUploadService {
  static parsePublishTime(value: string): number {
    const parts = value.trim().match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/)
    if (!parts) { throw new Error('请输入发布时间，例如 2026-11-24 18:30') }
    const year = Number(parts[1])
    const month = Number(parts[2]) - 1
    const day = Number(parts[3])
    const hour = Number(parts[4])
    const minute = Number(parts[5])
    const date = new Date(year, month, day, hour, minute)
    if (date.getFullYear() !== year || date.getMonth() !== month || date.getDate() !== day ||
      date.getHours() !== hour || date.getMinutes() !== minute || date.getTime() <= Date.now()) {
      throw new Error('请填写有效且晚于当前时间的发布时间')
    }
    return date.getTime()
  }

  static async lists(): Promise<VoiceList[]> {
    // 创作者自己的播客；/voicelist/search 是搜索接口，不能作为上传目标。
    const response = await ApiClient.get<VoiceListsResponse>('/voicelist/my/created', [
      { key: 'limit', value: '100' },
      { key: 'timestamp', value: String(Date.now()) }
    ])
    if (response.code !== 200) { throw new Error(response.message || '播客列表加载失败') }
    return (response.data?.data || response.data?.list || []).filter((list: VoiceList) => !!list.voiceListId)
  }

  static async detail(list: VoiceList): Promise<VoiceList> {
    if (list.coverImgId !== undefined && list.categoryId !== undefined && list.secondCategoryId !== undefined) {
      return list
    }
    const response = await ApiClient.get<VoiceDetailResponse>('/voicelist/detail', [
      { key: 'id', value: String(list.voiceListId) }
    ])
    if (response.code !== 200 || !response.data || String(response.data.voiceListId) !== String(list.voiceListId)) {
      throw new Error(response.message || '播客信息加载失败')
    }
    return response.data
  }

  static params(list: VoiceList, name: string, description: string, privacy: boolean, hasCover: boolean = false): ApiParam[] {
    if (!name.trim() || !description.trim()) { throw new Error('请填写声音名称和介绍') }
    if (!list.voiceListId || (!hasCover && list.coverImgId === undefined) || list.categoryId === undefined ||
      list.secondCategoryId === undefined) { throw new Error('播客封面或分类信息不完整，请重新加载') }
    const params: ApiParam[] = [
      { key: 'songName', value: name.trim() }, { key: 'description', value: description.trim() },
      { key: 'voiceListId', value: String(list.voiceListId) },
      { key: 'categoryId', value: String(list.categoryId) },
      { key: 'secondCategoryId', value: String(list.secondCategoryId) },
      { key: 'privacy', value: privacy || list.privacy ? '1' : '0' },
      { key: 'time', value: String(Date.now()) }
    ]
    if (list.coverImgId !== undefined) { params.push({ key: 'coverImgId', value: String(list.coverImgId) }) }
    return params
  }

  private static async coverFile(uri: string): Promise<ApiUploadFile> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
    try {
      const size = (await fileIo.stat(file.fd)).size
      if (size <= 0) { throw new Error('声音封面文件为空') }
      const data = new ArrayBuffer(size)
      const view = new Uint8Array(data)
      let offset = 0
      while (offset < size) {
        const chunk = new ArrayBuffer(Math.min(256 * 1024, size - offset))
        const count = await fileIo.read(file.fd, chunk, { offset: offset, length: chunk.byteLength })
        if (count <= 0) { throw new Error('声音封面读取不完整') }
        view.set(new Uint8Array(chunk, 0, count), offset)
        offset += count
      }
      const ext = uri.split('.').pop()?.toLowerCase() || 'jpg'
      return { name: 'imgFile', fileName: `voice-cover.${ext}`, data: data,
        contentType: ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : ext === 'gif' ? 'image/gif' : 'image/jpeg' }
    } finally { await fileIo.close(file) }
  }

  static async upload(list: VoiceList, name: string, description: string, privacy: boolean,
    uri: string, fileName: string, options: VoicePublishOptions = {}): Promise<void> {
    if (!uri) { throw new Error('请选择音频文件') }
    const cookie = ApiClient.cookie
    const params = VoiceUploadService.params(list, name, description, privacy, !!options.coverUri)
    if (options.publishTime !== undefined) {
      if (!Number.isFinite(options.publishTime) || options.publishTime <= Date.now()) { throw new Error('定时发布时间必须晚于当前时间') }
      params.push({ key: 'publishTime', value: String(options.publishTime) })
    }
    params.push({ key: 'autoPublish', value: options.autoPublish ? '1' : '0' })
    if (options.autoPublish) { params.push({ key: 'autoPublishText', value: options.autoPublishText?.trim() || name.trim() }) }
    // 与官方 demo 一致：参数走查询串，原始音频走 songFile multipart 字段。
    params.push({ key: 'cookie', value: cookie })
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
    try {
      const size = (await fileIo.stat(file.fd)).size
      if (size <= 0) { throw new Error('音频文件为空') }
      const data = new ArrayBuffer(size)
      const view = new Uint8Array(data)
      let offset = 0
      while (offset < size) {
        const chunk = new ArrayBuffer(Math.min(256 * 1024, size - offset))
        const count = await fileIo.read(file.fd, chunk, { offset: offset, length: chunk.byteLength })
        if (count <= 0) { throw new Error('音频文件读取不完整') }
        view.set(new Uint8Array(chunk, 0, count), offset)
        offset += count
      }
      const ext = fileName.split('.').pop()?.toLowerCase() || ''
      const contentType = ext === 'mp3' ? 'audio/mpeg' : ext === 'wav' ? 'audio/wav' :
        ext === 'flac' ? 'audio/flac' : ext === 'm4a' ? 'audio/mp4' : ext === 'aac' ? 'audio/aac' :
          ext === 'ogg' ? 'audio/ogg' : 'application/octet-stream'
      const covers: ApiUploadFile[] = options.coverUri ? [await VoiceUploadService.coverFile(options.coverUri)] : []
      if (ApiClient.cookie !== cookie) { throw new Error('账号已变更，请重新选择播客后发布') }
      const response = await ApiClient.upload<OperationResponse>('/voice/upload', [], 'songFile', fileName,
        data, contentType, 180000, params, covers)
      if (response.code !== 200) { throw new Error(response.message || '声音上传失败') }
    } finally {
      await fileIo.close(file)
    }
  }
}
