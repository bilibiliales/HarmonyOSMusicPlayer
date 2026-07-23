import { liveViewManager } from '@kit.LiveViewKit'
import { WantAgent } from '@kit.AbilityKit'
import { songItemType } from '../models/music'
import { PlaybackControlBridge } from './PlaybackControlBridge'

export class LiveViewController {
  private static readonly LIVE_VIEW_ID: number = 10001
  private static active: boolean = false
  private static sequence: number = 0
  private static revision: number = 0
  private static lastSong?: songItemType
  private static lastPlaying: boolean = false
  private static lastPosition: number = 0
  private static lastDuration: number = 0
  private static updateQueue: Promise<void> = Promise.resolve()

  public static async isLiveViewEnabled(): Promise<boolean> {
    try {
      return await liveViewManager.isLiveViewEnabled()
    } catch (_error) {
      return false
    }
  }

  private static formatTime(value: number): string {
    const totalSeconds = Math.max(0, Math.floor(value / 1000))
    return `${Math.floor(totalSeconds / 60)}:${(totalSeconds % 60).toString().padStart(2, '0')}`
  }

  private static async createLiveView(song: songItemType, isPlaying: boolean, position: number,
    duration: number, isMute: boolean = true): Promise<liveViewManager.LiveView> {
    let controlAction: WantAgent | undefined = undefined
    try {
      controlAction = await PlaybackControlBridge.getPlaybackWantAgent(isPlaying ? 'pause' : 'play')
    } catch (_error) {
    }
    const safeDuration = Math.max(1, duration || song.duration || 1)
    const safePosition = Math.max(0, Math.min(position, safeDuration))
    const progressPercent = Math.max(0, Math.min(100, safePosition * 100 / safeDuration))
    const content: liveViewManager.RichText[] = [
      { text: song.author || '未知歌手', textColor: '#FFB8B8C0' },
      { text: `  ${LiveViewController.formatTime(safePosition)} / ${LiveViewController.formatTime(safeDuration)}`,
        textColor: '#FF77777F' }
    ]
    const primary: liveViewManager.PrimaryData = {
      title: song.name || '云音乐',
      content: content,
      clickAction: controlAction,
      layoutData: {
        layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PROGRESS,
        progress: progressPercent,
        color: '#FFEF233C',
        backgroundColor: '#FF3A3A42',
        lineType: liveViewManager.LineType.LINE_TYPE_NORMAL_SOLID_LINE,
        indicatorType: liveViewManager.IndicatorType.INDICATOR_TYPE_UNDISPLAYED,
        nodeIcons: song.img ? [song.img] : []
      },
      extensionData: {
        text: isPlaying ? '暂停播放' : '继续播放',
        type: liveViewManager.ExtensionType.EXTENSION_TYPE_PROGRESS,
        progress: progressPercent,
        pic: song.img || undefined,
        clickAction: controlAction
      },
      aliveTime: 86400
    }
    const capsule: liveViewManager.ProgressCapsule = {
      type: liveViewManager.CapsuleType.CAPSULE_TYPE_PROGRESS,
      status: isPlaying ? 1 : 0,
      max: safeDuration,
      progress: safePosition,
      content: isPlaying ? 'Ⅱ' : '▶',
      backgroundColor: '#FFEF233C'
    }
    return {
      id: LiveViewController.LIVE_VIEW_ID,
      event: 'music_playback',
      sequence: ++LiveViewController.sequence,
      isMute: isMute,
      timer: {
        time: Date.now() - safePosition,
        isCountdown: false,
        isPaused: !isPlaying
      },
      lifeCycleMode: liveViewManager.LifeCycleMode.STOP_BY_APP,
      liveViewData: {
        primary: primary,
        capsule: capsule
      }
    }
  }

  private static log(event: string, detail: string): void {
    console.info(`[LiveViewController][${event}] ${detail}`)
  }

  private static async verifyActiveState(): Promise<void> {
    try {
      await liveViewManager.getActiveLiveView(LiveViewController.LIVE_VIEW_ID)
      LiveViewController.active = true
    } catch (_error) {
      LiveViewController.active = false
    }
  }

