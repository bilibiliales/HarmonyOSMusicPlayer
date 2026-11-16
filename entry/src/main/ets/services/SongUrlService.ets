import { ApiParam, SongDownloadUrlData, SongDownloadUrlResponse } from '../models/api'
import { ApiClient } from './ApiClient'

/**
 * 歌曲播放 / 下载地址（获取客户端歌曲下载链接 - 新版）。
 *
 * 历史：`/song/url/v1` 已对任意歌曲返回 404；`/song/url/v1/302` 虽然能 302 到真实音频，
 * 但接口本身不返回 size / 格式 / 试听信息，Range 流式播放、音质展示、试听标记全部失效，
 * 代价太大。这里回滚成统一的 `/song/download/url/v1`：它返回真实 CDN 地址以及
 * size / type / encodeType / level / freeTrialInfo，播放与下载共用同一套解析。
 *
 * 接口：GET /song/download/url/v1?id=..&level=..
 *  - level：standard / higher / exhigh / lossless / hires / jyeffect / dolby / vivid / jymaster / sky
 *  - 非 VIP 账号最高「极高」；免费歌曲（fee == 0）最高可拿 Hi-Res。
 *  - cookie 需要带 os=pc，否则部分音质会拿到异常码率。
 */
export class SongUrlService {
  static readonly PATH: string = '/song/download/url/v1'

  static params(id: string, level: string): ApiParam[] {
    const params: ApiParam[] = [
      { key: 'id', value: id },
      { key: 'level', value: level },
      { key: 'timestamp', value: Date.now().toString() }
    ]
    if (ApiClient.cookie) {
      const cookie = ApiClient.cookie.split(';')
        .filter((part: string) => part.trim().split('=')[0] !== 'os')
        .join(';')
      params.push({ key: 'cookie', value: `${cookie}; os=pc;` })
    }
    return params
  }

  /**
   * 解析某一档位的音频地址；返回 undefined 表示该档位没有可用地址，
   * 调用方可以继续降级到下一档。
   */
  static async resolve(id: string, level: string): Promise<SongDownloadUrlData | undefined> {
    const response = await ApiClient.get<SongDownloadUrlResponse>(SongUrlService.PATH,
      SongUrlService.params(id, level))
    if (response.code !== 200) {
      throw new Error(`获取播放地址失败 (${response.code})`)
    }
    const item = response.data
    if (!item || !item.url) { return undefined }
    if (String(item.id) !== id) {
      // 云盘 / 电台的部分 id 会被服务端映射成另一个内部 id，只要地址有效就继续用。
      console.info(`[SongUrl] id mismatch requested=${id} returned=${item.id} level=${level}`)
    }
    return item
  }
}
