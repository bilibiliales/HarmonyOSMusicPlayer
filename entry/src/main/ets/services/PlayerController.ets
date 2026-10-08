import { SongMetadataCache } from './SongMetadataCache'
import { fileIo } from '@kit.CoreFileKit'
import { LocalLibrary } from './LocalLibrary'
import { audio } from '@kit.AudioKit'
import { ApiClient } from './ApiClient'
import { UIContext } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { avSession } from '@kit.AVSessionKit'
import { media } from '@kit.MediaKit'
import { PlayMode, songItemType } from '../models/music'
import { PlayerStore } from '../stores/PlayerStore'
import { AppSettings } from './AppSettings'
import { LiveViewController } from './LiveViewController'
import { PlaybackAction, PlaybackControlBridge } from './PlaybackControlBridge'
import { ListeningScrobble } from './ListeningScrobble'
import { SongAudioResource, SongQualityService } from './SongQualityService'
import { MemoryAudioLoad } from './MemoryAudioSource'
import { RadioService } from './RadioService'
import { CloudService } from './CloudService'

export class PlayerController {
  private static instance: PlayerController = new PlayerController()

  static getInstance(): PlayerController { return PlayerController.instance }
  private localFiles: Map<media.AVPlayer, fileIo.File> = new Map()
  private closeLocalFile(player: media.AVPlayer): void {
    const file = this.localFiles.get(player)
    if (file) { this.localFiles.delete(player); try { fileIo.closeSync(file) } catch (_error) {} }
  }

  private player?: media.AVPlayer
  private store?: PlayerStore
  private shouldAutoPlay: boolean = false
  private resumePosition: number = 0
  private playRequestToken: number = 0
  private uiContext?: UIContext
  private lastFailureToastAt: number = 0
  private sourceSongId: string = ''
  private loadingSongId: string = ''
  private playerGeneration: number = 0
  private playerCreation?: Promise<media.AVPlayer>
  private metadataRevision: number = 0
  private desktopSessionEnabled: boolean = false
  private desktopConfiguring: boolean = false
  private metadataWrites: Promise<void> = Promise.resolve()
  private desktopChanging: boolean = false
  private sourceLocalUri: string = ''
  private lyricSongId: string = ''
  private systemLyric: string = ''
  private systemSession?: avSession.AVSession
  private systemSessionCreation?: Promise<avSession.AVSession>
  private lastSystemPositionSync: number = 0
  private lastLiveViewPositionSync: number = 0
  private externalControlInProgress: boolean = false
  private released: boolean = false
  private scrobble: ListeningScrobble = new ListeningScrobble()

  private audioLoad?: MemoryAudioLoad

  private cancelAudioLoad(): void {
    this.audioLoad?.cancel()
    this.audioLoad = undefined
  }

  private foreground: boolean = true
  private switchingBackground: boolean = false

  onAppForeground(): void { this.foreground = true }

  async setBackgroundPlayback(context: common.Context, enabled: boolean): Promise<void> {
    if (this.switchingBackground || enabled === AppSettings.backgroundPlaybackEnabled) { return }
    this.switchingBackground = true
    try {
      await AppSettings.saveBackgroundPlayback(context, enabled)
      if (!enabled) {
        PlaybackControlBridge.unsubscribe()
        if (this.systemSessionCreation) {
          try { await this.systemSessionCreation } catch (_error) {}
        }
        const session = this.systemSession
        this.systemSession = undefined
        ++this.metadataRevision
        this.desktopSessionEnabled = false
        if (this.store) { this.store.desktopLyricsVisible = false }
        if (session) { await session.destroy() }
        await LiveViewController.stop()
        if (!this.foreground) { this.onAppBackground() }
      } else {
        this.subscribeSystemControls()
        await this.ensureSystemSession()
        if (this.store?.currentSong.id) {
          await this.syncSystemMetadata(this.store.currentSong)
          await this.syncSystemPlayback(this.store.isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
            avSession.PlaybackState.PLAYBACK_STATE_PAUSE)
        }
      }
      this.persistState()
    } finally { this.switchingBackground = false }
  }

  private subscribeSystemControls(): void {
    if (!AppSettings.backgroundPlaybackEnabled || this.released) { return }
    PlaybackControlBridge.subscribe((action: PlaybackAction) => this.handleExternalControl(action)).catch((error: Error) => {
      this.log('CONTROL_BRIDGE_FAILED', error.message)
    })
  }

  async release(): Promise<void> {
    this.released = true
    PlaybackControlBridge.unsubscribe()
    await this.stopAndClearSource()
    await LiveViewController.stop()
    if (this.systemSessionCreation) {
      try { await this.systemSessionCreation } catch (_error) {}
    }
    const session = this.systemSession
    this.systemSession = undefined
    if (session) {
      try { await session.destroy() } catch (_error) {}
    }
    this.store = undefined
  }

  bind(store: PlayerStore, uiContext?: UIContext): void {
    this.store = store
    this.uiContext = uiContext
    this.released = false
    this.subscribeSystemControls()
    this.ensureSystemSession().catch(() => {})
  }

