import { common } from '@kit.AbilityKit'
import { SharePageParam } from '../models/api'
import { ProgramItem } from '../models/home'
import { PodcastStation, PodcastStationPage, PodcastVoicesParam } from '../models/podcast'
import { RadioPageParam } from '../models/radio'
import { AuthStore } from '../stores/AuthStore'
import { PodcastService } from '../services/PodcastService'
import { RadioService } from '../services/RadioService'
import { RadioPlayback } from '../services/RadioPlayback'
import { VoiceUploadParam } from '../services/VoiceUploadService'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'
import { ShareSheet } from './ShareSheet'

/**
 * 我的 - 播客（也用于独立的播客库页面）。
 *
 * 三个居中的分类：全部（订阅 + 创建 + 近期收听）/ 播客（全部订阅）/ 创建。
 * 不再自己画刷新按钮：宿主页面的下拉刷新会把 refreshKey 推进来。
 */
@Component
export struct PodcastLibrary {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @StorageProp(PodcastService.REVISION_KEY) @Watch('onRevision') revision: number = 0
  @Consume('authStore') @Watch('onAuthChanged') authStore: AuthStore
  @Consume('pageStack') pageStack: NavPathStack
  @Prop initialSection: string = 'all'
  @Prop @Watch('refresh') refreshKey: number = 0
  /** 宿主页提供的分享入口：把分享面板放在页面根 Stack 上，避免模态被列表菜单吞掉。 */
  onShareRequest?: (param: SharePageParam) => void
  @State tab: string = 'all'
  @State subscribed: PodcastStation[] = []
  @State created: PodcastStation[] = []
  @State recent: PodcastStation[] = []
  @State loading: boolean = false
  @State loadingMore: boolean = false
  @State more: boolean = false
  @State message: string = ''
  @State changing: string = ''
  @State playing: string = ''
  @State sharing: boolean = false
  @State shareParam: SharePageParam = { type: 'djradio', id: '', name: '', img: '' }
  private requestId: number = 0
  private owner: string = ''
  private alive: boolean = true
  private loaded: boolean = false
  private subOffset: number = 0
  private readonly tabs: string[] = ['all', 'podcast', 'created']

  aboutToAppear(): void {
    this.alive = true
    this.tab = this.normalizeSection(this.initialSection)
    this.onAuthChanged()
  }

  aboutToDisappear(): void { this.alive = false; this.requestId++ }

  private normalizeSection(section: string): string {
    if (section === 'created') { return 'created' }
    if (section === 'subscribed' || section === 'podcast') { return 'podcast' }
    return 'all'
  }

  private tabTitle(tab: string): string {
    return tab === 'podcast' ? '播客' : tab === 'created' ? '创建' : '全部'
  }

  private onAuthChanged(): void {
    const owner = this.authStore.loggedIn ? this.authStore.userId : ''
    if (owner === this.owner && (this.subscribed.length > 0 || this.created.length > 0 || this.recent.length > 0)) {
      return
    }
    this.owner = owner
    this.refresh()
  }

  private onRevision(): void { this.refresh() }

  private refresh(): void {
    this.requestId++
    this.subscribed = []
    this.created = []
    this.recent = []
    this.subOffset = 0
    this.more = false
    this.loading = false
    this.loadingMore = false
    this.loaded = false
    this.message = ''
    if (this.alive && this.authStore.loggedIn) { this.loadAll() }
  }

  private switchTab(tab: string): void {
    if (tab === this.tab) { return }
    this.tab = tab
    if (!this.loaded && !this.loading) { this.loadAll() }
  }

  private async loadAll(): Promise<void> {
    if (!this.alive || !this.authStore.loggedIn) { return }
    const request = ++this.requestId
    const owner = this.authStore.userId
    this.loading = true
    this.message = ''
    let failure = ''
    let subPage: PodcastStationPage = { items: [], more: false }
    let createdPage: PodcastStationPage = { items: [], more: false }
    let recentPage: PodcastStationPage = { items: [], more: false }
    try {
      try { subPage = await PodcastService.subscribed(0) }
      catch (error) { failure = error instanceof Error ? error.message : '订阅播客加载失败' }
      try { createdPage = await PodcastService.created() }
      catch (error) { failure = failure || (error instanceof Error ? error.message : '我创建的播客加载失败') }
      try { recentPage = await PodcastService.recent() }
      catch (error) { failure = failure || (error instanceof Error ? error.message : '最近收听播客加载失败') }
      if (!this.alive || request !== this.requestId || owner !== this.authStore.userId) { return }
      this.subscribed = subPage.items
      this.subOffset = subPage.items.length
      this.more = subPage.more
      this.created = createdPage.items
      this.recent = recentPage.items
      const total = this.subscribed.length + this.created.length + this.recent.length
      this.message = total === 0 ? failure : ''
      this.loaded = true
    } finally {
      if (request === this.requestId) { this.loading = false }
    }
  }

