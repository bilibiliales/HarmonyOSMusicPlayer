import { LyricPreferences } from '../models/lyricPreferences'
import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { preferences } from '@kit.ArkData'
import { fileIo } from '@kit.CoreFileKit'
import { MusicWidgetService, MusicWidgetState } from './MusicWidgetService'
import { ApiClient } from './ApiClient'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { PlayMode, songItemType } from '../models/music'

export class AppSettings {
  private static readonly STORE_NAME: string = 'music_player_settings'
  private static readonly API_BASE_URL_KEY: string = 'api_base_url'
  private static readonly AUTH_COOKIE_KEY: string = 'auth_cookie'
  private static readonly AUTH_USER_ID_KEY: string = 'auth_user_id'
  private static readonly AUTH_NICKNAME_KEY: string = 'auth_nickname'
  private static readonly AUTH_AVATAR_KEY: string = 'auth_avatar'
  private static readonly AUTH_SIGNATURE_KEY: string = 'auth_signature'
  private static readonly PLAYER_QUEUE_FILE: string = 'player_queue.json'
  private static readonly PLAYER_WIDGET_FILE: string = 'player_widget_state.json'
  private static readonly PLAYER_WIDGET_FORM_IDS_FILE: string = 'music_card_ids.json'
  private static readonly PLAYER_INDEX_KEY: string = 'player_index'
  private static readonly PLAYER_MODE_KEY: string = 'player_mode'
  private static readonly AI_BASE_URL_KEY: string = 'ai_base_url'
  private static readonly AI_API_KEY_KEY: string = 'ai_api_key'
  private static readonly AI_MODEL_KEY: string = 'ai_model'
  private static readonly DEFAULT_PLAY_MODE_KEY: string = 'default_play_mode'
  private static readonly DEFAULT_ONLINE_QUALITY_KEY: string = 'default_online_quality'
  private static readonly DEFAULT_DOWNLOAD_QUALITY_KEY: string = 'default_download_quality'
  private static readonly BACKGROUND_PLAYBACK_KEY: string = 'background_playback_enabled'
  private static readonly STREAMING_PLAYBACK_KEY: string = 'streaming_playback_enabled'
  private static readonly SCROBBLE_KEY: string = 'scrobble_enabled'
  private static readonly DEVICE_ALIAS_KEY: string = 'device_alias'
  private static readonly FM_MODE_KEY: string = 'fm_mode'
  private static readonly FM_SUBMODE_KEY: string = 'fm_submode'

  static lyricPreferences: LyricPreferences = new LyricPreferences()
  static desktopLyricsEnabled: boolean = false
  static desktopLyricsLocked: boolean = false
  static showProfileStatus: boolean = true
  static downloadSaveMode: string = 'download'
  static askDownloadSaveMode: boolean = true
  static effectsEnabled: boolean = true
  /** 是否在本机记录听歌记录（关闭则不调用网易云 V2 打卡，不计入听歌记录/排行）。 */
  static scrobbleEnabled: boolean = true
  /** 私人漫游模式：DEFAULT / FAMILIAR / EXPLORE / SCENE_RCMD。 */
  static fmMode: string = 'DEFAULT'
  /** 场景模式细分：EXERCISE / FOCUS / NIGHT_EMO（仅 SCENE_RCMD 生效）。 */
  static fmSubmode: string = ''

  static async saveFeature(key: string, value: preferences.ValueType): Promise<void> {
    if (!AppSettings.context) { throw new Error('设置存储尚未初始化') }
    const store = await preferences.getPreferences(AppSettings.context, AppSettings.STORE_NAME)
    await store.put(key, value)
    await store.flush()
  }

  static async saveLyrics(value: LyricPreferences): Promise<void> {
    await AppSettings.saveFeature('lyric_preferences', JSON.stringify(value))
    AppSettings.lyricPreferences = value
  }

  static async saveProfileStatusVisibility(visible: boolean): Promise<void> {
    await AppSettings.saveFeature('show_profile_status', visible)
    AppSettings.showProfileStatus = visible
    AppStorage.setOrCreate<boolean>('showProfileStatus', visible)
  }

  static backgroundPlaybackEnabled: boolean = true

  /**
   * Streaming playback (default ON). When ON, `PlayerController` feeds AVPlayer
   * a Range-backed data source whose memory footprint is bounded (~16 MB) regardless
   * of file size. When OFF, the whole file is downloaded into memory first (the
   * original strategy) — kept as a fallback for devices / VMs whose AVPlayer cannot
   * consume the streaming dataSrc.
   */
  static streamingPlaybackEnabled: boolean = true

