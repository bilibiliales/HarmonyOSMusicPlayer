import { common } from '@kit.AbilityKit'
import {
  IntelligencePlayItem,
  IntelligencePlayResponse,
  LikeListResponse,
  UserPlaylistResponse,
  mapApiSong,
  songItemType
} from '../models'
import { LocalTrack, LocalLibrary } from './LocalLibrary'
import { ApiClient } from './ApiClient'
import { playerController } from './PlayerController'
import { AuthStore } from '../stores/AuthStore'

/**
 * 桌面图标长按快捷方式的统一处理。
 * EntryAbility 把 want.parameters.shortcutAction 写进 AppStorage 并递增序号，
 * 由首页在 playerController.bind() 之后消费，避免冷启动时队列还没绑定就开播。
 */
export class ShortcutBridge {
  static readonly ACTION_KEY: string = 'shortcutAction'
  static readonly SEQ_KEY: string = 'shortcutSeq'

  static readonly SONG_RECOGNITION: string = 'song_recognition'
  static readonly HEART_MODE: string = 'heart_mode'
  static readonly SEARCH: string = 'search'
  static readonly LOCAL_MUSIC: string = 'local_music'

  /** Ability 收到快捷方式 want 时调用（冷启动 onCreate 与热启动 onNewWant 都走这里）。 */
  static publish(action: string): void {
    if (!action) { return }
    AppStorage.setOrCreate<string>(ShortcutBridge.ACTION_KEY, action)
    const seq = AppStorage.get<number>(ShortcutBridge.SEQ_KEY) ?? 0
    AppStorage.setOrCreate<number>(ShortcutBridge.SEQ_KEY, seq + 1)
  }

  /**
   * 首页消费快捷方式动作。返回是否已有服务接管（true 表示 action 已处理，页面无需再跳）。
   * 单纯的页面跳转由调用方完成；需要准备播放队列的动作在这里异步执行，成功后回跳 PlayPage。
   */
  static async handle(action: string, context: common.Context, authStore: AuthStore,
    push: (name: string, param: object | null) => void, tip: (text: string) => void): Promise<void> {
    if (action === ShortcutBridge.SONG_RECOGNITION) {
      push('SongRecognitionPage', null)
      return
    }
    if (action === ShortcutBridge.SEARCH) {
      push('SearchPage', null)
      return
    }
    if (action === ShortcutBridge.HEART_MODE) {
      await ShortcutBridge.startHeartMode(authStore, push, tip)
      return
    }
    if (action === ShortcutBridge.LOCAL_MUSIC) {
      await ShortcutBridge.startLocalMusic(context, push, tip)
      return
    }
  }

  /** 心动模式：复用推荐页同样的接口，随机取一首红心歌作为种子生成歌单后开播。 */
  private static async startHeartMode(authStore: AuthStore,
    push: (name: string, param: object | null) => void, tip: (text: string) => void): Promise<void> {
    if (!authStore.loggedIn || !authStore.userId) {
      tip('请先登录后再使用心动模式')
      push('LoginPage', null)
      return
    }
    try {
      const base = await Promise.all([
        ApiClient.get<LikeListResponse>('/likelist', [{ key: 'uid', value: authStore.userId }]),
        ApiClient.get<UserPlaylistResponse>('/user/playlist/create', [{ key: 'uid', value: authStore.userId }])
      ])
      const likedIds = base[0].ids || []
      const playlists = base[1].data?.playlist || base[1].playlist || []
      if (likedIds.length === 0) { tip('喜欢的音乐中还没有歌曲，无法开启心动模式'); return }
      if (playlists.length === 0) { tip('未找到喜欢音乐歌单'); return }
      const seedId = likedIds[Math.floor(Math.random() * likedIds.length)]
      const liked = playlists.find((item) => item.specialType === 5) || playlists[0]
      const response = await ApiClient.get<IntelligencePlayResponse>('/playmode/intelligence/list', [
        { key: 'id', value: seedId.toString() },
        { key: 'pid', value: liked.id.toString() }
      ])
      const queue: songItemType[] = (response.data || [])
        .filter((item: IntelligencePlayItem) => !!item.songInfo)
        .map((item: IntelligencePlayItem) => {
          const song = mapApiSong(item.songInfo!)
          song.recommendTag = item.recommended ? '心动推荐' : '红心歌曲'
          return song
        })
      if (queue.length === 0) { tip('心动模式暂时没有可播放歌曲'); return }
      await playerController.setQueue(queue, 0, true)
      push('PlayPage', null)
    } catch (error) {
      tip(error instanceof Error ? error.message : '心动模式启动失败')
    }
  }

  /** 播放本地音乐：读取已索引的本地曲目，直接开播并进入播放页。 */
  private static async startLocalMusic(context: common.Context,
    push: (name: string, param: object | null) => void, tip: (text: string) => void): Promise<void> {
    try {
      await LocalLibrary.init(context)
      await LocalLibrary.scan()
      const tracks: LocalTrack[] = LocalLibrary.cached()
      if (tracks.length === 0) { tip('还没有本地音乐，请先到「本地与下载」导入'); return }
      await playerController.setQueue(tracks.map((track: LocalTrack) => LocalLibrary.song(track)), 0, true)
      push('PlayPage', null)
    } catch (error) {
      tip(error instanceof Error ? error.message : '播放本地音乐失败')
    }
  }
}