  private async loadMoreSubscribed(): Promise<void> {
    if (this.loadingMore || !this.more || !this.alive || !this.authStore.loggedIn) { return }
    const request = this.requestId
    const owner = this.authStore.userId
    this.loadingMore = true
    try {
      const page = await PodcastService.subscribed(this.subOffset)
      if (!this.alive || request !== this.requestId || owner !== this.authStore.userId) { return }
      const added = page.items.filter((item: PodcastStation) =>
        !this.subscribed.some((old: PodcastStation) => old.id === item.id))
      this.subscribed = this.subscribed.concat(added)
      this.subOffset += page.items.length
      this.more = page.more && added.length > 0
    } catch (error) {
      if (request === this.requestId) {
        BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '加载更多失败')
      }
    } finally {
      if (request === this.requestId) { this.loadingMore = false }
    }
  }

  private openStation(station: PodcastStation): void {
    if (!this.authStore.loggedIn || this.owner !== this.authStore.userId) { return }
    if (station.list) {
      const param: PodcastVoicesParam = { list: station.list, owner: this.authStore.userId }
      this.pageStack.pushPathByName('PodcastVoicesPage', param)
    } else {
      const param: RadioPageParam = { id: station.id, name: station.name, cover: station.cover }
      this.pageStack.pushPathByName('RadioDetailPage', param)
    }
  }

  private async toggleSubscribe(station: PodcastStation): Promise<void> {
    if (!this.authStore.loggedIn) { this.pageStack.pushPathByName('LoginPage', null); return }
    if (this.changing || station.list) { return }
    this.changing = station.id
    try {
      await PodcastService.subscribe(station.id, !station.subscribed)
      BubbleTip.show(this.getUIContext(), station.subscribed ? '已取消订阅' : '已订阅')
      // 订阅状态通过 revision 广播刷新列表，这里不再重复请求
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '订阅操作失败')
    } finally { this.changing = '' }
  }

  /** 播客的「播放全部」：直接拉一页声音对应的节目进队列。 */
  private async playStation(station: PodcastStation): Promise<void> {
    if (this.playing) { return }
    this.playing = station.id
    try {
      const programs = await this.stationPrograms(station)
      if (!this.alive) { return }
      if (programs.length === 0) { throw new Error('这个播客还没有可播放的声音') }
      await RadioPlayback.play(programs, 0)
      this.pageStack.pushPathByName('PlayPage', null)
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败')
    } finally { this.playing = '' }
  }

  private async stationPrograms(station: PodcastStation): Promise<ProgramItem[]> {
    const programs: ProgramItem[] = []
    if (station.list) {
      const page = await PodcastService.voices(String(station.list.voiceListId), 0)
      const ids: string[] = []
      for (const voice of page.items) {
        if (voice.displayStatus === 'ONLINE' || voice.displayStatus === 'ONLY_SELF_SEE') {
          const id = PodcastService.voiceId(voice)
          if (id) { ids.push(id) }
        }
        if (ids.length >= 20) { break }
      }
      const details = await Promise.all(ids.map((id: string) =>
        RadioService.program(id).catch(() => undefined)))
      for (const detail of details) { if (detail) { programs.push(detail) } }
      return programs
    }
    const listPage = await RadioService.programs(station.id, 0, false)
    return listPage.programs || []
  }

  private shareStation(station: PodcastStation): void {
    if (station.list) { return }
    const param: SharePageParam = { type: 'djradio', id: station.id, name: station.name,
      img: station.cover, author: station.author || '' }
    if (this.onShareRequest) {
      this.onShareRequest(param)
      return
    }
    this.shareParam = param
    this.sharing = true
  }

  private stationMenu(station: PodcastStation): MenuElement[] {
    const options: MenuElement[] = []
    if (!station.list) {
      options.push({ value: station.subscribed ? '取消订阅' : '订阅', action: () => { this.toggleSubscribe(station) } })
    }
    options.push({ value: '播放全部', action: () => { this.playStation(station) } })
    if (station.list) {
      options.push({ value: '管理声音', action: () => { this.openStation(station) } })
    } else {
      options.push({ value: '分享', action: () => { this.shareStation(station) } })
    }
    return options
  }

  private upload(): void {
    if (!this.authStore.loggedIn) { this.pageStack.pushPathByName('LoginPage', null); return }
    const param: VoiceUploadParam = {}
    this.pageStack.pushPathByName('VoiceUploadPage', param)
  }

  private async create(): Promise<void> {
    if (!this.authStore.loggedIn) { this.pageStack.pushPathByName('LoginPage', null); return }
    try { await PodcastService.openCreator(this.getUIContext().getHostContext() as common.UIAbilityContext) }
    catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '创作者中心打开失败') }
  }

  private openDiscover(): void {
    this.pageStack.pushPathByName('RadioPage', null)
  }

  @Builder
  private SectionHeader(title: string, count: number) {
    Row() {
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(TC.textPrimary()).layoutWeight(1)
      Text(String(count)).fontSize(12).fontColor(TC.textTertiary())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 6 })
  }

  @Builder
  private StationRow(station: PodcastStation) {
    Row({ space: 12 }) {
      Image(station.cover || '').width(52).height(52).borderRadius(10)
        .objectFit(ImageFit.Cover).backgroundColor(TC.surfaceInset())
      Column({ space: 4 }) {
        Text(station.name).fontSize(14).fontColor(TC.textBody()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(station.subtitle).fontSize(11).fontColor(TC.textTertiary()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.playing === station.id) {
        LoadingProgress().width(24).height(24).color(TC.accent())
      }
      SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(20).fontColor([TC.textTertiary()])
        .width(32).height(40).enabled(!this.changing).bindMenu(this.stationMenu(station))
    }
    .width('100%')
    .height(70)
    .padding({ left: 16, right: 8 })
    .onClick(() => this.openStation(station))
  }

  @Builder
  private AllContent() {
    Column() {
      if (this.subscribed.length === 0 && this.created.length === 0 && this.recent.length === 0) {
        this.EmptyHint('还没有订阅或创建播客')
      } else {
        if (this.subscribed.length > 0) {
          this.SectionHeader('我订阅的播客', this.subscribed.length)
          ForEach(this.subscribed.slice(0, 6), (station: PodcastStation) => {
            this.StationRow(station)
          }, (station: PodcastStation) => `${station.id}-${station.subscribed}`)
          if (this.subscribed.length > 6 || this.more) {
            Text('查看全部订阅 ›').fontSize(12).fontColor(TC.accentSoft())
              .width('100%').padding({ left: 16, right: 16, bottom: 4 })
              .onClick(() => this.switchTab('podcast'))
          }
        }
        if (this.created.length > 0) {
          this.SectionHeader('我创建的播客', this.created.length)
          ForEach(this.created, (station: PodcastStation) => {
            this.StationRow(station)
          }, (station: PodcastStation) => `created-${station.id}`)
        }
        if (this.recent.length > 0) {
          this.SectionHeader('近期收听的播客', this.recent.length)
          ForEach(this.recent.slice(0, 10), (station: PodcastStation) => {
            this.StationRow(station)
          }, (station: PodcastStation) => `recent-${station.id}-${station.subscribed}`)
        }
      }
    }
    .width('100%')
  }

  @Builder
  private SubscribedContent() {
    Column() {
      if (this.subscribed.length === 0) {
        this.EmptyHint('还没有订阅播客，去发现更多吧')
      } else {
        this.SectionHeader('我订阅的播客', this.subscribed.length)
        ForEach(this.subscribed, (station: PodcastStation) => {
          this.StationRow(station)
        }, (station: PodcastStation) => `${station.id}-${station.subscribed}`)
        if (this.loadingMore) {
          LoadingProgress().width(28).height(28).color(TC.accent()).margin(16)
        } else if (this.more) {
          Text('加载更多').fontSize(12).fontColor(TC.accentSoft()).width('100%')
            .textAlign(TextAlign.Center).padding(16).onClick(() => this.loadMoreSubscribed())
        }
      }
    }
    .width('100%')
  }

  @Builder
  private CreatedContent() {
    Column() {
      if (this.created.length === 0) {
        this.EmptyHint('还没有创建播客')
      } else {
        this.SectionHeader('我创建的播客', this.created.length)
        ForEach(this.created, (station: PodcastStation) => {
          this.StationRow(station)
        }, (station: PodcastStation) => `created-${station.id}`)
      }
      Text('新播客在网易云创作者中心创建；返回后下拉刷新，即可在这里发布和管理声音。')
        .fontSize(11).lineHeight(18).fontColor(TC.textTertiary())
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
    }
    .width('100%')
  }

  @Builder
  private EmptyHint(text: string) {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.podcast')).fontSize(36).fontColor([TC.textQuaternary()])
      Text(text).fontSize(13).fontColor(TC.textTertiary())
    }
    .width('100%').height(160).justifyContent(FlexAlign.Center)
  }

  @Builder
  private LoginHint() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.podcast')).fontSize(40).fontColor([TC.textTertiary()])
      Text('登录后查看订阅、创建与最近收听的播客').fontSize(13).fontColor(TC.textTertiary())
      Button('去登录').fontSize(12).backgroundColor(TC.accent()).fontColor(TC.textOnAccent())
        .borderRadius(20).onClick(() => this.pageStack.pushPathByName('LoginPage', null))
    }
    .width('100%').height(200).justifyContent(FlexAlign.Center)
  }

  /** 与「我的 - 音乐」里的「新建歌单」一致的整行入口：56 图标 + 一行文字。 */
  @Builder
  private ActionRow(icon: Resource, label: string, action: () => void) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph(icon).fontSize(28).fontColor([TC.textTertiary()])
      }
      .width(56).height(56).borderRadius(8).backgroundColor(TC.surfaceRaised())
      .alignContent(Alignment.Center)
      Column() {
        Text(label).fontSize(14).fontColor(TC.textBody())
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(72)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16 })
    .onClick(action)
  }

  @Builder
  private BottomActions() {
    Column({ space: 0 }) {
      if (this.tab === 'created') {
        this.ActionRow($r('sys.symbol.plus_circle'), '创建播客', () => { this.create() })
        this.ActionRow($r('sys.symbol.arrow_up_circle'), '发布声音', () => { this.upload() })
      } else {
        this.ActionRow($r('sys.symbol.magnifyingglass'), '添加更多播客', () => this.openDiscover())
      }
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: this.shareParam, visible: true, onClose: () => this.sharing = false })
  }

  build() {
    Column() {
      Row() {
        ForEach(this.tabs, (tab: string) => {
          Text(this.tabTitle(tab))
            .layoutWeight(1)
            .fontSize(12)
            .textAlign(TextAlign.Center)
            .fontColor(this.tab === tab ? TC.textPrimary() : TC.textTertiary())
            .fontWeight(this.tab === tab ? FontWeight.Bold : FontWeight.Regular)
            .padding({ top: 5, bottom: 5 })
            .backgroundColor(this.tab === tab ? TC.surfaceRaised() : Color.Transparent)
            .borderRadius(14)
            .onClick(() => this.switchTab(tab))
        }, (tab: string) => tab)
      }
      .width('60%')
      .padding({ left: 14, right: 14, top: 10, bottom: 8 })

      if (!this.authStore.loggedIn) {
        this.LoginHint()
      } else if (this.loading && this.subscribed.length === 0 && this.created.length === 0 && this.recent.length === 0) {
        LoadingProgress().width(36).height(36).color(TC.accent()).margin({ top: 60, bottom: 60 })
      } else if (this.message.length > 0) {
        Column({ space: 10 }) {
          Text(this.message).fontSize(12).fontColor(TC.textTertiary())
          Button('重试').fontSize(12).backgroundColor(TC.surfaceRaised()).fontColor(TC.textBody())
            .onClick(() => this.loadAll())
        }
        .width('100%').padding({ top: 40, bottom: 40 })
      } else {
        if (this.tab === 'all') {
          this.AllContent()
        } else if (this.tab === 'podcast') {
          this.SubscribedContent()
        } else {
          this.CreatedContent()
        }
        this.BottomActions()
      }
    }
    .width('100%')
    .bindContentCover(this.sharing, this.ShareOptions(), {
      modalTransition: ModalTransition.NONE, backgroundColor: Color.Transparent,
      onDisappear: () => this.sharing = false
    })
  }
}
