/**
 * AVSession-backed background playback runtime.
 *
 * IMPORTANT: this is the ONLY file in the whole project that imports AVSession Kit.
 * It must never be statically imported by any module reachable from a cold-start
 * entry point. PlayerController loads it exclusively through
 * `await import('./MediaSessionBridge')` inside createSystemSession(), which is
 * reached only when shouldLoadMediaSession() returns true.
 *
 * Consequence: with the "background playback" switch off, this module is never
 * executed, so @kit.AVSessionKit / @ohos.multimedia.avsession is never resolved,
 * loaded, or called.
 */
import { avSession } from '@kit.AVSessionKit'
import { common } from '@kit.AbilityKit'
import {
  DesktopLyricConfig, MediaSessionApi, MediaSessionFactory, MediaSessionRegistry,
  SessionDesktopLyricStatus, SessionHandlers, SessionLoopMode, SessionLyricReadback,
  SessionMetadata, SessionPlaybackState, shouldLoadMediaSession
} from './MediaSessionContract'
import { AppSettings } from './AppSettings'

class MediaSessionRuntime implements MediaSessionApi {
  private readonly session: avSession.AVSession
  private desktopEnabled: boolean = false

  constructor(session: avSession.AVSession) {
    this.session = session
  }

  sessionId(): string {
    return this.session.sessionId
  }

  attach(handlers: SessionHandlers): void {
    try {
      this.session.onDesktopLyricVisibilityChanged((visible: boolean) => {
        handlers.onDesktopLyricVisibilityChanged(visible)
      })
    } catch (_error) {
      // Desktop lyric extension is optional on older images.
    }
    try {
      this.session.onDesktopLyricStateChanged((state: avSession.DesktopLyricState) => {
        handlers.onDesktopLyricStateChanged(state.isLocked)
      })
    } catch (_error) {
      // Desktop lyric extension is optional on older images.
    }
    this.session.on('play', handlers.onPlay)
    this.session.on('pause', handlers.onPause)
    this.session.on('playNext', handlers.onNext)
    this.session.on('playPrevious', handlers.onPrevious)
    this.session.on('seek', (time: number) => handlers.onSeek(time))
  }

  async activate(): Promise<void> {
    await this.session.activate()
  }

  async destroy(): Promise<void> {
    await this.session.destroy()
  }

  async setMetadata(metadata: SessionMetadata): Promise<void> {
    const value: avSession.AVMetadata = {
      assetId: metadata.assetId,
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      duration: metadata.duration,
      mediaImage: metadata.mediaImage,
      lyric: metadata.lyric,
      previousAssetId: metadata.previousAssetId,
      nextAssetId: metadata.nextAssetId
    }
    await this.session.setAVMetadata(value)
  }

  async setPlaybackState(state: number, position: number, loopMode: number): Promise<void> {
    const value: avSession.AVPlaybackState = {
      state: MediaSessionRuntime.toPlaybackState(state),
      speed: 1,
      position: {
        elapsedTime: Math.max(0, position),
        updateTime: Date.now()
      },
      loopMode: MediaSessionRuntime.toLoopMode(loopMode)
    }
    await this.session.setAVPlaybackState(value)
  }

  async configureDesktopLyrics(enabled: boolean, locked: boolean): Promise<void> {
    if (!(await avSession.isDesktopLyricSupported())) {
      throw new Error('当前设备不支持系统桌面歌词')
    }
    if (enabled && !this.desktopEnabled) {
      await this.session.enableDesktopLyric(true)
      this.desktopEnabled = true
    }
    if (!enabled && this.desktopEnabled) {
      await this.session.setDesktopLyricVisible(false)
    }
    if (enabled) {
      await this.session.setDesktopLyricState({ isLocked: locked })
      await this.session.setDesktopLyricVisible(true)
    }
  }

  async refreshDesktopLyrics(): Promise<SessionDesktopLyricStatus> {
    const visible = await this.session.isDesktopLyricVisible()
    const state = await this.session.getDesktopLyricState()
    return { visible: visible, locked: state.isLocked }
  }

  async readLyricMetadata(): Promise<SessionLyricReadback> {
    const controller = await this.session.getController()
    const received = await controller.getAVMetadata()
    return {
      assetId: received.assetId ? received.assetId : '',
      lyric: received.lyric ? received.lyric : ''
    }
  }

  private static toPlaybackState(state: number): avSession.PlaybackState {
    switch (state) {
      case SessionPlaybackState.PLAY:
        return avSession.PlaybackState.PLAYBACK_STATE_PLAY
      case SessionPlaybackState.PAUSE:
        return avSession.PlaybackState.PLAYBACK_STATE_PAUSE
      case SessionPlaybackState.STOP:
        return avSession.PlaybackState.PLAYBACK_STATE_STOP
      case SessionPlaybackState.COMPLETED:
        return avSession.PlaybackState.PLAYBACK_STATE_COMPLETED
      case SessionPlaybackState.ERROR:
        return avSession.PlaybackState.PLAYBACK_STATE_ERROR
      default:
        return avSession.PlaybackState.PLAYBACK_STATE_PREPARE
    }
  }

  private static toLoopMode(mode: number): avSession.LoopMode {
    if (mode === SessionLoopMode.SINGLE) {
      return avSession.LoopMode.LOOP_MODE_SINGLE
    }
    if (mode === SessionLoopMode.SHUFFLE) {
      return avSession.LoopMode.LOOP_MODE_SHUFFLE
    }
    return avSession.LoopMode.LOOP_MODE_LIST
  }
}

/** Only called from the dynamically imported, switch-gated runtime. */
export async function createMediaSession(context: common.Context, handlers: SessionHandlers,
  initial: DesktopLyricConfig): Promise<MediaSessionApi> {
  // Defence in depth: even if this module were ever loaded unexpectedly, no
  // session API may run while the background playback switch is off.
  if (!shouldLoadMediaSession(AppSettings.settingsLoaded, AppSettings.backgroundPlaybackEnabled, false)) {
    throw new Error('后台播放已关闭，媒体会话不可用')
  }
  const session = await avSession.createAVSession(context, 'HarmonyCloudMusic', 'audio')
  const runtime = new MediaSessionRuntime(session)
  runtime.attach(handlers)
  await session.activate()
  try {
    await session.setBackgroundPlayMode(avSession.BackgroundPlayMode.ENABLE_BACKGROUND_PLAY)
  } catch (_error) {
    // Older images may not expose background play mode; session still works.
  }
  if (initial.enabled) {
    try {
      await runtime.configureDesktopLyrics(true, initial.locked)
    } catch (error) {
      console.info(`[MediaSessionBridge] initial desktop lyrics failed: ${error instanceof Error ? error.message : 'unknown'}`)
    }
  }
  return runtime
}

// Side effect of the dynamic import: publish the typed factory into the neutral
// registry so PlayerController never has to cast an ESObject namespace.
const factory: MediaSessionFactory = createMediaSession
MediaSessionRegistry.factory = factory
