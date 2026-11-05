/**
 * Neutral contract for the OPTIONAL AVSession-backed background playback runtime.
 *
 * This file is statically imported by PlayerController, and PlayerController is
 * statically imported by EntryAbility at cold start. Therefore this file must stay
 * completely free of AVSession Kit:
 *   - no `import ... from '@kit.AVSessionKit'`
 *   - no `import ... from '@ohos.multimedia.avsession'`
 *   - no `avSession.*` symbol at all
 *
 * The only module allowed to reference AVSession Kit is MediaSessionBridge.ets,
 * which is loaded exclusively through a single guarded dynamic import. When the
 * "background playback" switch is off, PlayerController only ever evaluates the
 * plain numbers / interfaces below, so the AVSession native module is never
 * resolved, loaded or called.
 */
import { common } from '@kit.AbilityKit'

/** Playback states sent to the system media session (decoupled from AVSession enums). */
export class SessionPlaybackState {
  static readonly PREPARE: number = 0
  static readonly PLAY: number = 1
  static readonly PAUSE: number = 2
  static readonly STOP: number = 3
  static readonly COMPLETED: number = 4
  static readonly ERROR: number = 5
}

/** Loop modes sent to the system media session (decoupled from AVSession enums). */
export class SessionLoopMode {
  static readonly LIST: number = 0
  static readonly SINGLE: number = 1
  static readonly SHUFFLE: number = 2
}

export interface SessionMetadata {
  assetId: string
  title: string
  artist: string
  album: string
  duration: number
  mediaImage: string
  lyric: string
  previousAssetId?: string
  nextAssetId?: string
}

export interface SessionLyricReadback {
  assetId: string
  lyric: string
}

export interface SessionDesktopLyricStatus {
  visible: boolean
  locked: boolean
}

export interface DesktopLyricConfig {
  enabled: boolean
  locked: boolean
}

/** Callbacks the runtime wires into the system session; all remain Kit-free. */
export interface SessionHandlers {
  onPlay: () => void
  onPause: () => void
  onNext: () => void
  onPrevious: () => void
  onSeek: (time: number) => void
  onDesktopLyricVisibilityChanged: (visible: boolean) => void
  onDesktopLyricStateChanged: (locked: boolean) => void
}

/** The whole surface PlayerController is allowed to see. */
export interface MediaSessionApi {
  sessionId(): string
  activate(): Promise<void>
  destroy(): Promise<void>
  setMetadata(metadata: SessionMetadata): Promise<void>
  setPlaybackState(state: number, position: number, loopMode: number): Promise<void>
  configureDesktopLyrics(enabled: boolean, locked: boolean): Promise<void>
  refreshDesktopLyrics(): Promise<SessionDesktopLyricStatus>
  readLyricMetadata(): Promise<SessionLyricReadback>
}

export type MediaSessionFactory = (context: common.Context, handlers: SessionHandlers,
  initial: DesktopLyricConfig) => Promise<MediaSessionApi>

/**
 * THE single gate that decides whether AVSession Kit may be loaded at all.
 *
 * `settingsLoaded` matters: AppSettings.backgroundPlaybackEnabled defaults to
 * true, so without it a call arriving before the persisted preference is read
 * would load the Kit even for a user who has the switch turned off.
 */
export function shouldLoadMediaSession(settingsLoaded: boolean, enabled: boolean, released: boolean): boolean {
  return settingsLoaded && enabled && !released
}

/**
 * Registration slot filled as a side effect when MediaSessionBridge.ets is
 * dynamically imported. Keeping the factory in a neutral (Kit-free) holder lets
 * PlayerController stay fully typed and avoids ESObject casts at call sites.
 */
export class MediaSessionRegistry {
  static factory: MediaSessionFactory | undefined = undefined
}
