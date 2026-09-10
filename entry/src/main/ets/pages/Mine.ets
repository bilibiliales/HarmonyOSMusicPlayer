import { userPlaylists } from '../constants'
import { playlistType, songItemType } from '../models'
import {
  AlbumPageParam,
  AlbumSublistResponse,
  ApiArtist,
  ApiParam,
  ApiSong,
  CommentApiItem,
  CommentResponse,
  DjRadioItem,
  DjSublistResponse,
  EventCommentItem,
  EventCommentResponse,
  EventDetailPageParam,
  EventForwardData,
  EventJsonData,
  EventPicture,
  LikeListResponse,
  ListenDataResponse,
  ListenRankItem,
  ListenRankResponse,
  LoginStatusResponse,
  mapApiSong,
  mapPlaylist,
  OperationResponse,
  PlaylistCollectResponse,
  PlaylistImportStatusResponse,
  PlaylistImportTaskResponse,
  ShareResourceResponse,
  SongDetailResponse,
  SubscribedAlbum,
  UserDetailResponse,
  UserEventItem,
  UserEventResponse,
  UserLevelResponse,
  UserPlaylistResponse,
  VipInfoResponse
} from '../models/api'
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
  @State eventComments: EventCommentItem[] = []
  @State commentSheetVisible: boolean = false
  @State commentLoading: boolean = false
  @State commentTotal: number = 0
  @State selectedCommentType: number = 6
  @State selectedCommentResourceId: string = ''
  @State selectedCommentThreadId: string = ''
  @State selectedCommentEventId: number = 0
  @State commentTitle: string = '动态评论'
  @State commentInput: string = ''
  @State commentSubmitting: boolean = false
  @State eventMessage: string = ''
  @State listenRankItems: ListenRankItem[] = []
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
    return this.musicCategory === 'created' ? this.createdPlaylists : this.subscribedPlaylists
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
    if (!this.authStore.loggedIn || this.listenRankLoading) {
      return
    }
    this.listenRankLoading = true
    try {
      const response = await ApiClient.get<ListenRankResponse>('/listen/data/today/song',
        this.withTimestamp([], timestamp))
      if (response.code === 200 && response.data) {
        const rankItems: ListenRankItem[] = response.data.songDTOs || response.data.songPlayRank || []
        this.listenRankItems = rankItems
      }
    } catch (_error) {
    } finally {
      this.listenRankLoading = false
    }
  }

  private async loadRecentSongs(timestamp: string = ''): Promise<void> {
    if (!this.authStore.loggedIn || this.recentSongsLoading) {
      return
    }
    this.recentSongsLoading = true
    try {
      const response = await ApiClient.get<ListenRankResponse>('/listen/data/today/song',
        this.withTimestamp([], timestamp))
      if (response.code === 200 && response.data) {
        const songDTOs = response.data.songDTOs || []
        this.recentSongs = songDTOs.map((item: ListenRankItem): songItemType => {
          const artists = item.artists || []
          const mapped: songItemType = {
            id: (item.songId || 0).toString(),
            name: item.songName || '',
            author: artists.map((ar: ApiArtist) => ar.name).join(' / '),
            img: item.picUrl || '',
            url: '',
            duration: 0,
            album: '',
            fee: 0
          }
          return mapped
        })
      }
    } catch (_error) {
    } finally {
      this.recentSongsLoading = false
    }
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

  private threadIdOf(item: UserEventItem): string {
    return item.info.threadId || `A_EV_2_${item.id}_${item.user.userId}`
  }

  private async loadEventComments(item: UserEventItem): Promise<void> {
    this.selectedCommentType = 6
    this.selectedCommentResourceId = ''
    this.selectedCommentThreadId = this.threadIdOf(item)
    this.selectedCommentEventId = item.id
    this.commentTitle = '动态评论'
    this.commentInput = ''
    this.commentLoading = true
    this.commentSheetVisible = true
    try {
      const response = await ApiClient.get<EventCommentResponse>('/comment/event', [
        { key: 'threadId', value: this.selectedCommentThreadId },
        { key: 'limit', value: '30' }
      ])
      if (response.code === 200) {
        this.eventComments = (response.hotComments || []).concat(response.comments || [])
        this.commentTotal = response.total || 0
      }
    } catch (_error) {
      this.eventComments = []
    } finally {
      this.commentLoading = false
    }
  }

  private async loadSongComments(songId: string, songName: string): Promise<void> {
    this.selectedCommentType = 0
    this.selectedCommentResourceId = songId
    this.selectedCommentThreadId = ''
    this.selectedCommentEventId = 0
    this.commentTitle = `${songName} · 评论`
    this.commentInput = ''
    this.commentLoading = true
    this.commentSheetVisible = true
    try {
      const response = await ApiClient.get<CommentResponse>('/comment/music', [
        { key: 'id', value: songId },
        { key: 'limit', value: '30' }
      ])
      const source = (response.hotComments || []).concat(response.comments || [])
      this.eventComments = source.map((comment: CommentApiItem) => {
        const mapped: EventCommentItem = {
          commentId: comment.commentId,
          content: comment.content,
          time: 0,
          timeStr: comment.timeStr,
          likedCount: comment.likedCount,
          liked: comment.liked || false,
          user: {
            userId: 0,
            nickname: comment.user.nickname,
            avatarUrl: comment.user.avatarUrl,
            followed: false,
            mutual: false
          }
        }
        return mapped
      })
      this.commentTotal = response.total || this.eventComments.length
    } catch (_error) {
      this.eventComments = []
    } finally {
      this.commentLoading = false
    }
  }

  private async toggleCommentLike(comment: EventCommentItem): Promise<void> {
    const nextLiked = !(comment.liked || false)
    const params: ApiParam[] = [
      { key: 'type', value: this.selectedCommentType.toString() },
      { key: 'cid', value: comment.commentId.toString() },
      { key: 't', value: nextLiked ? '1' : '0' }
    ]
    if (this.selectedCommentType === 6) {
      params.push({ key: 'threadId', value: this.selectedCommentThreadId })
    } else {
      params.push({ key: 'id', value: this.selectedCommentResourceId })
    }
    try {
      const response = await ApiClient.get<OperationResponse>('/comment/like', params)
      if (response.code === 200) {
        comment.liked = nextLiked
        comment.likedCount = Math.max(0, comment.likedCount + (nextLiked ? 1 : -1))
        this.eventComments = this.eventComments.map((item: EventCommentItem) => item)
      }
    } catch (_error) {
    }
  }

  private async submitComment(): Promise<void> {
    const content = this.commentInput.trim()
    if (!content || this.commentSubmitting) {
      return
    }
    this.commentSubmitting = true
    const params: ApiParam[] = [
      { key: 't', value: '1' },
      { key: 'type', value: this.selectedCommentType.toString() },
      { key: 'content', value: content }
    ]
    if (this.selectedCommentType === 6) {
      params.push({ key: 'threadId', value: this.selectedCommentThreadId })
    } else {
      params.push({ key: 'id', value: this.selectedCommentResourceId })
    }
    try {
      const response = await ApiClient.get<OperationResponse>('/comment', params)
      if (response.code === 200) {
        this.commentInput = ''
        if (this.selectedCommentType === 6) {
          const event = this.userEvents.find((item: UserEventItem) => item.id === this.selectedCommentEventId)
          if (event) {
            event.info.commentCount = (event.info.commentCount || 0) + 1
            await this.loadEventComments(event)
          }
        } else {
          await this.loadSongComments(this.selectedCommentResourceId, this.commentTitle.replace(' · 评论', ''))
        }
      }
    } catch (_error) {
    } finally {
      this.commentSubmitting = false
    }
  }

  private async deleteEvent(evId: number): Promise<void> {
    try {
      const response = await ApiClient.get<OperationResponse>('/event/del', [
        { key: 'evId', value: evId.toString() }
      ])
      if (response.code === 200) {
        this.userEvents = this.userEvents.filter((item: UserEventItem) => item.id !== evId)
      }
    } catch (_error) {
    }
  }

  private async shareEvent(item: UserEventItem): Promise<void> {
    try {
      const response = await ApiClient.get<ShareResourceResponse>('/event/forward', [
        { key: 'evId', value: item.id.toString() },
        { key: 'uid', value: this.authStore.userId },
        { key: 'forwards', value: '转发动态' }
      ])
      if (response.code === 200) {
        item.info.shareCount = (item.info.shareCount || 0) + 1
        this.userEvents = this.userEvents.map((event: UserEventItem) => event)
        this.eventMessage = '动态已转发'
      }
    } catch (error) {
      this.eventMessage = error instanceof Error ? error.message : '动态转发失败'
    }
  }

  private async likeEvent(item: UserEventItem): Promise<void> {
    const nextLiked = !(item.info.liked || false)
    try {
      const response = await ApiClient.get<OperationResponse>('/resource/like', [
        { key: 'type', value: '6' },
        { key: 'threadId', value: this.threadIdOf(item) },
        { key: 't', value: nextLiked ? '1' : '0' }
      ])
      if (response.code === 200) {
        item.info.liked = nextLiked
        item.info.likedCount = Math.max(0, (item.info.likedCount || 0) + (nextLiked ? 1 : -1))
        this.userEvents = this.userEvents.map((event: UserEventItem) => event)
      }
    } catch (error) {
      this.eventMessage = error instanceof Error ? error.message : '动态点赞失败'
    }
  }

  private eventContent(item: UserEventItem): string {
    try {
      const data = JSON.parse(item.json) as EventJsonData
      return data.msg || data.title || '分享了一条动态'
    } catch (_error) {
      return '分享了一条动态'
    }
  }

  private eventPictureUrl(picture: EventPicture): string {
    const url = picture.rectangleUrl || picture.squareUrl || picture.pcSquareUrl || picture.originUrl || ''
    return resizeImageUrl(url, 520, 420)
  }

  private eventSong(item: UserEventItem): songItemType | null {
    try {
      const data = JSON.parse(item.json) as EventJsonData
      return data.song ? mapApiSong(data.song) : null
    } catch (_error) {
      return null
    }
  }

  private async playEventSong(item: UserEventItem): Promise<void> {
    const song = this.eventSong(item)
    if (!song) {
      return
    }
    const queue = this.playerStore.queue.map((queueSong: songItemType) => queueSong)
    let index = queue.findIndex((queueSong: songItemType) => queueSong.id === song.id)
    if (index < 0) {
      queue.push(song)
      index = queue.length - 1
    }
    await playerController.setQueue(queue, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private async toggleEventSongLike(item: UserEventItem): Promise<void> {
    const song = this.eventSong(item)
    if (!song) {
      return
    }
    const songId = Number(song.id)
    const nextLiked = !this.likedSongIds.includes(songId)
    try {
      const response = await ApiClient.get<OperationResponse>('/like', [
        { key: 'id', value: song.id },
        { key: 'like', value: nextLiked.toString() }
      ])
      if (response.code === 200) {
        if (nextLiked) {
          this.likedSongIds.push(songId)
        } else {
          this.likedSongIds = this.likedSongIds.filter((id: number) => id !== songId)
        }
      }
    } catch (_error) {
    }
  }

  private openEventDetail(item: UserEventItem): void {
    const param: EventDetailPageParam = { event: item, canDelete: true }
    this.pageStack.pushPathByName('EventDetailPage', param)
  }

  private forwardEvent(item: UserEventItem): EventForwardData | null {
    try {
      const data = JSON.parse(item.json) as EventJsonData
      return data.event || null
    } catch (_error) {
      return null
    }
  }

  private forwardContent(forward: EventForwardData): string {
    try {
      const data = JSON.parse(forward.json || '') as EventJsonData
      return data.msg || data.title || forward.actName || '源动态'
    } catch (_error) {
      return forward.actName || '源动态'
    }
  }

  private forwardEventItem(forward: EventForwardData): UserEventItem {
    return {
      id: forward.id || 0,
      type: forward.type,
      eventTime: forward.eventTime,
      showTime: forward.showTime,
      json: forward.json || '',
      user: forward.user || { userId: 0, nickname: '', avatarUrl: '', followed: false, mutual: false },
      info: forward.info || { commentCount: 0, likedCount: 0, shareCount: 0 },
      pics: forward.pics,
      actName: forward.actName
    }
  }

  @Builder
  private ForwardEventCard(forward: EventForwardData) {
    Column({ space: 7 }) {
      Row({ space: 7 }) {
        Image(resizeImageUrl(forward.user?.avatarUrl || '', 64, 64))
          .width(24).height(24).borderRadius(12).objectFit(ImageFit.Cover)
        Text(forward.user?.nickname || '源动态作者').fontSize(12).fontColor('#ededf0').maxLines(1)
      }
      .width('100%')
      Text(this.forwardContent(forward)).width('100%').fontSize(12).lineHeight(18).fontColor('#9999a1')
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      if ((forward.pics || []).length > 0) {
        Image(this.eventPictureUrl((forward.pics || [])[0]))
          .width('100%').height(120).borderRadius(9).objectFit(ImageFit.Cover)
      }
    }
    .width('100%').padding(10).backgroundColor('#202026').borderRadius(11)
    .onClick(() => this.openEventDetail(this.forwardEventItem(forward)))
  }

  private formatEventTime(timestamp: number): string {
    if (!timestamp) {
      return ''
    }
    const date = new Date(timestamp)
    const now = new Date()
    const diff = now.getTime() - date.getTime()
    if (diff < 60000) {
      return '刚刚'
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)}分钟前`
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)}小时前`
    }
    return `${date.getMonth() + 1}月${date.getDate()}日`
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
    .bindSheet(this.commentSheetVisible, this.CommentSheetContent(), {
      height: '60%',
      backgroundColor: '#19191f',
      showClose: false,
      dragBar: false,
      onDisappear: () => this.commentSheetVisible = false
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
      .padding({ top: 32, bottom: 16 })

      if (this.authStore.loggedIn) {
        Stack() {
          SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(19).fontColor(['#ffffff'])
        }
        .width(40).height(40).borderRadius(14).backgroundColor('rgba(20,20,25,0.55)')
        .position({ right: 18, top: 28 }).onClick(() => this.openProfileEditor())
      }
    }
    .width('100%')
    .height(220)
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
    .backgroundColor('#121215')
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
        this.RecentPlaySection()
        this.ListenRankSection()
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
  LikedSongsSection() {
    Column() {
      Row({ space: 8 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.heart_fill'))
            .fontSize(22)
            .fontColor(['#c0392b'])
        }
        .width(56)
        .height(56)
        .borderRadius(8)
        .backgroundColor('#2a2a2a')
        .alignContent(Alignment.Center)

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

  @Builder
  RecentPlaySection() {
    Column() {
      Row() {
        Text('最近播放')
          .fontSize(14)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
        Text('今天')
          .fontSize(11)
          .fontColor('#77777f')
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 6 })

      if (this.recentSongsLoading) {
        LoadingProgress().width(42).color('#ef233c').margin({ top: 20, bottom: 20 })
      } else if (this.recentSongs.length === 0) {
        Text('暂无最近播放')
          .fontSize(12)
          .fontColor('#77777f')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 16, bottom: 16 })
      } else {
        Column() {
          ForEach(this.recentSongs.slice(0, 10), (item: songItemType, index: number) => {
            Row({ space: 12 }) {
              Text(`${(index as number) + 1}`)
                .fontSize(14)
                .fontColor((index as number) < 3 ? '#c0392b' : '#66666e')
                .fontWeight((index as number) < 3 ? FontWeight.Bold : FontWeight.Regular)
                .width(24)
                .textAlign(TextAlign.Center)

              if (item.img) {
                Image(item.img).width(42).height(42).borderRadius(8).objectFit(ImageFit.Cover)
                  .onClick(() => {
                    const queue = this.playerStore.queue.map((s: songItemType) => s)
                    let pos = queue.findIndex((s: songItemType) => s.id === item.id)
                    if (pos < 0) {
                      queue.push(item)
                      pos = queue.length - 1
                    }
                    playerController.setQueue(queue, pos, true)
                    this.pageStack.pushPathByName('PlayPage', null)
                  })
              } else {
                Stack() {
                  SymbolGlyph($r('sys.symbol.music')).fontSize(20).fontColor(['#55555d'])
                }
                .width(42).height(42).borderRadius(8).backgroundColor('#25252c')
              }

              Column({ space: 3 }) {
                Text(item.name)
                  .fontSize(13)
                  .fontColor('#ededf0')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.author)
                  .fontSize(11)
                  .fontColor('#77777f')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .height(56)
            .padding({ left: 12, right: 16 })
          })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  ListenRankSection() {
    Column() {
      Row() {
        Text('听歌排行')
          .fontSize(14)
          .fontColor('#ffffff')
          .fontWeight(FontWeight.Medium)
        Text('近1个月')
          .fontSize(11)
          .fontColor('#77777f')
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 6 })

      if (this.listenRankLoading) {
        LoadingProgress().width(42).color('#ef233c').margin({ top: 20, bottom: 20 })
      } else if (this.listenRankItems.length === 0) {
        Text('暂无听歌排行数据')
          .fontSize(12)
          .fontColor('#77777f')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 16, bottom: 16 })
      } else {
        Column() {
          ForEach(this.listenRankItems.slice(0, 10), (item: ListenRankItem, index: number) => {
            Row({ space: 12 }) {
              Text(`${(index as number) + 1}`)
                .fontSize(14)
                .fontColor((index as number) < 3 ? '#c0392b' : '#66666e')
                .fontWeight((index as number) < 3 ? FontWeight.Bold : FontWeight.Regular)
                .width(24)
                .textAlign(TextAlign.Center)

              Column({ space: 3 }) {
                Text(item.songName || item.song?.songName || item.song?.name || '')
                  .fontSize(13)
                  .fontColor('#ededf0')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.artists?.map((ar: ApiArtist) => ar.name).join(' / ') ||
                  item.song?.artists?.map((ar: ApiArtist) => ar.name).join(' / ') ||
                  item.song?.ar?.map((ar: ApiArtist) => ar.name).join(' / ') || '')
                  .fontSize(11)
                  .fontColor('#77777f')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (item.playCount) {
                Text(`${item.playCount}次`)
                  .fontSize(10)
                  .fontColor('#55555d')
              }
            }
            .width('100%')
            .height(52)
            .padding({ left: 12, right: 16 })
          })
        }
        .width('100%')
      }
    }
    .width('100%')
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

      ForEach(this.createdPlaylists.slice(0, 4), (item: playlistType) => {
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
          Image(item.cover)
            .width(56)
            .height(56)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)

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
              Image(item.cover)
                .width('100%')
                .aspectRatio(1)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)

              if (item.isLiked) {
                SymbolGlyph($r('sys.symbol.heart_fill'))
                  .fontSize(14)
                  .fontColor(['#c0392b'])
                  .position({ right: 6, top: 6 })
              }
            }
            .width('100%')

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
          .width('100%').height(72).padding({ left: 16, right: 16 })
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
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Image(item.user.avatarUrl).width(32).height(32).borderRadius(16).objectFit(ImageFit.Cover)
              Text(item.user.nickname).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#ffffff')
              Text(this.formatEventTime(item.showTime || item.eventTime || 0))
                .fontSize(10).fontColor('#66666e')
            }
            .width('100%')
            .onClick(() => this.openEventDetail(item))
            Text(this.eventContent(item)).width('100%').fontSize(13).lineHeight(20).fontColor('#b5b5bc')
              .onClick(() => this.openEventDetail(item))
            if (this.forwardEvent(item)) {
              this.ForwardEventCard(this.forwardEvent(item)!)
            }
            if ((item.pics || []).length > 0) {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(item.pics || [], (picture: EventPicture) => {
                    Image(this.eventPictureUrl(picture))
                      .width((item.pics || []).length === 1 ? 260 : 116)
                      .height((item.pics || []).length === 1 ? 210 : 116)
                      .sourceSize({ width: 520, height: 420 })
                      .borderRadius(12).objectFit(ImageFit.Cover)
                      .onClick(() => this.openEventDetail(item))
                  })
                }
              }
              .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            }
            if (this.eventSong(item)) {
              Row({ space: 10 }) {
                Image(this.eventSong(item)?.img || '')
                  .width(54).height(54).borderRadius(10).objectFit(ImageFit.Cover)
                  .onClick(() => this.playEventSong(item))
                Column({ space: 4 }) {
                  Text(this.eventSong(item)?.name || '').fontSize(13).fontColor('#ededf0').maxLines(1)
                  Text(this.eventSong(item)?.author || '').fontSize(10).fontColor('#77777f').maxLines(1)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph(this.likedSongIds.includes(Number(this.eventSong(item)?.id || '0')) ?
                  $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(20)
                  .fontColor([this.likedSongIds.includes(Number(this.eventSong(item)?.id || '0')) ? '#ef233c' : '#77777f'])
                  .onClick(() => this.toggleEventSongLike(item))
                SymbolGlyph($r('sys.symbol.ellipsis_bubble'))
                  .fontSize(20).fontColor(['#77777f'])
                  .onClick(() => this.loadSongComments(this.eventSong(item)?.id || '',
                    this.eventSong(item)?.name || '歌曲'))
                SymbolGlyph($r('sys.symbol.play_circle_fill'))
                  .fontSize(23).fontColor(['#ffffff'])
                  .onClick(() => this.playEventSong(item))
              }
              .width('100%').padding(10).backgroundColor('#25252b').borderRadius(12)
            }
            Row({ space: 24 }) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.arrow_right_up_and_square')).fontSize(16).fontColor(['#77777f'])
                Text(`${item.info.shareCount || 0}`).fontSize(10).fontColor('#77777f')
              }.onClick(() => this.shareEvent(item))
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(16).fontColor(['#77777f'])
                Text(`${item.info.commentCount || 0}`).fontSize(10).fontColor('#77777f')
              }.onClick(() => this.loadEventComments(item))
              Row({ space: 4 }) {
                SymbolGlyph(item.info.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(16).fontColor([item.info.liked ? '#ef233c' : '#77777f'])
                Text(`${item.info.likedCount || 0}`).fontSize(10)
                  .fontColor(item.info.liked ? '#ef233c' : '#77777f')
              }.onClick(() => this.likeEvent(item))
              SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor(['#55555d'])
                .onClick(() => this.deleteEvent(item.id))
            }
            .width('100%')
          }
          .width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(16)
          .margin({ bottom: 8 })
        })
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

  @Builder
  CommentSheetContent() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text(`${this.commentTitle} · ${this.commentTotal}`).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text('可以发布评论，点击红心可点赞或取消点赞').fontSize(10).fontColor('#77777f')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor(['#686870'])
          .onClick(() => this.commentSheetVisible = false)
      }
      .height(66).padding({ left: 20, right: 20 })
      if (this.commentLoading) {
        LoadingProgress().layoutWeight(1).width(42).color('#ef233c')
      } else if (this.eventComments.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(38).fontColor(['#55555d'])
          Text('暂无评论').fontSize(12).fontColor('#77777f')
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 14 }) {
          ForEach(this.eventComments, (item: EventCommentItem) => {
            ListItem() {
              Row({ space: 10 }) {
                Image(item.user.avatarUrl).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover)
                Column({ space: 6 }) {
                  Row() {
                    Text(item.user.nickname).layoutWeight(1).fontSize(12).fontColor('#a9a9b0')
                    Row({ space: 4 }) {
                      SymbolGlyph(item.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                        .fontSize(14).fontColor([item.liked ? '#ef233c' : '#77777f'])
                      Text(`${item.likedCount}`).fontSize(10).fontColor(item.liked ? '#ef233c' : '#77777f')
                    }
                    .onClick(() => this.toggleCommentLike(item))
                  }
                  Text(item.content).fontSize(13).lineHeight(20).fontColor('#ededf0')
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .padding({ left: 18, right: 18 })
            }
          })
        }
        .layoutWeight(1)
      }
      Row({ space: 10 }) {
        TextInput({ text: this.commentInput, placeholder: '写下你的评论…' })
          .layoutWeight(1).height(42).fontSize(13).fontColor('#ffffff')
          .placeholderColor('#66666e').backgroundColor('#25252b').borderRadius(18)
          .onChange((value: string) => this.commentInput = value)
          .onSubmit(() => this.submitComment())
        Button(this.commentSubmitting ? '发送中' : '发送')
          .height(40).fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
          .borderRadius(18).enabled(!this.commentSubmitting && this.commentInput.trim().length > 0)
          .onClick(() => this.submitComment())
      }
      .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 12 })
    }
    .width('100%').height('100%')
  }

  navigateToPlaylist(playlist: playlistType) {
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
