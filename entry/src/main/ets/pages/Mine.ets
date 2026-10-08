import { EventUpdates } from '../services/EventUpdates'
import { EventPresentation } from '../services/EventPresentation'
import { EventCard } from '../components/EventCard'
import { ListeningPlaylistService } from '../services/ListeningPlaylistService'
import { userPlaylists } from '../constants'
import { playlistType, songItemType } from '../models'
import {
  AlbumPageParam,
  AlbumSublistResponse,
  ApiParam,
  ApiSong,
  DjRadioItem,
  DjSublistResponse,
  LikeListResponse,
  ListenDataResponse,
  LoginStatusResponse,
  mapApiSong,
  mapPlaylist,
  OperationResponse,
  PlaylistCollectResponse,
  PlaylistImportStatusResponse,
  PlaylistImportTaskResponse,
  SongDetailResponse,
  SubscribedAlbum,
  UserDetailResponse,
  UserEventItem,
  UserEventResponse,
  UserLevelResponse,
  UserPlaylistResponse,
  VipInfoResponse
} from '../models/api'
import { RadioPageParam } from '../models/radio'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'
import { parseVipInfo } from '../services/VipService'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { RelationshipPageParam } from './RelationshipList'
import { PublishEventPageParam } from './PublishEvent'
import { PlaylistEditorPageParam } from './PlaylistEditor'
import { ProfileEditorPageParam } from './ProfileEditor'

interface SubTabItem {
  name: string
  title: string
}

export interface UserProfile {
  nickName: string
  avatar: string
  vipLevel: number
  followCount: number
  fanCount: number
  level: number
  listenHours: number
  gender: number
  city: string
  signature: string
  medalCount: number
  birthday: number
  province: number
  rawSignature: string
}

@Component
export struct Mine {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') @Watch('onAuthStoreChanged') authStore: AuthStore
  @Consume('playerStore') playerStore: PlayerStore

  @State userProfile: UserProfile = {
    nickName: '未登录',
    avatar: '',
    vipLevel: 0,
    followCount: 0,
    fanCount: 0,
    level: 0,
    listenHours: 0,
    gender: 1,
    city: '',
    signature: '登录后同步个人资料、收藏与歌单',
    medalCount: 0,
    birthday: 0,
    province: 0,
    rawSignature: ''
  }

  @State currentTab: string = 'music'
  @State viewMode: string = 'list'
  @State playlists: playlistType[] = userPlaylists
  @State createdPlaylists: playlistType[] = userPlaylists
  @State subscribedPlaylists: playlistType[] = []
  @State collectedPlaylists: playlistType[] = []
  @State subscribedAlbums: SubscribedAlbum[] = []
  @State musicCategory: string = 'recent'
  @State albumsLoading: boolean = false
  @State loadedUserId: string = ''
  @State lastLoggedInState: boolean = false
  @State djRadios: DjRadioItem[] = []
  @State djLoading: boolean = false
  @State djHasMore: boolean = true
  @State djOffset: number = 0
  @State userEvents: UserEventItem[] = []
  @State eventsLoading: boolean = false
  @State eventsLasttime: number = -1
  @State eventsHasMore: boolean = true
  @State eventMessage: string = ''
  @State listenRankItems: songItemType[] = []
  @State listenRankError: string = ''
  @State recentSongsError: string = ''
  @State listenRankLoading: boolean = false
  @State recentSongs: songItemType[] = []
  @State recentSongsLoading: boolean = false
  @State likedSongIds: number[] = []
  @State likedSongs: songItemType[] = []
  @State likedSongsLoading: boolean = false
  @State importSheetVisible: boolean = false
  @State importMode: string = 'text'
  @State importText: string = ''
  @State importLinkText: string = ''
  @State importLoading: boolean = false
  @State importTaskId: string = ''
  @State isRefreshing: boolean = false
  @State vipActive: boolean = false
  @State vipSvip: boolean = false
  @State vipLevel: number = 0
  @State totalListenTime: number = 0

  // `Mine` is kept alive by `Tabs`, so its appear callback is not guaranteed
  // to run when the login destination is popped or the sidebar logs out.
  // Keep the last identity separately and synchronize as soon as the observed
  // AuthStore changes.
  private authStateKey: string = ''

  private onAuthStoreChanged(): void {
    const nextKey = `${this.authStore.loggedIn ? '1' : '0'}:${this.authStore.userId}`
    if (nextKey === this.authStateKey) {
      return
    }
    this.authStateKey = nextKey
    this.lastLoggedInState = this.authStore.loggedIn
    this.loadedUserId = ''

    if (!this.authStore.loggedIn) {
      this.resetUserData()
      return
    }

    // A login response can publish the cookie/login flag before the user id.
    // Wait for the id update; the watcher will run again and start the load.
    if (!this.authStore.userId) {
      this.resetUserData()
      return
    }
    this.loadUserData()
    this.loadVipInfo()
  }

  private getVipText(vipLevel: number): string {
    return vipLevel == 1 ? '壹'
      : vipLevel == 2 ? '贰'
        : vipLevel == 3 ? '叁'
          : vipLevel == 4 ? '肆'
            : vipLevel == 5 ? '伍'
              : vipLevel == 6 ? '陆'
                : vipLevel == 7 ? '柒'
                  : '未知'
  }

  private withTimestamp(params: ApiParam[], timestamp: string = ''): ApiParam[] {
    if (!timestamp) {
      return params
    }
    return params.concat([{ key: 'timestamp', value: timestamp }])
  }

