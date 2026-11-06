// 定时关闭（睡眠定时器）全局服务。
// 倒计时仅在播放态由 PlayerController 按真实流逝时间递减；归零时：
//   - 未开启"播完整首歌后停止" → 立即暂停播放；
//   - 开启"播完整首歌后停止" → 标记 pendingStop，待当前歌曲自然播完后再暂停。
export class SleepTimerService {
  static enabled: boolean = false
  static stopAfterSong: boolean = false
  static remainingMs: number = 0
  static totalMs: number = 0
  static pendingStop: boolean = false

  static start(minutes: number, stopAfterSong: boolean): void {
    SleepTimerService.startMs(minutes * 60 * 1000, stopAfterSong)
  }

  static startMs(ms: number, stopAfterSong: boolean): void {
    if (ms <= 0) { return }
    SleepTimerService.enabled = true
    SleepTimerService.stopAfterSong = stopAfterSong
    SleepTimerService.totalMs = ms
    SleepTimerService.remainingMs = ms
    SleepTimerService.pendingStop = false
  }

  static cancel(): void {
    SleepTimerService.enabled = false
    SleepTimerService.stopAfterSong = false
    SleepTimerService.remainingMs = 0
    SleepTimerService.totalMs = 0
    SleepTimerService.pendingStop = false
  }

  // 由 PlayerController 在播放中调用，按真实流逝毫秒递减
  static tick(deltaMs: number): void {
    if (!SleepTimerService.enabled || SleepTimerService.remainingMs <= 0 || deltaMs <= 0) { return }
    SleepTimerService.remainingMs = Math.max(0, SleepTimerService.remainingMs - deltaMs)
    if (SleepTimerService.remainingMs <= 0 && SleepTimerService.stopAfterSong) {
      SleepTimerService.pendingStop = true
    }
  }

  // 当前歌曲自然播完时由 PlayerController 调用：若为"播完整首歌后停止"则消耗标记并停止
  static consumePendingStop(): boolean {
    if (SleepTimerService.pendingStop) {
      SleepTimerService.pendingStop = false
      SleepTimerService.enabled = false
      SleepTimerService.remainingMs = 0
      SleepTimerService.totalMs = 0
      return true
    }
    return false
  }

  static get remainingSeconds(): number {
    return Math.ceil(SleepTimerService.remainingMs / 1000)
  }

  static format(ms: number): string {
    const total = Math.max(0, Math.ceil(ms / 1000))
    const m = Math.floor(total / 60)
    const s = total % 60
    return `${m < 10 ? '0' + m : '' + m}:${s < 10 ? '0' + s : '' + s}`
  }
}
