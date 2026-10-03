import { ApiParam, ApiSong, mapApiSong } from '../models/api'
import { playlistType, songItemType } from '../models/music'
import { ApiClient } from './ApiClient'

interface RecentSongRecord {
  resourceId: number
  playTime: number
  data: ApiSong
}
interface RecentSongsData {
  total: number
  list: RecentSongRecord[]
}
interface RecentSongsResponse {
  code: number
  message?: string
  data?: RecentSongsData
}
interface UserRecordItem {
  song: ApiSong
  playCount: number
  score: number
}
interface UserRecordResponse {
  code: number
  message?: string
  msg?: string
  weekData?: UserRecordItem[]
  allData?: UserRecordItem[]
}

export class ListeningPlaylistService {
  static playlist(kind: 'recent' | 'record', uid: string, nickname: string,
    songs: songItemType[] = [], recordType: 0 | 1 = 1): playlistType {
    return {
      id: `${kind}:${uid}`, specialType: kind, recordType: recordType,
      name: kind === 'recent' ? '最近播放' : '听歌排行',
      cover: songs[0]?.img || '', count: songs.length, creator: nickname, creatorId: uid
    }
  }

  private static songs(source: ApiSong[]): songItemType[] {
    const result: songItemType[] = []
    const seen: Set<string> = new Set<string>()
    for (const item of source) {
      if (!item || !item.id) { continue }
      const song = mapApiSong(item)
      if (!seen.has(song.id)) { seen.add(song.id); result.push(song) }
    }
    return result
  }

  static async recent(timestamp: string = ''): Promise<songItemType[]> {
    const response = await ApiClient.get<RecentSongsResponse>('/record/recent/song', [
      { key: 'limit', value: '300' }, { key: 'timestamp', value: timestamp || Date.now().toString() }
    ])
    if (response.code !== 200 || !response.data || !Array.isArray(response.data.list)) {
      throw new Error(response.message || '最近播放加载失败，请确认已登录')
    }
    // The endpoint returns newest first. Preserve that order, retaining the newest occurrence.
    return ListeningPlaylistService.songs(response.data.list.map((item: RecentSongRecord) => item.data))
  }

  static async record(uid: string, type: 0 | 1 = 1, timestamp: string = ''): Promise<songItemType[]> {
    if (!uid) { throw new Error('用户参数无效') }
    const params: ApiParam[] = [
      { key: 'uid', value: uid }, { key: 'type', value: type.toString() },
      { key: 'timestamp', value: timestamp || Date.now().toString() }
    ]
    const response = await ApiClient.get<UserRecordResponse>('/user/record', params)
    if (response.code !== 200) {
      throw new Error(response.message || response.msg || '无法查看听歌排行，用户可能设置了隐私权限')
    }
    const items = type === 1 ? response.weekData : response.allData
    if (!Array.isArray(items)) { throw new Error('该用户的听歌排行未公开或暂不可用') }
    const songs = ListeningPlaylistService.songs(items.map((item: UserRecordItem) => item.song))
    songs.forEach((song: songItemType) => {
      song.playCount = items.find((item: UserRecordItem) => item.song.id.toString() === song.id)?.playCount || 0
    })
    return songs
  }
}
