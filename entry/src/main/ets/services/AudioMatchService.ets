import { ApiSong, mapApiSong, songItemType } from '../models'
import { ApiClient } from './ApiClient'
import { http } from '@kit.NetworkKit'
import { GenerateFP } from '../libs/audiofp/afp'

/** /audio/match 返回的单条命中：歌曲本体 + 在歌中的起始时间。 */
export interface AudioMatchRawRow {
  song: ApiSong
  startTime?: number
}

interface AudioMatchData {
  result?: AudioMatchRawRow[]
}

interface AudioMatchResponse {
  code: number
  message?: string
  data?: AudioMatchData
}

export class MatchedSong {
  song: songItemType | undefined = undefined
  startTimeMs: number = 0
}

/**
 * 听歌识曲：把 8kHz 单声道 Float32 PCM 交给官方音频指纹运行时生成 AFP，
 * 再用 AFP 查询匹配结果。指纹算法完全在本地执行，不依赖网页。
 */
export class AudioMatchService {
  /** 官方 demo 使用 3 秒 8kHz 单声道 AFP。 */
  static readonly SAMPLE_RATE: number = 8000
  static readonly DURATION_SECONDS: number = 3
  static readonly SAMPLE_COUNT: number = AudioMatchService.SAMPLE_RATE * AudioMatchService.DURATION_SECONDS

  static async recognize(pcm: Float32Array): Promise<MatchedSong[]> {
    const audioFP: string = await AudioMatchService.fingerprintNative(pcm)
    return AudioMatchService.recognizeByFP(audioFP)
  }

  /** 原生（wasm2js）指纹实现，作为网页引擎不可用时的兜底。 */
  static async fingerprintNative(pcm: Float32Array): Promise<string> {
    const pending: ESObject = GenerateFP(pcm)
    return await (pending as Promise<string>)
  }

  /** 用已经算好的 base64 音频指纹查询 /audio/match。 */
  static async recognizeByFP(audioFP: string): Promise<MatchedSong[]> {
    const duration = AudioMatchService.DURATION_SECONDS.toString()
    const boundary = '----HarmonyAfpBoundary' + Date.now().toString()
    const body = `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="duration"\r\n\r\n${duration}\r\n` +
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="audioFP"\r\n\r\n${audioFP}\r\n` +
      `--${boundary}--\r\n`
    const url = `${ApiClient.baseUrl}/audio/match?duration=${duration}&audioFP=${encodeURIComponent(audioFP)}`
    const request = http.createHttp()
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': `multipart/form-data; boundary=${boundary}`,
          'Cookie': ApiClient.cookie
        },
        body: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 20000,
        usingCache: false
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`识别请求失败 (${response.responseCode})`)
      }
      const payload = JSON.parse(response.result as string) as AudioMatchResponse
      if (payload.code !== 200) {
        throw new Error(payload.message || '识别失败，请重试')
      }
      const rows = payload.data?.result ?? []
      const result: MatchedSong[] = []
      for (const row of rows) {
        if (!row || !row.song || !row.song.id) { continue }
        const item = new MatchedSong()
        item.song = mapApiSong(row.song)
        item.startTimeMs = Math.max(0, row.startTime ?? 0)
        result.push(item)
      }
      return result
    } finally {
      request.destroy()
    }
  }

  /** 多次识别结果按歌曲 id 去重。 */
  static dedupe(rows: MatchedSong[]): MatchedSong[] {
    const seen: Set<string> = new Set<string>()
    const out: MatchedSong[] = []
    for (const row of rows) {
      if (!row.song || !row.song.id || seen.has(row.song.id)) { continue }
      seen.add(row.song.id)
      out.push(row)
    }
    return out
  }
}
