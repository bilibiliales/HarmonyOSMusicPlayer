import { UIContext } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { avSession } from '@kit.AVSessionKit'
import { media } from '@kit.MediaKit'
import { PlayMode, songItemType } from '../models/music'
import { ApiParam, SongDownloadUrlResponse, SongUrlData, SongUrlResponse } from '../models/api'
import { PlayerStore } from '../stores/PlayerStore'
import { ApiClient } from './ApiClient'
import { AppSettings } from './AppSettings'
import { LiveViewController } from './LiveViewController'
import { PlaybackAction, PlaybackControlBridge } from './PlaybackControlBridge'

export class PlayerController {
  private static instance: PlayerController = new PlayerController()
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
  private systemSession?: avSession.AVSession
  private systemSessionCreation?: Promise<avSession.AVSession>
  private lastSystemPositionSync: number = 0
  private lastLiveViewPositionSync: number = 0
  private externalControlInProgress: boolean = false

  static getInstance(): PlayerController {
    return PlayerController.instance
  }

  bind(store: PlayerStore, uiContext?: UIContext): void {
    this.store = store
    this.uiContext = uiContext
    PlaybackControlBridge.subscribe((action: PlaybackAction) => this.handleExternalControl(action)).catch((error: Error) => {
      this.log('CONTROL_BRIDGE_FAILED', error.message)
    })
    this.ensureSystemSession().catch(() => {
    })
  }

