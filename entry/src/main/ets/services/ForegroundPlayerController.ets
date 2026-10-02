import media from '@ohos.multimedia.media'
import { UIContext } from '@kit.ArkUI'
import { PlayMode, songItemType } from '../models/music'
import { ApiParam, SongUrlResponse } from '../models/api'
import { PlayerStore } from '../stores/PlayerStore'
import { ApiClient } from './ApiClient'
import { AppSettings } from './AppSettings'
import { PlaybackEngine } from './PlaybackEngine'
import { BubbleTip } from './BubbleTip'

// Intentional use of the API 6 AudioPlayer for the experimental compatibility path.
// No AVPlayer, AVSession, live view, or background task is created here.
export class ForegroundPlayerController implements PlaybackEngine {
  private player?: media.AudioPlayer
  private store?: PlayerStore
  private uiContext?: UIContext
  private foreground: boolean = true
  private released: boolean = false
  private request: number = 0
  private sourceSongId: string = ''
  private ready: boolean = false
  private pendingPosition: number = 0
  private pendingSongId: string = ''

  bind(store: PlayerStore, uiContext?: UIContext): void {
    this.store = store
    this.uiContext = uiContext
    store.quality = this.mp3Quality(store.quality)
  }

  private mp3Quality(level: string): string {
    return level === 'standard' || level === 'higher' ? level : 'exhigh'
  }
  onAppForeground(): void { this.foreground = true }
  onAppBackground(): void {
    this.foreground = false
    this.pendingPosition = this.store?.position || 0
    this.pendingSongId = this.store?.currentSong.id || ''
    this.stopSource()
    this.persist()
  }

  private persist(): void {
    if (this.store) { AppSettings.savePlayerState(this.store).catch(() => {}) }
  }

  private stopSource(): void {
    ++this.request
    const player = this.player
    this.player = undefined
    this.sourceSongId = ''
    this.ready = false
    if (this.store) { this.store.isPlaying = false; this.store.isLoading = false }
    if (player) {
      try { player.release() } catch (error) { console.error(`[ForegroundPlayer] ${error}`) }
    }
  }

  async release(): Promise<void> { this.released = true; this.stopSource(); this.store = undefined }

  private fail(message: string): void {
    this.stopSource()
    if (this.store) { this.store.errorMessage = message }
    if (this.uiContext && this.foreground) { BubbleTip.show(this.uiContext, message) }
  }

