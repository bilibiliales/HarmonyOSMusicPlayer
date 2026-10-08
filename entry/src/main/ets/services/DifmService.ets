import { ApiClient } from './ApiClient'
import { songItemType } from '../models/music'

export interface DifmChannel {
  id: number
  source: number
  name: string
  chineseName?: string
  cover?: string
  description?: string
}
export interface DifmStyle {
  id: number
  name: string
  chineseName?: string
  channels?: DifmChannel[]
}
export interface DifmSource {
  source: number
  styles?: DifmStyle[]
}
interface DifmCatalogResponse { code: number; data?: DifmSource[] }
export interface DifmTrack {
  id: number
  name: string
  artist?: string
  cover?: string
  audio?: string
  duration?: number
  channelId?: number
  source?: number
}
interface DifmTrackData { list?: DifmTrack[]; total?: number }
interface DifmTracksResponse { code: number; data?: DifmTrackData }

export class DifmService {
  static async catalog(): Promise<DifmSource[]> {
    const result = await ApiClient.get<DifmCatalogResponse>('/dj/difm/all/style/channel', [{ key: 'sources', value: '[0,1,2]' }])
    if (result.code !== 200) { throw new Error('音乐电台分类加载失败') }
    return result.data || []
  }

  static async tracks(channel: DifmChannel): Promise<DifmTrack[]> {
    const result = await ApiClient.get<DifmTracksResponse>('/dj/difm/playing/tracks/list', [
      { key: 'source', value: String(channel.source) }, { key: 'channelId', value: String(channel.id) },
      { key: 'limit', value: '6' }, { key: 'timestamp', value: String(Date.now()) }
    ])
    if (result.code !== 200) { throw new Error('频道曲目加载失败') }
    return (result.data?.list || []).filter((track: DifmTrack) => !!track.audio && /^https?:\/\//i.test(track.audio))
  }

  static song(track: DifmTrack, channel: DifmChannel): songItemType {
    return {
      id: `difm:${channel.source}:${track.id}`, name: track.name, author: track.artist || channel.name,
      img: track.cover || channel.cover || '', url: track.audio || '', duration: (track.duration || 0) * 1000,
      album: channel.chineseName || channel.name, isVoice: true, isDifm: true
    }
  }
}
