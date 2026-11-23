import { playerController } from './PlayerController'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { AppSettings } from './AppSettings'

export class MusicCardActionBridge {
  private static store?: PlayerStore
  private static auth?: AuthStore
  private static seen: Set<string> = new Set()
  private static tasks: Promise<void> = Promise.resolve()
  static bind(store: PlayerStore, auth: AuthStore): void { MusicCardActionBridge.store = store; MusicCardActionBridge.auth = auth }
  static ready(): boolean { return !!MusicCardActionBridge.store && !!MusicCardActionBridge.auth }
  static unbind(): void { MusicCardActionBridge.store = undefined; MusicCardActionBridge.auth = undefined }
  static execute(action: string, songId: string, requestId: string): Promise<void> {
    if (requestId && MusicCardActionBridge.seen.has(requestId)) { return Promise.resolve() }
    if (requestId) {
      MusicCardActionBridge.seen.add(requestId)
      if (MusicCardActionBridge.seen.size > 100) {
        const first: string | undefined = Array.from(MusicCardActionBridge.seen)[0]
        if (first) { MusicCardActionBridge.seen.delete(first) }
      }
    }
    const task = MusicCardActionBridge.tasks.catch(() => {}).then(async () => {
      const store = MusicCardActionBridge.store
      const auth = MusicCardActionBridge.auth
      if (store && auth) { await MusicCardActionBridge.handle(action, songId, store, auth) }
    })
    MusicCardActionBridge.tasks = task
    return task
  }
  static publish(action: string, songId: string): void {
    if (!['previous', 'toggle', 'next', 'like', 'mode'].includes(action)) { return }
    AppStorage.setOrCreate<string>('musicCardSongId', songId)
    AppStorage.setOrCreate<string>('musicCardAction', action)
    AppStorage.setOrCreate<number>('musicCardSeq', (AppStorage.get<number>('musicCardSeq') || 0) + 1)
  }

  static async handle(action: string, songId: string, store: PlayerStore, auth: AuthStore): Promise<void> {
    if (!store.queue.length) { return }
    if (action === 'previous') { await playerController.previous() }
    else if (action === 'next') { await playerController.next() }
    else if (action === 'toggle') { await playerController.toggle() }
    else if (action === 'mode') { playerController.cycleMode() }
    else if (action === 'like') {
      if (!auth.loggedIn) { throw new Error('请先登录后喜欢歌曲') }
      const song = store.currentSong
      if (songId && song.id !== songId) { throw new Error('歌曲已切换，请使用更新后的卡片') }
      await playerController.toggleFavorite(song.id)
    }
  }
}