  onAppBackground(): void {
    this.foreground = false
    if (!AppSettings.backgroundPlaybackEnabled) {
      this.shouldAutoPlay = false
      ++this.playRequestToken
      this.cancelAudioLoad()
      this.loadingSongId = ''
      if (this.store) { this.store.isLoading = false }
      this.pause().catch((error: Error) => this.log('FOREGROUND_PAUSE_FAILED', error.message))
      return
    }
    if (!this.store || this.store.queue.length === 0 || !this.store.currentSong.id) {
      return
    }
    const song = this.store.currentSong
    const isPlaying = this.store.isPlaying
    const position = this.store.position
    const duration = this.store.duration || song.duration || 0
    this.ensureSystemSession().then((session: avSession.AVSession | undefined) => {
      if (session) {
        session.activate().catch(() => {
        })
      }
    }).catch(() => {
    })
    this.syncSystemMetadata(song)
    this.syncSystemPlayback(isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
      avSession.PlaybackState.PLAYBACK_STATE_PAUSE, position)
    LiveViewController.refresh(song, isPlaying, position, duration).catch((error: Error) => {
      this.log('LIVE_VIEW_BACKGROUND_REFRESH_FAILED', error.message)
    })
  }

  private handleExternalControl(action: PlaybackAction): void {
    this.log('EXTERNAL_CONTROL', `action=${action} playerState=${this.player ? this.player.state : 'none'} storePlaying=${this.store?.isPlaying || false}`)
    this.performExternalControl(action).catch((error: Error) => {
      this.log('EXTERNAL_CONTROL_FAILED', error.message)
    })
  }

  private async performExternalControl(action: PlaybackAction): Promise<void> {
    if (!AppSettings.backgroundPlaybackEnabled) { return }
    if (this.released || (!AppSettings.backgroundPlaybackEnabled && !this.foreground)) { return }
    if (this.externalControlInProgress || !this.store || this.store.queue.length === 0) {
      return
    }
    this.externalControlInProgress = true
    try {
      const player = this.player
      if (action === 'pause') {
        if (player && this.sourceSongId === this.store.currentSong.id && player.state === 'playing') {
          await player.pause()
        }
      } else if (player && this.sourceSongId === this.store.currentSong.id &&
        (player.state === 'paused' || player.state === 'prepared')) {
        await player.play()
      } else if (!player || player.state !== 'playing') {
        await this.resumeFromExternalControl()
      }
      await this.wait(120)
      if (this.store.currentSong.id) {
        const actualPlaying = this.player?.state === 'playing'
        this.store.isPlaying = actualPlaying
        await LiveViewController.refresh(this.store.currentSong, actualPlaying, this.store.position,
          this.store.duration || this.store.currentSong.duration || 0)
      }
    } finally {
      this.externalControlInProgress = false
    }
  }

