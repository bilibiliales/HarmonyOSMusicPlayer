import { songItemType } from './music'

export interface VipSignSongRaw {
  songId?: number
  songName?: string
  artistName?: string
  album?: string
  cover?: string
  artistIds?: number[]
}

export interface VipSignPrizeRaw {
  prizeId?: number
  vipType?: number
  prizeType?: number
  day?: number
  prizeShowName?: string
  showSubTitle?: string
  unitNum?: number
  userPrizeRecordId?: number
  time?: number
}

export interface VipSignData {
  recordId?: number
  userId?: number
  time?: number
  songSrc?: number
  songInfo?: VipSignSongRaw
  wishWords?: string
  wishWordType?: number
  wishUserNickname?: string
  monthCheckInTotalDay?: number
  monthCheckInPrizList?: VipSignPrizeRaw[]
}

export interface VipSignResponse { code: number; message?: string; data?: VipSignData }
export interface SignDateParts { month: string; day: string }

export class VipSignPrize {
  id: number = 0
  day: number = 0
  name: string = ''
  subtitle: string = ''
  recordId: number = 0
}

/** 乐签只展示接口返回的歌曲、寄语和签到奖励，不据此自动签到或领取。 */
export class VipSignInfo {
  time: number = 0
  fetchedAt: number = Date.now()
  song: songItemType = { id: '', name: '', author: '', img: '', url: '', album: '' }
  wishWords: string = ''
  wishAuthor: string = ''
  monthDays: number = 0
  prizes: VipSignPrize[] = []
}