  private static async applySync(revision: number, song: songItemType, isPlaying: boolean,
    position: number, duration: number, verifyActive: boolean = false): Promise<void> {
    if (revision !== LiveViewController.revision || !await LiveViewController.isLiveViewEnabled()) {
      return
    }
    if (verifyActive) {
      await LiveViewController.verifyActiveState()
    }
    if (revision !== LiveViewController.revision) {
      return
    }
    if (!LiveViewController.active) {
      const liveView = await LiveViewController.createLiveView(song, isPlaying, position, duration, false)
      try {
        const result = await liveViewManager.startLiveView(liveView)
        LiveViewController.active = result.resultCode === 0
        LiveViewController.log('START', `code=${result.resultCode} message=${result.message}`)
        if (LiveViewController.active) {
          return
        }
      } catch (error) {
        LiveViewController.log('START_FAILED', error instanceof Error ? error.message : 'unknown error')
      }
      liveView.isMute = true
      try {
        const result = await liveViewManager.updateLiveView(liveView)
        LiveViewController.active = result.resultCode === 0
        LiveViewController.log('UPDATE_AFTER_START', `code=${result.resultCode} message=${result.message}`)
      } catch (error) {
        LiveViewController.log('UPDATE_AFTER_START_FAILED', error instanceof Error ? error.message : 'unknown error')
        LiveViewController.active = false
      }
      return
    }

    const liveView = await LiveViewController.createLiveView(song, isPlaying, position, duration, true)
    try {
      const result = await liveViewManager.updateLiveView(liveView)
      LiveViewController.active = result.resultCode === 0
      LiveViewController.log('UPDATE', `code=${result.resultCode} message=${result.message}`)
      if (LiveViewController.active) {
        return
      }
    } catch (error) {
      LiveViewController.log('UPDATE_FAILED', error instanceof Error ? error.message : 'unknown error')
      LiveViewController.active = false
    }
    liveView.isMute = false
    try {
      const result = await liveViewManager.startLiveView(liveView)
      LiveViewController.active = result.resultCode === 0
      LiveViewController.log('START_AFTER_UPDATE', `code=${result.resultCode} message=${result.message}`)
    } catch (error) {
      LiveViewController.log('START_AFTER_UPDATE_FAILED', error instanceof Error ? error.message : 'unknown error')
      LiveViewController.active = false
    }
  }

  public static sync(song: songItemType, isPlaying: boolean, position: number = 0,
    duration: number = 0): Promise<void> {
    LiveViewController.lastSong = song
    LiveViewController.lastPlaying = isPlaying
    LiveViewController.lastPosition = Math.max(0, position)
    LiveViewController.lastDuration = Math.max(0, duration || song.duration || 0)
    const revision = ++LiveViewController.revision
    const task = (): Promise<void> => LiveViewController.applySync(revision, song, isPlaying,
      LiveViewController.lastPosition, LiveViewController.lastDuration)
    const next = LiveViewController.updateQueue.then(task, task)
    LiveViewController.updateQueue = next.catch(() => {
    })
    return next
  }

  public static refresh(song: songItemType, isPlaying: boolean, position: number = 0,
    duration: number = 0): Promise<void> {
    LiveViewController.lastSong = song
    LiveViewController.lastPlaying = isPlaying
    LiveViewController.lastPosition = Math.max(0, position)
    LiveViewController.lastDuration = Math.max(0, duration || song.duration || 0)
    const revision = ++LiveViewController.revision
    const task = (): Promise<void> => LiveViewController.applySync(revision, song, isPlaying,
      LiveViewController.lastPosition, LiveViewController.lastDuration, true)
    const next = LiveViewController.updateQueue.then(task, task)
    LiveViewController.updateQueue = next.catch(() => {
    })
    return next
  }

  public static stop(): Promise<void> {
    const revision = ++LiveViewController.revision
    const task = async (): Promise<void> => {
      if (revision !== LiveViewController.revision || !LiveViewController.active || !LiveViewController.lastSong) {
        return
      }
      const liveView = await LiveViewController.createLiveView(LiveViewController.lastSong, false,
        LiveViewController.lastPosition, LiveViewController.lastDuration)
      try {
        await liveViewManager.stopLiveView(liveView)
      } catch (_error) {
      }
      LiveViewController.active = false
      LiveViewController.lastSong = undefined
      LiveViewController.lastPlaying = false
      LiveViewController.lastPosition = 0
      LiveViewController.lastDuration = 0
    }
    const next = LiveViewController.updateQueue.then(task, task)
    LiveViewController.updateQueue = next.catch(() => {
    })
    return next
  }
}
