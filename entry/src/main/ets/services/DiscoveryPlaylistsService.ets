import { ApiClient } from './ApiClient'
import { HomepageResponse, HomepageBlock, PersonalFmResponse } from '../models/home'
import { mapApiSong } from '../models/api'
import { playlistType, songItemType } from '../models/music'

export const FM_ICON: string = 'http://p1.music.126.net/Shi7cRT1bDhwpVDM7AOFXg==/109951165265330616.jpg'

export class DiscoveryPlaylistsService {
  static isRadar(block: HomepageBlock): boolean {
    return (block.blockCode || '').includes('RADAR') || (block.uiElement?.mainTitle?.title || '').includes('雷达')
  }
  static async radar(): Promise<playlistType[]> {
    const response = await ApiClient.get<HomepageResponse>('/homepage/block/page')
    const result: playlistType[] = []
    for (const block of response.data?.blocks || []) {
      if (!DiscoveryPlaylistsService.isRadar(block)) { continue }
      for (const creative of block.creatives || []) {
        for (const item of creative.resources || []) {
          if (item.resourceType !== 'list' || !item.resourceId) { continue }
          result.push({ id: item.resourceId, name: item.uiElement?.mainTitle?.title || creative.uiElement?.mainTitle?.title || '雷达歌单',
            cover: item.uiElement?.image?.imageUrl || creative.uiElement?.image?.imageUrl || '', count: 0, creator: '网易云音乐' })
        }
      }
    }
    return result
  }
  static playlist(): playlistType {
    return { id: 'privatefm', specialType: 'fm', name: '私人FM', cover: FM_ICON, count: 0, creator: '网易云音乐' }
  }
  static async fm(): Promise<songItemType[]> {
    const response = await ApiClient.get<PersonalFmResponse>('/personal_fm', [{ key: 'timestamp', value: Date.now().toString() }])
    if (response.code !== 200) { throw new Error('私人FM加载失败') }
    return (response.data || []).map((item) => mapApiSong(item))
  }
}
