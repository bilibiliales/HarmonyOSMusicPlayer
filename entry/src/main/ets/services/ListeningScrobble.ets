import { ApiClient } from './ApiClient'
import { ApiParam } from '../models/api'
import { songItemType } from '../models/music'

// Track media time actually traversed; seeks and resumed progress do not count as listening.
// 听歌打卡（V2 / NCBL 加密版）：
//   - 整首歌自然播放完毕 → 提交 time = 整首歌秒数（不限时长长短）
//   - 切歌且实际听歌时长 > 60 秒 → 提交 time = 实际听歌秒数
// 上报走 /scrobble/v1（服务端做 NCBL 加密），参数对齐 neteaseapi.gksm.store/scrobble.html 的 NCBL 版本。
export class ListeningScrobble {
  private listened: number = 0
  private lastPosition: number = 0
  private lastWallTime: number = 0
  private submitted: boolean = false
  private cookie: string = ''
  private trial: boolean = false

  reset(trial: boolean = false): void {
    this.listened = 0
    this.lastPosition = 0
    this.lastWallTime = 0
    this.submitted = false
    this.cookie = ApiClient.cookie
    this.trial = trial
  }
  discontinuity(): void { this.lastWallTime = 0 }
  setTrial(trial: boolean): void { this.trial = this.trial || trial }
  restart(): void { this.reset(this.trial) }
  update(position: number, playing: boolean, now: number = Date.now()): void {
    const delta = position - this.lastPosition
    const elapsed = now - this.lastWallTime
    if (playing && this.lastWallTime > 0 && delta > 0 && delta <= elapsed + 500 && elapsed < 5000) {
      this.listened += Math.min(delta, elapsed + 100)
    }
    this.lastPosition = position
    this.lastWallTime = playing ? now : 0
  }

  private canSubmit(song: songItemType): boolean {
    return !!this.cookie && this.cookie === ApiClient.cookie &&
      !this.trial && !(song.isVoice || !!song.localUri) && !this.submitted
  }

  // 提交打卡（NCBL V2）。参数在进入 await 之前全部捕获进局部变量，
  // 因此即便随后 reset() 清掉了 this.* 也不会影响本次在途请求。
  private async submit(song: songItemType, seconds: number): Promise<void> {
    const sourceId = song.sourceId || song.albumId || ''
    if (!sourceId || !/^\d+$/.test(sourceId)) { return }
    const id = song.id.toString()
    const time = Math.max(1, Math.floor(seconds)).toString()
    const name = song.name || ''
    const artist = song.author || ''
    const total = Math.floor((song.duration || 0) / 1000).toString()
    const timestamp = Date.now().toString()
    // 同步置位，避免与随后到来的 reset() 竞争导致重复提交
    this.submitted = true
    const params: ApiParam[] = [
      { key: 'id', value: id },
      { key: 'time', value: time },
      { key: 'sourceid', value: sourceId },
      { key: 'name', value: name },
      { key: 'artist', value: artist },
      { key: 'total', value: total },
      { key: 'timestamp', value: timestamp }
    ]
    await ApiClient.get<Object>('/scrobble/v1', params)
  }

  // 整首歌自然播放完毕：time 填整首歌的秒数（由调用方传 duration）。
  async completed(song: songItemType, duration: number): Promise<void> {
    if (!this.canSubmit(song) || duration <= 0) { return }
    await this.submit(song, duration / 1000)
  }

  // 切歌时由 PlayerController 在 reset() 之前调用：仅当实际听歌时长 > 60 秒才补打卡。
  async switchOut(song: songItemType, duration: number): Promise<void> {
    if (!this.canSubmit(song)) { return }
    const seconds = this.listened / 1000
    if (seconds <= 60) { return }
    await this.submit(song, seconds)
  }
}