  private wait(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds)
    })
  }

  private async resumeFromExternalControl(): Promise<void> {
    if (!this.store || this.store.queue.length === 0) {
      return
    }
    const targetIndex = this.store.currentIndex
    const targetSongId = this.store.currentSong.id
    const storedPosition = Math.max(0, this.store.position)
    const session = await this.ensureSystemSession()
    if (session) {
      try {
        await session.activate()
      } catch (error) {
        this.log('EXTERNAL_SESSION_ACTIVATE_FAILED', error instanceof Error ? error.message : 'unknown error')
      }
    }
    await this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_PAUSE, storedPosition)
    const player = this.player
    if (player && this.sourceSongId === targetSongId) {
      try {
        if (player.state === 'paused' || player.state === 'prepared') {
          await player.play()
        } else if (player.state === 'completed') {
          this.scrobble.restart()
          player.seek(0)
          await player.play()
        } else if (player.state === 'playing') {
          return
        }
      } catch (error) {
        this.log('EXTERNAL_RESUME_PLAY_FAILED', error instanceof Error ? error.message : 'unknown error')
      }
      await this.wait(320)
      if (this.isCurrentPlayer(player, this.playerGeneration) && this.sourceSongId === targetSongId &&
        player.state === 'playing') {
        return
      }
      this.log('EXTERNAL_RESUME_NOT_PLAYING', `songId=${targetSongId} state=${player.state}`)
    }
    this.resumePosition = player?.state === 'completed' ? 0 : storedPosition
    await this.playAt(targetIndex, true, true)
  }

  private async ensureSystemSession(): Promise<avSession.AVSession | undefined> {
    if (this.released || !AppSettings.backgroundPlaybackEnabled) { return undefined }
    if (this.systemSession) {
      return this.systemSession
    }
    if (this.systemSessionCreation) {
      const session = await this.systemSessionCreation
      return !this.released && AppSettings.backgroundPlaybackEnabled ? session : undefined
    }
    const hostContext = this.uiContext?.getHostContext()
    if (!hostContext) {
      return undefined
    }
    const context = hostContext as common.Context
    const creation = avSession.createAVSession(context, 'HarmonyCloudMusic', 'audio')
    this.systemSessionCreation = creation
    let session: avSession.AVSession
    try {
      session = await creation
    } finally {
      if (this.systemSessionCreation === creation) {
        this.systemSessionCreation = undefined
      }
    }
    this.systemSession = session
    this.desktopSessionEnabled = false
    try { session.onDesktopLyricVisibilityChanged((visible: boolean) => {
      if (this.systemSession !== session) { return }
      if (this.store) { this.store.desktopLyricsVisible = visible }
      if (!this.desktopChanging && !this.desktopConfiguring) {
        AppSettings.desktopLyricsEnabled = visible
        AppSettings.saveFeature('desktop_lyrics_enabled', visible).catch(() => {})
      }
    })
    } catch (_error) {}
    try { session.onDesktopLyricStateChanged((state: avSession.DesktopLyricState) => {
      if (this.systemSession !== session) { return }
      if (this.store) { this.store.desktopLyricsLocked = state.isLocked }
      if (!this.desktopChanging && !this.desktopConfiguring) {
        AppSettings.desktopLyricsLocked = state.isLocked
        AppSettings.saveFeature('desktop_lyrics_locked', state.isLocked).catch(() => {})
      }
    })
    } catch (_error) {}
    if (this.released || !AppSettings.backgroundPlaybackEnabled) {
      this.systemSession = undefined
      await session.destroy()
      return undefined
    }
    session.on('play', () => this.handleSystemPlay())
    session.on('pause', () => this.handleSystemPause())
    session.on('playNext', () => this.next())
    session.on('playPrevious', () => this.previous())
    session.on('seek', (time: number) => this.seek(time))
    await session.activate()
    try {
      await session.setBackgroundPlayMode(avSession.BackgroundPlayMode.ENABLE_BACKGROUND_PLAY)
    } catch (_error) {
    }
    if (AppSettings.desktopLyricsEnabled) {
      try { await this.configureDesktopLyrics(session, true, AppSettings.desktopLyricsLocked) }
      catch (error) { this.log('DESKTOP_LYRICS_FAILED', String(error)) }
    }
    this.log('AVSESSION_READY', `sessionId=${session.sessionId}`)
    return session
  }

  private async configureDesktopLyrics(session: avSession.AVSession, enabled: boolean, locked: boolean): Promise<void> {
    if (!(await avSession.isDesktopLyricSupported())) { throw new Error('当前设备不支持系统桌面歌词') }
    this.desktopConfiguring = true
    try {
      if (enabled && !this.desktopSessionEnabled) {
        await session.enableDesktopLyric(true)
        this.desktopSessionEnabled = true
      }
      if (!enabled && this.desktopSessionEnabled) { await session.setDesktopLyricVisible(false) }
      if (enabled) {
        await session.setDesktopLyricState({ isLocked: locked })
        await session.setDesktopLyricVisible(true)
      }
    } finally { this.desktopConfiguring = false }
  }

  async refreshDesktopLyrics(): Promise<void> {
    const session = this.systemSession
    if (!session || !this.desktopSessionEnabled || !this.store) {
      if (this.store) { this.store.desktopLyricsVisible = false }
      return
    }
    const visible = await session.isDesktopLyricVisible()
    const state = await session.getDesktopLyricState()
    if (session !== this.systemSession) { return }
    this.store.desktopLyricsVisible = visible
    this.store.desktopLyricsLocked = state.isLocked
  }

  async setDesktopLyrics(enabled: boolean, locked: boolean): Promise<void> {
    if (this.desktopChanging) { return }
    if (enabled && !AppSettings.backgroundPlaybackEnabled) { throw new Error('请先开启后台播放以使用系统桌面歌词') }
    this.desktopChanging = true
    try {
      const session = await this.ensureSystemSession()
      if (session) { await this.configureDesktopLyrics(session, enabled, locked) }
      else if (enabled) { throw new Error('媒体会话尚未就绪') }
      await AppSettings.saveFeature('desktop_lyrics_enabled', enabled)
      await AppSettings.saveFeature('desktop_lyrics_locked', locked)
      AppSettings.desktopLyricsEnabled = enabled
      AppSettings.desktopLyricsLocked = locked
      if (enabled && this.store?.currentSong.id) {
        this.syncSystemMetadata(this.store.currentSong)
        await this.syncSystemPlayback(this.store.isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
          avSession.PlaybackState.PLAYBACK_STATE_PAUSE, this.store.position)
      }
    } finally {
      try { await this.refreshDesktopLyrics() } catch (_error) {}
      this.desktopChanging = false
    }
  }

  async setEffects(enabled: boolean): Promise<void> {
    const mode = enabled ? audio.AudioEffectMode.EFFECT_DEFAULT : audio.AudioEffectMode.EFFECT_NONE
    const supported = await audio.getAudioManager().getStreamManager().getAudioEffectInfoArray(audio.StreamUsage.STREAM_USAGE_MUSIC)
    if (!supported.includes(mode)) { throw new Error('当前输出设备不支持该音效模式') }
    if (this.player && ['prepared', 'playing', 'paused', 'completed'].includes(this.player.state)) {
      this.player.audioEffectMode = mode
    }
    await AppSettings.saveFeature('effects_enabled', enabled)
    AppSettings.effectsEnabled = enabled
  }

  private handleSystemPlay(): void {
    if (!AppSettings.backgroundPlaybackEnabled) { return }
    if (this.released || (!AppSettings.backgroundPlaybackEnabled && !this.foreground)) { return }
    if (this.externalControlInProgress || !this.store || this.store.queue.length === 0) {
      return
    }
    this.externalControlInProgress = true
    this.resumeFromExternalControl().catch((error: Error) => {
      this.log('SYSTEM_RESUME_FAILED', error.message)
      if (this.store) {
        this.store.isPlaying = false
        this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_PAUSE, this.store.position)
      }
    }).finally(() => {
      this.externalControlInProgress = false
    })
  }

  private handleSystemPause(): void {
    if (!AppSettings.backgroundPlaybackEnabled) { return }
    if (this.player && this.player.state === 'playing') {
      this.player.pause().catch(() => {
      })
    }
  }

  private avLoopMode(): avSession.LoopMode {
    if (!this.store || this.store.playMode === PlayMode.LOOP) {
      return avSession.LoopMode.LOOP_MODE_LIST
    }
    if (this.store.playMode === PlayMode.SINGLE) {
      return avSession.LoopMode.LOOP_MODE_SINGLE
    }
    return avSession.LoopMode.LOOP_MODE_SHUFFLE
  }

  private metadataCurrent(revision: number, song: songItemType, session: avSession.AVSession): boolean {
    return revision === this.metadataRevision && !this.released && session === this.systemSession &&
      this.store?.currentSong.id === song.id && this.store?.currentSong.localUri === song.localUri
  }

  private async writeMetadata(revision: number, song: songItemType, session: avSession.AVSession,
    metadata: avSession.AVMetadata): Promise<void> {
    const job = this.metadataWrites.catch(() => {}).then(async () => {
      if (this.metadataCurrent(revision, song, session)) { await session.setAVMetadata(metadata) }
    })
    this.metadataWrites = job
    await job
  }

  refreshLocalMetadata(song: songItemType): void {
    if (!song.localUri || !this.store) { return }
    this.store.queue = this.store.queue.map((item: songItemType) => item.localUri === song.localUri ? song : item)
    if (this.store.currentSong.localUri === song.localUri) {
      this.store.currentSong = song
      this.sourceSongId = song.id
      this.syncSystemMetadata(song)
      LiveViewController.refresh(song, this.store.isPlaying, this.store.position, this.store.duration).catch(() => {})
    }
    this.persistState()
  }

  private async syncSystemMetadata(song: songItemType): Promise<void> {
    const revision = ++this.metadataRevision
    try {
      const session = await this.ensureSystemSession()
      if (!session) {
        return
      }
      if (!this.metadataCurrent(revision, song, session)) { return }
      const metadata: avSession.AVMetadata = {
        assetId: song.id,
        title: song.name,
        artist: song.author,
        album: song.album || '',
        duration: song.duration || this.store?.duration || 0,
        mediaImage: song.img || '',
        lyric: this.lyricSongId === song.id + (song.localUri || '') ? this.systemLyric : '',
        previousAssetId: this.store && this.store.queue.length > 1 ? 'previous' : undefined,
        nextAssetId: this.store && this.store.queue.length > 1 ? 'next' : undefined
      }
      await this.writeMetadata(revision, song, session, metadata)
      if (!song.isDifm && !song.programId) {
        try {
          const response = await SongMetadataCache.lyrics(song)
          if (!this.metadataCurrent(revision, song, session)) { return }
          this.lyricSongId = song.id + (song.localUri || '')
          this.systemLyric = SongMetadataCache.lrc(response)
          metadata.lyric = this.systemLyric
          await this.writeMetadata(revision, song, session, metadata)
          if (this.metadataCurrent(revision, song, session) && metadata.lyric) {
            const controller = await session.getController()
            const received = await controller.getAVMetadata()
            this.log('SYSTEM_LRC_READBACK', 'songId=' + received.assetId + ' chars=' +
              (received.lyric || '').length + ' lines=' + (received.lyric || '').split('\n').length)
          }
        } catch (error) { this.log('DESKTOP_LYRIC_LOAD_FAILED', error instanceof Error ? error.message : 'unknown') }
      }
    } catch (error) {
      this.log('AVSESSION_METADATA_FAILED', error instanceof Error ? error.message : 'unknown error')
    }
  }

  private async syncSystemPlayback(state: avSession.PlaybackState, position?: number): Promise<void> {
    try {
      const session = await this.ensureSystemSession()
      if (!session) {
        return
      }
      const playbackState: avSession.AVPlaybackState = {
        state: state,
        speed: 1,
        position: {
          elapsedTime: Math.max(0, position !== undefined ? position : (this.store?.position || 0)),
          updateTime: Date.now()
        },
        loopMode: this.avLoopMode()
      }
      await session.setAVPlaybackState(playbackState)
    } catch (error) {
      this.log('AVSESSION_STATE_FAILED', error instanceof Error ? error.message : 'unknown error')
    }
  }

  private log(event: string, detail: string): void {
    console.info(`[PlayerController][${event}] ${detail}`)
  }

  private isCurrentPlayer(player: media.AVPlayer, generation: number): boolean {
    return this.player === player && this.playerGeneration === generation
  }

  private notifyPlaybackFailure(detail: string): void {
    console.error(`[PlayerController] ${detail}`)
    if (this.store) {
      this.store.errorMessage = detail
    }
    const now = Date.now()
    if (now - this.lastFailureToastAt < 800) {
      return
    }
    this.lastFailureToastAt = now
    try {
      this.uiContext?.getPromptAction().showToast({
        message: '播放失败，请稍后重试',
        duration: 2200
      })
    } catch (error) {
      console.error(`[PlayerController] toast failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player) {
      return this.player
    }
    if (this.playerCreation) {
      return await this.playerCreation
    }
    const creation = media.createAVPlayer()
    this.playerCreation = creation
    let player: media.AVPlayer
    try {
      player = await creation
    } finally {
      if (this.playerCreation === creation) {
        this.playerCreation = undefined
      }
    }
    if (this.player) {
      try {
        await player.release()
        this.closeLocalFile(player)
      } catch (_error) {
      }
      return this.player
    }
    const generation = ++this.playerGeneration
    this.player = player
    this.log('CREATE_PLAYER', `generation=${generation} state=${player.state}`)
    player.on('stateChange', (state: media.AVPlayerState) => {
      this.handleStateChange(player, generation, state)
    })
    player.on('timeUpdate', (time: number) => {
      if (this.isCurrentPlayer(player, generation) && this.store &&
        this.sourceSongId === this.store.currentSong.id) {
        this.store.position = Math.max(0, time)
        this.scrobble.update(time, this.store.isPlaying)
        const now = Date.now()
        if (now - this.lastSystemPositionSync >= 2000) {
          this.lastSystemPositionSync = now
          this.syncSystemPlayback(this.store.isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
            avSession.PlaybackState.PLAYBACK_STATE_PAUSE, time)
        }
        if (now - this.lastLiveViewPositionSync >= 2000) {
          this.lastLiveViewPositionSync = now
          LiveViewController.sync(this.store.currentSong, this.store.isPlaying, time, this.store.duration)
        }
      }
    })
    player.on('durationUpdate', (duration: number) => {
      if (this.isCurrentPlayer(player, generation) && this.store &&
        this.sourceSongId === this.store.currentSong.id) {
        this.store.duration = Math.max(0, duration)
        LiveViewController.sync(this.store.currentSong, this.store.isPlaying, this.store.position, duration)
      }
    })
    player.on('error', (error) => {
      if (!this.isCurrentPlayer(player, generation)) {
        this.log('STALE_PLAYER_ERROR', `generation=${generation} message=${error.message}`)
        return
      }
      const activeSongId = this.loadingSongId || this.sourceSongId
      this.log('PLAYBACK_ERROR', `generation=${generation} songId=${activeSongId} state=${player.state} message=${error.message}`)
      if (this.store && activeSongId.length > 0 && activeSongId === this.store.currentSong.id) {
        this.store.isLoading = false
        this.store.isPlaying = false
        this.sourceSongId = ''
        this.loadingSongId = ''
        this.shouldAutoPlay = false
        this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_ERROR)
        LiveViewController.stop()
        this.notifyPlaybackFailure(`AVPlayer error: ${error.message}`)
      }
    })
    return player
  }

  private handleStateChange(player: media.AVPlayer, generation: number, state: media.AVPlayerState): void {
    if (!this.isCurrentPlayer(player, generation)) {
      this.log('STALE_PLAYER_STATE', `generation=${generation} state=${state} activeGeneration=${this.playerGeneration}`)
      return
    }
    if (!this.store) {
      return
    }
    this.log('STATE_CHANGE', `generation=${generation} state=${state} sourceSongId=${this.sourceSongId} loadingSongId=${this.loadingSongId} storeSongId=${this.store.currentSong.id}`)
    if (state === 'initialized') {
      if (this.sourceSongId.length === 0 || this.sourceSongId !== this.store.currentSong.id) {
        return
      }
      const preparingSongId = this.sourceSongId
      this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_PREPARE)
      player.prepare().catch(() => {
        if (this.isCurrentPlayer(player, generation) && this.store && preparingSongId === this.store.currentSong.id) {
          this.store.isLoading = false
          this.store.isPlaying = false
          this.sourceSongId = ''
          this.loadingSongId = ''
          this.shouldAutoPlay = false
          this.notifyPlaybackFailure('audio resource prepare failed')
        }
      })
    } else if (state === 'prepared') {
      if (this.sourceSongId.length === 0 || this.sourceSongId !== this.store.currentSong.id) {
        return
      }
      const expectedDuration = this.store.currentSong.duration
      player.loop = false
      try { player.audioEffectMode = AppSettings.effectsEnabled ? audio.AudioEffectMode.EFFECT_DEFAULT : audio.AudioEffectMode.EFFECT_NONE }
      catch (error) { this.log('AUDIO_EFFECT_FAILED', String(error)) }
      this.store.duration = Math.max(0, player.duration)
      this.store.isLoading = false
      this.loadingSongId = ''
      this.syncSystemMetadata(this.store.currentSong)
      this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_PAUSE)
      LiveViewController.sync(this.store.currentSong, false, this.store.position, this.store.duration)
      this.log('PREPARED', `generation=${generation} songId=${this.sourceSongId} expectedDuration=${expectedDuration} actualDuration=${player.duration} autoPlay=${this.shouldAutoPlay}`)
      if (this.resumePosition > 0) {
        player.seek(this.resumePosition)
        this.resumePosition = 0
      }
      if (this.shouldAutoPlay && (AppSettings.backgroundPlaybackEnabled || this.foreground)) {
        player.play().catch(() => {
          if (this.isCurrentPlayer(player, generation) && this.store) {
            this.store.isPlaying = false
            this.notifyPlaybackFailure('audio resource play failed')
          }
        })
      }
    } else if (state === 'playing') {
      if (!AppSettings.backgroundPlaybackEnabled && !this.foreground) {
        this.shouldAutoPlay = false
        player.pause().catch((error: Error) => this.log('FOREGROUND_PAUSE_FAILED', error.message))
        return
      }
      if (this.sourceSongId !== this.store.currentSong.id) {
        return
      }
      player.loop = false
      this.store.isPlaying = true
      this.scrobble.update(Math.max(0, player.currentTime), true)
      this.store.isLoading = false
      this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_PLAY)
      LiveViewController.sync(this.store.currentSong, true, this.store.position, this.store.duration)
      this.persistState()
      this.log('PLAYING_CONFIRMED', `generation=${generation} songId=${this.sourceSongId} duration=${player.duration}`)
    } else if (state === 'paused') {
      this.scrobble.update(Math.max(0, player.currentTime), this.store.isPlaying)
      this.scrobble.discontinuity()
      if (this.sourceSongId === this.store.currentSong.id) {
        this.store.isPlaying = false
        this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_PAUSE)
        this.store.position = Math.max(0, player.currentTime)
        LiveViewController.sync(this.store.currentSong, false, this.store.position, this.store.duration)
        this.persistState()
      }
    } else if (state === 'completed') {
      if (this.sourceSongId !== this.store.currentSong.id) {
        return
      }
      this.store.isPlaying = false
      this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_COMPLETED)
      this.store.position = this.store.duration
      this.scrobble.update(this.store.duration, true)
      this.scrobble.completed(this.store.currentSong, this.store.duration).catch((error: Error) => {
        this.log('SCROBBLE_FAILED', error.message)
      })
      LiveViewController.sync(this.store.currentSong, false, this.store.position, this.store.duration)
      this.handleCompleted()
    } else if (state === 'error') {
      const activeSongId = this.loadingSongId || this.sourceSongId
      if (activeSongId === this.store.currentSong.id) {
        this.store.isPlaying = false
        this.store.isLoading = false
        this.sourceSongId = ''
        this.loadingSongId = ''
        this.shouldAutoPlay = false
        this.resumePosition = 0
        this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_ERROR)
        LiveViewController.stop()
      }
    }
  }

  private persistState(): void {
    if (!this.store) {
      return
    }
    AppSettings.savePlayerState(this.store).catch(() => {
    })
  }

  private async replacePlayerForSongSwitch(requestToken: number): Promise<media.AVPlayer | undefined> {
    const player = this.player
    const oldGeneration = this.playerGeneration
    this.sourceSongId = ''
    this.loadingSongId = ''
    this.shouldAutoPlay = false
    if (this.store) {
      this.store.isPlaying = false
    }
    if (player) {
      this.player = undefined
      ++this.playerGeneration
      this.log('RELEASE_OLD_PLAYER', `requestToken=${requestToken} generation=${oldGeneration} state=${player.state}`)
      try {
        await player.release()
        this.closeLocalFile(player)
        this.log('OLD_PLAYER_RELEASED', `requestToken=${requestToken} generation=${oldGeneration}`)
      } catch (error) {
        this.closeLocalFile(player)
        this.log('OLD_PLAYER_RELEASE_FAILED', `requestToken=${requestToken} generation=${oldGeneration} message=${error instanceof Error ? error.message : 'unknown error'}`)
      }
    }
    if (requestToken !== this.playRequestToken) {
      this.log('STALE_REQUEST', `stage=afterRelease requestToken=${requestToken} activeToken=${this.playRequestToken}`)
      return undefined
    }
    return await this.ensurePlayer()
  }

  private hasReusableSource(songId: string): boolean {
    return songId.length > 0 && (this.sourceSongId === songId || this.loadingSongId === songId)
  }

  private async resolveSongResource(song: songItemType, requestToken: number): Promise<SongAudioResource> {
    let resource: SongAudioResource | undefined
    if (song.isCloud) {
      resource = await CloudService.playback(song.id)
    } else if (song.isDifm) {
      if (!/^https?:\/\//i.test(song.url)) { throw new Error('频道音源已失效，请返回音乐电台刷新曲目') }
      resource = { url: song.url, requestedLevel: '', selectedLevel: '', actualLevel: '',
        size: 0, type: '', encodeType: '', trial: false }
    } else if (song.programId) {
      resource = await RadioService.audio(song.id)
    } else if (song.isVoice) {
      resource = await SongQualityService.playbackAtLevel(song.id, 'standard')
      if (!resource && song.url) {
        resource = { url: song.url, requestedLevel: '', selectedLevel: '', actualLevel: '',
          size: 0, type: '', encodeType: '', trial: false }
      }
    } else {
      resource = await SongQualityService.playback(song.id, this.store?.quality || 'exhigh')
    }
    if (!resource) { throw new Error('暂无可播放音源') }
    if (requestToken === this.playRequestToken && this.store) {
      this.store.actualQuality = resource.actualLevel
      this.scrobble.setTrial(resource.trial)
      this.log('QUALITY_RESOLVED', `songId=${song.id} requested=${resource.requestedLevel} selected=${resource.selectedLevel} actual=${resource.actualLevel}`)
    }
    return resource
  }

  async playAt(index: number, autoPlay: boolean = true, forceReload: boolean = false): Promise<void> {
    if (this.released || (!AppSettings.backgroundPlaybackEnabled && !this.foreground)) { return }
    if (!this.store || this.store.queue.length === 0) {
      this.log('PLAY_AT_IGNORED', 'reason=emptyQueue')
      return
    }
    const safeIndex = Math.max(0, Math.min(index, this.store.queue.length - 1))
    const song = this.store.queue[safeIndex]
    this.log('PLAY_AT_START', `targetSongId=${song.id} targetName=${song.name} index=${safeIndex} autoPlay=${autoPlay} forceReload=${forceReload} sourceSongId=${this.sourceSongId} loadingSongId=${this.loadingSongId}`)
    if (!forceReload && this.hasReusableSource(song.id) && this.sourceLocalUri === (song.localUri || '')) {
      this.log('REUSE_SOURCE', `songId=${song.id} index=${safeIndex} playerState=${this.player ? this.player.state : 'none'}`)
      this.store.selectAt(safeIndex, true)
      this.store.errorMessage = ''
      this.persistState()
      this.syncSystemMetadata(song)
      if (autoPlay && this.loadingSongId.length === 0) {
        const reusablePlayer = await this.ensurePlayer()
        if (reusablePlayer.state === 'paused' || reusablePlayer.state === 'prepared') {
          await reusablePlayer.play()
        } else if (reusablePlayer.state === 'completed') {
          this.scrobble.restart()
          reusablePlayer.seek(0)
          await reusablePlayer.play()
        }
      }
      return
    }

    const requestToken = ++this.playRequestToken
    this.sourceLocalUri = song.localUri || ''
    this.cancelAudioLoad()
    if (!forceReload) { this.scrobble.reset() }
    this.store.actualQuality = ''
    if (!forceReload) {
      this.resumePosition = 0
    }
    this.store.selectAt(safeIndex, false)
    this.store.isLoading = true
    this.store.isPlaying = false
    this.store.errorMessage = ''
    this.persistState()
    this.syncSystemMetadata(song)
    this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_PREPARE, 0)
    let player: media.AVPlayer | undefined
    try {
      player = await this.replacePlayerForSongSwitch(requestToken)
    } catch (error) {
      if (requestToken === this.playRequestToken) {
        this.store.isLoading = false
        this.store.isPlaying = false
        this.notifyPlaybackFailure(error instanceof Error ? error.message : 'player initialization failed')
      }
      return
    }
    if (!player || requestToken !== this.playRequestToken) {
      this.log('STALE_REQUEST', `stage=playerReady requestToken=${requestToken} activeToken=${this.playRequestToken}`)
      return
    }
    const generation = this.playerGeneration
    this.loadingSongId = song.id
    this.shouldAutoPlay = autoPlay
    try {
      if (song.localUri) {
        const file = await LocalLibrary.open(song.localUri, song.localManaged)
        let attached = false
        try {
          const stat = await fileIo.stat(file.fd)
          if (requestToken !== this.playRequestToken || !this.isCurrentPlayer(player, generation)) { return }
          if (!stat.size) { throw new Error('本地音频文件为空') }
          this.sourceSongId = song.id
          this.localFiles.set(player, file)
          attached = true
          player.fdSrc = { fd: file.fd, offset: 0, length: stat.size }
        } finally { if (!attached) { await fileIo.close(file) } }
        return
      }
      const resource = await this.resolveSongResource(song, requestToken)
      if (requestToken !== this.playRequestToken || this.store.currentSong.id !== song.id ||
        !this.isCurrentPlayer(player, generation)) {
        this.log('STALE_REQUEST', `stage=urlResolved requestToken=${requestToken} activeToken=${this.playRequestToken} targetSongId=${song.id} storeSongId=${this.store?.currentSong.id} generation=${generation} activeGeneration=${this.playerGeneration}`)
        return
      }
      const load = new MemoryAudioLoad()
      this.audioLoad = load
      const source = await load.load(resource.url, resource.size)
      if (this.audioLoad === load) { this.audioLoad = undefined }
      if (requestToken !== this.playRequestToken || this.store.currentSong.id !== song.id ||
        !this.isCurrentPlayer(player, generation)) { return }
      this.sourceSongId = song.id
      this.log('SET_MEMORY_SOURCE', `requestToken=${requestToken} generation=${generation} songId=${song.id} bytes=${source.size}`)
      // The descriptor callback retains the complete file until this AVPlayer is released.
      player.dataSrc = source.descriptor()
    } catch (error) {
      if (requestToken !== this.playRequestToken) {
        return
      }
      this.store.isLoading = false
      this.store.isPlaying = false
      this.sourceSongId = ''
      this.loadingSongId = ''
      this.shouldAutoPlay = false
      this.resumePosition = 0
      this.cancelAudioLoad()
      this.store.actualQuality = ''
      this.notifyPlaybackFailure(error instanceof Error ? error.message : 'unable to load audio')
    }
  }

  async setQueue(queue: songItemType[], index: number = 0, autoPlay: boolean = true): Promise<void> {
    if (!this.store) {
      return
    }
    if (queue.length === 0) {
      await this.clearQueue()
      return
    }
    const safeIndex = Math.max(0, Math.min(index, queue.length - 1))
    const targetSong = queue[safeIndex]
    const preservePlayback = this.hasReusableSource(targetSong.id)
    this.store.setQueue(queue, safeIndex, preservePlayback)
    this.persistState()
    await this.playAt(this.store.currentIndex, autoPlay)
  }

  async insertNext(songs: songItemType[]): Promise<void> {
    if (!this.store || songs.length === 0) { return }
    if (!this.store.hasQueue()) {
      this.store.setQueue(songs, 0, false)
      this.persistState()
      return
    }
    const queue = this.store.queue.slice()
    queue.splice(this.store.currentIndex + 1, 0, ...songs)
    this.store.setQueue(queue, this.store.currentIndex, true)
    this.persistState()
  }

  async toggle(): Promise<void> {
    if (this.released || (!AppSettings.backgroundPlaybackEnabled && !this.foreground)) { return }
    if (!this.store || this.store.queue.length === 0 || this.store.isLoading) {
      return
    }
    const player = await this.ensurePlayer()
    if (player.state === 'playing') {
      await player.pause()
    } else if (player.state === 'paused' || player.state === 'prepared') {
      await player.play()
    } else if (player.state === 'completed') {
      this.scrobble.restart()
      player.seek(0)
      await player.play()
    } else {
      await this.playAt(this.store.currentIndex, true)
    }
  }

  async pause(): Promise<void> {
    if (this.player && this.player.state === 'playing') {
      await this.player.pause()
    }
  }

  async previous(): Promise<void> {
    if (!this.store || this.store.queue.length === 0) {
      return
    }
    if (this.store.position > 5000) {
      this.seek(0)
      return
    }
    let index = this.store.currentIndex <= 0 ? this.store.queue.length - 1 : this.store.currentIndex - 1
    if (this.store.playMode === PlayMode.SHUFFLE && this.store.queue.length > 1) {
      index = this.randomIndex()
    }
    await this.playAt(index, true)
  }

  private randomIndex(): number {
    if (!this.store || this.store.queue.length <= 1) {
      return 0
    }
    let index = this.store.currentIndex
    while (index === this.store.currentIndex) {
      index = Math.floor(Math.random() * this.store.queue.length)
    }
    return index
  }

  async next(): Promise<void> {
    if (!this.store || this.store.queue.length === 0) {
      return
    }
    let index = this.store.currentIndex + 1
    if (this.store.playMode === PlayMode.SHUFFLE && this.store.queue.length > 1) {
      index = this.randomIndex()
    } else if (index >= this.store.queue.length) {
      index = 0
    }
    await this.playAt(index, true)
  }

  private handleCompleted(): void {
    if (this.released || (!AppSettings.backgroundPlaybackEnabled && !this.foreground)) { return }
    if (!this.store || this.store.queue.length === 0) {
      return
    }
    if (this.store.playMode === PlayMode.SINGLE) {
      this.scrobble.restart()
      this.seek(0)
      this.player?.play()
      return
    }
    if (this.store.playMode === PlayMode.SHUFFLE) {
      this.next()
      return
    }
    if (this.store.currentIndex >= this.store.queue.length - 1) {
      this.playAt(0, true)
    } else {
      this.playAt(this.store.currentIndex + 1, true)
    }
  }

  seek(position: number): void {
    this.scrobble.discontinuity()
    if (!this.player || !this.store || this.store.queue.length === 0 || this.sourceSongId !== this.store.currentSong.id) {
      return
    }
    const safePosition = Math.max(0, Math.min(position, this.store.duration))
    this.player.seek(safePosition)
    this.store.position = safePosition
    this.syncSystemPlayback(this.store.isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
      avSession.PlaybackState.PLAYBACK_STATE_PAUSE, safePosition)
    LiveViewController.sync(this.store.currentSong, this.store.isPlaying, safePosition, this.store.duration)
  }

  cycleMode(): void {
    if (!this.store) {
      return
    }
    if (this.store.playMode === PlayMode.LOOP) {
      this.store.playMode = PlayMode.SINGLE
    } else if (this.store.playMode === PlayMode.SINGLE) {
      this.store.playMode = PlayMode.SHUFFLE
    } else {
      this.store.playMode = PlayMode.LOOP
    }
    this.persistState()
    this.syncSystemPlayback(this.store.isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
      avSession.PlaybackState.PLAYBACK_STATE_PAUSE)
    if (this.player) {
      const validStates: media.AVPlayerState[] = ['prepared', 'playing', 'paused', 'completed']
      if (validStates.indexOf(this.player.state) >= 0) {
        this.player.loop = false
      }
    }
  }

  async changeQuality(level: string): Promise<void> {
    if (!this.store) { return }
    if (this.store.quality === level && this.store.actualQuality === level &&
      this.sourceSongId === this.store.currentSong.id) { return }
    const wasPlaying = this.store.isPlaying
    this.resumePosition = this.store.position
    this.store.quality = level
    await this.playAt(this.store.currentIndex, wasPlaying, true)
  }

  async removeAt(index: number): Promise<void> {
    if (!this.store || index < 0 || index >= this.store.queue.length) {
      return
    }
    const removingCurrent = this.store.removeAt(index)
    this.persistState()
    if (this.store.queue.length === 0) {
      await this.stopAndClearSource()
      return
    }
    if (removingCurrent) {
      await this.playAt(this.store.currentIndex, true)
    }
  }

  private async stopAndClearSource(): Promise<void> {
    const requestToken = ++this.playRequestToken
    this.cancelAudioLoad()
    ++this.metadataRevision
    this.lyricSongId = ''
    this.systemLyric = ''
    this.sourceLocalUri = ''
    this.sourceSongId = ''
    this.loadingSongId = ''
    this.shouldAutoPlay = false
    this.resumePosition = 0
    if (!this.player && this.playerCreation) {
      try {
        await this.playerCreation
      } catch (_error) {
      }
    }
    const player = this.player
    const generation = this.playerGeneration
    if (player) {
      this.player = undefined
      ++this.playerGeneration
      this.log('RELEASE_PLAYER_FOR_CLEAR', `requestToken=${requestToken} generation=${generation} state=${player.state}`)
      try {
        await player.release()
        this.closeLocalFile(player)
      } catch (error) {
        this.closeLocalFile(player)
        this.log('RELEASE_PLAYER_FOR_CLEAR_FAILED', `generation=${generation} message=${error instanceof Error ? error.message : 'unknown error'}`)
      }
    }
    this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_STOP, 0)
    LiveViewController.stop()
  }

  async clearQueue(): Promise<void> {
    if (!this.store) {
      return
    }
    this.store.clearQueue()
    await this.stopAndClearSource()
    this.persistState()
  }
}

export const playerController = PlayerController.getInstance()
