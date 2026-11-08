import { EventUpdates } from '../services/EventUpdates'
import { EventPresentation } from '../services/EventPresentation'
import { EventCard } from '../components/EventCard'
import { ListeningPlaylistService } from '../services/ListeningPlaylistService'
import { ListeningPlaylistCard } from '../components/ListeningPlaylistCard'
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
  SharePageParam,
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
import { TC } from '../services/ThemeColors'
import { DetailTopBar } from '../components/DetailTopBar'
import { ShareSheet } from '../components/ShareSheet'

@Component
export struct UserProfilePage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
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
  @State shareSheetVisible: boolean = false
  @State scrollOffset: number = 0
  private scroller: Scroller = new Scroller()

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

  /** 统一走 ShareSheet（与专辑/歌单/歌手一致：系统分享 + 私信 + 碰一碰）。 */
  private shareUserProfile(): void {
    if (!this.pageParam.uid) {
      return
    }
    this.shareSheetVisible = true
  }

  private shareParam(): SharePageParam {
    return {
      type: 'user',
      id: this.pageParam.uid,
      name: this.detail?.profile.nickname || '用户',
      img: this.detail?.profile.avatarUrl || '',
      author: this.detail?.profile.signature || ''
    }
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
          .backgroundColor(TC.surfaceCardAlt())
      }
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 180, colors: [[TC.headerScrimTop(), 0], [TC.pageBackground(), 1]] })
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
            .fontSize(21).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          if (this.detail?.profile.userType === 4) {
            Text('歌手').fontSize(10).fontColor(TC.accentSoft())
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor(TC.accentContainer()).borderRadius(8)
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
            .fontSize(12).fontColor(TC.textBody()).maxLines(2).textAlign(TextAlign.Center).width('82%')
        }

        Row({ space: 8 }) {
          if (this.detail?.profile.gender === 1) {
            Image($r('app.media.ic_boy')).width(14).height(14).objectFit(ImageFit.Contain).fillColor('#26a6e4')
          } else if (this.detail?.profile.gender === 2) {
            Image($r('app.media.ic_girl')).width(14).height(14).objectFit(ImageFit.Contain).fillColor('#ffb5d3')
          }
          if (this.detail?.profile.birthday && this.detail.profile.birthday > 0) {
            Text(this.formatBirthday(this.detail.profile.birthday))
              .fontSize(11).fontColor(TC.textBody())
          }
          if (this.detail?.profile.province && this.detail.profile.province > 0) {
            Text(this.formatLocation(this.detail.profile.province, this.detail.profile.city || 0))
              .fontSize(11).fontColor(TC.textBody())
          }
        }
        .margin({ top: 2 })
        if (this.pageParam.uid !== this.authStore.userId) {
          Row({ space: 10 }) {
            Button(this.followButtonText())
              .width(112).height(36).fontSize(12)
              .fontColor(this.isFollowActive() ? TC.accent() : TC.textOnAccent())
              .backgroundColor(this.isFollowActive() ? '#00ffffff' : TC.accent())
              .border({ width: this.isFollowActive() ? 1 : 0, color: TC.accent() })
              .borderRadius(18).onClick(() => this.follow())
            Button('私聊')
              .height(36).fontSize(12)
              .fontColor(TC.textPrimary()).backgroundColor(TC.surfaceRaised())
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
        .width('100%').fontSize(13).fontColor(TC.textSecondary())
      ForEach(this.playlists.slice(0, 3), (item: playlistType) => {
        Row({ space: 12 }) {
          Image(item.cover).width(54).height(54).borderRadius(12).objectFit(ImageFit.Cover)
          Column({ space: 4 }) {
            Text(item.name).fontSize(14).fontColor(TC.textBody()).maxLines(1)
            Text(`${item.count} 首 · ${item.creator}`).fontSize(11).fontColor(TC.textTertiary())
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([TC.textQuaternary()])
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
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
      Row({ space: 12 }) {
        Button('暂不取消').layoutWeight(1).backgroundColor(TC.surfaceRaised())
          .onClick(() => this.cancelSheetVisible = false)
        Button('取消关注').layoutWeight(1).fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
          .onClick(() => this.cancelFollow())
      }
    }
    .width('100%').padding(24)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          if (this.loading) {
            LoadingProgress().layoutWeight(1).width(46).color(TC.accent())
          } else if (!this.detail) {
            Column({ space: 12 }) {
              Text(this.message || '无法加载用户主页').fontSize(13).fontColor(TC.textTertiary())
            }
            .layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            Scroll(this.scroller) {
              Column() {
                this.Header()
                Row() {
                  Row({ space: 4 }) {
                    Text(`${this.detail?.profile.follows || 0}`).fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor(TC.textPrimary())
                    Text('关注').fontSize(12).fontColor(TC.textTertiary())
                  }.onClick(() => this.openRelation('following', '关注'))

                  Divider().vertical(true).height(16).color(TC.textQuaternary()).margin({ left: 12, right: 12 })

                  Row({ space: 4 }) {
                    Text(`${this.detail?.profile.followeds || 0}`).fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor(TC.textPrimary())
                    Text('粉丝').fontSize(12).fontColor(TC.textTertiary())
                  }.onClick(() => this.openRelation('followers', '粉丝'))

                  Divider().vertical(true).height(16).color(TC.textQuaternary()).margin({ left: 12, right: 12 })

                  Text(`Lv.${this.detail?.level || 0}`).fontSize(16).fontWeight(FontWeight.Bold)
                    .fontColor(TC.textPrimary())

                  Divider().vertical(true).height(16).color(TC.textQuaternary()).margin({ left: 12, right: 12 })

                  Row({ space: 4 }) {
                    Text(`${this.detail?.listenSongs || 0}`).fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor(TC.textPrimary())
                    Text('首').fontSize(12).fontColor(TC.textTertiary())
                  }
                }
                .height(52).width('100%').justifyContent(FlexAlign.Center)

                Row() {
                  ForEach(['home', 'playlists', 'events'], (tab: string) => {
                    Column({ space: 8 }) {
                      Text(tab === 'home' ? '主页' : tab === 'playlists' ? '歌单' : '动态')
                        .fontSize(15)
                        .fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Regular)
                        .fontColor(this.currentTab === tab ? TC.textPrimary() : TC.textTertiary())
                      Column().width(this.currentTab === tab ? 28 : 0).height(3).borderRadius(2)
                        .backgroundColor(TC.accent())
                    }
                    .layoutWeight(1).height(52).justifyContent(FlexAlign.Center)
                    .onClick(() => this.currentTab = tab)
                  }, (tab: string) => tab)
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
                          Text(item.name).fontSize(14).fontColor(TC.textBody()).maxLines(1)
                          Text(`${item.count} 首`).fontSize(11).fontColor(TC.textTertiary())
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
            .onDidScroll(() => { this.scrollOffset = this.scroller.currentOffset().yOffset })
          }
        }
        .width('100%').height('100%')
        .bindSheet(this.cancelSheetVisible, this.CancelSheet(), {
          height: '30%',
          backgroundColor: TC.sheetBackground(),
          showClose: false,
          dragBar: false,
          onDisappear: () => this.cancelSheetVisible = false
        })
        DetailTopBar({
          title: this.detail?.profile.nickname || '用户主页',
          scrollOffset: this.scrollOffset,
          onShare: () => this.shareUserProfile()
        })
        if (this.shareSheetVisible) {
          ShareSheet({
            shareParam: this.shareParam(),
            visible: this.shareSheetVisible,
            onClose: () => this.shareSheetVisible = false
          })
        }
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }
    .hideTitleBar(true)
  }
}
