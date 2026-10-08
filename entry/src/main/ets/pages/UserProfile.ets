import { EventUpdates } from '../services/EventUpdates'
import { EventPresentation } from '../services/EventPresentation'
import { EventCard } from '../components/EventCard'
import { common } from '@kit.AbilityKit'
import { ListeningPlaylistService } from '../services/ListeningPlaylistService'
import { ListeningPlaylistCard } from '../components/ListeningPlaylistCard'
import { SystemShareService, NearbyShareSession, ShareLink } from '../services/SystemShareService'
import {
  ArtistPageParam,
  EventDetailPageParam,
  EventForwardData,
  EventJsonData,
  EventPicture,
  mapApiSong,
  mapPlaylist,
  MsgPrivateHistoryResponse,
  MutualFollowResponse,
  OperationResponse,
  PrivateChatPageParam,
  PrivateMsgContent,
  SendMsgResponse,
  UserDetailResponse,
  UserEventItem,
  UserEventResponse,
  UserFollowedsResponse,
  UserFollowsResponse,
  UserPlaylistResponse,
  UserProfilePageParam,
  VipInfoResponse
} from '../models/api'
import { playlistType, songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { parseVipInfo } from '../services/VipService'
import { resizeImageUrl } from '../services/ImageUrl'
import { AuthStore } from '../stores/AuthStore'
import { RelationshipPageParam } from './RelationshipList'
import { BubbleTip } from '../services/BubbleTip'

@Component
export struct UserProfilePage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: UserProfilePageParam = { uid: '' }

  @State detail?: UserDetailResponse = undefined
  @State playlists: playlistType[] = []
  @State recordSongs: songItemType[] = []
  @State recordLoading: boolean = true
  @State recordPreviewType: 0 | 1 = 1
  @State recordError: string = ''
  @State events: UserEventItem[] = []
  @State currentTab: string = 'home'
  @State loading: boolean = true
  @State message: string = ''
  @State cancelSheetVisible: boolean = false
  @State vipActive: boolean = false
  @State vipSvip: boolean = false
  @State vipLevel: number = 0
  @State followsTarget: boolean = false
  @State followedByTarget: boolean = false
  @State moreMenuVisible: boolean = false

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

  aboutToAppear(): void {
    this.watchEventUpdates()
    this.applyRelationHint()
    this.loadProfile()
    this.loadRecord()
  }

  private rankingPlaylist(): playlistType {
    return ListeningPlaylistService.playlist('record', this.pageParam.uid,
      this.detail?.profile.nickname || '', this.recordSongs, this.recordPreviewType)
  }

  private async loadRecord(): Promise<void> {
    const uid = this.pageParam.uid
    this.recordSongs = []
    this.recordError = ''
    this.recordLoading = true
    try {
      let songs = await ListeningPlaylistService.record(uid, 1)
      const type: 0 | 1 = songs.length === 0 ? 0 : 1
      if (type === 0) { songs = await ListeningPlaylistService.record(uid, 0) }
      if (uid === this.pageParam.uid) { this.recordSongs = songs; this.recordPreviewType = type }
    } catch (error) {
      if (uid === this.pageParam.uid) {
        this.recordSongs = []
        this.recordError = error instanceof Error ? error.message : '听歌排行暂不可用'
      }
    } finally { this.recordLoading = false }
  }

  private hasRelationHint(): boolean {
    return this.pageParam.followsTarget !== undefined && this.pageParam.followedByTarget !== undefined
  }

  private applyRelationHint(): void {
    if (!this.hasRelationHint()) {
      return
    }
    this.followsTarget = this.pageParam.followsTarget || false
    this.followedByTarget = this.pageParam.followedByTarget || false
  }

  private async loadProfile(): Promise<void> {
    try {
      const detail = await ApiClient.get<UserDetailResponse>('/user/detail', [
        { key: 'uid', value: this.pageParam.uid }
      ])
      this.detail = detail
      if (this.hasRelationHint()) {
        this.applyRelationHint()
      } else {
        this.followsTarget = false
        this.followedByTarget = false
      }
      await this.loadVipInfo()
      await this.loadRelationState()
      const playlistResponse = await ApiClient.get<UserPlaylistResponse>('/user/playlist', [
        { key: 'uid', value: this.pageParam.uid },
        { key: 'limit', value: '50' },
        { key: 'offset', value: '0' }
      ])
      this.playlists = (playlistResponse.playlist || []).map((item) => mapPlaylist(item))
      const eventResponse = await ApiClient.get<UserEventResponse>('/user/event', [
        { key: 'uid', value: this.pageParam.uid },
        { key: 'limit', value: '20' },
        { key: 'lasttime', value: '-1' },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      this.events = eventResponse.events || []
    } catch (error) {
      this.message = error instanceof Error ? error.message : '用户主页加载失败'
    } finally {
      this.loading = false
    }
  }

  private async loadVipInfo(): Promise<void> {
    if (!this.pageParam.uid) {
      return
    }
    try {
      const response = await ApiClient.get<VipInfoResponse>('/vip/info', [
        { key: 'uid', value: this.pageParam.uid }
      ])
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

  private async loadRelationState(): Promise<void> {
    if (!this.detail || !this.authStore.loggedIn || this.pageParam.uid === this.authStore.userId) {
      return
    }
    if (this.hasRelationHint()) {
      this.applyRelationHint()
      this.syncRelationDetail()
      return
    }
    this.followsTarget = false
    this.followedByTarget = false
    try {
      const response = await ApiClient.get<MutualFollowResponse>('/user/mutualfollow/get', [
        { key: 'uid', value: this.pageParam.uid }
      ])
      const mutual = response.data === true || response.mutual === true ||
        (typeof response.data !== 'boolean' && response.data?.mutual === true)
      if (mutual) {
        this.followsTarget = true
        this.followedByTarget = true
        this.syncRelationDetail()
        return
      }

      if (await this.ownFollowersContainTarget()) {
        this.followedByTarget = true
        this.syncRelationDetail()
        return
      }

      if (await this.ownFollowsContainTarget()) {
        this.followsTarget = true
      }
      this.syncRelationDetail()
    } catch (_error) {
      this.syncRelationDetail()
    }
  }

  private async ownFollowersContainTarget(): Promise<boolean> {
    const limit = 100
    let offset = 0
    let more = true
    while (more) {
      const response = await ApiClient.get<UserFollowedsResponse>('/user/followeds', [
        { key: 'uid', value: this.authStore.userId },
        { key: 'limit', value: limit.toString() },
        { key: 'offset', value: offset.toString() }
      ])
      if (response.code !== 200) {
        return false
      }
      const users = response.followeds || []
      if (users.some((user) => user.userId.toString() === this.pageParam.uid)) {
        return true
      }
      if (users.length === 0) {
        return false
      }
      offset += users.length
      more = response.more || false
    }
    return false
  }

  private async ownFollowsContainTarget(): Promise<boolean> {
    const limit = 100
    let offset = 0
    let more = true
    while (more) {
      const response = await ApiClient.get<UserFollowsResponse>('/user/follows', [
        { key: 'uid', value: this.authStore.userId },
        { key: 'limit', value: limit.toString() },
        { key: 'offset', value: offset.toString() }
      ])
      if (response.code !== 200) {
        return false
      }
      const users = response.follow || []
      if (users.some((user) => user.userId.toString() === this.pageParam.uid)) {
        return true
      }
      if (users.length === 0) {
        return false
      }
      offset += users.length
      more = response.more || false
    }
    return false
  }

  private syncRelationDetail(): void {
    if (!this.detail) {
      return
    }
    this.detail.profile.followed = this.followsTarget
    this.detail.profile.mutual = this.followsTarget && this.followedByTarget
    this.detail = this.detail
  }

  private stopEventUpdates?: () => void

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
    this.events = EventPresentation.changeList(this.events, item, deleted)
  }

  private openRelation(type: string, title: string): void {
    const param: RelationshipPageParam = { type: type, title: title, uid: this.pageParam.uid }
    this.pageStack.pushPathByName(type === 'following' ? 'FollowingPage' : 'FollowersPage', param)
  }

  private followButtonText(): string {
    if (this.followsTarget && this.followedByTarget) {
      return '互相关注'
    }
    if (this.followsTarget) {
      return '已关注'
    }
    if (this.followedByTarget) {
      return '回关'
    }
    return '关注'
  }

  private isFollowActive(): boolean {
    return this.followsTarget
  }

  private async follow(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    if (this.followsTarget) {
      this.cancelSheetVisible = true
      return
    }
    try {
      const response = await ApiClient.get<OperationResponse>('/follow', [
        { key: 'id', value: this.pageParam.uid },
        { key: 't', value: '1' }
      ])
      if (response.code === 200 && this.detail) {
        this.followsTarget = true
        this.detail.profile.followed = true
        this.detail.profile.mutual = this.followedByTarget
        this.detail = this.detail
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '关注失败'
    }
  }

  private async cancelFollow(): Promise<void> {
    try {
      const response = await ApiClient.get<OperationResponse>('/follow', [
        { key: 'id', value: this.pageParam.uid },
        { key: 't', value: '0' }
      ])
      if (response.code === 200 && this.detail) {
        this.followsTarget = false
        this.detail.profile.followed = false
        this.detail.profile.mutual = false
        this.detail = this.detail
        this.cancelSheetVisible = false
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '取消关注失败'
    }
  }

  private openChat(): void {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const param: PrivateChatPageParam = {
      uid: this.pageParam.uid,
      nickname: this.detail?.profile.nickname || '',
      avatarUrl: this.detail?.profile.avatarUrl || ''
    }
    this.pageStack.pushPathByName('PrivateChatPage', param)
  }

  private openArtist(): void {
    const artistId = this.detail?.profile.artistId || 0
    if (artistId <= 0) {
      return
    }
    const param: ArtistPageParam = {
      id: artistId.toString(),
      name: this.detail?.profile.nickname || '',
      picUrl: this.detail?.profile.avatarUrl || ''
    }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  private isOtherUser(): boolean {
    return !!this.pageParam.uid && this.pageParam.uid !== this.authStore.userId
  }

  private async shareUserProfile(): Promise<void> {
    this.moreMenuVisible = false
    if (!this.pageParam.uid) {
      return
    }
    try {
      await SystemShareService.showLink(this.getUIContext().getHostContext() as common.UIAbilityContext,
        this.profileShareLink())
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '无法打开系统分享面板')
    }
  }

  private nearbyShare: NearbyShareSession = new NearbyShareSession()

  private profileShareLink(): ShareLink {
    return { url: `https://music.163.com/user/home?id=${encodeURIComponent(this.pageParam.uid)}`,
      title: this.detail?.profile.nickname || '用户', description: this.detail?.profile.signature || '分享用户主页',
      label: '用户', image: this.detail?.profile.avatarUrl }
  }

  @Builder
  private MoreMenuOption() {
    Row({ space: 13 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.share')).fontSize(21).fontColor(['#ededf0'])
      }.width(42).height(42).borderRadius(13).backgroundColor('#29292f')
      Column({ space: 3 }) {
        Text('分享').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#ededf0')
        Text('将这个用户主页分享给朋友').fontSize(10).fontColor('#77777f')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor(['#55555d'])
    }.width('100%').height(64).onClick(() => this.shareUserProfile())
  }

  @Builder
  private MoreMenuOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.58)')
        .onClick(() => this.moreMenuVisible = false)
      Column({ space: 4 }) {
        Row() {
          Column({ space: 3 }) {
            Text('更多操作').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            Text(this.detail?.profile.nickname || '').fontSize(10).fontColor('#77777f').maxLines(1)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(25).fontColor(['#686870'])
            .onClick(() => this.moreMenuVisible = false)
        }.width('100%').height(54)
        this.MoreMenuOption()
      }
      .width('100%').height(174).padding({ left: 20, right: 20, top: 10, bottom: 24 })
      .backgroundColor('#19191f').borderRadius({ topLeft: 28, topRight: 28 })
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.42)', offsetY: -4 })
      .transition(TransitionEffect.translate({ y: 260 }).animation({ duration: 240, curve: Curve.EaseOut }))
    }.width('100%').height('100%')
  }

  @Builder
  private Header() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.detail?.profile.avatarUrl) {
        Image(this.detail.profile.avatarUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(32)
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
        .linearGradient({ angle: 180, colors: [['rgba(10,10,14,0.12)', 0], ['#121215', 1]] })
      Column({ space: 10 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Image(resizeImageUrl(this.detail?.profile.avatarUrl || '', 180, 180))
            .width(88).height(88).sourceSize({ width: 180, height: 180 }).borderRadius(90).objectFit(ImageFit.Cover)
            .border({ width: 2, color: 'rgba(255,255,255,0.8)' })
          if (this.detail?.profile.userType === 4) {
            Image($r('app.media.ic_singer')).width(26).height(26).borderRadius(13)
          }
        }
        .width(88).height(88)
        Row({ space: 7 }) {
          Text(this.detail?.profile.nickname || '')
            .fontSize(21).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          if (this.detail?.profile.userType === 4) {
            Text('歌手').fontSize(10).fontColor('#ff6577')
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor('#2b2024').borderRadius(8)
          }
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
            .backgroundColor(this.vipSvip ? '#ff342a2a' : '#ff372c2c')
            .borderRadius(16)
          }
        }
        .onClick(() => this.openArtist())
        if (this.detail?.profile.signature) {
          Text(this.detail.profile.signature)
            .fontSize(12).fontColor('#aaaab2').maxLines(2).textAlign(TextAlign.Center).width('82%')
        }

        Row({ space: 8 }) {
          if (this.detail?.profile.gender === 1) {
            Image($r('app.media.ic_boy')).width(14).height(14).objectFit(ImageFit.Contain).fillColor('#26a6e4')
          } else if (this.detail?.profile.gender === 2) {
            Image($r('app.media.ic_girl')).width(14).height(14).objectFit(ImageFit.Contain).fillColor('#ffb5d3')
          }
          if (this.detail?.profile.birthday && this.detail.profile.birthday > 0) {
            Text(this.formatBirthday(this.detail.profile.birthday))
              .fontSize(11).fontColor('#999999')
          }
          if (this.detail?.profile.province && this.detail.profile.province > 0) {
            Text(this.formatLocation(this.detail.profile.province, this.detail.profile.city || 0))
              .fontSize(11).fontColor('#999999')
          }
        }
        .margin({ top: 2 })
        if (this.pageParam.uid !== this.authStore.userId) {
          Row({ space: 10 }) {
            Button(this.followButtonText())
              .width(112).height(36).fontSize(12)
              .fontColor(this.isFollowActive() ? '#ef233c' : '#ffffff')
              .backgroundColor(this.isFollowActive() ? '#00ffffff' : '#ef233c')
              .border({ width: this.isFollowActive() ? 1 : 0, color: '#ef233c' })
              .borderRadius(18).onClick(() => this.follow())
            Button('私聊')
              .height(36).fontSize(12)
              .fontColor($r('sys.color.white')).backgroundColor('#2a2a30')
              .borderRadius(18).onClick(() => this.openChat())
          }
        }
      }
      .width('100%').padding({ bottom: 18 })
    }
    .width('100%').height(280 + this.topAvoidHeight + 54)
  }

  @Builder
  private HomeTab() {
    Column({ space: 14 }) {
      if (this.recordSongs.length > 0 && !this.recordError) {
      ListeningPlaylistCard({
        playlist: this.rankingPlaylist(), loading: this.recordLoading, message: this.recordError,
        onOpen: () => this.pageStack.pushPathByName('PlaylistDetailPage', this.rankingPlaylist())
      })
      }
      Text(`共公开 ${this.playlists.length} 个歌单`)
        .width('100%').fontSize(13).fontColor('#92929a')
      ForEach(this.playlists.slice(0, 3), (item: playlistType) => {
        Row({ space: 12 }) {
          Image(item.cover).width(54).height(54).borderRadius(12).objectFit(ImageFit.Cover)
          Column({ space: 4 }) {
            Text(item.name).fontSize(14).fontColor('#ededf0').maxLines(1)
            Text(`${item.count} 首 · ${item.creator}`).fontSize(11).fontColor('#77777f')
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor(['#66666e'])
        }
        .height(68).onClick(() => this.pageStack.pushPathByName('PlaylistDetailPage', item))
      })
    }
    .padding({ left: 16, right: 16, top: 14, bottom: 28 })
  }

  @Builder
  private CancelSheet() {
    Column({ space: 18 }) {
      Text(`确定取消关注「${this.detail?.profile.nickname || ''}」吗？`)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
      Row({ space: 12 }) {
        Button('暂不取消').layoutWeight(1).backgroundColor('#2a2a30')
          .onClick(() => this.cancelSheetVisible = false)
        Button('取消关注').layoutWeight(1).backgroundColor('#ef233c')
          .onClick(() => this.cancelFollow())
      }
    }
    .width('100%').padding(24)
  }

  @Builder
  private ProfileNavigation() {
    Column() {
      Column().width('100%').height(this.topAvoidHeight)
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24).fontColor(['#ffffff']).width(44).height(44).onClick(() => this.pageStack.pop())
        Text('用户主页').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
          .fontColor('#ffffff').textAlign(TextAlign.Center)
        SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(22).fontColor(['#ffffff'])
          .width(44).height(44)
          .visibility(this.isOtherUser() ? Visibility.Visible : Visibility.Hidden)
          .onClick(() => this.moreMenuVisible = true)
      }
      .height(54).width('100%').padding({ left: 6, right: 6 })
    }
    .width('100%')
    .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0.5)', 0], ['rgba(0,0,0,0)', 1]] })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          if (this.loading) {
            LoadingProgress().layoutWeight(1).width(46).color('#ef233c')
          } else if (!this.detail) {
            Column({ space: 12 }) {
              Text(this.message || '无法加载用户主页').fontSize(13).fontColor('#77777f')
            }
            .layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column() {
                this.Header()
                Row() {
                  Row({ space: 4 }) {
                    Text(`${this.detail?.profile.follows || 0}`).fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor('#ffffff')
                    Text('关注').fontSize(12).fontColor('#888888')
                  }.onClick(() => this.openRelation('following', '关注'))

                  Divider().vertical(true).height(16).color('#333333').margin({ left: 12, right: 12 })

                  Row({ space: 4 }) {
                    Text(`${this.detail?.profile.followeds || 0}`).fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor('#ffffff')
                    Text('粉丝').fontSize(12).fontColor('#888888')
                  }.onClick(() => this.openRelation('followers', '粉丝'))

                  Divider().vertical(true).height(16).color('#333333').margin({ left: 12, right: 12 })

                  Text(`Lv.${this.detail?.level || 0}`).fontSize(16).fontWeight(FontWeight.Bold)
                    .fontColor('#ffffff')

                  Divider().vertical(true).height(16).color('#333333').margin({ left: 12, right: 12 })

                  Row({ space: 4 }) {
                    Text(`${this.detail?.listenSongs || 0}`).fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor('#ffffff')
                    Text('首').fontSize(12).fontColor('#888888')
                  }
                }
                .height(52).width('100%').justifyContent(FlexAlign.Center)

                Row() {
                  ForEach(['home', 'playlists', 'events'], (tab: string) => {
                    Text(tab === 'home' ? '主页' : tab === 'playlists' ? '歌单' : '动态')
                      .layoutWeight(1).height(44).fontSize(14)
                      .fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Regular)
                      .fontColor(this.currentTab === tab ? '#ffffff' : '#66666e')
                      .textAlign(TextAlign.Center).onClick(() => this.currentTab = tab)
                  })
                }
                .width('100%')

                if (this.currentTab === 'home') {
                  this.HomeTab()
                } else if (this.currentTab === 'playlists') {
                  Column() {
                    ForEach(this.playlists, (item: playlistType) => {
                      Row({ space: 12 }) {
                        Image(item.cover).width(58).height(58).borderRadius(12).objectFit(ImageFit.Cover)
                        Column({ space: 5 }) {
                          Text(item.name).fontSize(14).fontColor('#ededf0').maxLines(1)
                          Text(`${item.count} 首`).fontSize(11).fontColor('#77777f')
                        }
                        .layoutWeight(1).alignItems(HorizontalAlign.Start)
                      }
                      .height(72).padding({ left: 16, right: 16 })
                      .onClick(() => this.pageStack.pushPathByName('PlaylistDetailPage', item))
                    })
                  }
                } else {
                  Column({ space: 12 }) {
                    ForEach(this.events, (item: UserEventItem) => {
                      EventCard({ item: item,
                        onChanged: (event: UserEventItem, deleted: boolean) => this.applyEventChange(event, deleted) })
                    }, (item: UserEventItem) => item.id.toString())
                  }
                  .padding({ left: 16, right: 16, bottom: 28 })
                }
              }
            }
            .layoutWeight(1).scrollBar(BarState.Off)
          }
        }
        .width('100%').height('100%')
        .bindSheet(this.cancelSheetVisible, this.CancelSheet(), {
          height: '30%',
          backgroundColor: '#19191f',
          showClose: false,
          dragBar: false,
          onDisappear: () => this.cancelSheetVisible = false
        })
        this.ProfileNavigation()
        if (this.moreMenuVisible) {
          this.MoreMenuOverlay()
        }
      }
      .width('100%').height('100%').backgroundColor('#121215')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }
    .hideTitleBar(true)
    .onShown(() => this.nearbyShare.activate(() => SystemShareService.linkRecords(this.profileShareLink())))
    .onHidden(() => this.nearbyShare.deactivate())
  }
}
