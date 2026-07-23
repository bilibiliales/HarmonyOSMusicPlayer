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

export interface HomepageUiElement {
  mainTitle?: HomepageTitle
  subTitle?: HomepageTitle
  image?: HomepageImage
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
  title: string
  showType: string
  creativeType: string
  creatives: HomeCreativeView[]
}
