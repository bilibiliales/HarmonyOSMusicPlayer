import { ApiClient } from './ApiClient'
import { ApiParam, ApiSong, mapApiSong, OperationResponse } from '../models/api'
import { songItemType } from '../models/music'
import {
  LyricMarkDraft,
  LyricMarkPageData,
  LyricMarkPageResponse,
  LyricMarkPayload,
  LyricMarkSongData,
  LyricMarkSongResponse,
  LyricMarkVO
} from '../models/lyricmark'

/** 歌词摘录接口封装：我的歌词本、某首歌的摘录、新增/修改、删除。 */
export class LyricMarkService {
  /** 我的歌词本（按摘录时间倒序，offset 是后端给的游标）。 */
  static async mine(limit: number, offset: number): Promise<LyricMarkPageData> {
    const response = await ApiClient.get<LyricMarkPageResponse>('/song/lyrics/mark/user/page', [
      { key: 'limit', value: String(limit) },
      { key: 'offset', value: String(offset) }
    ])
    if (response.code !== 200) {
      throw new Error(LyricMarkService.reason(response.code, response.msg || response.message, '歌词本加载失败'))
    }
    const data = response.data
    const list: LyricMarkVO[] = data?.markVOList || []
    return {
      offset: data?.offset || 0,
      hasMore: data?.hasMore === true && list.length > 0,
      markVOList: list
    }
  }

  /** 某首歌已有的摘录（用于编辑页展示「这首歌你摘录过几句」）。 */
  static async bySong(songId: string): Promise<LyricMarkVO[]> {
    const response = await ApiClient.get<LyricMarkSongResponse>('/song/lyrics/mark', [
      { key: 'id', value: songId }
    ])
    if (response.code !== 200) {
      throw new Error(LyricMarkService.reason(response.code, response.msg || response.message, '摘录加载失败'))
    }
    const data: LyricMarkSongData | undefined = response.data
    return data?.markVOList || []
  }

  /** 新增或修改一条摘录。draft.markId > 0 时视为修改。 */
  static async save(draft: LyricMarkDraft): Promise<void> {
    const row: LyricMarkPayload = {
      startTimeStamp: Math.max(0, Math.round(draft.startTimeStamp)),
      originalLyricsText: draft.originalLyricsText,
      translateType: draft.translateType,
      translateLyricsText: draft.translateType === 0 ? '' : draft.translateLyricsText
    }
    if (draft.markId > 0) {
      row.markId = draft.markId
    }
    const rows: LyricMarkPayload[] = [row]
    const params: ApiParam[] = [
      { key: 'id', value: draft.songId },
      // buildUrl 会统一 encodeURIComponent，这里直接传原始 JSON
      { key: 'data', value: JSON.stringify(rows) }
    ]
    if (draft.markId > 0) {
      params.push({ key: 'markId', value: String(draft.markId) })
    }
    const response = await ApiClient.get<OperationResponse>('/song/lyrics/mark/add', params)
    if (response.code !== 200) {
      throw new Error(LyricMarkService.reason(response.code, response.message, '摘录保存失败'))
    }
  }

  /** 一次摘录多句（接口的 data 本身是数组），按 10 句一批提交。 */
  static async saveMany(songId: string, drafts: LyricMarkDraft[]): Promise<void> {
    if (drafts.length === 0) {
      return
    }
    const batchSize = 10
    for (let start = 0; start < drafts.length; start += batchSize) {
      const rows: LyricMarkPayload[] = []
      const end = Math.min(drafts.length, start + batchSize)
      for (let i = start; i < end; i++) {
        const draft = drafts[i]
        const row: LyricMarkPayload = {
          startTimeStamp: Math.max(0, Math.round(draft.startTimeStamp)),
          originalLyricsText: draft.originalLyricsText,
          translateType: draft.translateType,
          translateLyricsText: draft.translateType === 0 ? '' : draft.translateLyricsText
        }
        if (draft.markId > 0) {
          row.markId = draft.markId
        }
        rows.push(row)
      }
      const response = await ApiClient.get<OperationResponse>('/song/lyrics/mark/add', [
        { key: 'id', value: songId },
        { key: 'data', value: JSON.stringify(rows) }
      ])
      if (response.code !== 200) {
        throw new Error(LyricMarkService.reason(response.code, response.message, '摘录保存失败'))
      }
    }
  }

  /** 删除摘录。 */
  static async remove(markId: number): Promise<void> {
    const response = await ApiClient.get<OperationResponse>('/song/lyrics/mark/del', [
      { key: 'id', value: String(markId) }
    ])
    if (response.code !== 200) {
      throw new Error(LyricMarkService.reason(response.code, response.message, '删除失败'))
    }
  }

  /** 摘录卡片里那首歌的播放对象。 */
  static toSong(mark: LyricMarkVO): songItemType {
    const source: ApiSong = mark.songData ? mark.songData : { id: mark.songId, name: '未知歌曲' }
    const song = mapApiSong(source)
    if (!song.id || song.id === '0') {
      song.id = String(mark.songId)
    }
    return song
  }

  private static reason(code: number, message: string | undefined, fallback: string): string {
    if (code === 301) {
      return '请先登录再使用歌词本'
    }
    return message && message.length > 0 ? message : fallback
  }
}
