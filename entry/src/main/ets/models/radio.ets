import { ProgramItem } from './home'

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
