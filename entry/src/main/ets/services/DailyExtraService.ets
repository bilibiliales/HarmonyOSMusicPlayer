import {
  DailySong,
  HistoryDetailResponse,
  HistoryRecommendResponse,
  HistoryRecommendSummary
} from '../models/home'
import { ApiClient } from './ApiClient'
import { SignDateParts, VipSignData, VipSignInfo, VipSignPrize, VipSignResponse } from '../models/vipSign'

/**
 * 每日推荐的附加数据：历史日推列表 / 某一天的详情 / 今日乐签。
 * 只做请求与字段整理，UI 状态由页面自己维护。
 */
export class DailyExtraService {
  /** 可查看的历史日期（近期 5 次）。 */
  static async historyDates(): Promise<HistoryRecommendSummary> {
    const response = await ApiClient.get<HistoryRecommendResponse>('/history/recommend/songs')
    if (response.code !== 200) {
      throw new Error(response.message || '历史日推加载失败')
    }
    const out = new HistoryRecommendSummary()
    const data = response.data
    if (data) {
      out.dates = data.dates ?? []
      out.description = data.description ?? ''
      out.noHistoryMessage = data.noHistoryMessage ?? ''
      out.purchaseUrl = data.purchaseUrl ?? ''
    }
    return out
  }

  /** 某一天的歌曲；空数组表示当天没有可展示的歌曲。 */
  static async historyDetail(date: string): Promise<DailySong[]> {
    if (!date) { return [] }
    const response = await ApiClient.get<HistoryDetailResponse>('/history/recommend/songs/detail', [
      { key: 'date', value: date }
    ])
    if (response.code !== 200) {
      throw new Error(response.message || '历史日推详情加载失败')
    }
    return response.data?.songs ?? []
  }

  /** 今日乐签的歌曲、寄语和本月签到权益。 */
  static async vipSign(): Promise<VipSignInfo> {
    const response = await ApiClient.get<VipSignResponse>('/vip/sign/detail', [
      { key: 'timestamp', value: String(Date.now()) }
    ])
    if (response.code !== 200 || !response.data) {
      throw new Error(response.message || '今日乐签加载失败')
    }
    return DailyExtraService.signInfo(response.data)
  }

  static signInfo(raw: VipSignData): VipSignInfo {
    const out = new VipSignInfo()
    const time = raw.time || 0
    out.time = Number.isFinite(time) && time > 0 && Number.isFinite(new Date(time).getTime()) ? time : 0
    const song = raw.songInfo
    if (song) {
      out.song = { id: song.songId && song.songId > 0 ? String(song.songId) : '',
        name: song.songName || '', author: song.artistName || '', album: song.album || '',
        img: (song.cover || '').replace(/^http:/, 'https:'), url: '' }
    }
    out.wishWords = raw.wishWords || ''
    out.wishAuthor = raw.wishUserNickname || ''
    const monthDays = raw.monthCheckInTotalDay || 0
    out.monthDays = Number.isFinite(monthDays) ? Math.max(0, Math.floor(monthDays)) : 0
    for (const item of raw.monthCheckInPrizList || []) {
      const day = item.day || 0
      if (!Number.isFinite(day) || day <= 0) { continue }
      const prize = new VipSignPrize()
      prize.id = item.prizeId || 0
      prize.day = day
      prize.name = item.prizeShowName || ''
      prize.subtitle = item.showSubTitle || ''
      prize.recordId = item.userPrizeRecordId || 0
      out.prizes.push(prize)
    }
    out.prizes.sort((left: VipSignPrize, right: VipSignPrize) => left.day - right.day)
    return out
  }

  static signDate(info: VipSignInfo): SignDateParts {
    const date = new Date(info.time || info.fetchedAt)
    return { month: String(date.getMonth() + 1).padStart(2, '0'), day: String(date.getDate()).padStart(2, '0') }
  }

  static nextSignPrize(info: VipSignInfo): VipSignPrize | undefined {
    return info.prizes.find((prize: VipSignPrize) => prize.day > info.monthDays) || info.prizes[info.prizes.length - 1]
  }

  static signPrizeStatus(info: VipSignInfo, prize: VipSignPrize): string {
    if (prize.recordId > 0) { return '已领取' }
    return info.monthDays >= prize.day ? '已达标' : `再累计 ${prize.day - info.monthDays} 天`
  }
}
