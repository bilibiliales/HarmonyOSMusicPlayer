import {
  DailySong,
  HappySignHotComment,
  HappySignInfo,
  HappySignInfoRaw,
  HappySignResponse,
  HistoryDetailResponse,
  HistoryRecommendResponse,
  HistoryRecommendSummary
} from '../models/home'
import { ApiClient } from './ApiClient'

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

  /** 今日乐签内容。 */
  static async happySign(): Promise<HappySignInfo> {
    const response = await ApiClient.get<HappySignResponse>('/sign/happy/info')
    if (response.code !== 200) {
      throw new Error(response.message || '今日乐签加载失败')
    }
    const raw: HappySignInfoRaw | undefined = response.data?.info
    const out = new HappySignInfo()
    if (raw) {
      out.mainText = raw.mainText ?? ''
      out.author = raw.author ?? ''
      out.backColor = raw.backColor ?? ''
      out.cover = raw.newPicUrl || raw.picUrl || ''
      out.resourceName = raw.resourceName ?? ''
      out.resourceAuthor = raw.resourceAuthor ?? ''
      out.resourceCover = raw.resourceCover ?? ''
      out.resourceUrl = raw.resourceUrl ?? ''
      out.qrCode = raw.qrCodeWithLogoUrl || raw.qrCodeUrl || ''
      out.sharePic = raw.sharePicUrl ?? ''
      out.currentUserName = raw.currentUserName ?? ''
      const comments = raw.hotComments ?? []
      for (const item of comments) {
        if (!item.content) { continue }
        const comment = new HappySignHotComment()
        comment.content = item.content
        comment.authorName = item.authorName ?? ''
        out.hotComments.push(comment)
      }
    }
    return out
  }

  /** backColor 可能是 6 位不带 # 的十六进制，统一补 #。 */
  static signBackgroundColor(value: string): string {
    const text = (value || '').trim()
    if (!text) { return '' }
    if (text.startsWith('#')) { return text }
    return /^[0-9a-fA-F]{6}$/.test(text) ? `#${text}` : ''
  }
}
