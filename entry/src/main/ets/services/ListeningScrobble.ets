import { ApiClient } from './ApiClient'
import { songItemType } from '../models/music'

// Track media time actually traversed; seeks and resumed progress do not count as listening.
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
  async completed(song: songItemType, duration: number): Promise<void> {
    if (this.submitted || this.trial || song.isVoice || !this.cookie || this.cookie !== ApiClient.cookie ||
      duration <= 0 || this.listened < duration - 1500 ||
      (song.duration && duration < song.duration - 2000)) { return }
    const sourceId = song.sourceId || song.albumId || ''
    if (!sourceId || !/^\d+$/.test(sourceId)) { return }
    this.submitted = true
    await ApiClient.get<Object>('/scrobble', [
      { key: 'id', value: song.id }, { key: 'sourceid', value: sourceId },
      { key: 'time', value: Math.floor(Math.min(duration, this.listened) / 1000).toString() },
      { key: 'timestamp', value: Date.now().toString() }
    ])
  }
}
