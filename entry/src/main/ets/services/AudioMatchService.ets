import { ApiSong, mapApiSong, songItemType } from '../models'
import { ApiClient } from './ApiClient'
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
  /** 5 秒 8kHz 单声道，按 40000 个采样点计算。 */
  static readonly SAMPLE_RATE: number = 8000
  static readonly DURATION_SECONDS: number = 5
  static readonly SAMPLE_COUNT: number = AudioMatchService.SAMPLE_RATE * AudioMatchService.DURATION_SECONDS

  static async recognize(pcm: Float32Array): Promise<MatchedSong[]> {
    const pending: ESObject = GenerateFP(pcm)
    const audioFP: string = await (pending as Promise<string>)
    const response = await ApiClient.get<AudioMatchResponse>('/audio/match', [
      { key: 'audioFP', value: audioFP },
      { key: 'duration', value: AudioMatchService.DURATION_SECONDS.toString() }
    ])
    if (response.code !== 200) {
      throw new Error(response.message || '识别失败，请重试')
    }
    const rows = response.data?.result ?? []
    const result: MatchedSong[] = []
    for (const row of rows) {
      if (!row || !row.song || !row.song.id) { continue }
      const item = new MatchedSong()
      item.song = mapApiSong(row.song)
      item.startTimeMs = Math.max(0, row.startTime ?? 0)
      result.push(item)
    }
    return result
  }
}
