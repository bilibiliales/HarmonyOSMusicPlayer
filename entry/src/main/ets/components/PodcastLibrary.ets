import { common } from '@kit.AbilityKit'
import { PodcastStation, PodcastStationPage, PodcastVoicesParam } from '../models/podcast'
import { RadioPageParam } from '../models/radio'
import { AuthStore } from '../stores/AuthStore'
import { PodcastService } from '../services/PodcastService'
import { VoiceUploadParam } from '../services/VoiceUploadService'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'
import { SecondaryTabContent, SecondaryTabMotion } from './SecondaryTabContent'

/** 同一播客库用于“我的－播客”和发现页入口，避免上传目标混入搜索结果。 */
@Component
export struct PodcastLibrary {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @StorageProp(PodcastService.REVISION_KEY) @Watch('refresh') revision: number = 0
  @Consume('authStore') @Watch('authChanged') authStore: AuthStore
  @Consume('pageStack') pageStack: NavPathStack
  @Prop initialSection: string = 'recent'
  @Prop @Watch('refresh') refreshKey: number = 0
  @State section: string = 'recent'
  @State motionDirection: number = -1
  @State stations: PodcastStation[] = []
  @State loading: boolean = false
  @State more: boolean = false
  @State message: string = ''
  @State changing: string = ''
  private requestId: number = 0
  private owner: string = ''
  private alive: boolean = true
  private listOffset: number = 0
  private cache: Map<string, PodcastStation[]> = new Map()
  private moreCache: Map<string, boolean> = new Map()
  private readonly sections: string[] = ['recent', 'subscribed', 'created']

  aboutToAppear(): void {
    this.alive = true
    this.section = this.sections.includes(this.initialSection) ? this.initialSection : 'recent'
    this.authChanged()
  }
  aboutToDisappear(): void { this.alive = false; this.requestId++ }

  private authChanged(): void {
    const owner = this.authStore.loggedIn ? this.authStore.userId : ''
    if (owner === this.owner && this.cache.has(this.section)) { return }
    this.owner = owner
    this.refresh()
  }

  private refresh(): void {
    this.requestId++
    this.cache.clear()
    this.moreCache.clear()
    this.stations = []
    this.listOffset = 0
    this.loading = false
    this.more = false
    this.message = ''
    if (this.alive && this.authStore.loggedIn) { this.load(true) }
  }

  private switchSection(section: string): void {
    if (this.section === section) { return }
    this.motionDirection = SecondaryTabMotion.direction(this.section, section, this.sections)
    this.requestId++
    this.getUIContext().animateTo({ duration: SecondaryTabMotion.DURATION, curve: Curve.EaseOut }, () => this.section = section)
    this.message = ''
    this.loading = false
    this.stations = this.cache.get(section) || []
    this.listOffset = this.stations.length
    this.more = this.moreCache.get(section) || false
    if (this.authStore.loggedIn && !this.cache.has(section)) { this.load(true) }
  }

  private async load(reset: boolean = false): Promise<void> {
    if (!this.authStore.loggedIn || !this.alive || (!reset && (this.loading || !this.more))) { return }
    const request = ++this.requestId
    const owner = this.authStore.userId
    const section = this.section
    if (reset) { this.listOffset = 0; this.stations = [] }
    const offset = this.listOffset
    this.loading = true
    this.message = ''
    try {
      const page: PodcastStationPage = section === 'recent' ? await PodcastService.recent() :
        section === 'subscribed' ? await PodcastService.subscribed(offset) : await PodcastService.created()
      if (!this.alive || request !== this.requestId || owner !== this.authStore.userId || !this.authStore.loggedIn) { return }
      const added = page.items.filter((item: PodcastStation) => !this.stations.some((old: PodcastStation) => old.id === item.id))
      this.stations = this.stations.concat(added)
      this.listOffset = offset + page.items.length
      this.more = page.more && added.length > 0
      this.cache.set(section, this.stations)
      this.moreCache.set(section, this.more)
    } catch (error) {
      if (request === this.requestId && owner === this.authStore.userId) {
        this.message = error instanceof Error ? error.message : '播客加载失败'
      }
    } finally { if (request === this.requestId) { this.loading = false } }
  }

  private open(station: PodcastStation): void {
    if (!this.authStore.loggedIn || this.owner !== this.authStore.userId) { return }
    if (station.list) {
      const param: PodcastVoicesParam = { list: station.list, owner: this.authStore.userId }
      this.pageStack.pushPathByName('PodcastVoicesPage', param)
    } else {
      const param: RadioPageParam = { id: station.id, name: station.name, cover: station.cover }
      this.pageStack.pushPathByName('RadioDetailPage', param)
    }
  }

