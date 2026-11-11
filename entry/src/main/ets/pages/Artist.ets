import {
  AlbumPageParam,
  ApiAlbum,
  ApiArtist,
  ArtistAlbumResponse,
  ArtistDetailArtist,
  ArtistDetailResponse,
  ArtistExpertIdentity,
  ArtistFollowCountResponse,
  ArtistMvItem,
  ArtistMvResponse,
  ArtistPageParam,
  ArtistSongsPageParam,
  ArtistTopSongsResponse,
  MvPlayerPageParam,
  SharePageParam,
  SimilarArtistResponse,
  UserEventItem,
  UserEventResponse,
  mapApiSong
} from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'
import { EventPresentation } from '../services/EventPresentation'
import { EventUpdates } from '../services/EventUpdates'
import { TC } from '../services/ThemeColors'
import { DetailTopBar } from '../components/DetailTopBar'
import { ShareSheet } from '../components/ShareSheet'
import { EventCard } from '../components/EventCard'
import { NoMoreFooter } from '../components/NoMoreFooter'
import { RelationshipPageParam } from './RelationshipList'
import { ImagePreviewPageParam } from './ImagePreviewPage'

@Component
export struct ArtistPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: ArtistPageParam = { id: '' }

  @State artist: ApiArtist = { name: '' }
  @State artistDetail: ArtistDetailArtist = { name: '' }
  @State expertIdentities: ArtistExpertIdentity[] = []
  @State topSongs: songItemType[] = []
  @State topSongsExpanded: boolean = false
  @State albums: ApiAlbum[] = []
  @State allAlbums: ApiAlbum[] = []
  @State mvs: ArtistMvItem[] = []
  @State similarArtists: ApiArtist[] = []
  @State loading: boolean = true
  @State message: string = ''
  @State bioExpanded: boolean = false
  @State currentTab: string = 'music'
  @State allAlbumsLoading: boolean = false
  @State allAlbumsMore: boolean = true
  private allAlbumsOffset: number = 0
  // 认证信息、粉丝数、绑定用户与动态
  @State verified: boolean = false
  @State verifyIcon: string = ''
  @State artistUid: string = ''
  @State fansCount: number = 0
  @State events: UserEventItem[] = []
  @State eventsMore: boolean = true
  @State eventsLoading: boolean = false
  private eventsLastTime: number = -1
  @State shareSheetVisible: boolean = false
  @State scrollOffset: number = 0
  private scroller: Scroller = new Scroller()
  private stopEventUpdates?: () => void

  private watchEventUpdates(): void {
    this.stopEventUpdates?.()
    this.stopEventUpdates = EventUpdates.subscribe((item: UserEventItem, deleted: boolean) => {
      this.events = EventPresentation.changeList(this.events, item, deleted)
    })
  }

  aboutToDisappear(): void {
    this.stopEventUpdates?.()
  }

  private shareParam(): SharePageParam {
    return {
      type: 'artist',
      id: this.pageParam.id,
      name: this.displayName(),
      img: this.headerImage(),
      author: `${this.totalSongs()} 首歌曲`
    }
  }

  /** 全部歌曲总数：优先用详情里的 musicSize。 */
  private totalSongs(): number {
    return this.artistDetail.musicSize || this.artist.musicSize || this.topSongs.length
  }

  private openAllSongs(): void {
    const param: ArtistSongsPageParam = {
      id: this.pageParam.id,
      name: this.displayName(),
      total: this.totalSongs(),
      cover: this.headerImage()
    }
    this.pageStack.pushPathByName('ArtistSongsPage', param)
  }

  private openFans(): void {
    const param: RelationshipPageParam = {
      type: 'artistFans',
      title: `${this.displayName()} 的粉丝`,
      uid: this.pageParam.id
    }
    this.pageStack.pushPathByName('FollowersPage', param)
  }

  aboutToAppear(): void {
    this.watchEventUpdates()
    this.artist = {
      id: Number(this.pageParam.id),
      name: this.pageParam.name || '',
      picUrl: this.pageParam.picUrl || ''
    }
    this.artistDetail = {
      id: Number(this.pageParam.id),
      name: this.pageParam.name || '',
      avatar: this.pageParam.picUrl || ''
    }
    this.loadArtist()
  }

  private async loadArtist(): Promise<void> {
    if (!this.pageParam.id) {
      this.loading = false
      this.message = '歌手参数无效'
      return
    }
    this.loading = true
    this.message = ''
    await Promise.all([
      this.loadSongs(),
      this.loadAlbums(),
      this.loadMvs(),
      this.loadArtistDetail(),
      this.loadSimilarArtists(),
      this.loadFollowCount()
    ])
    if (!this.hasContent()) {
      this.message = '暂时没有可展示的歌手内容'
    }
    this.loading = false
  }

  private async loadSongs(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistTopSongsResponse>('/artist/top/song', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200) {
        this.topSongs = (response.songs || []).slice(0, 50).map((song) => mapApiSong(song))
      }
    } catch (error) {
      console.error(`[ArtistPage] load songs failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async loadAlbums(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistAlbumResponse>('/artist/album', [
        { key: 'id', value: this.pageParam.id },
        { key: 'limit', value: '5' },
        { key: 'offset', value: '0' }
      ])
      if (response.code === 200) {
        if (response.artist) {
          this.artist = response.artist
        }
        this.albums = (response.hotAlbums || []).slice(0, 5)
      }
    } catch (error) {
      console.error(`[ArtistPage] load albums failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async loadAllAlbums(reset: boolean = false): Promise<void> {
    if (this.allAlbumsLoading || (!this.allAlbumsMore && !reset)) {
      return
    }
    if (reset) {
      this.allAlbums = []
      this.allAlbumsOffset = 0
      this.allAlbumsMore = true
    }
    this.allAlbumsLoading = true
    try {
      const response = await ApiClient.get<ArtistAlbumResponse>('/artist/album', [
        { key: 'id', value: this.pageParam.id },
        { key: 'limit', value: '30' },
        { key: 'offset', value: this.allAlbumsOffset.toString() }
      ])
      if (response.code === 200) {
        const incoming = response.hotAlbums || []
        const merged = this.allAlbums.slice()
        incoming.forEach((album: ApiAlbum) => {
          if (!merged.some((item: ApiAlbum) => item.id === album.id)) {
            merged.push(album)
          }
        })
        this.allAlbums = merged
        this.allAlbumsOffset += incoming.length
        this.allAlbumsMore = response.more === true || (response.more === undefined && incoming.length >= 30)
      }
    } catch (error) {
      console.error(`[ArtistPage] load all albums failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    } finally {
      this.allAlbumsLoading = false
    }
  }

  private switchTab(tab: string): void {
    this.currentTab = tab
    if (tab === 'albums' && this.allAlbums.length === 0) {
      this.loadAllAlbums(true)
    }
    if (tab === 'events' && this.events.length === 0) {
      this.loadArtistEvents(true)
    }
  }

  /** /artist/follow/count：歌手粉丝数。 */
  private async loadFollowCount(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistFollowCountResponse>('/artist/follow/count', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200 && response.data) {
        this.fansCount = response.data.fansCnt || 0
      }
    } catch (error) {
      console.error(`[ArtistPage] load fans count failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  /** 歌手绑定的官方用户动态：/user/event，按 lasttime 分页。 */
  private async loadArtistEvents(reset: boolean = false): Promise<void> {
    if (this.eventsLoading || !this.artistUid || (!this.eventsMore && !reset)) {
      return
    }
    if (reset) {
      this.events = []
      this.eventsLastTime = -1
      this.eventsMore = true
    }
    this.eventsLoading = true
    try {
      const response = await ApiClient.get<UserEventResponse>('/user/event', [
        { key: 'uid', value: this.artistUid },
        { key: 'limit', value: '20' },
        { key: 'lasttime', value: this.eventsLastTime.toString() }
      ])
      if (response.code === 200) {
        this.events = this.events.concat(response.events || [])
        if (response.lasttime) {
          this.eventsLastTime = response.lasttime
        }
        this.eventsMore = response.more === true
      }
    } catch (error) {
      console.error(`[ArtistPage] load events failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    } finally {
      this.eventsLoading = false
    }
  }

  private applyEventChange(item: UserEventItem, deleted: boolean): void {
    EventUpdates.publish(item, deleted)
  }

  private async loadMvs(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistMvResponse>('/artist/mv', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200) {
        this.mvs = response.mvs || []
      }
    } catch (error) {
      console.error(`[ArtistPage] load mvs failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async loadArtistDetail(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistDetailResponse>('/artist/detail', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200 && response.data) {
        if (response.data.artist) {
          this.artistDetail = response.data.artist
        }
        this.expertIdentities = response.data.secondaryExpertIdentiy || []
        const boundUser = response.data.user
        if (boundUser && boundUser.userId) {
          this.artistUid = boundUser.userId.toString()
        }
        // 圆形认证标：优先用官方身份图，其次用「入驻艺人」标签判定
        const icon = response.data.identify?.imageUrl || boundUser?.avatarDetail?.identityIconUrl || ''
        this.verifyIcon = icon
        this.verified = (boundUser?.authenticated === true) || icon.length > 0 ||
          (this.artistDetail.identifyTag || []).length > 0
        if (this.currentTab === 'events') {
          this.loadArtistEvents(true)
        }
      }
    } catch (error) {
      console.error(`[ArtistPage] load detail failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async loadSimilarArtists(): Promise<void> {
    try {
      const response = await ApiClient.get<SimilarArtistResponse>('/simi/artist', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200) {
        this.similarArtists = response.artists || []
      }
    } catch (error) {
      console.error(`[ArtistPage] load similar artists failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private hasContent(): boolean {
    return this.topSongs.length > 0 || this.albums.length > 0 || this.mvs.length > 0 ||
      this.hasWikiContent() || this.similarArtists.length > 0
  }

  private hasWikiContent(): boolean {
    return (this.artistDetail.briefDesc || '').length > 0 ||
      (this.artistDetail.identities || []).length > 0 || this.expertIdentities.length > 0
  }

  private async playSong(index: number): Promise<void> {
    if (this.topSongs.length === 0) {
      return
    }
    await playerController.setQueue(this.topSongs, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  /** 译名/别名，用于相似歌手卡片里的浅色括号。 */
  private artistAlias(artist: ApiArtist): string {
    const trans = artist.transNames || []
    const names = trans.length > 0 ? trans : (artist.alias || [])
    return names.length > 0 ? names[0] : ''
  }

  private albumYear(album: ApiAlbum): string {
    if (!album.publishTime) {
      return ''
    }
    return new Date(album.publishTime).getFullYear().toString()
  }

  private displayName(): string {
    return this.artistDetail.name || this.artist.name || this.pageParam.name || '歌手'
  }

  /** 歌手专属横版封面（artist/detail 的 cover），头图优先用它。 */
  private headerImage(): string {
    return this.artistDetail.cover || this.artist.cover || this.pageParam.picUrl ||
      this.artistDetail.avatar || this.artist.picUrl || this.artist.img1v1Url || ''
  }

  /** 圆形头像用 avatar，与横版 cover 分开。 */
  private avatarImage(): string {
    return this.artistDetail.avatar || this.artist.picUrl || this.artist.img1v1Url ||
      this.pageParam.picUrl || this.headerImage()
  }

  private formatCount(count: number | undefined): string {
    const value = count || 0
    if (value >= 100000000) {
      return `${(value / 100000000).toFixed(1)}亿`
    }
    if (value >= 10000) {
      return `${(value / 10000).toFixed(1)}万`
    }
    return value.toString()
  }

  private formatDuration(duration: number | undefined): string {
    const totalSeconds = Math.floor((duration || 0) / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`
  }

  private openAlbum(album: ApiAlbum): void {
    if (!album.id) {
      return
    }
    const param: AlbumPageParam = {
      id: album.id.toString(),
      name: album.name,
      picUrl: album.picUrl,
      artist: this.displayName()
    }
    this.pageStack.pushPathByName('AlbumDetailPage', param)
  }

  private openArtist(artist: ApiArtist): void {
    if (!artist.id) {
      return
    }
    const param: ArtistPageParam = {
      id: artist.id.toString(),
      name: artist.name,
      picUrl: artist.picUrl || artist.img1v1Url || ''
    }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  private openMv(mv: ArtistMvItem): void {
    const param: MvPlayerPageParam = {
      id: mv.id.toString(),
      name: mv.name,
      cover: mv.imgurl16v9 || mv.imgurl || '',
      artistName: mv.artistName || this.displayName(),
      duration: mv.duration,
      playCount: mv.playCount,
      publishTime: mv.publishTime
    }
    this.pageStack.pushPathByName('MvPlayerPage', param)
  }

  /** 头像点开：与专辑封面同款的全屏预览 + 保存。 */
  private openAvatarPreview(): void {
    const url = this.avatarImage()
    if (url.length === 0) {
      return
    }
    const param: ImagePreviewPageParam = { url: url, name: this.displayName() }
    this.pageStack.pushPathByName('ImagePreviewPage', param)
  }

  @Builder
  private ArtistHeader() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image(resizeImageUrl(this.headerImage(), 720, 560))
        .width('100%').height('100%').sourceSize({ width: 720, height: 560 })
        .objectFit(ImageFit.Cover).blur(32).opacity(0.55)
      Column().width('100%').height('100%')
        .linearGradient({ angle: 180, colors: [[TC.headerScrimTop(), 0], [TC.pageBackground(), 1]] })
      Column({ space: 9 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Image(resizeImageUrl(this.avatarImage(), 220, 220))
            .width(104).height(104).sourceSize({ width: 220, height: 220 })
            .borderRadius(52).objectFit(ImageFit.Cover)
            .border({ width: 2, color: 'rgba(255,255,255,0.78)' })
            .onClick(() => this.openAvatarPreview())
          if (this.verified && this.verifyIcon) {
            Image(this.verifyIcon).width(22).height(22).borderRadius(11)
              .objectFit(ImageFit.Cover).border({ width: 1.5, color: '#FFFFFF' })
          }
        }
        .width(104).height(104)
        Row({ space: 7 }) {
          Text(this.displayName())
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          if (this.verified) {
            if (this.verifyIcon) {
              Image(this.verifyIcon).width(20).height(20).borderRadius(10).objectFit(ImageFit.Cover)
            } else {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(20).fontColor([TC.accent()])
            }
          }
          Text('歌手').fontSize(9).fontColor(TC.accentSoft())
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .border({ width: 1, color: TC.accentSoft() }).borderRadius(5)
        }
        Text(`${this.artistDetail.musicSize || this.artist.musicSize || this.topSongs.length} 首单曲 · ${this.artistDetail.albumSize || this.artist.albumSize || this.albums.length} 张专辑 · ${this.artistDetail.mvSize || this.mvs.length} 个 MV`)
          .fontSize(11).fontColor(TC.textBody())
        // 粉丝数：点击进粉丝列表
        Row({ space: 4 }) {
          Text(this.formatCount(this.fansCount)).fontSize(13).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary())
          Text('粉丝').fontSize(11).fontColor(TC.textBody())
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([TC.textBody()])
        }
        .padding({ left: 12, right: 10, top: 5, bottom: 5 })
        .borderRadius(14).backgroundColor('rgba(255,255,255,0.18)')
        .onClick(() => this.openFans())
        if ((this.artistDetail.alias || []).length > 0) {
          Text((this.artistDetail.alias || []).join(' / ')).width('82%').fontSize(11).fontColor(TC.textSecondary())
            .maxLines(1).textAlign(TextAlign.Center)
        }
      }
      .width('100%').padding({ bottom: 18 })
    }
    .width('100%').height(280 + this.topAvoidHeight + 54)
  }

  @Builder
  private SongsTab() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([TC.textPrimary()])
        Text(`播放热门歌曲 (${this.topSongs.length})`).fontSize(14).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
      }
      .width('100%').height(50).padding({ left: 18 })
      .onClick(() => this.playSong(0))
      ForEach(this.topSongsExpanded ? this.topSongs : this.topSongs.slice(0, 5), (song: songItemType, index: number) => {
        Row({ space: 12 }) {
          Text((index + 1).toString()).width(28).fontSize(12)
            .fontColor(index < 3 ? TC.accentSoft() : TC.textTertiary()).textAlign(TextAlign.Center)
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text(song.name).fontSize(14).fontColor(TC.textBody()).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              if (song.fee === 1) {
                Text('VIP').fontSize(8).fontColor(TC.accentSoft())
                  .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                  .border({ width: 1, color: TC.accentSoft() }).borderRadius(3)
              }
            }
            Text(song.album || song.author).fontSize(11).fontColor(TC.textTertiary()).maxLines(1)
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.play_circle')).fontSize(21).fontColor([TC.textTertiary()])
        }
        .height(62).padding({ left: 12, right: 16 }).onClick(() => this.playSong(index))
      }, (song: songItemType) => song.id)
      if (this.topSongs.length > 5) {
        Text(this.topSongsExpanded ? '收起' : `展开更多 ${this.topSongs.length} 首`)
          .width('100%').constraintSize({ minHeight: 40 })
          .fontSize(13).fontColor(TC.textSecondary()).textAlign(TextAlign.Center)
          .onClick(() => this.topSongsExpanded = !this.topSongsExpanded)
      }
      Row({ space: 6 }) {
        Text(`全部 ${this.totalSongs()} 曲`).fontSize(12).fontColor(TC.accent())
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([TC.accent()])
      }
      .height(34).padding({ left: 16, right: 12 })
      .borderRadius(17).backgroundColor(TC.accentContainer())
      .margin({ top: 2, bottom: 12 })
      .onClick(() => this.openAllSongs())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private AlbumsTab() {
    Column({ space: 12 }) {
      if (this.allAlbums.length === 0 && this.allAlbumsLoading) {
        LoadingProgress().width(38).height(38).color(TC.accent()).margin({ top: 80 })
      } else if (this.allAlbums.length === 0) {
        Text('暂无专辑').width('100%').height(180).fontSize(13).fontColor(TC.textTertiary())
          .textAlign(TextAlign.Center)
      }
      ForEach(this.allAlbums, (album: ApiAlbum) => {
        Row({ space: 13 }) {
          Image(resizeImageUrl(album.picUrl, 160, 160)).width(72).height(72)
            .sourceSize({ width: 160, height: 160 }).borderRadius(13).objectFit(ImageFit.Cover)
          Column({ space: 6 }) {
            Text(album.name).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor(TC.textBody()).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text([this.albumYear(album), album.type || '', album.size ? `${album.size} 首` : '']
              .filter((value: string) => value.length > 0).join(' · '))
              .fontSize(11).fontColor(TC.textTertiary())
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        .width('100%').padding({ left: 16, right: 16 })
        .onClick(() => this.openAlbum(album))
      })
      if (this.allAlbums.length > 0) {
        Row() {
          if (this.allAlbumsLoading) {
            LoadingProgress().width(24).height(24).color(TC.accent())
          } else {
            Text(this.allAlbumsMore ? '继续上滑加载更多' : '已经到底了').fontSize(11).fontColor(TC.textQuaternary())
          }
        }.width('100%').height(56).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').padding({ top: 14, bottom: 30 })
  }

  /** 歌手绑定的官方用户动态（与其他用户主页的「动态」二级页同款）。 */
  @Builder
  private EventsTab() {
    Column({ space: 12 }) {
      if (this.events.length === 0 && this.eventsLoading) {
        LoadingProgress().width(38).height(38).color(TC.accent()).margin({ top: 80 })
      } else if (this.events.length === 0) {
        Text(this.artistUid ? '暂无动态' : '该歌手暂未绑定官方账号')
          .width('100%').height(180).fontSize(13).fontColor(TC.textTertiary())
          .textAlign(TextAlign.Center)
      }
      ForEach(this.events, (item: UserEventItem) => {
        EventCard({
          item: item,
          onChanged: (event: UserEventItem, deleted: boolean) => this.applyEventChange(event, deleted)
        })
      }, (item: UserEventItem) => item.id.toString())
      if (this.events.length > 0) {
        Row() {
          if (this.eventsLoading) {
            LoadingProgress().width(24).height(24).color(TC.accent())
          } else {
            Text(this.eventsMore ? '继续上滑加载更多' : '已经到底了')
              .fontSize(11).fontColor(TC.textQuaternary())
          }
        }.width('100%').height(56).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 30 })
  }

  @Builder
  private SectionHeader(title: string, subtitle: string = '') {
    Row() {
      Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(TC.textBody())
      Blank()
      if (subtitle.length > 0) {
        Text(subtitle).fontSize(11).fontColor(TC.textTertiary())
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 22, bottom: 13 })
  }

  @Builder
  private ArtistNavigation() {
    Row() {
      ForEach(['music', 'albums', 'events'], (tab: string) => {
        Column({ space: 8 }) {
          Text(tab === 'music' ? '音乐' : tab === 'albums' ? '全部专辑' : '动态').fontSize(15)
            .fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.currentTab === tab ? TC.textPrimary() : TC.textTertiary())
          Column().width(this.currentTab === tab ? 28 : 0).height(3).borderRadius(2)
            .backgroundColor(TC.accent())
        }
        .layoutWeight(1).height(52).justifyContent(FlexAlign.Center)
        .onClick(() => this.switchTab(tab))
      }, (tab: string) => tab)
    }
    .width('100%')
  }

  @Builder
  private HotAlbumsSection() {
    Column() {
      this.SectionHeader('热门专辑', `${this.albums.length} 张`)
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.albums, (album: ApiAlbum) => {
            Column({ space: 7 }) {
              Image(resizeImageUrl(album.picUrl, 280, 280)).width(132).height(132)
                .sourceSize({ width: 280, height: 280 }).borderRadius(14).objectFit(ImageFit.Cover)
              Text(album.name).width(132).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(TC.textBody()).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.albumYear(album)).width(132).fontSize(10).fontColor(TC.textTertiary())
            }
            .alignItems(HorizontalAlign.Start).onClick(() => this.openAlbum(album))
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
    .width('100%')
  }

  @Builder
  private HotMvsSection() {
    Column() {
      this.SectionHeader('热门 MV', `${this.mvs.length} 个`)
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.mvs, (mv: ArtistMvItem) => {
            Column({ space: 7 }) {
              Stack({ alignContent: Alignment.BottomEnd }) {
                Image(resizeImageUrl(mv.imgurl16v9 || mv.imgurl || '', 480, 270)).width(218).height(123)
                  .sourceSize({ width: 480, height: 270 }).borderRadius(13).objectFit(ImageFit.Cover)
                Text(this.formatDuration(mv.duration)).fontSize(9).fontColor(TC.textPrimary())
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .margin({ right: 7, bottom: 7 }).borderRadius(5).backgroundColor('rgba(0,0,0,0.58)')
              }
              Text(mv.name).width(218).fontSize(13).fontColor(TC.textBody()).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 10 }) {
                Text(`${this.formatCount(mv.playCount)} 次播放`).fontSize(10).fontColor(TC.textTertiary())
                if (mv.publishTime) {
                  Text(mv.publishTime).fontSize(10).fontColor(TC.textTertiary())
                }
              }
            }
            .alignItems(HorizontalAlign.Start).onClick(() => this.openMv(mv))
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
    .width('100%')
  }

  @Builder
  private ArtistWikiSection() {
    Column() {
      this.SectionHeader('歌手百科')
      Column({ space: 13 }) {
        if ((this.artistDetail.identities || []).length > 0) {
          Text((this.artistDetail.identities || []).join(' · ')).width('100%')
            .fontSize(12).fontColor(TC.accentSoft())
        }
        if (this.expertIdentities.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.expertIdentities, (identity: ArtistExpertIdentity) => {
              Text(`${identity.expertIdentiyName}${identity.expertIdentiyCount ? ` ${identity.expertIdentiyCount}` : ''}`)
                .fontSize(10).fontColor(TC.textBody())
                .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                .margin({ right: 7, bottom: 7 }).borderRadius(12).backgroundColor(TC.surfaceInset())
            })
          }
          .width('100%')
        }
        Text(this.artistDetail.briefDesc || '').width('100%').fontSize(13).fontColor(TC.textBody())
          .lineHeight(22).maxLines(this.bioExpanded ? 100 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 收起态高度固定为 3 行（22×3），不随文字多少变化
          .constraintSize({ minHeight: this.bioExpanded ? 0 : 66 })
        if ((this.artistDetail.briefDesc || '').length > 75) {
          Text(this.bioExpanded ? '收起' : '展开全部').fontSize(12).fontColor(TC.accentSoft())
            .onClick(() => this.bioExpanded = !this.bioExpanded)
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 16, bottom: 17 })
      .borderRadius(17).backgroundColor(TC.surfaceCard())
    }
    .width('100%').padding({ left: 12, right: 12 })
  }

  @Builder
  private SimilarArtistsSection() {
    Column() {
      this.SectionHeader('相似歌手')
      Scroll() {
        Row({ space: 17 }) {
          ForEach(this.similarArtists, (artist: ApiArtist) => {
            Column({ space: 8 }) {
              Image(resizeImageUrl(artist.picUrl || artist.img1v1Url || artist.cover || '', 180, 180))
                .width(82).height(82)
                .sourceSize({ width: 180, height: 180 }).borderRadius(41).objectFit(ImageFit.Cover)
              Text() {
                Span(artist.name)
                Span(this.artistAlias(artist) ? `(${this.artistAlias(artist)})` : '')
                  .fontColor(TC.textQuaternary())
              }
              .width(110).fontSize(12).fontColor(TC.textBody()).maxLines(1)
              .textAlign(TextAlign.Center).textOverflow({ overflow: TextOverflow.Ellipsis })
              if ((artist.fansCount || artist.fansSize || 0) > 0) {
                Text(`${this.formatCount(artist.fansCount || artist.fansSize)} 粉丝`)
                  .fontSize(9).fontColor(TC.textTertiary())
              }
            }
            .onClick(() => this.openArtist(artist))
          }, (artist: ApiArtist) => `${artist.id}_${artist.name}`)
        }
        .padding({ left: 16, right: 16 })
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
    .width('100%').padding({ bottom: 34 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
          Scroll(this.scroller) {
            Column() {
              this.ArtistHeader()
              if (this.loading) {
                LoadingProgress().width(46).height(46).color(TC.accent()).margin({ top: 36 })
              } else {
              this.ArtistNavigation()
              if (this.currentTab === 'music') {
                if (this.topSongs.length > 0) {
                  this.SectionHeader('热门歌曲', `${this.topSongs.length} 首`)
                  this.SongsTab()
                }
                if (this.albums.length > 0) {
                  this.HotAlbumsSection()
                }
                if (this.mvs.length > 0) {
                  this.HotMvsSection()
                }
                if (this.hasWikiContent()) {
                  this.ArtistWikiSection()
                }
                if (this.similarArtists.length > 0) {
                  this.SimilarArtistsSection()
                }
                if (!this.hasContent()) {
                  Text(this.message).width('100%').height(180).fontSize(13).fontColor(TC.textTertiary())
                    .textAlign(TextAlign.Center)
                }
              } else if (this.currentTab === 'albums') {
                this.AlbumsTab()
              } else {
                this.EventsTab()
              }
              NoMoreFooter()
              }
            }
            .width('100%').constraintSize({ minHeight: '100%' })
          }
          .width('100%').height('100%').scrollBar(BarState.Off)
          .onDidScroll(() => {
            const y = this.scroller.currentOffset().yOffset
            // 顶栏只用到 0~160 这段做渐显，钳住后长列表滚动时不再逐帧刷新页面
            const barOffset = y > 170 ? 170 : y
            if (barOffset !== this.scrollOffset) {
              this.scrollOffset = barOffset
            }
          })
          .onReachEnd(() => {
            if (this.currentTab === 'albums') {
              this.loadAllAlbums()
            } else if (this.currentTab === 'events') {
              this.loadArtistEvents()
            }
          })

        DetailTopBar({
          title: this.displayName(),
          scrollOffset: this.scrollOffset,
          onShare: () => this.shareSheetVisible = true
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
