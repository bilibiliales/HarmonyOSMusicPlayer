import { ApiSong } from './api'
import { songItemType } from './music'

/**
 * 歌词摘录（歌词本）相关数据结构。
 *
 * 对应接口：
 * - GET /song/lyrics/mark?id=<歌曲id>            某首歌的摘录
 * - GET /song/lyrics/mark/user/page?limit&offset 我的歌词本
 * - GET /song/lyrics/mark/add?id&data            新增 / 修改
 * - GET /song/lyrics/mark/del?id=<markId>        删除
 */

/** 摘录里的一句歌词。translateType：0 无、1 译文、2 音译。 */
export interface LyricMarkDetail {
  startTimeStamp: number
  originalLyricsText: string
  translateType: number
  translateLyricsText?: string | null
}

/** 一条摘录（当前接口一次摘录只带一句歌词）。 */
export interface LyricMarkVO {
  markId: number
  songId: number
  songData: ApiSong
  canShare?: boolean
  detailList?: LyricMarkDetail[]
  createTime?: number
  updateTime?: number
}

export interface LyricMarkPageData {
  /** 下一页游标（时间戳），后端在首页也会给一个非 0 值。 */
  offset: number
  hasMore: boolean
  markVOList: LyricMarkVO[]
}

export interface LyricMarkPageResponse {
  code: number
  data?: LyricMarkPageData
  message?: string
  msg?: string
}

export interface LyricMarkSongResponse {
  code: number
  data?: LyricMarkSongData
  message?: string
  msg?: string
}

export interface LyricMarkSongData {
  markVOList?: LyricMarkVO[]
}

/** 提交给 /song/lyrics/mark/add 的单项。修改时带上 markId。 */
export interface LyricMarkPayload {
  markId?: number
  startTimeStamp: number
  originalLyricsText: string
  translateType: number
  translateLyricsText: string
}

/** 页面间传递的编辑草稿。 */
export interface LyricMarkDraft {
  songId: string
  markId: number
  startTimeStamp: number
  originalLyricsText: string
  translateType: number
  translateLyricsText: string
}

export interface LyricMarkEditorParam {
  mark: LyricMarkVO
  /** 保存成功后把最新内容回传给列表页。 */
  onSaved: (mark: LyricMarkVO) => void
}

/** 播放页长按歌词进入的「挑歌句」页面。 */
export interface LyricMarkPickParam {
  song: songItemType
}