  // 本机上报到设备中心的别名。默认取设备对外传播名（deviceInfo.marketName，
  // 例如「HUAWEI Mate 60 Pro」），不再使用应用名。
  static deviceAlias: string = ''

  private static readonly LEGACY_DEVICE_ALIAS: string = 'HarmonyOS 音乐播放器'

  /** 本机的默认设备名：marketName（对外传播名）> productModel > brand。 */
  static localDeviceName(): string {
    const candidates: string[] = [deviceInfo.marketName, deviceInfo.productModel, deviceInfo.brand]
    for (const value of candidates) {
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim()
      }
    }
    return 'HarmonyOS 设备'
  }

  /** 归一化设备别名：空值或旧版默认名一律回落到本机型号名。 */
  static resolveDeviceAlias(value: preferences.ValueType): string {
    const text: string = typeof value === 'string' ? value.trim() : ''
    if (text.length === 0 || text === AppSettings.LEGACY_DEVICE_ALIAS) {
      return AppSettings.localDeviceName()
    }
    return text
  }

  /**
   * Guards the media session gate against the `true` default above: until the
   * persisted preference has actually been read, background playback is treated
   * as undecided (and therefore the media session Kit must stay unloaded).
   */
  static settingsLoaded: boolean = false

  static aiBaseUrl: string = 'https://ncme.scfd.top'
  static aiApiKey: string = ''
  static aiModel: string = 'gpt-3.5-turbo'
  static defaultPlayMode: PlayMode = PlayMode.LOOP
  static defaultOnlineQuality: string = 'exhigh'
  static defaultDownloadQuality: string = 'exhigh'
  static aiWorkspaceId: string

  static async load(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    const lyricValue = await store.get('lyric_preferences', '')
    if (typeof lyricValue === 'string' && lyricValue) {
      try { AppSettings.lyricPreferences = LyricPreferences.normalize(JSON.parse(lyricValue) as LyricPreferences) } catch (_error) {}
    }
    AppSettings.desktopLyricsEnabled = await store.get('desktop_lyrics_enabled', false) === true
    AppSettings.desktopLyricsLocked = await store.get('desktop_lyrics_locked', false) === true
    AppSettings.showProfileStatus = await store.get('show_profile_status', true) === true
    AppStorage.setOrCreate<boolean>('showProfileStatus', AppSettings.showProfileStatus)
    AppSettings.effectsEnabled = await store.get('effects_enabled', true) === true
    AppSettings.downloadSaveMode = await store.get('download_save_mode', 'download') === 'saveAs' ? 'saveAs' : 'download'
    AppSettings.askDownloadSaveMode = await store.get('ask_download_save_mode', true) === true
    const backgroundValue = await store.get(AppSettings.BACKGROUND_PLAYBACK_KEY, true)
    AppSettings.backgroundPlaybackEnabled = typeof backgroundValue === 'boolean' ? backgroundValue : true
    AppSettings.streamingPlaybackEnabled = await store.get(AppSettings.STREAMING_PLAYBACK_KEY, true) === true
    AppSettings.scrobbleEnabled = await store.get(AppSettings.SCROBBLE_KEY, true) === true
    const fmModeValue = await store.get(AppSettings.FM_MODE_KEY, 'DEFAULT')
    const fmSubmodeValue = await store.get(AppSettings.FM_SUBMODE_KEY, '')
    AppSettings.fmMode = typeof fmModeValue === 'string' && fmModeValue.length > 0 ? fmModeValue : 'DEFAULT'
    AppSettings.fmSubmode = typeof fmSubmodeValue === 'string' ? fmSubmodeValue : ''
    AppSettings.settingsLoaded = true
    AppSettings.deviceAlias = AppSettings.resolveDeviceAlias(await store.get(AppSettings.DEVICE_ALIAS_KEY,
      AppSettings.LEGACY_DEVICE_ALIAS))
    // 上报本机设备别名到设备中心（该接口无需登录）
    AppSettings.reportDeviceName().catch(() => {})
    const urlValue = await store.get(AppSettings.API_BASE_URL_KEY, ApiClient.baseUrl)
    if (typeof urlValue === 'string') {
      ApiClient.setBaseUrl(urlValue)
    }
    const baseUrlValue = await store.get(AppSettings.AI_BASE_URL_KEY, 'https://api.openai.com/v1')
    const apiKeyValue = await store.get(AppSettings.AI_API_KEY_KEY, '')
    const modelValue = await store.get(AppSettings.AI_MODEL_KEY, 'gpt-3.5-turbo')
    AppSettings.aiBaseUrl = typeof baseUrlValue === 'string' && baseUrlValue.length > 0 ? baseUrlValue : 'https://api.openai.com/v1'
    AppSettings.aiApiKey = typeof apiKeyValue === 'string' ? apiKeyValue : ''
    AppSettings.aiModel = typeof modelValue === 'string' && modelValue.length > 0 ? modelValue : 'gpt-3.5-turbo'
    const playModeValue = await store.get(AppSettings.DEFAULT_PLAY_MODE_KEY, PlayMode.LOOP)
    const onlineQualityValue = await store.get(AppSettings.DEFAULT_ONLINE_QUALITY_KEY, 'exhigh')
    const downloadQualityValue = await store.get(AppSettings.DEFAULT_DOWNLOAD_QUALITY_KEY, 'exhigh')
    if (typeof playModeValue === 'number' && playModeValue >= PlayMode.LOOP && playModeValue <= PlayMode.SHUFFLE) {
      AppSettings.defaultPlayMode = playModeValue as PlayMode
    }
    AppSettings.defaultOnlineQuality = AppSettings.normalizeQuality(onlineQualityValue)
    AppSettings.defaultDownloadQuality = AppSettings.normalizeQuality(downloadQualityValue)
  }

  static async saveDeviceAlias(context: common.Context, name: string): Promise<void> {
    const alias = AppSettings.resolveDeviceAlias(name)
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    await store.put(AppSettings.DEVICE_ALIAS_KEY, alias)
    await store.flush()
    AppSettings.deviceAlias = alias
    await AppSettings.reportDeviceName()
  }

  // 把本机别名上报到设备中心：/deviceinfo/center/upload?deviceName=XXXXX
  // 直接走 ApiClient，避免与 DeviceService 形成循环依赖。
  static async reportDeviceName(): Promise<void> {
    await ApiClient.get<Object>('/deviceinfo/center/upload', [
      { key: 'deviceName', value: AppSettings.deviceAlias }
    ])
  }

  static async loadAuth(authStore: AuthStore): Promise<void> {
    if (!AppSettings.context) {
      return
    }
    try {
      const store = await preferences.getPreferences(AppSettings.context, AppSettings.STORE_NAME)
      const cookie = await store.get(AppSettings.AUTH_COOKIE_KEY, '')
      if (typeof cookie === 'string' && cookie.length > 0) {
        ApiClient.setCookie(cookie)
        authStore.cookie = cookie
        const userId = await store.get(AppSettings.AUTH_USER_ID_KEY, '')
        const nickname = await store.get(AppSettings.AUTH_NICKNAME_KEY, '网易云用户')
        const avatarUrl = await store.get(AppSettings.AUTH_AVATAR_KEY, '')
        const signature = await store.get(AppSettings.AUTH_SIGNATURE_KEY, '')
        authStore.userId = typeof userId === 'string' ? userId : ''
        authStore.nickname = typeof nickname === 'string' ? nickname : '网易云用户'
        authStore.avatarUrl = typeof avatarUrl === 'string' ? avatarUrl : ''
        authStore.signature = typeof signature === 'string' ? signature : ''
        authStore.loggedIn = true
      }
    } catch (_error) {
    }
  }

  static async saveAuth(authStore: AuthStore): Promise<void> {
    if (!AppSettings.context) {
      return
    }
    try {
      const store = await preferences.getPreferences(AppSettings.context, AppSettings.STORE_NAME)
      if (authStore.loggedIn && authStore.cookie.length > 0) {
        await store.put(AppSettings.AUTH_COOKIE_KEY, authStore.cookie)
        await store.put(AppSettings.AUTH_USER_ID_KEY, authStore.userId)
        await store.put(AppSettings.AUTH_NICKNAME_KEY, authStore.nickname)
        await store.put(AppSettings.AUTH_AVATAR_KEY, authStore.avatarUrl)
        await store.put(AppSettings.AUTH_SIGNATURE_KEY, authStore.signature)
      } else {
        await store.delete(AppSettings.AUTH_COOKIE_KEY)
        await store.delete(AppSettings.AUTH_USER_ID_KEY)
        await store.delete(AppSettings.AUTH_NICKNAME_KEY)
        await store.delete(AppSettings.AUTH_AVATAR_KEY)
        await store.delete(AppSettings.AUTH_SIGNATURE_KEY)
      }
      await store.flush()
    } catch (_error) {
    }
  }

  static async saveBaseUrl(context: common.Context, value: string): Promise<void> {
    ApiClient.setBaseUrl(value)
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    await store.put(AppSettings.API_BASE_URL_KEY, ApiClient.baseUrl)
    await store.flush()
  }

  /**
   * 重置本地偏好为出厂默认。
   * 只删偏好类键：登录态（cookie / uid / 昵称 / 头像）与设备别名在同一 preferences 库里，
   * 不能整库删除，否则会把账号一起清掉。后端地址也单独由「重置后端服务地址」处理。
   */
  static async resetLocalSettings(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    const keys: string[] = [
      'lyric_preferences', 'desktop_lyrics_enabled', 'desktop_lyrics_locked', 'effects_enabled', 'show_profile_status',
      'download_save_mode', 'ask_download_save_mode', 'background_playback_enabled',
      'streaming_playback_enabled', 'scrobble_enabled', 'default_play_mode',
      'default_online_quality', 'default_download_quality', 'fm_mode', 'fm_submode',
      'ai_base_url', 'ai_api_key', 'ai_model'
    ]
    for (const key of keys) {
      await store.delete(key)
    }
    await store.flush()
    AppSettings.lyricPreferences = new LyricPreferences()
    AppSettings.desktopLyricsEnabled = false
    AppSettings.desktopLyricsLocked = false
    AppSettings.showProfileStatus = true
    AppStorage.setOrCreate<boolean>('showProfileStatus', true)
    AppSettings.effectsEnabled = true
    AppSettings.downloadSaveMode = 'download'
    AppSettings.askDownloadSaveMode = true
    // 后台播放不能只改内存：会话的装载/卸载由 PlayerController 负责，
    // 由调用方在重置后按需调用 setBackgroundPlayback(true)，否则开关显示 ON 但会话仍是卸载态。
    AppSettings.streamingPlaybackEnabled = true
    AppSettings.scrobbleEnabled = true
    AppSettings.fmMode = 'DEFAULT'
    AppSettings.fmSubmode = ''
    AppSettings.defaultPlayMode = PlayMode.LOOP
    AppSettings.defaultOnlineQuality = 'exhigh'
    AppSettings.defaultDownloadQuality = 'exhigh'
    AppSettings.aiBaseUrl = 'https://api.openai.com/v1'
    AppSettings.aiApiKey = ''
    AppSettings.aiModel = 'gpt-3.5-turbo'
  }

  static async saveBackgroundPlayback(context: common.Context, enabled: boolean): Promise<void> {
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    await store.put(AppSettings.BACKGROUND_PLAYBACK_KEY, enabled)
    await store.flush()
    AppSettings.backgroundPlaybackEnabled = enabled
    // An explicit user choice is authoritative even if the initial load failed.
    AppSettings.settingsLoaded = true
  }

  static async saveStreamingPlayback(context: common.Context, enabled: boolean): Promise<void> {
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    await store.put(AppSettings.STREAMING_PLAYBACK_KEY, enabled)
    await store.flush()
    AppSettings.streamingPlaybackEnabled = enabled
  }

  static async saveScrobble(context: common.Context, enabled: boolean): Promise<void> {
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    await store.put(AppSettings.SCROBBLE_KEY, enabled)
    await store.flush()
    AppSettings.scrobbleEnabled = enabled
  }

  /** 私人漫游模式（mode + scene 细分）持久化。 */
  static async saveFmMode(mode: string, submode: string): Promise<void> {
    AppSettings.fmMode = mode.length > 0 ? mode : 'DEFAULT'
    AppSettings.fmSubmode = submode
    await AppSettings.saveFeature(AppSettings.FM_MODE_KEY, AppSettings.fmMode)
    await AppSettings.saveFeature(AppSettings.FM_SUBMODE_KEY, AppSettings.fmSubmode)
  }

  static async saveAiSettings(context: common.Context, baseUrl: string, apiKey: string,
    model: string): Promise<void> {
    const normalizedBaseUrl = baseUrl.trim() || 'https://api.openai.com/v1'
    const normalizedApiKey = apiKey.trim()
    const normalizedModel = model.trim() || 'gpt-3.5-turbo'
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    await store.put(AppSettings.AI_BASE_URL_KEY, normalizedBaseUrl)
    await store.put(AppSettings.AI_API_KEY_KEY, normalizedApiKey)
    await store.put(AppSettings.AI_MODEL_KEY, normalizedModel)
    await store.flush()
    AppSettings.aiBaseUrl = normalizedBaseUrl
    AppSettings.aiApiKey = normalizedApiKey
    AppSettings.aiModel = normalizedModel
  }

  private static normalizeQuality(value: preferences.ValueType): string {
    if (typeof value !== 'string') {
      return 'exhigh'
    }
    if (value === 'standard' || value === 'higher' || value === 'exhigh' || value === 'lossless' || value === 'hires' ||
      value === 'jyeffect' || value === 'sky' || value === 'dolby' || value === 'jymaster') {
      return value
    }
    return 'exhigh'
  }

  static async savePlaybackDefaults(context: common.Context, playMode: PlayMode, onlineQuality: string,
    downloadQuality: string): Promise<void> {
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
    const normalizedOnlineQuality = AppSettings.normalizeQuality(onlineQuality)
    const normalizedDownloadQuality = AppSettings.normalizeQuality(downloadQuality)
    await store.put(AppSettings.DEFAULT_PLAY_MODE_KEY, playMode)
    await store.put(AppSettings.DEFAULT_ONLINE_QUALITY_KEY, normalizedOnlineQuality)
    await store.put(AppSettings.DEFAULT_DOWNLOAD_QUALITY_KEY, normalizedDownloadQuality)
    await store.flush()
    AppSettings.defaultPlayMode = playMode
    AppSettings.defaultOnlineQuality = normalizedOnlineQuality
    AppSettings.defaultDownloadQuality = normalizedDownloadQuality
  }

  static async loadPlayerState(playerStore: PlayerStore): Promise<void> {
    if (!AppSettings.context) {
      return
    }
    try {
      const store = await preferences.getPreferences(AppSettings.context, AppSettings.STORE_NAME)
      const indexValue = await store.get(AppSettings.PLAYER_INDEX_KEY, 0)
      const modeValue = await store.get(AppSettings.PLAYER_MODE_KEY, AppSettings.defaultPlayMode)
      const queuePath = `${AppSettings.context.filesDir}/${AppSettings.PLAYER_QUEUE_FILE}`
      if (fileIo.accessSync(queuePath)) {
        const queueValue = fileIo.readTextSync(queuePath)
        const queue = JSON.parse(queueValue) as songItemType[]
        if (queue.length > 0) {
          const index = typeof indexValue === 'number' ? indexValue : 0
          playerStore.setQueue(queue, index, false)
        }
      }
      if (typeof modeValue === 'number' && modeValue >= PlayMode.LOOP && modeValue <= PlayMode.SHUFFLE) {
        playerStore.playMode = modeValue as PlayMode
      }
      playerStore.quality = AppSettings.defaultOnlineQuality
    } catch (_error) {
      playerStore.clearQueue()
    }
  }

  static async savePlayerState(playerStore: PlayerStore): Promise<void> {
    if (!AppSettings.context) {
      return
    }
    try {
      const store = await preferences.getPreferences(AppSettings.context, AppSettings.STORE_NAME)
      const queuePath = `${AppSettings.context.filesDir}/${AppSettings.PLAYER_QUEUE_FILE}`
      if (playerStore.queue.length > 0) {
        const file = fileIo.openSync(queuePath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
        try {
          fileIo.writeSync(file.fd, JSON.stringify(playerStore.queue))
        } finally {
          fileIo.closeSync(file)
        }
        await store.put(AppSettings.PLAYER_INDEX_KEY, playerStore.currentIndex)
        const widgetState: MusicWidgetState = {
          songName: playerStore.currentSong.name,
          artist: playerStore.currentSong.author,
          songId: playerStore.currentSong.id,
          isPlaying: playerStore.isPlaying,
          liked: playerStore.currentSong.liked || false,
          playMode: playerStore.playMode,
          cover: playerStore.currentSong.img || playerStore.currentSong.remoteImg || ''
        }
        await MusicWidgetService.publish(AppSettings.context, widgetState)
      } else {
        try { fileIo.unlinkSync(queuePath) } catch (_error) {}
        await MusicWidgetService.publish(AppSettings.context, MusicWidgetService.empty())
        await store.delete(AppSettings.PLAYER_INDEX_KEY)
      }
      await store.put(AppSettings.PLAYER_MODE_KEY, playerStore.playMode)
      await store.flush()
    } catch (_error) {
    }
  }

  static context: common.Context | null = null
}
