import { ApiAlbum, ApiArtist, ApiSong } from './api'

export interface StyleTagPreference {
  tagId: number
  tagName: string
  ratio: string
  picUrl: string
}

export interface StyleTag {
  tagId: number
  tagName: string
  enName?: string
  level?: number
  childrenTags?: StyleTag[] | null
  picUrl?: string
  colorDeep?: string
  colorShallow?: string
  link?: string
  showText?: string
  tabs?: string[]
}

export interface StylePreferenceData {
  tagPreferenceVos?: StyleTagPreference[]
  tags?: StyleTag[]
}

export interface StylePreferenceResponse {
  code: number
  data?: StylePreferenceData
}

export interface StyleListResponse {
  code: number
  data?: StyleTag[]
}

export interface StylePatternText {
  text?: string
}

export interface StyleProfessionalReview {
  templateContent?: string
  pattern?: Record<string, StylePatternText>
}

export interface StyleFavouriteSong {
  favouriteSong?: ApiSong
  markHeart?: number
}

export interface StyleDetailData {
  tagId: number
  name: string
  level?: number
  parentNames?: string
  enName?: string
  desc?: string
  cover?: string[]
  colorDeep?: string
  colorShallow?: string
  songNum?: string
  artistNum?: string
  professionalReviews?: StyleProfessionalReview
  favouriteSong?: StyleFavouriteSong
  tabs?: string[]
}

export interface StyleDetailResponse {
  code: number
  data?: StyleDetailData
}

export interface StylePageInfo {
  cursor: number
  size: number
  total?: number
  more: boolean
}

export interface StyleSongResponse {
  code: number
  data?: StyleSongData
}

export interface StyleSongData {
  page?: StylePageInfo
  songs?: ApiSong[]
}

export interface StyleAlbumResponse {
  code: number
  data?: StyleAlbumData
}

export interface StyleAlbumData {
  page?: StylePageInfo
  albums?: ApiAlbum[]
}

export interface StylePlaylistItem {
  id: number
  name: string
  cover: string
  songCount: number
  userName: string
  userId: number
  playCount: number
}

export interface StylePlaylistResponse {
  code: number
  data?: StylePlaylistData
}

export interface StylePlaylistData {
  page?: StylePageInfo
  playlist?: StylePlaylistItem[]
}

export interface StyleArtistResponse {
  code: number
  data?: StyleArtistData
}

export interface StyleArtistData {
  page?: StylePageInfo
  artists?: ApiArtist[]
}

export interface StyleDetailPageParam {
  tagId: number
  name: string
  cover?: string
  colorDeep?: string
  colorShallow?: string
}