  private async unsubscribe(station: PodcastStation): Promise<void> {
    if (this.changing || !this.authStore.loggedIn || this.owner !== this.authStore.userId) { return }
    this.changing = station.id
    try { await PodcastService.subscribe(station.id, false) }
    catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '取消订阅失败') }
    finally { this.changing = '' }
  }

  private moreOptions(station: PodcastStation): MenuElement[] {
    const options: MenuElement[] = [{ value: station.list ? '管理声音' : '打开播客', action: () => this.open(station) }]
    if (station.subscribed) { options.push({ value: '取消订阅', action: () => { this.unsubscribe(station) } }) }
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

  @Builder
  private Body() {
    if (!this.authStore.loggedIn) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.podcast')).fontSize(40).fontColor([TC.textTertiary()])
        Text('登录后查看收听记录、订阅和自己的播客').fontSize(13).fontColor(TC.textTertiary())
        Button('去登录').fontSize(12).backgroundColor(TC.accent()).fontColor(TC.textOnAccent())
          .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
      }.width('100%').height(200).justifyContent(FlexAlign.Center)
    } else {
      ForEach(this.stations, (station: PodcastStation) => {
        Row({ space: 12 }) {
          Image(station.cover).width(56).height(56).sourceSize({ width: 112, height: 112 }).borderRadius(12).objectFit(ImageFit.Cover)
          Column({ space: 5 }) {
            Text(station.name).fontSize(14).fontColor(TC.textBody()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(station.subtitle).fontSize(11).fontColor(TC.textTertiary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(20).fontColor([TC.textTertiary()])
            .width(30).height(36).enabled(!this.changing).bindMenu(this.moreOptions(station))
        }.width('100%').height(76).padding({ left: 16, right: 16 }).onClick(() => this.open(station))
      }, (station: PodcastStation) => station.id)
      if (this.loading) {
        LoadingProgress().width(36).height(36).color(TC.accent()).margin(24)
      } else if (this.message) {
        Text(this.message).fontSize(12).fontColor(TC.accentSoft()).padding(16)
        Button('重试').fontSize(12).onClick(() => this.load(this.stations.length === 0))
      } else if (this.stations.length === 0) {
        Text(this.section === 'recent' ? '还没有最近收听的播客' : this.section === 'subscribed' ? '还没有订阅播客' : '还没有创建播客')
          .width('100%').height(120).fontSize(13).fontColor(TC.textTertiary()).textAlign(TextAlign.Center)
      } else if (this.more) {
        Text('加载更多').fontSize(12).fontColor(TC.accentSoft()).padding(16).onClick(() => this.load())
      }
      if (this.section === 'created') {
        Text('新播客在网易云创作者中心创建；返回后刷新，即可在这里发布和管理声音。')
          .fontSize(11).lineHeight(18).fontColor(TC.textTertiary()).padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
    }
  }

  build() {
    Column() {
      Row() {
        ForEach(this.sections, (section: string) => {
          Column({ space: 7 }) {
            Text(section === 'recent' ? '最近收听' : section === 'subscribed' ? '已订阅' : '我的播客')
              .fontSize(14).fontWeight(this.section === section ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.section === section ? TC.textPrimary() : TC.textTertiary())
            Column().width(24).height(3).borderRadius(2).backgroundColor(this.section === section ? TC.accent() : Color.Transparent)
          }.layoutWeight(1).height(48).justifyContent(FlexAlign.Center).onClick(() => this.switchSection(section))
        }, (section: string) => section)
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(18).fontColor([TC.textSecondary()])
          .width(40).height(48).onClick(() => this.refresh())
      }.width('100%').padding({ left: 8, right: 8 })
      SecondaryTabContent({ value: this.section, motionDirection: this.motionDirection }) { this.Body() }
      Row({ space: 10 }) {
        Button('创建播客').fontSize(12).backgroundColor(TC.surfaceRaised()).fontColor(TC.textBody()).onClick(() => this.create())
        Button('发布声音').fontSize(12).backgroundColor(TC.accent()).fontColor(TC.textOnAccent()).onClick(() => this.upload())
        Text('发现更多 ›').fontSize(12).fontColor(TC.accentSoft()).onClick(() => this.pageStack.pushPathByName('RadioPage', null))
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 })
    }.width('100%')
  }
}
