import { UIContext } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { PlayerStore } from '../stores/PlayerStore'
import { songItemType } from '../models/music'
import { AppSettings } from './AppSettings'
import { PlaybackEngine } from './PlaybackEngine'
import { PlaybackControlBridge } from './PlaybackControlBridge'

// Load the native background stack only when background playback is enabled.
export class PlayerController {
  private static instance: PlayerController = new PlayerController()
  private engine?: PlaybackEngine
  private creation?: Promise<PlaybackEngine>
  private store?: PlayerStore
  private uiContext?: UIContext
  private foreground: boolean = true
  private switching: boolean = false

  static getInstance(): PlayerController { return PlayerController.instance }

  bind(store: PlayerStore, uiContext?: UIContext): void {
    this.store = store
    this.uiContext = uiContext
    this.getEngine().catch((error: Error) => this.report(error))
  }

  private report(error: Error): void {
    console.error(`[PlayerController] ${error.message}`)
    if (this.store) {
      this.store.isLoading = false
      this.store.isPlaying = false
      this.store.errorMessage = error.message
    }
  }

  private async createEngine(): Promise<PlaybackEngine> {
    let engine: PlaybackEngine
    if (AppSettings.backgroundPlaybackEnabled) {
      const module = await import('./BackgroundPlayerController')
      engine = new module.PlayerController()
    } else {
      const module = await import('./ForegroundPlayerController')
      engine = new module.ForegroundPlayerController()
    }
    if (this.store) { engine.bind(this.store, this.uiContext) }
    if (!this.foreground) { engine.onAppBackground() }
    this.engine = engine
    return engine
  }

  private async getEngine(): Promise<PlaybackEngine> {
    if (this.engine) { return this.engine }
    if (!this.creation) { this.creation = this.createEngine() }
    try { return await this.creation } finally { this.creation = undefined }
  }

  private async activeEngine(): Promise<PlaybackEngine | undefined> {
    if (this.switching) { return undefined }
    const engine = await this.getEngine()
    return !this.switching && engine === this.engine ? engine : undefined
  }

  async setBackgroundPlayback(context: common.Context, enabled: boolean): Promise<void> {
    if (this.switching || enabled === AppSettings.backgroundPlaybackEnabled) { return }
    this.switching = true
    try {
      // Persist first: a preferences error must leave the current engine intact.
      await AppSettings.saveBackgroundPlayback(context, enabled)
      if (this.creation) { await this.creation }
      PlaybackControlBridge.unsubscribe()
      await this.engine?.release()
      this.engine = undefined
      if (this.store) {
        this.store.isPlaying = false
        this.store.isLoading = false
        this.store.position = 0
        this.store.quality = AppSettings.defaultOnlineQuality
        await AppSettings.savePlayerState(this.store)
      }
      // Switching stops playback. The next explicit play starts the new engine.
    } finally { this.switching = false }
  }

  onAppBackground(): void { this.foreground = false; this.engine?.onAppBackground() }
  onAppForeground(): void { this.foreground = true; this.engine?.onAppForeground() }
  async release(): Promise<void> {
    if (this.creation) { await this.creation }
    PlaybackControlBridge.unsubscribe()
    await this.engine?.release()
    this.engine = undefined
  }
  async playAt(index: number, autoPlay: boolean = true, forceReload: boolean = false): Promise<void> {
    await (await this.activeEngine())?.playAt(index, autoPlay, forceReload)
  }
  async setQueue(queue: songItemType[], index: number = 0, autoPlay: boolean = true): Promise<void> {
    await (await this.activeEngine())?.setQueue(queue, index, autoPlay)
  }
  async toggle(): Promise<void> { await (await this.activeEngine())?.toggle() }
  async pause(): Promise<void> { await this.engine?.pause() }
  async previous(): Promise<void> { await (await this.activeEngine())?.previous() }
  async next(): Promise<void> { await (await this.activeEngine())?.next() }
  seek(position: number): void { if (!this.switching) { this.engine?.seek(position) } }
  cycleMode(): void {
    this.activeEngine().then((engine?: PlaybackEngine) => engine?.cycleMode()).catch((e: Error) => this.report(e))
  }
  async changeQuality(level: string): Promise<void> {
    await (await this.activeEngine())?.changeQuality(level)
  }
  async removeAt(index: number): Promise<void> {
    await (await this.activeEngine())?.removeAt(index)
  }
  async clearQueue(): Promise<void> { await (await this.activeEngine())?.clearQueue() }
}

export const playerController = PlayerController.getInstance()
