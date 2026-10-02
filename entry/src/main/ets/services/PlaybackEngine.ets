import { UIContext } from '@kit.ArkUI'
import { PlayerStore } from '../stores/PlayerStore'
import { songItemType } from '../models/music'

export interface PlaybackEngine {
  bind(store: PlayerStore, uiContext?: UIContext): void
  onAppBackground(): void
  onAppForeground(): void
  release(): Promise<void>
  playAt(index: number, autoPlay?: boolean, forceReload?: boolean): Promise<void>
  setQueue(queue: songItemType[], index?: number, autoPlay?: boolean): Promise<void>
  toggle(): Promise<void>
  pause(): Promise<void>
  previous(): Promise<void>
  next(): Promise<void>
  seek(position: number): void
  cycleMode(): void
  changeQuality(level: string): Promise<void>
  removeAt(index: number): Promise<void>
  clearQueue(): Promise<void>
}
