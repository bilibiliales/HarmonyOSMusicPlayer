import { ProgramItem } from './home'
import { DjRadioItem } from './api'

export interface RadioPageParam {
  id: string
  name?: string
  cover?: string
}

export interface RadioCategory {
  id: number
  name: string
  pic56x56Url?: string
}

export interface RadioCategoriesResponse {
  code: number
  categories?: RadioCategory[]
}

export interface RadioStationsResponse {
  code: number
  djRadios?: DjRadioItem[]
  toplist?: DjRadioItem[]
  hasMore?: boolean
}

export interface RadioProgramsResponse {
  code: number
  programs?: ProgramItem[]
  more?: boolean
  count?: number
}

export interface RadioStationPage {
  items: DjRadioItem[]
  more: boolean
}

export interface DjBannerItem {
  targetId: number
  targetType: number
  pic: string
  url?: string
  typeTitle?: string
  exclusive?: boolean
}

export interface DjBannerResponse {
  code: number
  data?: DjBannerItem[]
}

export interface DjProgramTopItem {
  program: ProgramItem
  rank: number
  lastRank: number
  score: number
  programFeeType?: number
}

export interface DjProgramTopResponse {
  code: number
  updateTime?: number
  toplist?: DjProgramTopItem[]
}

export interface DjProgramDetailResponse {
  code: number
  program?: ProgramItem
}