  private async mp3Url(song: songItemType): Promise<string> {
    const quality = this.store?.quality || 'exhigh'
    const level = this.mp3Quality(quality)
    const bitrate = level === 'standard' ? '128000' : level === 'higher' ? '192000' : '320000'
    const endpoints: string[] = ['/song/url/v1', '/song/url']
    for (const endpoint of endpoints) {
      const params: ApiParam[] = [
        { key: 'id', value: song.id },
        { key: endpoint === '/song/url/v1' ? 'level' : 'br', value: endpoint === '/song/url/v1' ? level : bitrate },
        { key: 'timestamp', value: Date.now().toString() }
      ]
      if (ApiClient.cookie) { params.push({ key: 'cookie', value: ApiClient.cookie }) }
      try {
        const response = await ApiClient.get<SongUrlResponse>(endpoint, params)
        const item = response.data?.[0]
        if (item && item.id.toString() === song.id && item.url &&
          (item.type?.toLowerCase() === 'mp3' || (!item.type && /\.mp3(?:[?#]|$)/i.test(item.url)))) {
          return item.url
        }
      } catch (_error) {}
    }
    if (song.url && /\.mp3(?:[?#]|$)/i.test(song.url)) { return song.url }
    throw new Error('未找到可播放的 MP3 音源，请检查登录状态或版权限制')
  }

  async playAt(index: number, autoPlay: boolean = true, forceReload: boolean = false): Promise<void> {
    if (!this.store || !this.store.queue.length || this.released || !this.foreground) { return }
    const safeIndex = Math.max(0, Math.min(index, this.store.queue.length - 1))
    const song = this.store.queue[safeIndex]
    this.store.quality = this.mp3Quality(this.store.quality)
    if (!forceReload && this.player && this.sourceSongId === song.id && this.ready) {
      this.store.selectAt(safeIndex, true)
      if (autoPlay) { this.player.play() }
      return
    }
    const position = forceReload ? this.store.position : (this.pendingSongId === song.id ? this.pendingPosition : 0)
    this.pendingPosition = 0
    this.pendingSongId = ''
    this.stopSource()
    const request = this.request
    this.store.selectAt(safeIndex, false)
    this.store.errorMessage = ''
    this.store.isLoading = true
    this.persist()
    try {
      const url = await this.mp3Url(song)
      if (request !== this.request || !this.foreground || this.released) { return }
      const player = media.createAudioPlayer()
      this.player = player
      this.sourceSongId = song.id
      const current = (): boolean => this.player === player && request === this.request &&
        this.store?.currentSong.id === song.id && this.foreground && !this.released
      player.on('dataLoad', () => {
        if (!current() || !this.store) { return }
        this.ready = true
        this.store.isLoading = false
        this.store.duration = Math.max(0, player.duration)
        if (position > 0 && position < player.duration) { player.seek(position) }
        if (autoPlay) { player.play() }
      })
      player.on('play', () => {
        if (!current() || !this.store) { return }
        this.store.isPlaying = true
        this.store.isLoading = false
        this.persist()
      })
      player.on('pause', () => {
        if (!current() || !this.store) { return }
        this.store.isPlaying = false
        this.persist()
      })
      player.on('timeUpdate', (position: number) => {
        if (current() && this.store) { this.store.position = Math.max(0, position) }
      })
      player.on('finish', () => {
        if (!current() || !this.store) { return }
        this.store.isPlaying = false
        this.store.position = 0
        const index = this.store.playMode === PlayMode.SINGLE ? this.store.currentIndex : this.nextIndex()
        this.playAt(index, true, true).catch((error: Error) => this.fail(error.message))
      })
      player.on('error', (error) => {
        if (current()) { this.fail(`前台 MP3 播放失败：${error.message}`) }
      })
      player.src = url
    } catch (error) {
      if (request === this.request) { this.fail(error instanceof Error ? error.message : '前台 MP3 播放失败') }
    }
  }

  async setQueue(queue: songItemType[], index: number = 0, autoPlay: boolean = true): Promise<void> {
    if (!this.store) { return }
    if (!queue.length) { await this.clearQueue(); return }
    const safeIndex = Math.max(0, Math.min(index, queue.length - 1))
    this.store.setQueue(queue, safeIndex, this.sourceSongId === queue[safeIndex].id)
    this.pendingPosition = 0
    await this.playAt(safeIndex, autoPlay)
  }

  async toggle(): Promise<void> {
    if (!this.store || !this.foreground || this.store.isLoading) { return }
    if (this.player && this.ready) {
      if (this.store.isPlaying) { this.player.pause() } else { this.player.play() }
    } else { await this.playAt(this.store.currentIndex) }
  }

  async pause(): Promise<void> {
    // Also invalidate an in-flight URL request, e.g. when opening the MV page.
    if (!this.ready) { this.stopSource() }
    else if (this.player && this.store?.isPlaying) { this.player.pause() }
  }

  private nextIndex(): number {
    if (!this.store || this.store.queue.length <= 1) { return 0 }
    if (this.store.playMode === PlayMode.SHUFFLE) {
      return (this.store.currentIndex + 1 + Math.floor(Math.random() * (this.store.queue.length - 1))) % this.store.queue.length
    }
    return (this.store.currentIndex + 1) % this.store.queue.length
  }
  async next(): Promise<void> { this.pendingPosition = 0; await this.playAt(this.nextIndex()) }
  async previous(): Promise<void> {
    if (!this.store || !this.store.queue.length) { return }
    if (this.store.position > 5000 && this.ready) { this.seek(0); return }
    this.pendingPosition = 0
    await this.playAt(this.store.playMode === PlayMode.SHUFFLE ? this.nextIndex() :
      (this.store.currentIndex + this.store.queue.length - 1) % this.store.queue.length)
  }
  seek(position: number): void {
    if (this.player && this.ready && this.store) {
      const safe = Math.max(0, Math.min(position, this.store.duration))
      this.player.seek(safe)
      this.store.position = safe
    }
  }
  cycleMode(): void {
    if (!this.store) { return }
    this.store.playMode = this.store.playMode === PlayMode.LOOP ? PlayMode.SINGLE :
      this.store.playMode === PlayMode.SINGLE ? PlayMode.SHUFFLE : PlayMode.LOOP
    this.persist()
  }
  async changeQuality(level: string): Promise<void> {
    if (!this.store) { return }
    if (level === 'lossless' || level === 'hires') {
      if (this.uiContext) { BubbleTip.show(this.uiContext, '前台兼容播放最高使用 MP3 高音质') }
    }
    const effectiveLevel = this.mp3Quality(level)
    if (this.store.quality === effectiveLevel) { return }
    this.store.quality = effectiveLevel
    await this.playAt(this.store.currentIndex, this.store.isPlaying, true)
  }
  async removeAt(index: number): Promise<void> {
    if (!this.store || index < 0 || index >= this.store.queue.length) { return }
    const current = this.store.removeAt(index)
    if (!this.store.queue.length) { this.stopSource() }
    else if (current) { this.pendingPosition = 0; await this.playAt(this.store.currentIndex) }
    this.persist()
  }
  async clearQueue(): Promise<void> {
    this.stopSource()
    this.pendingPosition = 0
    this.store?.clearQueue()
    this.persist()
  }
}
