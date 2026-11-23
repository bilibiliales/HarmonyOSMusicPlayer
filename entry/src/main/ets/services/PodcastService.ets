import { common } from '@kit.AbilityKit'
import { DjRadioItem, DjSublistResponse, OperationResponse } from '../models/api'
import { PodcastStation, PodcastStationPage, PodcastVoice, PodcastVoicePage } from '../models/podcast'
import { ApiClient } from './ApiClient'
import { RadioService } from './RadioService'
import { VoiceList, VoiceUploadService } from './VoiceUploadService'

interface RecentDjRecord { resourceId: string | number; data: DjRadioItem }
interface RecentDjData { list?: RecentDjRecord[] }
interface RecentDjResponse { code: number; message?: string; data?: RecentDjData }
interface PodcastVoicesData { list?: PodcastVoice[]; count?: number; totalCount?: number; total?: number; hasMore?: boolean }
interface PodcastVoicesResponse { code: number; message?: string; data?: PodcastVoicesData }
interface PodcastVoiceResponse { code: number; message?: string; data?: PodcastVoice }

export class PodcastService {
  static readonly PAGE_SIZE: number = 30
  static readonly REVISION_KEY: string = 'podcastRevision'

  static changed(): void {
    AppStorage.setOrCreate<number>(PodcastService.REVISION_KEY, (AppStorage.get<number>(PodcastService.REVISION_KEY) || 0) + 1)
  }

  static station(item: DjRadioItem, fallback: string = ''): PodcastStation {
    return { id: String(item.id || fallback), name: item.name || '播客', cover: item.picUrl || '',
      subtitle: `${item.programCount || 0} 个声音 · ${item.dj?.nickname || item.creator?.nickname || RadioService.count(item.subCount) + ' 人订阅'}`,
      subscribed: item.subed }
  }

  static async recent(): Promise<PodcastStationPage> {
    const response = await ApiClient.get<RecentDjResponse>('/record/recent/dj', [
      { key: 'limit', value: '100' }, { key: 'timestamp', value: String(Date.now()) }
    ])
    if (response.code !== 200 || !response.data) { throw new Error(response.message || '最近收听播客加载失败') }
    const items = (response.data.list || []).map((item: RecentDjRecord) => PodcastService.station(item.data, String(item.resourceId)))
    const seen: Set<string> = new Set()
    return { items: items.filter((item: PodcastStation) => {
      if (!item.id || item.id === '0' || seen.has(item.id)) { return false }
      seen.add(item.id)
      return true
    }), more: false }
  }

  static async subscribed(offset: number): Promise<PodcastStationPage> {
    const response = await ApiClient.get<DjSublistResponse>('/dj/sublist', [
      { key: 'limit', value: String(PodcastService.PAGE_SIZE) }, { key: 'offset', value: String(offset) },
      { key: 'timestamp', value: String(Date.now()) }
    ])
    if (response.code !== 200) { throw new Error('订阅播客加载失败') }
    const items = (response.djRadios || []).map((item: DjRadioItem) => {
      const station = PodcastService.station(item)
      station.subscribed = true
      return station
    })
    return { items: items, more: response.hasMore ?? items.length >= PodcastService.PAGE_SIZE }
  }

  static async created(): Promise<PodcastStationPage> {
    const lists = await VoiceUploadService.lists()
    return { items: lists.map((list: VoiceList): PodcastStation => {
      return { id: String(list.voiceListId), name: list.voiceListName, cover: list.coverUrl || '',
        subtitle: list.privacy ? '私密播客 · 管理声音' : list.voiceCount !== undefined ? `${list.voiceCount} 个声音 · 管理声音` : '管理我的声音', list: list }
    }), more: false }
  }

  static async subscribe(id: string, subscribed: boolean): Promise<void> {
    const response = await ApiClient.get<OperationResponse>('/dj/sub', [
      { key: 'rid', value: id }, { key: 't', value: subscribed ? '1' : '0' },
      { key: 'timestamp', value: String(Date.now()) }
    ])
    if (response.code !== 200) { throw new Error(response.message || '订阅操作失败') }
    PodcastService.changed()
  }

  static voiceId(voice: PodcastVoice): string { return String(voice.voiceId || voice.id || '') }
  static voiceName(voice: PodcastVoice): string { return voice.voiceName || voice.name || '声音' }

  static status(status: string = ''): string {
    if (status === 'ONLINE') { return '已发布' }
    if (status === 'AUDITING') { return '审核中' }
    if (status === 'ONLY_SELF_SEE') { return '仅自己可见' }
    if (status === 'SCHEDULE_PUBLISH') { return '定时发布' }
    if (status === 'TRANSCODE_FAILED') { return '转码失败' }
    if (status === 'PUBLISHING') { return '发布中' }
    if (status === 'FAILED') { return '发布失败' }
    return '状态待更新'
  }

  static async voices(id: string, offset: number, status: string = '', query: string = ''): Promise<PodcastVoicePage> {
    // 当前模块把 voiceListId 映射为上游 radioId，按模块实际参数发送。
    const response = await ApiClient.get<PodcastVoicesResponse>('/voicelist/list/search', [
      { key: 'voiceListId', value: id }, { key: 'limit', value: String(PodcastService.PAGE_SIZE) },
      { key: 'offset', value: String(offset) }, { key: 'displayStatus', value: status },
      { key: 'name', value: query.trim() }, { key: 'timestamp', value: String(Date.now()) }
    ])
    if (response.code !== 200 || !response.data) { throw new Error(response.message || '播客声音加载失败') }
    const items = response.data.list || []
    const total = response.data.totalCount ?? response.data.count ?? response.data.total
    return { items: items, total: total,
      more: response.data.hasMore ?? (total !== undefined ? offset + items.length < total : items.length >= PodcastService.PAGE_SIZE) }
  }

  static async voice(id: string): Promise<PodcastVoice> {
    const response = await ApiClient.get<PodcastVoiceResponse>('/voice/detail', [{ key: 'id', value: id }])
    if (response.code !== 200 || !response.data || PodcastService.voiceId(response.data) !== id) {
      throw new Error(response.message || '声音详情加载失败')
    }
    return response.data
  }

  static async moveToTop(voiceId: string, listId: string): Promise<void> {
    const response = await ApiClient.get<OperationResponse>('/voicelist/trans', [
      { key: 'programId', value: voiceId }, { key: 'radioId', value: listId }, { key: 'position', value: '1' },
      { key: 'limit', value: '200' }, { key: 'offset', value: '0' }
    ])
    if (response.code !== 200) { throw new Error(response.message || '声音排序失败') }
    PodcastService.changed()
  }

  static async openCreator(context: common.UIAbilityContext): Promise<void> {
    // 文档与模块清单没有创建播客 API，由用户在官方创作者中心创建后回到应用刷新。
    await context.startAbility({ action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'], uri: 'https://music.163.com/st/creator' })
  }
}
