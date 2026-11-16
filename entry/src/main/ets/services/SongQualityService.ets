import { ApiParam, SongMusicDetailResponse, SongMusicQualityInfo } from '../models/api'
import { QUALITY_OPTIONS, QualityOption } from '../models/music'
import { ApiClient } from './ApiClient'
import { SongUrlService } from './SongUrlService'

export interface SongAudioResource {
  url: string
  requestedLevel: string
  selectedLevel: string
  actualLevel: string
  size: number
  type: string
  encodeType: string
  trial: boolean
}

// File availability and account entitlement are separate: the URL response is authoritative
// for the delivered level. Never label a lower-quality response with the requested level.
export class SongQualityService {
  private static params(id: string, level: string = ''): ApiParam[] {
    const params: ApiParam[] = [{ key: 'id', value: id },
      { key: 'timestamp', value: Date.now().toString() }]
    if (level) { params.push({ key: 'level', value: level }) }
    if (ApiClient.cookie) {
      const cookie = ApiClient.cookie.split(';').filter((part: string) =>
        part.trim().split('=')[0] !== 'os').join(';')
      params.push({ key: 'cookie', value: `${cookie}; os=pc;` })
    }
    return params
  }

  static async available(id: string): Promise<QualityOption[]> {
    const response = await ApiClient.get<SongMusicDetailResponse>('/song/music/detail', SongQualityService.params(id))
    if (response.code !== 200 || !response.data) {
      throw new Error(response.message || '无法查询歌曲音质，请稍后重试')
    }
    const data = response.data
    if (String(data.songId) !== id) { throw new Error('歌曲音质信息不匹配') }
    const files: (SongMusicQualityInfo | undefined)[] = [data.l, data.m, data.h, data.sq,
      data.hr, data.je, data.sk, data.db, data.jm]
    const options: QualityOption[] = []
    for (let i = 0; i < QUALITY_OPTIONS.length; i++) {
      const info = files[i]
      if (!info || info.size <= 0 || !Number.isFinite(info.size)) { continue }
      const option = QUALITY_OPTIONS[i]
      const details: string[] = []
      if (info.br > 0) { details.push(`${Math.round(info.br / 1000)} kbps`) }
      if (info.sr > 0) { details.push(`${Math.round(info.sr / 100) / 10} kHz`) }
      details.push(`${(info.size / 1024 / 1024).toFixed(1)} MB`)
      options.push({ level: option.level, title: option.title, description: details.join(' · ') })
    }
    return options
  }

  static candidates(preferred: string, available: QualityOption[]): string[] {
    const index = QUALITY_OPTIONS.findIndex((option: QualityOption) => option.level === preferred)
    if (index < 0) { throw new Error('不支持的音质设置') }
    const levels: string[] = []
    for (let i = index; i >= 0; i--) {
      const level = QUALITY_OPTIONS[i].level
      if (available.some((option: QualityOption) => option.level === level)) { levels.push(level) }
    }
    return levels
  }

  static title(level: string): string {
    return QUALITY_OPTIONS.find((option: QualityOption) => option.level === level)?.title || '未知音质'
  }

  static async playback(id: string, preferred: string): Promise<SongAudioResource> {
    const qualities = await SongQualityService.available(id)
    const levels = SongQualityService.candidates(preferred, qualities)
    if (levels.length === 0) { throw new Error('所选音质及以下档位均无可播放资源') }
    // 逐级降级：某一档没有可用地址就换下一档（下载链接接口会返回空 url）。
    for (let i = 0; i < levels.length; i++) {
      const resource = await SongQualityService.playbackAtLevel(id, levels[i], preferred)
      if (resource) { return resource }
    }
    throw new Error('当前歌曲或账号没有可播放资源')
  }

  /**
   * 播放地址统一走「获取客户端歌曲下载链接 - 新版」/song/download/url/v1。
   *
   * /song/url/v1 已 404；/song/url/v1/302 不返回大小/格式/试听信息，代价太大，已回滚。
   * 这里拿到的是真实 CDN 地址与完整元数据，因此 Range 流式播放（size > 0）可以照常工作。
   * 电台节目等没有 song/music/detail 条目的场景也用这个方法，只要 id 有效即可。
   */
  static async playbackAtLevel(id: string, level: string, preferred: string = level): Promise<SongAudioResource | undefined> {
    const item = await SongUrlService.resolve(id, level)
    if (!item) { return undefined }
    console.info(`[SongUrl] playback id=${id} level=${level} delivered=${item.level} size=${item.size}`)
    return { url: item.url, requestedLevel: preferred, selectedLevel: level,
      actualLevel: item.level || level, size: item.size || 0, type: item.type || '',
      encodeType: item.encodeType || '', trial: !!item.freeTrialInfo }
  }

  static async download(id: string, preferred: string): Promise<SongAudioResource> {
    // Recheck on confirmation as well, since the track/account may have changed while the sheet was open.
    const levels = SongQualityService.candidates(preferred, await SongQualityService.available(id))
    if (levels.length === 0) { throw new Error('所选音质及以下档位均无可下载资源') }
    for (let i = 0; i < levels.length; i++) {
      const level = levels[i]
      const item = await SongUrlService.resolve(id, level)
      if (!item || item.freeTrialInfo) { continue }
      return { url: item.url, requestedLevel: preferred, selectedLevel: level,
        actualLevel: item.level || level, size: item.size || 0, type: item.type || '',
        encodeType: item.encodeType || '', trial: false }
    }
    throw new Error('当前歌曲或账号没有完整的可下载资源')
  }
}
