import { ApiParam, mapApiSong } from '../models/api'
import { PersonalFmResponse } from '../models/home'
import { songItemType } from '../models/music'
import { ApiClient } from './ApiClient'
import { AppSettings } from './AppSettings'
import { playerController } from './PlayerController'

/**
 * 私人漫游（原私人 FM）。
 *
 * 和心动模式一样是「按需生成」的队列，不落到服务端的歌单里：
 *  - `/personal_fm` 固定返回一小批歌；
 *  - `/personal/fm/mode` 可以按模式取歌（默认 / 熟悉 / 探索 / 场景）。
 *
 * 队列放到最后一首时由 `refill()` 再取一批并追加到队尾，实现无限漫游；
 * 钩子的挂载与清除都在 `PlayerController.setQueue()` 里，普通歌单不会续歌。
 */
export interface FmModeOption {
  mode: string
  submode: string
  title: string
  desc: string
}

export const FM_MODE_OPTIONS: FmModeOption[] = [
  { mode: 'DEFAULT', submode: '', title: '默认漫游', desc: '综合你的口味随机推荐' },
  { mode: 'FAMILIAR', submode: '', title: '熟悉模式', desc: '只推你听过、红心过的歌' },
  { mode: 'EXPLORE', submode: '', title: '探索模式', desc: '多推没听过的新鲜歌' },
  { mode: 'SCENE_RCMD', submode: 'EXERCISE', title: '运动', desc: '节奏更带劲，适合动起来' },
  { mode: 'SCENE_RCMD', submode: 'FOCUS', title: '专注', desc: '少人声、更平稳的背景音乐' },
  { mode: 'SCENE_RCMD', submode: 'NIGHT_EMO', title: '夜间情绪', desc: '深夜适合安静听的那一类' }
]

const DEFAULT_MODE: string = 'DEFAULT'

export class PrivateFmService {
  /** 当前选中的模式（读不到时回落默认漫游）。 */
  static current(): FmModeOption {
    return PrivateFmService.find(AppSettings.fmMode, AppSettings.fmSubmode)
  }

  private static find(mode: string, submode: string): FmModeOption {
    for (let i = 0; i < FM_MODE_OPTIONS.length; i++) {
      const option = FM_MODE_OPTIONS[i]
      if (option.mode === mode && option.submode === submode) {
        return option
      }
    }
    return FM_MODE_OPTIONS[0]
  }

  static async saveMode(mode: string, submode: string): Promise<void> {
    await AppSettings.saveFmMode(mode, submode)
  }

  /** 按模式取一批歌；默认模式走 /personal_fm，其余走 /personal/fm/mode。 */
  static async fetch(mode: string, submode: string): Promise<songItemType[]> {
    const params: ApiParam[] = [{ key: 'timestamp', value: Date.now().toString() }]
    let path = '/personal_fm'
    if (mode !== DEFAULT_MODE || submode.length > 0) {
      path = '/personal/fm/mode'
      params.push({ key: 'mode', value: mode.length > 0 ? mode : DEFAULT_MODE })
      if (mode === 'SCENE_RCMD' && submode.length > 0) {
        params.push({ key: 'submode', value: submode })
      }
    }
    const response = await ApiClient.get<PersonalFmResponse>(path, params)
    if (response.code !== 200) {
      throw new Error('私人漫游加载失败')
    }
    return (response.data || []).map((item) => mapApiSong(item))
  }

  /**
   * 取一批歌。接口单次返回的数量不稳定（未登录时往往只有 1 首），
   * 所以按需多取几次凑够 count 首，调用方拿到的是一个不重复的小列表。
   */
  static async load(count: number = 3): Promise<songItemType[]> {
    const result: songItemType[] = []
    const seen: Set<string> = new Set()
    const target = count > 0 ? count : 1
    for (let attempt = 0; attempt < 4 && result.length < target; attempt++) {
      const batch = await PrivateFmService.fetch(AppSettings.fmMode, AppSettings.fmSubmode)
      for (let i = 0; i < batch.length; i++) {
        const song = batch[i]
        if (song.id.length === 0 || seen.has(song.id)) {
          continue
        }
        seen.add(song.id)
        result.push(song)
      }
    }
    return result
  }

  /**
   * 队列放完时再取一批：过滤掉队列里已有的歌，最多取三轮。
   * 返回追加数量，0 表示这次没拿到新歌（播放器会退回从头循环）。
   */
  static async refill(): Promise<number> {
    const known: Set<string> = new Set()
    const queue = playerController.queueSnapshot()
    for (let i = 0; i < queue.length; i++) {
      known.add(queue[i].id)
    }
    const fresh: songItemType[] = []
    for (let attempt = 0; attempt < 3 && fresh.length < 3; attempt++) {
      let batch: songItemType[] = []
      try {
        batch = await PrivateFmService.fetch(AppSettings.fmMode, AppSettings.fmSubmode)
      } catch (_error) {
        break
      }
      for (let i = 0; i < batch.length; i++) {
        const song = batch[i]
        if (song.id.length > 0 && !known.has(song.id)) {
          known.add(song.id)
          fresh.push(song)
        }
      }
    }
    return fresh.length > 0 ? playerController.appendToQueue(fresh) : 0
  }
}
