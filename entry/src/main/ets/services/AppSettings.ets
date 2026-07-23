import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { fileIo } from '@kit.CoreFileKit'
import { formBindingData, formProvider } from '@kit.FormKit'
import { ApiClient } from './ApiClient'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { PlayMode, songItemType } from '../models/music'

interface MusicWidgetState {
  songName: string
  artist: string
  songId: string
  isPlaying: boolean
}

class MusicWidgetBindingState {
  songName: string = ''
  artist: string = ''
  songId: string = ''
  isPlaying: boolean = false
}

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

  static aiBaseUrl: string = 'https://api.openai.com/v1'
  static aiApiKey: string = ''
  static aiModel: string = 'gpt-3.5-turbo'
  static defaultPlayMode: PlayMode = PlayMode.LOOP
  static defaultOnlineQuality: string = 'exhigh'
  static defaultDownloadQuality: string = 'exhigh'

  static async load(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, AppSettings.STORE_NAME)
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
    if (value === 'standard' || value === 'higher' || value === 'exhigh' || value === 'lossless' || value === 'hires') {
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
      const modeValue = AppSettings.defaultPlayMode
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
      const widgetPath = `${AppSettings.context.filesDir}/${AppSettings.PLAYER_WIDGET_FILE}`
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
          isPlaying: playerStore.isPlaying
        }
        const widgetFile = fileIo.openSync(widgetPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
        try {
          fileIo.writeSync(widgetFile.fd, JSON.stringify(widgetState))
        } finally {
          fileIo.closeSync(widgetFile)
        }
        await AppSettings.updateMusicCards(widgetState)
      } else {
        if (fileIo.accessSync(queuePath)) {
          fileIo.unlinkSync(queuePath)
        }
        if (fileIo.accessSync(widgetPath)) {
          fileIo.unlinkSync(widgetPath)
        }
        await store.delete(AppSettings.PLAYER_INDEX_KEY)
      }
      await store.put(AppSettings.PLAYER_MODE_KEY, playerStore.playMode)
      await store.flush()
    } catch (_error) {
    }
  }

  private static async updateMusicCards(state: MusicWidgetState): Promise<void> {
    if (!AppSettings.context) {
      return
    }
    try {
      const idsPath = `${AppSettings.context.filesDir}/${AppSettings.PLAYER_WIDGET_FORM_IDS_FILE}`
      if (!fileIo.accessSync(idsPath)) {
        return
      }
      const ids = JSON.parse(fileIo.readTextSync(idsPath)) as string[]
      const bindingState = new MusicWidgetBindingState()
      bindingState.songName = state.songName
      bindingState.artist = state.artist
      bindingState.songId = state.songId
      bindingState.isPlaying = state.isPlaying
      const binding = formBindingData.createFormBindingData(bindingState)
      for (const formId of ids) {
        try {
          await formProvider.updateForm(formId, binding)
        } catch (_error) {
        }
      }
    } catch (_error) {
    }
  }

  static context: common.Context | null = null
}