  onAppBackground(): void {
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
    if (this.systemSession) {
      return this.systemSession
    }
    if (this.systemSessionCreation) {
      return await this.systemSessionCreation
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
    this.log('AVSESSION_READY', `sessionId=${session.sessionId}`)
    return session
  }

  private handleSystemPlay(): void {
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

  private async syncSystemMetadata(song: songItemType): Promise<void> {
    try {
      const session = await this.ensureSystemSession()
      if (!session) {
        return
      }
      const metadata: avSession.AVMetadata = {
        assetId: song.id,
        title: song.name,
        artist: song.author,
        album: song.album || '',
        duration: song.duration || this.store?.duration || 0,
        mediaImage: song.img || '',
        previousAssetId: this.store && this.store.queue.length > 1 ? 'previous' : undefined,
        nextAssetId: this.store && this.store.queue.length > 1 ? 'next' : undefined
      }
      await session.setAVMetadata(metadata)
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

  private urlSummary(url: string): string {
    const queryIndex = url.indexOf('?')
    const cleanUrl = queryIndex >= 0 ? url.substring(0, queryIndex) : url
    const parts = cleanUrl.split('/')
    const tail = parts.length > 0 ? parts[parts.length - 1] : cleanUrl
    return `${tail} urlLength=${url.length}`
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
      player.loop = this.store.playMode === PlayMode.SINGLE
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
      if (this.shouldAutoPlay) {
        player.play().catch(() => {
          if (this.isCurrentPlayer(player, generation) && this.store) {
            this.store.isPlaying = false
            this.notifyPlaybackFailure('audio resource play failed')
          }
        })
      }
    } else if (state === 'playing') {
      if (this.sourceSongId !== this.store.currentSong.id) {
        return
      }
      player.loop = this.store.playMode === PlayMode.SINGLE
      this.store.isPlaying = true
      this.store.isLoading = false
      this.syncSystemPlayback(avSession.PlaybackState.PLAYBACK_STATE_PLAY)
      LiveViewController.sync(this.store.currentSong, true, this.store.position, this.store.duration)
      this.persistState()
      this.log('PLAYING_CONFIRMED', `generation=${generation} songId=${this.sourceSongId} duration=${player.duration}`)
    } else if (state === 'paused') {
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
        this.log('OLD_PLAYER_RELEASED', `requestToken=${requestToken} generation=${oldGeneration}`)
      } catch (error) {
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

  private playbackCookie(): string {
    const cookie = ApiClient.cookie
    if (cookie.length === 0) {
      return ''
    }
    if (cookie.indexOf('os=') >= 0) {
      return cookie
    }
    return `${cookie}; os=pc;`
  }

  private bitrateForLevel(level: string): number {
    if (level === 'standard') {
      return 128000
    }
    if (level === 'higher') {
      return 192000
    }
    if (level === 'exhigh') {
      return 320000
    }
    return 999000
  }

  private extractUrlItem(data: SongUrlResponse): SongUrlData | null {
    if (data.data && data.data.length > 0) {
      return data.data[0]
    }
    return null
  }

  private async attemptUrl(endpoint: string, body: Record<string, string>, songId: string,
    requestToken: number): Promise<string> {
    try {
      const params: ApiParam[] = []
      const keys = Object.keys(body)
      for (let i = 0; i < keys.length; i++) {
        params.push({ key: keys[i], value: body[keys[i]] })
      }
      params.push({ key: 'timestamp', value: Date.now().toString() })
      const response = await ApiClient.get<SongUrlResponse>(endpoint, params)
      const item = this.extractUrlItem(response)
      if (item && item.url && item.url.length > 0) {
        if (item.id.toString() !== songId) {
          this.log('URL_ID_MISMATCH', `requestToken=${requestToken} endpoint=${endpoint} requestedSongId=${songId} responseSongId=${item.id} rejected=true`)
          return ''
        }
        this.log('URL_RESOLVED', `requestToken=${requestToken} endpoint=${endpoint} requestedSongId=${songId} responseSongId=${item.id} ${this.urlSummary(item.url)}`)
        return item.url
      }
      this.log('URL_EMPTY', `requestToken=${requestToken} endpoint=${endpoint} requestedSongId=${songId} code=${response.code}`)
    } catch (error) {
      this.log('URL_REQUEST_FAILED', `requestToken=${requestToken} endpoint=${endpoint} requestedSongId=${songId} message=${error instanceof Error ? error.message : 'unknown error'}`)
    }
    return ''
  }

  private async resolveSongUrl(song: songItemType, requestToken: number): Promise<string> {
    const cookie = this.playbackCookie()
    const level = this.store?.quality || 'exhigh'
    const id = song.id

    const body1: Record<string, string> = {}
    body1['id'] = id
    body1['level'] = level
    if (cookie.length > 0) {
      body1['cookie'] = cookie
    }
    let url = await this.attemptUrl('/song/url/v1', body1, id, requestToken)
    if (url.length > 0) {
      return url
    }

    const body2: Record<string, string> = {}
    body2['id'] = id
    body2['br'] = this.bitrateForLevel(level).toString()
    if (cookie.length > 0) {
      body2['cookie'] = cookie
    }
    url = await this.attemptUrl('/song/url', body2, id, requestToken)
    if (url.length > 0) {
      return url
    }

    try {
      const params: ApiParam[] = [
        { key: 'id', value: id },
        { key: 'level', value: level },
        { key: 'timestamp', value: Date.now().toString() }
      ]
      const response = await ApiClient.get<SongDownloadUrlResponse>('/song/download/url/v1', params)
      if (response.code === 200 && response.data && response.data.url && response.data.url.length > 0) {
        if (response.data.id.toString() !== id) {
          this.log('URL_ID_MISMATCH', `requestToken=${requestToken} endpoint=/song/download/url/v1 requestedSongId=${id} responseSongId=${response.data.id} rejected=true`)
          throw new Error('audio source response song id mismatch')
        }
        this.log('URL_RESOLVED', `requestToken=${requestToken} endpoint=/song/download/url/v1 requestedSongId=${id} responseSongId=${response.data.id} ${this.urlSummary(response.data.url)}`)
        return response.data.url
      }
    } catch (error) {
      console.error(`[PlayerController] /song/download/url/v1 failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }

    if (song.url && song.url.length > 0) {
      this.log('URL_RESOLVED', `requestToken=${requestToken} endpoint=song.url requestedSongId=${id} ${this.urlSummary(song.url)}`)
      return song.url
    }
    throw new Error('所有接口均未返回可播放地址，请检查登录状态或版权限制')
  }

  async playAt(index: number, autoPlay: boolean = true, forceReload: boolean = false): Promise<void> {
    if (!this.store || this.store.queue.length === 0) {
      this.log('PLAY_AT_IGNORED', 'reason=emptyQueue')
      return
    }
    const safeIndex = Math.max(0, Math.min(index, this.store.queue.length - 1))
    const song = this.store.queue[safeIndex]
    this.log('PLAY_AT_START', `targetSongId=${song.id} targetName=${song.name} index=${safeIndex} autoPlay=${autoPlay} forceReload=${forceReload} sourceSongId=${this.sourceSongId} loadingSongId=${this.loadingSongId}`)
    if (!forceReload && this.hasReusableSource(song.id)) {
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
          reusablePlayer.seek(0)
          await reusablePlayer.play()
        }
      }
      return
    }

    const requestToken = ++this.playRequestToken
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
      const url = await this.resolveSongUrl(song, requestToken)
      if (requestToken !== this.playRequestToken || this.store.currentSong.id !== song.id ||
        !this.isCurrentPlayer(player, generation)) {
        this.log('STALE_REQUEST', `stage=urlResolved requestToken=${requestToken} activeToken=${this.playRequestToken} targetSongId=${song.id} storeSongId=${this.store.currentSong.id} generation=${generation} activeGeneration=${this.playerGeneration}`)
        return
      }
      if (!url) {
        throw new Error('暂无可播放音源')
      }
      this.sourceSongId = song.id
      this.log('SET_PLAYER_URL', `requestToken=${requestToken} generation=${generation} songId=${song.id} expectedDuration=${song.duration} ${this.urlSummary(url)}`)
      player.url = url
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
      this.notifyPlaybackFailure(error instanceof Error ? error.message : 'unable to resolve song url')
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

  async toggle(): Promise<void> {
    if (!this.store || this.store.queue.length === 0 || this.store.isLoading) {
      return
    }
    const player = await this.ensurePlayer()
    if (player.state === 'playing') {
      await player.pause()
    } else if (player.state === 'paused' || player.state === 'prepared') {
      await player.play()
    } else if (player.state === 'completed') {
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
    if (!this.store || this.store.queue.length === 0) {
      return
    }
    if (this.store.playMode === PlayMode.SINGLE) {
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
        this.player.loop = this.store.playMode === PlayMode.SINGLE
      }
    }
  }

  async changeQuality(level: string): Promise<void> {
    if (!this.store || this.store.quality === level) {
      return
    }
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
      } catch (error) {
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
