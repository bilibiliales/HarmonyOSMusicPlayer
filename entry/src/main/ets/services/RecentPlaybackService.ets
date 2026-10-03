import { ApiClient } from './ApiClient'
import { ApiSong, mapApiSong } from '../models/api'
import { songItemType } from '../models/music'

export interface RecentResource {
  id?: number | string
  vid?: string
  name?: string
  title?: string
  picUrl?: string
  coverImgUrl?: string
  coverUrl?: string
  imgurl?: string
  mainSong?: ApiSong
  song?: ApiSong
  artist?: RecentCreator
  creator?: RecentCreator
  dj?: RecentCreator
  radio?: RecentResource
  duration?: number
}
interface RecentCreator { nickname?: string; name?: string }
interface RecentRecord { resourceId: string | number; data: RecentResource }
interface RecentData { list: RecentRecord[] }
interface RecentResponse { code: number; message?: string; data?: RecentData }
interface ProgramResponse { code: number; programs?: RecentResource[] }
export interface RecentEntry {
  id: string
  name: string
  cover: string
  creator: string
  song?: songItemType
  video: boolean
}

export class RecentPlaybackService {
  private static entry(data: RecentResource, fallback: string): RecentEntry {
    const raw = data.mainSong || data.song
    const song = raw ? mapApiSong(raw) : undefined
    if (song) { song.isVoice = true }
    return { id: String(data.vid || data.id || fallback), name: data.name || data.title || song?.name || '',
      cover: data.coverUrl || data.coverImgUrl || data.picUrl || data.imgurl || song?.img || '',
      creator: data.creator?.nickname || data.artist?.name || data.dj?.nickname || '', song: song,
      video: !!data.vid }
  }

  static async load(kind: string): Promise<RecentEntry[]> {
    if (!ApiClient.cookie) { throw new Error('请先登录查看自己的最近播放') }
    const response = await ApiClient.get<RecentResponse>(`/record/recent/${kind}`, [
      { key: 'limit', value: '100' }, { key: 'timestamp', value: Date.now().toString() }
    ])
    if (response.code !== 200 || !response.data?.list) { throw new Error(response.message || '最近播放加载失败') }
    return response.data.list.map((item: RecentRecord) => RecentPlaybackService.entry(item.data, String(item.resourceId)))
  }

  static async programs(id: string): Promise<RecentEntry[]> {
    const response = await ApiClient.get<ProgramResponse>('/dj/program', [
      { key: 'rid', value: id }, { key: 'limit', value: '100' }
    ])
    if (response.code !== 200) { throw new Error('播客节目加载失败') }
    return (response.programs || []).map((item: RecentResource) => RecentPlaybackService.entry(item, ''))
  }
}