  private async loadVipInfo(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn || !this.authStore.userId) {
      this.vipActive = false
      this.vipSvip = false
      this.vipLevel = 0
      return
    }
    try {
      const response = await ApiClient.get<VipInfoResponse>('/vip/info', this.withTimestamp([
        { key: 'uid', value: this.authStore.userId }
      ], timestamp))
      const display = parseVipInfo(response.data)
      this.vipActive = display.active
      this.vipSvip = display.isSvip
      this.vipLevel = display.level
    } catch (_error) {
      this.vipActive = false
      this.vipSvip = false
      this.vipLevel = 0
    }
  }

  private openProfileEditor(): void {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const param: ProfileEditorPageParam = {
      nickname: this.userProfile.nickName,
      avatarUrl: this.userProfile.avatar,
      signature: this.userProfile.rawSignature,
      gender: this.userProfile.gender,
      birthday: this.userProfile.birthday,
      province: this.userProfile.province,
      city: Number(this.userProfile.city) || 0,
      onSaved: () => {
        this.loadedUserId = ''
        this.loadUserData()
      }
    }
    this.pageStack.pushPathByName('ProfileEditorPage', param)
  }

  private resetUserData(): void {
    this.userProfile = {
      nickName: '未登录',
      avatar: '',
      vipLevel: 0,
      followCount: 0,
      fanCount: 0,
      level: 0,
      listenHours: 0,
      gender: 1,
      city: '',
      signature: '登录后同步个人资料、收藏与歌单',
      medalCount: 0,
      birthday: 0,
      province: 0,
      rawSignature: ''
    }
    this.playlists = userPlaylists
    this.createdPlaylists = userPlaylists
    this.subscribedPlaylists = []
    this.collectedPlaylists = []
    this.subscribedAlbums = []
    this.djRadios = []
    this.userEvents = []
    this.recentSongs = []
    this.likedSongs = []
    this.likedSongIds = []
    this.listenRankItems = []
    this.listenRankError = ''
    this.recentSongsError = ''
    this.djOffset = 0
    this.djHasMore = true
    this.eventsLasttime = -1
    this.eventsHasMore = true
    this.eventMessage = ''
    this.vipActive = false
    this.vipSvip = false
    this.vipLevel = 0
    this.totalListenTime = 0
    this.loadedUserId = ''
  }

  private async loadUserData(timestamp: string = '', refreshRecent: boolean = false): Promise<void> {
    if (!this.authStore.loggedIn || !this.authStore.userId) {
      if (this.loadedUserId.length > 0) {
        this.resetUserData()
      }
      return
    }
    if (this.loadedUserId === this.authStore.userId) {
      return
    }
    try {
      const detailResp = await ApiClient.get<UserDetailResponse>('/user/detail', this.withTimestamp([
        { key: 'uid', value: this.authStore.userId }
      ], timestamp))
      if (detailResp.code === 200 && detailResp.profile) {
        const profile = detailResp.profile
        this.authStore.applyProfile(profile)
        this.userProfile = {
          nickName: profile.nickname,
          avatar: profile.avatarUrl,
          vipLevel: 0,
          followCount: profile.follows || 0,
          fanCount: profile.followeds || 0,
          level: this.userProfile.level,
          listenHours: this.userProfile.listenHours,
          gender: profile.gender || 1,
          city: profile.city?.toString() || '',
          signature: profile.signature || '还没有填写个人介绍',
          medalCount: this.userProfile.medalCount,
          birthday: profile.birthday || 0,
          province: profile.province || 0,
          rawSignature: profile.signature || ''
        }
        await this.loadListenTotalData(timestamp)
      }

      const response = await ApiClient.get<UserPlaylistResponse>('/user/playlist', this.withTimestamp([
        { key: 'uid', value: this.authStore.userId },
        { key: 'limit', value: '1000' },
        { key: 'offset', value: '0' }
      ], timestamp))
      this.playlists = (response.playlist || []).map((item) => mapPlaylist(item))
      this.createdPlaylists = (response.playlist || [])
        .filter((item) => item.creator?.userId?.toString() === this.authStore.userId)
        .map((item) => mapPlaylist(item))
      this.subscribedPlaylists = (response.playlist || [])
        .filter((item) => item.creator?.userId?.toString() !== this.authStore.userId)
        .map((item) => mapPlaylist(item))

      try {
        const collectResp = await ApiClient.get<PlaylistCollectResponse>('/user/playlist/collect', this.withTimestamp([
          { key: 'uid', value: this.authStore.userId },
          { key: 'limit', value: '1000' },
          { key: 'offset', value: '0' }
        ], timestamp))
        if (collectResp.code === 200 && collectResp.playlist) {
          this.collectedPlaylists = collectResp.playlist.map((item) => mapPlaylist(item))
        }
      } catch (_e) {
      }

      await this.loadSubscribedAlbums(timestamp)
      const levelResponse = await ApiClient.get<UserLevelResponse>('/user/level', this.withTimestamp([], timestamp))
      if (levelResponse.code === 200 && levelResponse.data) {
        this.userProfile = {
          nickName: this.userProfile.nickName,
          avatar: this.userProfile.avatar,
          vipLevel: this.userProfile.vipLevel,
          followCount: this.userProfile.followCount,
          fanCount: this.userProfile.fanCount,
          level: levelResponse.data.level,
          listenHours: this.userProfile.listenHours,
          gender: this.userProfile.gender,
          city: this.userProfile.city,
          signature: this.userProfile.signature,
          medalCount: this.userProfile.medalCount,
          birthday: this.userProfile.birthday,
          province: this.userProfile.province,
          rawSignature: this.userProfile.rawSignature
        }
      }
      this.loadedUserId = this.authStore.userId
      this.loadRecentSongs(timestamp)
      this.loadListenRank(timestamp)
      if (this.currentTab === 'music' && this.musicCategory === 'recent') {
        await this.loadRecentData(timestamp, refreshRecent)
      }
    } catch (_error) {
      try {
        const statusParams: Record<string, string> = {}
        if (timestamp) {
          statusParams['timestamp'] = timestamp
        }
        const statusResp = await ApiClient.postJson<LoginStatusResponse>('/login/status', statusParams)
        const profile = statusResp.data?.profile
        if (profile) {
          this.authStore.applyProfile(profile)
          this.userProfile = {
            nickName: profile.nickname,
            avatar: profile.avatarUrl,
            vipLevel: 0,
            followCount: profile.follows || 0,
            fanCount: profile.followeds || 0,
            level: this.userProfile.level,
            listenHours: this.userProfile.listenHours,
            gender: this.userProfile.gender,
            city: this.userProfile.city,
            signature: profile.signature || '还没有填写个人介绍',
            medalCount: this.userProfile.medalCount,
            birthday: this.userProfile.birthday,
            province: this.userProfile.province,
            rawSignature: profile.signature || ''
          }
        }
      } catch (_e2) {
      }
    }
  }

  private openProtectedPage(name: string, param: object | null = null): void {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.pageStack.pushPathByName(name, param)
  }

  private currentPlaylists(): playlistType[] {
    if (this.musicCategory !== 'created') { return this.subscribedPlaylists }
    return this.createdWithListening()
  }

  private createdWithListening(): playlistType[] {
    const result = this.createdPlaylists.slice()
    const likedIndex = result.findIndex((item: playlistType) => item.isLiked === true)
    result.splice(likedIndex >= 0 ? likedIndex + 1 : Math.min(1, result.length), 0,
      this.listeningPlaylist('recent'), this.listeningPlaylist('record'))
    return result
  }

  private async loadRecentData(timestamp: string = '', forceRefresh: boolean = false): Promise<void> {
    const requests: Promise<void>[] = []
    if (forceRefresh || this.likedSongs.length === 0) {
      requests.push(this.loadLikedSongs(timestamp))
    }
    if (forceRefresh || this.listenRankItems.length === 0) {
      requests.push(this.loadListenRank(timestamp))
    }
    if (forceRefresh || this.recentSongs.length === 0) {
      requests.push(this.loadRecentSongs(timestamp))
    }
    await Promise.all(requests)
  }

  private async loadSubscribedAlbums(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn || !this.authStore.userId || this.albumsLoading) {
      return
    }
    this.albumsLoading = true
    try {
      const response = await ApiClient.get<AlbumSublistResponse>('/album/sublist', this.withTimestamp([
        { key: 'uid', value: this.authStore.userId },
        { key: 'limit', value: '1000' },
        { key: 'offset', value: '0' }
      ], timestamp))
      if (response.code === 200) {
        this.subscribedAlbums = response.data || []
      }
    } catch (_error) {
      this.subscribedAlbums = []
    } finally {
      this.albumsLoading = false
    }
  }

  private async loadListenTotalData(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn) {
      return
    }
    try {
      const response = await ApiClient.get<ListenDataResponse>('/listen/data/total',
        this.withTimestamp([], timestamp))
      if (response.code === 200 && response.data) {
        const raw = response.data.totalTime || response.data.totalDuration ||
          response.data.duration || response.data.listenTime || 0
        const ms = raw > 100000000 ? raw : raw * 1000
        this.totalListenTime = ms
        this.userProfile = {
          nickName: this.userProfile.nickName,
          avatar: this.userProfile.avatar,
          vipLevel: this.userProfile.vipLevel,
          followCount: this.userProfile.followCount,
          fanCount: this.userProfile.fanCount,
          level: this.userProfile.level,
          listenHours: Math.floor(ms / 3600000),
          gender: this.userProfile.gender,
          city: this.userProfile.city,
          signature: this.userProfile.signature,
          medalCount: this.userProfile.medalCount,
          birthday: this.userProfile.birthday,
          province: this.userProfile.province,
          rawSignature: this.userProfile.rawSignature
        }
      }
    } catch (_error) {
    }
  }

  private formatBirthday(timestamp: number): string {
    if (timestamp <= 0) {
      return ''
    }
    const date = new Date(timestamp)
    const year = date.getFullYear()
    if (year < 1970) {
      return ''
    }
    const month = date.getMonth() + 1
    const day = date.getDate()
    return `${year}.${month < 10 ? '0' + month : month}.${day < 10 ? '0' + day : day}`
  }

  private provinceNameOf(code: number): string {
    const map: Record<number, string> = {
      11: '北京', 12: '天津', 13: '河北', 14: '山西', 15: '内蒙古',
      21: '辽宁', 22: '吉林', 23: '黑龙江',
      31: '上海', 32: '江苏', 33: '浙江', 34: '安徽', 35: '福建', 36: '江西', 37: '山东',
      41: '河南', 42: '湖北', 43: '湖南', 44: '广东', 45: '广西', 46: '海南',
      50: '重庆', 51: '四川', 52: '贵州', 53: '云南', 54: '西藏',
      61: '陕西', 62: '甘肃', 63: '青海', 64: '宁夏', 65: '新疆',
      71: '台湾', 81: '香港', 82: '澳门'
    }
    return map[Math.floor(code / 10000)] || ''
  }

  private cityNameOf(code: number): string {
    const map: Record<number, string> = {
      1101: '北京', 1201: '天津', 3101: '上海', 5001: '重庆',
      4401: '广州', 4403: '深圳', 3301: '杭州', 3201: '南京',
      4201: '武汉', 4301: '长沙', 4101: '郑州', 3701: '济南',
      3702: '青岛', 2101: '沈阳', 2201: '长春', 2301: '哈尔滨',
      1301: '石家庄', 1401: '太原', 6101: '西安', 5101: '成都',
      5301: '昆明', 5201: '贵阳', 4501: '南宁', 4601: '海口',
      3501: '福州', 3502: '厦门', 3401: '合肥', 3601: '南昌',
      6201: '兰州', 6401: '银川', 6301: '西宁', 1501: '呼和浩特',
      4302: '株洲', 4303: '湘潭', 3205: '苏州', 3202: '无锡',
      3302: '宁波', 4406: '佛山', 4419: '东莞'
    }
    return map[Math.floor(code / 1000)] || ''
  }

  private formatLocation(provinceCode: number, cityCode: number): string {
    const province = this.provinceNameOf(provinceCode)
    const city = this.cityNameOf(cityCode)
    if (province && city) {
      if (city === province || city === '北京' || city === '上海' || city === '天津' || city === '重庆') {
        return city
      }
      return `${province} ${city}`
    }
    if (province) {
      return province
    }
    return ''
  }

  private async loadLikedSongs(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn || !this.authStore.userId || this.likedSongsLoading) {
      return
    }
    this.likedSongsLoading = true
    try {
      const likeResp = await ApiClient.get<LikeListResponse>('/likelist', this.withTimestamp([
        { key: 'uid', value: this.authStore.userId }
      ], timestamp))
      if (likeResp.code === 200 && likeResp.ids && likeResp.ids.length > 0) {
        this.likedSongIds = likeResp.ids
        const sliceIds = likeResp.ids.slice(0, 50)
        const detailResp = await ApiClient.get<SongDetailResponse>('/song/detail', this.withTimestamp([
          { key: 'ids', value: sliceIds.join(',') }
        ], timestamp))
        if (detailResp.code === 200 && detailResp.songs) {
          this.likedSongs = detailResp.songs.map((song: ApiSong) => mapApiSong(song))
        }
      }
    } catch (_error) {
    } finally {
      this.likedSongsLoading = false
    }
  }

  private async loadListenRank(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn || this.listenRankLoading) { return }
    const uid = this.authStore.userId
    this.listenRankLoading = true
    this.listenRankError = ''
    try {
      const songs = await ListeningPlaylistService.record(uid, 1, timestamp)
      if (this.authStore.userId === uid) { this.listenRankItems = songs }
    } catch (error) {
      if (this.authStore.userId === uid) {
        this.listenRankItems = []
        this.listenRankError = error instanceof Error ? error.message : '听歌排行加载失败'
      }
    } finally { this.listenRankLoading = false }
  }

  private async loadRecentSongs(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn || this.recentSongsLoading) { return }
    const uid = this.authStore.userId
    this.recentSongsLoading = true
    this.recentSongsError = ''
    try {
      const songs = await ListeningPlaylistService.recent(timestamp)
      if (this.authStore.userId === uid) { this.recentSongs = songs }
    } catch (error) {
      if (this.authStore.userId === uid) {
        this.recentSongs = []
        this.recentSongsError = error instanceof Error ? error.message : '最近播放加载失败'
      }
    } finally { this.recentSongsLoading = false }
  }

  private async loadDjRadios(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn || this.djLoading || !this.djHasMore) {
      return
    }
    this.djLoading = true
    try {
      const response = await ApiClient.get<DjSublistResponse>('/dj/sublist', this.withTimestamp([
        { key: 'limit', value: '30' },
        { key: 'offset', value: this.djOffset.toString() }
      ], timestamp))
      if (response.code === 200) {
        this.djRadios = this.djRadios.concat(response.djRadios || [])
        this.djHasMore = response.hasMore || false
        this.djOffset = this.djRadios.length
      }
    } catch (_error) {
    } finally {
      this.djLoading = false
    }
  }

  private async loadUserEvents(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn || this.eventsLoading) {
      return
    }
    this.eventsLoading = true
    try {
      const response = await ApiClient.get<UserEventResponse>('/user/event', [
        { key: 'uid', value: this.authStore.userId },
        { key: 'limit', value: '20' },
        { key: 'lasttime', value: this.eventsLasttime.toString() },
        { key: 'timestamp', value: timestamp || Date.now().toString() }
      ])
      if (response.code === 200) {
        if (this.eventsLasttime === -1) {
          this.userEvents = response.events || []
        } else {
          this.userEvents = this.userEvents.concat(response.events || [])
        }
        this.eventsLasttime = response.lasttime || -1
        this.eventsHasMore = response.more || false
      }
    } catch (_error) {
    } finally {
      this.eventsLoading = false
    }
  }

  private stopEventUpdates?: () => void

  aboutToAppear(): void { this.watchEventUpdates() }

  private watchEventUpdates(): void {
    this.stopEventUpdates?.()
    this.stopEventUpdates = EventUpdates.subscribe((item: UserEventItem, deleted: boolean) => {
      this.applyLocalEventChange(item, deleted)
    })
  }

  aboutToDisappear(): void { this.stopEventUpdates?.() }

  private applyEventChange(item: UserEventItem, deleted: boolean): void {
    EventUpdates.publish(item, deleted)
  }

  private applyLocalEventChange(item: UserEventItem, deleted: boolean): void {
    this.userEvents = EventPresentation.changeList(this.userEvents, item, deleted)
  }

  private async startPlaylistImport(): Promise<void> {
    this.importLoading = true
    try {
      let params: ApiParam[] = []
      if (this.importMode === 'text') {
        const textParam: ApiParam = { key: 'text', value: this.importText }
        params = [textParam]
      } else if (this.importMode === 'link') {
        const linkParam: ApiParam = { key: 'link', value: this.importLinkText }
        params = [linkParam]
      }
      const response = await ApiClient.get<PlaylistImportTaskResponse>(
        '/playlist/import/name/task/create', params)
      if (response.code === 200 && response.id) {
        this.importTaskId = response.id.toString()
        this.pollImportStatus()
      }
    } catch (_error) {
    } finally {
      this.importLoading = false
    }
  }

  private async pollImportStatus(): Promise<void> {
    if (this.importTaskId.length === 0) {
      return
    }
    try {
      const response = await ApiClient.get<PlaylistImportStatusResponse>(
        '/playlist/import/task/status', [
        { key: 'id', value: this.importTaskId }
      ])
      if (response.code === 200) {
        if (response.status === 1 || response.playlistId) {
          this.importSheetVisible = false
          this.importText = ''
          this.importLinkText = ''
          this.loadedUserId = ''
          this.loadUserData()
        }
      }
    } catch (_error) {
    }
  }

  private subTabs: SubTabItem[] = [
    { name: 'music', title: '音乐' },
    { name: 'podcast', title: '播客' },
    { name: 'moment', title: '笔记' }
  ]

  private openPublishEvent(): void {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const param: PublishEventPageParam = {
      onPublished: () => {
        this.eventsLasttime = -1
        this.eventsHasMore = true
        this.userEvents = []
        this.loadUserEvents()
      }
    }
    this.pageStack.pushPathByName('PublishEventPage', param)
  }

  private async pullRefresh(): Promise<void> {
    const timestamp = Date.now().toString()
    this.loadedUserId = ''
    await this.loadUserData(timestamp, this.currentTab === 'music' && this.musicCategory === 'recent')
    const requests: Promise<void>[] = [this.loadVipInfo(timestamp)]
    if (this.currentTab === 'podcast') {
      this.djOffset = 0
      this.djHasMore = true
      this.djRadios = []
      requests.push(this.loadDjRadios(timestamp))
    } else if (this.currentTab === 'moment') {
      this.eventsLasttime = -1
      this.eventsHasMore = true
      this.userEvents = []
      requests.push(this.loadUserEvents(timestamp))
    }
    await Promise.all(requests)
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
      this.HeaderSection()
      this.StatsSection()
      this.SubTabBar()
      Refresh({ refreshing: $$this.isRefreshing }) {
        Scroll() {
          Column() {
            if (this.currentTab === 'music') {
              this.MusicContent()
            } else if (this.currentTab === 'podcast') {
              this.PodcastContent()
            } else {
              this.MomentContent()
            }
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .onRefreshing(() => {
        this.pullRefresh().then(() => {
          this.isRefreshing = false
        }).catch(() => {
          this.isRefreshing = false
        })
      })
      }
      .width('100%').height('100%')

      if (this.currentTab === 'moment' && this.authStore.loggedIn) {
        Stack() {
          SymbolGlyph($r('sys.symbol.plus_circle_fill')).fontSize(31).fontColor(['#ffffff'])
        }
        .width(58).height(58).borderRadius(29).backgroundColor('#ef233c')
        .shadow({ radius: 18, color: 'rgba(239,35,60,0.38)', offsetY: 7 })
        .margin({ right: 20, bottom: 24 }).onClick(() => this.openPublishEvent())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121215')
    .onAppear(() => {
      // TabContent can stay mounted while another page is on top of it.  Run
      // the same synchronization on appear for the initial state, while the
      // AuthStore watcher handles login/logout changes made in the meantime.
      this.onAuthStoreChanged()
      if (this.musicCategory === 'recent') {
        this.loadRecentData()
      }
    })
    .bindSheet(this.importSheetVisible, this.ImportSheetContent(), {
      height: '70%',
      backgroundColor: '#19191f',
      showClose: false,
      dragBar: true,
      onDisappear: () => this.importSheetVisible = false
    })
  }

  @Builder
  HeaderSection() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.userProfile.avatar) {
        Image(this.userProfile.avatar)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(48)
          .opacity(0.55)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#1a1a2e')
      }
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 180, colors: [['rgba(15,15,20,0.22)', 0], ['#121215', 1]] })

      Column({ space: 8 }) {
        if (this.userProfile.avatar) {
          Image(this.userProfile.avatar)
            .width(72)
            .height(72)
            .borderRadius(36)
            .objectFit(ImageFit.Cover)
            .border({ width: 2, color: '#ffffff' })
        } else {
          Stack() {
            SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
              .fontSize(52)
              .fontColor(['#cccccc'])
          }
          .width(72)
          .height(72)
          .borderRadius(36)
          .backgroundColor('#2a2a3e')
          .border({ width: 2, color: '#ffffff' })
        }

        Row({ space: 6 }) {
          Text(this.userProfile.nickName)
            .fontColor(Color.White)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)

          if (this.vipActive) {
            Row({ space: 3 }) {
              Image(this.vipSvip ? $r('app.media.ic_svip') : $r('app.media.ic_vip'))
                .width(this.vipSvip ? 40 : 34)
                .height(18)
                .objectFit(ImageFit.Contain)

              Text(`${this.getVipText(this.vipLevel)}`)
                .fontSize(10)
                .fontWeight(FontWeight.Regular)
                .fontColor(this.vipSvip ? '#fff8e1b9' : '#ffe8d1cc')
            }
            .padding({ left: 0, right: 6, top: 0, bottom: 0 })
            .backgroundColor(this.vipSvip ? '#ff2d2516' : '#ff372c2c')
            .borderRadius(16)
          }
        }

        if (this.userProfile.rawSignature) {
          Text(this.userProfile.signature)
            .fontSize(13)
            .fontColor('#cccccc')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width('80%')
        }

        if (this.userProfile.rawSignature) {
          Row({ space: 10 }) {
            if (this.userProfile.gender === 1) {
              Image($r('app.media.ic_boy')).width(14).height(14).objectFit(ImageFit.Contain).fillColor('#26a6e4')
            } else if (this.userProfile.gender === 2) {
              Image($r('app.media.ic_girl')).width(14).height(14).objectFit(ImageFit.Contain).fillColor('#ffb5d3')
            }
            if (this.userProfile.birthday > 0) {
              Text(this.formatBirthday(this.userProfile.birthday))
                .fontSize(11).fontColor('#999999')
            }
            if (this.userProfile.province > 0) {
              Text(this.formatLocation(this.userProfile.province, Number(this.userProfile.city) || 0))
                .fontSize(11).fontColor('#999999')
            }
          }
          .margin({ top: 4 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: this.topAvoidHeight + 32, bottom: 16 })

      if (this.authStore.loggedIn) {
        Stack() {
          SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(19).fontColor(['#ffffff'])
        }
        .width(40).height(40).borderRadius(14).backgroundColor('rgba(20,20,25,0.55)')
        .position({ right: 18, top: this.topAvoidHeight + 28 }).onClick(() => this.openProfileEditor())
      }
    }
    .width('100%')
    .height(this.topAvoidHeight + 220)
    .constraintSize({ minHeight: this.topAvoidHeight + 220 })
    .flexShrink(0)
    .onClick(() => {
      if (!this.authStore.loggedIn) {
        this.pageStack.pushPathByName('LoginPage', null)
      }
    })
  }

  @Builder
  StatsSection() {
    Row() {
      Row({ space: 4 }) {
        Text(`${this.userProfile.followCount}`)
          .fontSize(16)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Bold)
        Text('关注')
          .fontSize(12)
          .fontColor('#888888')
      }
      .onClick(() => {
        const param: RelationshipPageParam = { type: 'following', title: '关注' }
        this.openProtectedPage('FollowingPage', param)
      })

      Divider().vertical(true).height(16).color('#333333').margin({ left: 16, right: 16 })

      Row({ space: 4 }) {
        Text(`${this.userProfile.fanCount}`)
          .fontSize(16)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Bold)
        Text('粉丝')
          .fontSize(12)
          .fontColor('#888888')
      }
      .onClick(() => {
        const param: RelationshipPageParam = { type: 'followers', title: '粉丝' }
        this.openProtectedPage('FollowersPage', param)
      })

      Divider().vertical(true).height(16).color('#333333').margin({ left: 16, right: 16 })

      Row({ space: 4 }) {
        Text(`Lv.${this.userProfile.level}`)
          .fontSize(16)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Bold)
      }
      .onClick(() => {
        this.openProtectedPage('UserLevelPage')
      })

      Divider().vertical(true).height(16).color('#333333').margin({ left: 16, right: 16 })

      Row({ space: 4 }) {
        Text(`${this.userProfile.listenHours}`)
          .fontSize(16)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Bold)
        Text('小时')
          .fontSize(12)
          .fontColor('#888888')
      }
      .onClick(() => {
        this.openProtectedPage('ListeningStatsPage')
      })
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(18,18,21,0.65)')
  }

  @Builder
  SubTabBar() {
    Stack() {
      Row() {
        ForEach(this.subTabs, (item: SubTabItem) => {
          Column() {
            Text(item.title)
              .fontSize(18)
              .fontColor(this.currentTab === item.name ? '#ffffff' : '#666666')
              .fontWeight(this.currentTab === item.name ? FontWeight.Medium : FontWeight.Regular)
              .transition({ type: TransitionType.All })
              .padding({ top: 4, bottom: 4 })

            Column()
              .width(20)
              .height(2)
              .backgroundColor(this.currentTab === item.name ? '#c0392b' : Color.Transparent)
              .borderRadius(1)
              .margin({ top: 4 })
              .animation({ duration: 250, curve: Curve.EaseInOut })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.currentTab = item.name
            if (item.name === 'music' && this.musicCategory === 'recent') {
              this.loadRecentData()
            } else if (item.name === 'podcast' && this.djRadios.length === 0) {
              this.loadDjRadios()
            } else if (item.name === 'moment' && this.userEvents.length === 0) {
              this.loadUserEvents()
            }
          })
        })
      }
      .width('100%')
      .height(44)
    }
    .width('100%')
    .height(44)
  }

  @Builder
  RecentContent() {
    Column() {
      if (!this.authStore.loggedIn) {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
            .fontSize(26)
            .fontColor(['#ff6577'])
          Column({ space: 4 }) {
            Text('登录后查看近期内容')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#ffffff')
            Text('登录后同步你的听歌记录与歌单')
              .fontSize(11)
              .fontColor('#77777f')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button('去登录')
            .fontSize(12)
            .fontColor('#ffffff')
            .backgroundColor('#ef233c')
            .borderRadius(16)
            .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
        }
        .width('100%')
        .padding(14)
        .margin({ left: 14, right: 14, top: 10, bottom: 6 })
        .backgroundColor('#1d1d23')
        .borderRadius(16)
      } else {
        this.RecentPlaylistsSection()
        this.RecentAlbumsSection()
        Text('已通过分页参数查询全部可见收藏内容，该列表仅自己可见')
          .fontSize(11)
          .fontColor('#666666')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 16, bottom: 64 })
      }
    }
    .width('100%')
    .padding({ bottom: 24 })
  }

  @Builder
  private SpecialPlaylistCover(cover: string, kind: string) {
    Stack() {
      if (cover) { Image(cover).width('100%').height('100%').objectFit(ImageFit.Cover) }
      Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.35)')
      SymbolGlyph(kind === 'recent' ? $r('sys.symbol.clock') :
        kind === 'record' ? $r('sys.symbol.sort') : $r('sys.symbol.heart_fill'))
        .fontSize(26).fontColor(['#ffffff'])
    }.width('100%').height('100%').backgroundColor('#2a2a2a').borderRadius(8).clip(true)
  }

  @Builder
  LikedSongsSection() {
    Column() {
      Row({ space: 8 }) {
        Column() {
          this.SpecialPlaylistCover(this.likedSongs[0]?.img || '', 'liked')
        }.width(56).height(56)

        Column({ space: 4 }) {
          Text('我喜欢的音乐')
            .fontSize(14)
            .fontColor('#ededf0')
            .fontWeight(FontWeight.Medium)
          Text(`${this.likedSongIds.length}首`)
            .fontSize(11)
            .fontColor('#77777f')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)

        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(22)
          .fontColor(['#ffffff'])
          .onClick(() => {
            if (this.likedSongs.length > 0) {
              const likedPlaylist: playlistType = {
                id: 'liked',
                name: '我喜欢的音乐',
                cover: '',
                count: this.likedSongIds.length,
                creator: this.authStore.nickname,
                isLiked: true
              }
              this.pageStack.pushPathByName('PlaylistDetailPage', likedPlaylist)
            }
          })
      }
      .width('100%')
      .height(72)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .margin({ top: 10 })
  }

  private listeningPlaylist(kind: 'recent' | 'record'): playlistType {
    return ListeningPlaylistService.playlist(kind, this.authStore.userId, this.authStore.nickname,
      kind === 'recent' ? this.recentSongs : this.listenRankItems)
  }

  @Builder
  RecentPlaylistsSection() {
    Column() {
      Row() {
        Text('创建的歌单')
          .fontSize(14)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(`${this.createdPlaylists.length}`)
          .fontSize(12)
          .fontColor('#77777f')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 6 })

      ForEach(this.createdWithListening().slice(0, 6), (item: playlistType) => {
        Row({ space: 12 }) {
          Stack() {
            if (item.isLiked || item.specialType === 'recent' || item.specialType === 'record') {
              this.SpecialPlaylistCover(item.cover, item.isLiked ? 'liked' : item.specialType || '')
            } else {
              Image(item.cover).width(56).height(56).borderRadius(8).objectFit(ImageFit.Cover)
            }
          }.width(56).height(56)
          Column({ space: 4 }) {
            Text(item.name)
              .fontSize(13)
              .fontColor('#ededf0')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${item.count}首`)
              .fontSize(11)
              .fontColor('#77777f')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height(64)
        .padding({ left: 16, right: 16 })
        .onClick(() => this.navigateToPlaylist(item))
      })

      Row() {
        Text('收藏的歌单')
          .fontSize(14)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(`${this.collectedPlaylists.length > 0 ? this.collectedPlaylists.length : this.subscribedPlaylists.length}`)
          .fontSize(12)
          .fontColor('#77777f')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 6 })

      ForEach((this.collectedPlaylists.length > 0 ? this.collectedPlaylists : this.subscribedPlaylists).slice(0, 4), (item: playlistType) => {
        Row({ space: 12 }) {
          Image(item.cover)
            .width(48)
            .height(48)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
          Column({ space: 4 }) {
            Text(item.name)
              .fontSize(13)
              .fontColor('#ededf0')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${item.count}首 · ${item.creator}`)
              .fontSize(11)
              .fontColor('#77777f')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height(64)
        .padding({ left: 16, right: 16 })
        .onClick(() => this.navigateToPlaylist(item))
      })
    }
    .width('100%')
  }

  @Builder
  RecentAlbumsSection() {
    Column() {
      Row() {
        Text('收藏的专辑')
          .fontSize(14)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(`${this.subscribedAlbums.length}`)
          .fontSize(12)
          .fontColor('#77777f')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 6 })

      if (this.subscribedAlbums.length === 0) {
        Text('暂无收藏专辑')
          .fontSize(12)
          .fontColor('#77777f')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 12, bottom: 12 })
      } else {
        ForEach(this.subscribedAlbums.slice(0, 4), (item: SubscribedAlbum) => {
          Row({ space: 12 }) {
            Image(item.picUrl).width(48).height(48).borderRadius(8).objectFit(ImageFit.Cover)
            Column({ space: 3 }) {
              Text(item.name).fontSize(13).fontColor('#ededf0').maxLines(1)
              Text(item.artists.map((artist) => artist.name).join(' / '))
                .fontSize(11).fontColor('#77777f').maxLines(1)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%').height(64).padding({ left: 16, right: 16 })
          .onClick(() => this.navigateToAlbum(item))
        })
      }
    }
    .width('100%')
  }

  @Builder
  MusicContent() {
    Column() {
      if (!this.authStore.loggedIn && this.musicCategory !== 'recent') {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
            .fontSize(26)
            .fontColor(['#ff6577'])
          Column({ space: 4 }) {
            Text('登录后查看真实歌单')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#ffffff')
            Text('当前列表为离线演示内容')
              .fontSize(11)
              .fontColor('#77777f')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button('去登录')
            .fontSize(12)
            .fontColor('#ffffff')
            .backgroundColor('#ef233c')
            .borderRadius(16)
            .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
        }
        .width('100%')
        .padding(14)
        .margin({ left: 14, right: 14, top: 10, bottom: 6 })
        .backgroundColor('#1d1d23')
        .borderRadius(16)
      }

      Row() {
        Text('近期')
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(this.musicCategory === 'recent' ? '#ffffff' : '#66666e')
          .fontWeight(this.musicCategory === 'recent' ? FontWeight.Bold : FontWeight.Regular)
          .textAlign(TextAlign.Center)
          .padding({ top: 5, bottom: 5 })
          .backgroundColor(this.musicCategory === 'recent' ? '#25252c' : Color.Transparent)
          .borderRadius(14)
          .onClick(() => {
            this.musicCategory = 'recent'
            this.loadRecentData()
          })
        Text(`创建 ${this.createdPlaylists.length}`)
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(this.musicCategory === 'created' ? '#ffffff' : '#66666e')
          .fontWeight(this.musicCategory === 'created' ? FontWeight.Bold : FontWeight.Regular)
          .textAlign(TextAlign.Center)
          .padding({ top: 5, bottom: 5 })
          .backgroundColor(this.musicCategory === 'created' ? '#25252c' : Color.Transparent)
          .borderRadius(18)
          .onClick(() => this.musicCategory = 'created')
        Text(`收藏 ${this.subscribedPlaylists.length}`)
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(this.musicCategory === 'subscribed' ? '#ffffff' : '#66666e')
          .fontWeight(this.musicCategory === 'subscribed' ? FontWeight.Bold : FontWeight.Regular)
          .textAlign(TextAlign.Center)
          .padding({ top: 5, bottom: 5 })
          .backgroundColor(this.musicCategory === 'subscribed' ? '#25252c' : Color.Transparent)
          .borderRadius(18)
          .onClick(() => this.musicCategory = 'subscribed')
        Text(`专辑 ${this.subscribedAlbums.length}`)
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(this.musicCategory === 'albums' ? '#ffffff' : '#66666e')
          .fontWeight(this.musicCategory === 'albums' ? FontWeight.Bold : FontWeight.Regular)
          .textAlign(TextAlign.Center)
          .padding({ top: 5, bottom: 5 })
          .backgroundColor(this.musicCategory === 'albums' ? '#25252c' : Color.Transparent)
          .borderRadius(18)
          .onClick(() => {
            this.musicCategory = 'albums'
            if (this.subscribedAlbums.length === 0) {
              this.loadSubscribedAlbums()
            }
          })
      }
      .width('60%')
      .padding({ left: 14, right: 14, top: 10, bottom: 8 })

      if (this.musicCategory === 'recent') {
        this.RecentContent()
      } else {
        Row() {
          Text(this.musicCategory === 'created' ? '我创建的歌单' :
            this.musicCategory === 'subscribed' ? '我收藏的歌单' : '我收藏的专辑')
            .fontSize(14)
            .fontColor('#ffffff')
            .fontWeight(FontWeight.Medium)

          Blank()

          if (this.musicCategory !== 'albums') {
            SymbolGlyph(this.viewMode === 'list' ? $r('sys.symbol.square_grid_2x2') : $r('sys.symbol.list_bullet'))
              .fontSize(20)
              .fontColor(['#888888'])
              .onClick(() => {
                this.viewMode = this.viewMode === 'list' ? 'card' : 'list'
              })
          }
        }
        .width('100%')
        .height(40)
        .padding({ left: 16, right: 16 })

        if (this.musicCategory === 'albums') {
          this.AlbumListView()
        } else if (this.viewMode === 'list') {
          this.PlaylistListView()
        } else {
          this.PlaylistCardView()
        }

        if (this.musicCategory === 'created') {
          this.BottomButtons()
        }
      }
    }
    .width('100%')
    .padding({ bottom: 24 })
  }

  @Builder
  PlaylistListView() {
    Column() {
      ForEach(this.currentPlaylists(), (item: playlistType) => {
        Row({ space: 12 }) {
          Stack() {
            if (item.isLiked || item.specialType === 'recent' || item.specialType === 'record') {
              this.SpecialPlaylistCover(item.cover, item.isLiked ? 'liked' : item.specialType || '')
            } else {
              Image(item.cover).width(56).height(56).borderRadius(8).objectFit(ImageFit.Cover)
            }
          }.width(56).height(56)

          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text(item.name)
                .fontSize(14)
                .fontColor('#e9e9e7')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (item.isLiked) {
                SymbolGlyph($r('sys.symbol.heart_fill'))
                  .fontSize(12)
                  .fontColor(['#c0392b'])
              }
            }

            Text(`${item.count}首 · ${item.creator}`)
              .fontSize(12)
              .fontColor('#888888')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)

          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(18)
            .fontColor(['#666666'])
        }
        .width('100%')
        .height(72)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.navigateToPlaylist(item)
        })
      })
    }
    .width('100%')
  }

  @Builder
  PlaylistCardView() {
    GridRow({ columns: 3, gutter: 12 }) {
      ForEach(this.currentPlaylists(), (item: playlistType) => {
        GridCol() {
          Column({ space: 6 }) {
            Stack() {
              if (item.isLiked || item.specialType === 'recent' || item.specialType === 'record') {
                this.SpecialPlaylistCover(item.cover, item.isLiked ? 'liked' : item.specialType || '')
              } else {
                Image(item.cover).width('100%').height('100%').objectFit(ImageFit.Cover).borderRadius(8)
              }
            }.width('100%').aspectRatio(1)

            Text(item.name)
              .fontSize(12)
              .fontColor('#e9e9e7')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text(`${item.count}首`)
              .fontSize(11)
              .fontColor('#888888')
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .onClick(() => {
            this.navigateToPlaylist(item)
          })
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  AlbumListView() {
    Column() {
      if (this.albumsLoading) {
        Column({ space: 10 }) {
          LoadingProgress().width(40).color('#ef233c')
          Text('正在加载收藏专辑…').fontSize(12).fontColor('#77777f')
        }
        .width('100%').height(180).justifyContent(FlexAlign.Center)
      } else if (this.subscribedAlbums.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(40).fontColor(['#55555d'])
          Text(this.authStore.loggedIn ? '暂时没有收藏专辑' : '登录后查看收藏专辑')
            .fontSize(12).fontColor('#77777f')
        }
        .width('100%').height(180).justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.subscribedAlbums, (item: SubscribedAlbum) => {
          Row({ space: 12 }) {
            Image(item.picUrl).width(58).height(58).borderRadius(12).objectFit(ImageFit.Cover)
            Column({ space: 5 }) {
              Text(item.name).fontSize(14).fontColor('#ededf0').maxLines(1)
              Text(`${item.artists.map((artist) => artist.name).join(' / ')} · ${item.size} 首`)
                .fontSize(11).fontColor('#77777f').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(18).fontColor(['#66666e'])
          }
          .height(72).padding({ left: 16, right: 16 })
          .onClick(() => this.navigateToAlbum(item))
        })
      }
    }
    .width('100%')
  }

  @Builder
  BottomButtons() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(28)
            .fontColor(['#ff7c7c7c'])
        }
        .width(56)
        .height(56)
        .borderRadius(8)
        .backgroundColor('#2a2a2a')
        .alignContent(Alignment.Center)

        Column() {
          Text('新建歌单')
            .fontSize(14)
            .fontColor('#e9e9e7')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(72)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        const param: PlaylistEditorPageParam = {
          mode: 'create',
          onSaved: (_playlistId: string) => {
            this.loadedUserId = ''
            this.loadUserData()
          }
        }
        this.pageStack.pushPathByName('PlaylistEditorPage', param)
      })

      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.arrow_up_circle'))
            .fontSize(28)
            .fontColor(['#ff7c7c7c'])
        }
        .width(56)
        .height(56)
        .borderRadius(8)
        .backgroundColor('#2a2a2a')
        .alignContent(Alignment.Center)

        Column() {
          Text('导入外部歌单')
            .fontSize(14)
            .fontColor('#e9e9e7')
          Text('轻松导入其他APP里的歌单')
            .fontSize(11)
            .fontColor('#888888')
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(72)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.importSheetVisible = true
      })
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  ImportSheetContent() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text('导入外部歌单')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
          Text('支持文字或链接导入')
            .fontSize(10)
            .fontColor('#77777f')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(24)
          .fontColor(['#686870'])
          .onClick(() => this.importSheetVisible = false)
      }
      .height(66)
      .padding({ left: 20, right: 20 })

      Row() {
        Text('文字导入')
          .fontSize(13)
          .fontColor(this.importMode === 'text' ? '#ffffff' : '#66666e')
          .fontWeight(this.importMode === 'text' ? FontWeight.Bold : FontWeight.Regular)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(this.importMode === 'text' ? '#25252c' : Color.Transparent)
          .borderRadius(14)
          .onClick(() => this.importMode = 'text')

        Text('链接导入')
          .fontSize(13)
          .fontColor(this.importMode === 'link' ? '#ffffff' : '#66666e')
          .fontWeight(this.importMode === 'link' ? FontWeight.Bold : FontWeight.Regular)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(this.importMode === 'link' ? '#25252c' : Color.Transparent)
          .borderRadius(14)
          .onClick(() => this.importMode = 'link')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 12 })

      if (this.importMode === 'text') {
        Column() {
          Text('每行一首歌，格式：歌名 歌手')
            .fontSize(11)
            .fontColor('#77777f')
            .width('100%')
            .margin({ bottom: 8 })
          TextArea({ text: this.importText, placeholder: 'アイニーブルー ZLMS\nファンタズマ sasakure.UK' })
            .width('100%')
            .height(160)
            .fontColor('#ffffff')
            .placeholderColor('#55555d')
            .backgroundColor('#1d1d23')
            .borderRadius(12)
            .onChange((value: string) => {
              this.importText = value
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      } else {
        Column() {
          Text('每行一个歌单链接（支持QQ音乐、酷狗等）')
            .fontSize(11)
            .fontColor('#77777f')
            .width('100%')
            .margin({ bottom: 8 })
          TextArea({ text: this.importLinkText, placeholder: 'https://i.y.qq.com/n2/m/share/details/taoge.html?id=xxx' })
            .width('100%')
            .height(160)
            .fontColor('#ffffff')
            .placeholderColor('#55555d')
            .backgroundColor('#1d1d23')
            .borderRadius(12)
            .onChange((value: string) => {
              this.importLinkText = value
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }

      Button('开始导入')
        .width('90%')
        .height(44)
        .fontSize(15)
        .fontColor('#ffffff')
        .backgroundColor('#ef233c')
        .borderRadius(22)
        .margin({ top: 20 })
        .enabled(!this.importLoading && (this.importText.length > 0 || this.importLinkText.length > 0))
        .onClick(() => this.startPlaylistImport())

      if (this.importLoading) {
        LoadingProgress().width(28).color('#ef233c').margin({ top: 12 })
      }
    }
    .width('100%')
  }

  @Builder
  PodcastContent() {
    Column() {
      if (!this.authStore.loggedIn) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
            .fontSize(40).fontColor(['#55555d'])
          Text('登录后查看订阅电台').fontSize(13).fontColor('#77777f')
          Button('去登录').fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
            .borderRadius(16).onClick(() => this.pageStack.pushPathByName('LoginPage', null))
        }
        .width('100%').height(200).justifyContent(FlexAlign.Center)
      } else if (this.djLoading && this.djRadios.length === 0) {
        LoadingProgress().width(46).color('#ef233c')
          .margin({ top: 60 })
      } else if (this.djRadios.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.podcast')).fontSize(40).fontColor(['#55555d'])
          Text('还没有订阅电台').fontSize(13).fontColor('#77777f')
        }
        .width('100%').height(200).justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.djRadios, (item: DjRadioItem) => {
          Row({ space: 12 }) {
            Image(item.picUrl).width(56).height(56).borderRadius(12).objectFit(ImageFit.Cover)
            Column({ space: 4 }) {
              Text(item.name).fontSize(14).fontColor('#ededf0').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(item.desc || `${item.programCount}期节目 · ${item.subCount}人订阅`)
                .fontSize(11).fontColor('#77777f').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(18).fontColor(['#66666e'])
          }
          .width('100%').height(72).padding({ left: 16, right: 16 }).onClick(() => {
            const param: RadioPageParam = { id: String(item.id), name: item.name, cover: item.picUrl }
            this.pageStack.pushPathByName('RadioDetailPage', param)
          })
        })
        if (this.djHasMore) {
          Text('加载更多').width('100%').height(44).fontSize(12).fontColor('#77777f')
            .textAlign(TextAlign.Center).onClick(() => this.loadDjRadios())
        }
      }

      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(28).fontColor(['#ff7c7c7c'])
        }
        .width(56).height(56).borderRadius(8).backgroundColor('#2a2a2a').alignContent(Alignment.Center)
        Column() {
          Text('创建播客').fontSize(14).fontColor('#e9e9e7')
          Text('在网易云音乐创建你的电台').fontSize(11).fontColor('#888888')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
      }
      .width('100%').height(72).padding({ left: 16, right: 16 }).margin({ top: 8 })
    }
    .width('100%').padding({ bottom: 24 })
  }

  @Builder
  MomentContent() {
    Column() {
      if (!this.authStore.loggedIn) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
            .fontSize(40).fontColor(['#55555d'])
          Text('登录后查看笔记').fontSize(13).fontColor('#77777f')
          Button('去登录').fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
            .borderRadius(16).onClick(() => this.pageStack.pushPathByName('LoginPage', null))
        }
        .width('100%').height(200).justifyContent(FlexAlign.Center)
      } else if (this.eventsLoading && this.userEvents.length === 0) {
        LoadingProgress().width(46).color('#ef233c')
          .margin({ top: 60 })
      } else if (this.userEvents.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(40).fontColor(['#55555d'])
          Text('还没有笔记').fontSize(13).fontColor('#77777f')
        }
        .width('100%').height(200).justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.userEvents.filter((event: UserEventItem) => event.id > 0), (item: UserEventItem) => {
          EventCard({ item: item,
            onChanged: (event: UserEventItem, deleted: boolean) => this.applyEventChange(event, deleted) })
            .margin({ bottom: 8 })
        }, (item: UserEventItem) => item.id.toString())
        if (this.eventsHasMore) {
          Text('加载更多').width('100%').height(44).fontSize(12).fontColor('#77777f')
            .textAlign(TextAlign.Center).onClick(() => this.loadUserEvents())
        }
        if (this.eventMessage) {
          Text(this.eventMessage).width('100%').fontSize(10).fontColor('#ff7587')
            .textAlign(TextAlign.Center).padding({ bottom: 8 })
        }
      }
    }
    .width('100%').padding({ left: 16, right: 16, bottom: 24 })
  }


  navigateToPlaylist(playlist: playlistType) {
    if (playlist.specialType === 'recent') {
      this.pageStack.pushPathByName('RecentPlaybackPage', null)
      return
    }
    playlist.onChanged = () => {
      this.loadedUserId = ''
      this.loadUserData()
    }
    this.pageStack.pushPathByName('PlaylistDetailPage', playlist)
  }

  navigateToAlbum(album: SubscribedAlbum) {
    const artistNames: string[] = []
    album.artists.forEach((ar) => {
      artistNames.push(ar.name)
    })
    const param: AlbumPageParam = {
      id: album.id.toString(),
      name: album.name,
      picUrl: album.picUrl,
      artist: artistNames.join(' / ')
    }
    this.pageStack.pushPathByName('AlbumDetailPage', param)
  }
}

export default Mine
