import { ApiArtist, ApiSong } from './api'
import { songItemType } from './music'

export interface DailyPlaylistResponse {
  code: number
  recommend?: DailyPlaylistItem[]
}

export interface DailyPlaylistItem {
  id: number
  name: string
  picUrl: string
  playcount?: number
  trackCount?: number
  creator?: DailyPlaylistCreator
}

export interface DailyPlaylistCreator {
  nickname?: string
}

export interface DailySong extends ApiSong {
  reason?: string
  recommendReason?: string
}

export interface DailySongsData {
  dailySongs?: DailySong[]
}

export interface DailySongsResponse {
  code: number
  data?: DailySongsData
}

export interface PersonalFmResponse {
  code: number
  data?: ApiSong[]
}

export interface TopSongResponse {
  code: number
  data?: ApiSong[]
}

export interface ProgramRadio {
  id?: number
  name?: string
  picUrl?: string
  category?: string
  secondCategory?: string
  subCount?: number
  programCount?: number
}

export interface ProgramDj {
  nickname?: string
  avatarUrl?: string
  userId?: number
  brand?: string
}

export interface ProgramItem {
  id: number
  name: string
  coverUrl?: string
  duration?: number
  listenerCount?: number
  description?: string
  mainSong?: ApiSong
  radio?: ProgramRadio
  dj?: ProgramDj
  mainTrackId?: number
  categoryName?: string
  secondCategoryName?: string
  likedCount?: number
  commentCount?: number
  shareCount?: number
}

export interface PersonalizedProgramItem {
  id: number
  name: string
  copywriter?: string
  picUrl?: string
  program?: ProgramItem
}

export interface PersonalizedProgramResponse {
  code: number
  result?: PersonalizedProgramItem[]
}

export interface ProgramRecommendResponse {
  code: number
  programs?: ProgramItem[]
}

export interface PrivateContentItem {
  id: number
  name: string
  copywriter?: string
  picUrl: string
  sPicUrl?: string
  url?: string
  type?: number
}

export interface PrivateContentResponse {
  code: number
  result?: PrivateContentItem[]
}

export interface SongColumn {
  key: string
  songs: songItemType[]
}

export interface NewSongCategory {
  type: number
  title: string
  subtitle: string
  cover: string
}

export interface NewSongPageParam {
  type: number
  title: string
  cover?: string
}

export interface ProgramCard {
  id: string
  title: string
  subtitle: string
  image: string
  song?: songItemType
}

export interface HomepageTitle {
  title?: string
}

export interface HomepageImage {
  imageUrl?: string
}

/** 区块右上角按钮（「查看更多 / 播放全部」），带客户端深链。 */
export interface HomepageButton {
  action?: string
  actionType?: string
  text?: string
  iconUrl?: string
}

export interface HomepageUiElement {
  mainTitle?: HomepageTitle
  subTitle?: HomepageTitle
  image?: HomepageImage
  button?: HomepageButton
}

export interface HomepageResourceExtInfo {
  artists?: ApiArtist[]
  songData?: ApiSong
  song?: ApiSong
  playCount?: number
}

export interface HomepageResource {
  resourceType?: string
  resourceId?: string
  resourceUrl?: string
  /** 客户端深链（orpheus://…）。本应用不解析深链，字段仅用于描述载荷，不参与跳转。 */
  action?: string
  actionType?: string
  uiElement?: HomepageUiElement
  resourceExtInfo?: HomepageResourceExtInfo
}

export interface HomepageCreative {
  creativeType?: string
  uiElement?: HomepageUiElement
  resources?: HomepageResource[]
}

export interface HomepageBlock {
  blockCode?: string
  showType?: string
  /** 整个区块的入口深链（通常是「查看更多」）。本应用不解析，不参与跳转。 */
  action?: string
  actionType?: string
  uiElement?: HomepageUiElement
  creatives?: HomepageCreative[]
}

export interface HomepageData {
  cursor?: string
  blocks?: HomepageBlock[]
  hasMore?: boolean
}

export interface HomepageResponse {
  code: number
  data?: HomepageData
  message?: string
}

export interface HomeResourceView {
  id: string
  title: string
  subtitle: string
  image: string
  resourceType: string
  playCount: number
  song?: songItemType
}

export interface HomeCreativeView {
  key: string
  title: string
  items: HomeResourceView[]
}

export interface HomeBlockView {
  key: string
  /** 原始区块编码，用于少量特殊区块的判断。 */
  blockCode: string
  title: string
  showType: string
  creativeType: string
  creatives: HomeCreativeView[]
}

// ---- 历史日推 ----

/** /history/recommend/songs 的可选返回字段。 */
export interface HistoryRecommendData {
  dates?: string[]
  purchaseUrl?: string
  description?: string | null
  noHistoryMessage?: string
}

export interface HistoryRecommendResponse {
  code: number
  message?: string
  data?: HistoryRecommendData
}

/** /history/recommend/songs/detail 的返回体：songs 与每日推荐歌曲同构。 */
export interface HistoryDetailData {
  dates?: string[]
  songs?: DailySong[]
  description?: string | null
  noHistoryMessage?: string
}

export interface HistoryDetailResponse {
  code: number
  message?: string
  data?: HistoryDetailData
}

/** 历史日推日期与说明，交给页面展示。 */
export class HistoryRecommendSummary {
  dates: string[] = []
  description: string = ''
  noHistoryMessage: string = ''
  purchaseUrl: string = ''
}
