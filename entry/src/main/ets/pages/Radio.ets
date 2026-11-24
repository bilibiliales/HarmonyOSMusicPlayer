import { SheetSkinFrame } from '../components/SheetSkin'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { DjRadioItem } from '../models/api'
import { ProgramItem } from '../models/home'
import { RadioCategory, RadioPageParam } from '../models/radio'
import { RadioService } from '../services/RadioService'
import { RadioPlayback } from '../services/RadioPlayback'
import { BubbleTip } from '../services/BubbleTip'
import { RadioStationCard, RadioProgramRow } from '../components/RadioCards'
import { TC } from '../services/ThemeColors'
import { SecondaryTabContent, SecondaryTabMotion } from '../components/SecondaryTabContent'

@Component
export struct RadioPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  embedded: boolean = false
  @State categories: RadioCategory[] = []
  @State stations: DjRadioItem[] = []
  @State ranked: ProgramItem[] = []
  @State category: number = 0
  @State categoryName: string = '全部分类'
  @State mode: string = 'recommend'
  @State motionDirection: number = -1
  @State loading: boolean = false
  @State refreshing: boolean = false
  @State more: boolean = true
  @State message: string = ''
  @State homeMessage: string = ''
  @State categoryVisible: boolean = false
  @State query: string = ''
  @State playing: boolean = false
  private token: number = 0
  private homeToken: number = 0
  private listOffset: number = 0

  aboutToAppear(): void { this.loadHome() }
  aboutToDisappear(): void { this.token++; this.homeToken++ }

  private async loadHome(): Promise<void> {
    const generation = ++this.homeToken
    this.homeMessage = ''
    await Promise.all([
      RadioService.categories().then((items: RadioCategory[]) => {
        if (generation === this.homeToken) { this.categories = items }
      }).catch(() => { if (generation === this.homeToken) { this.homeMessage = '分类加载失败，可下拉重试' } }),
      this.loadList(true)
    ])
  }

  private async loadList(reset: boolean = false): Promise<void> {
    if (!reset && (this.loading || !this.more || this.message)) { return }
    const generation = ++this.token
    if (reset) { this.listOffset = 0; this.stations = []; this.ranked = []; this.more = true }
    this.loading = true
    this.message = ''
    try {
      if (this.mode === 'programs') {
        const result = await RadioService.rankedPrograms(this.listOffset)
        if (generation !== this.token) { return }
        const incoming = result.programs || []
        const added = incoming.filter((item: ProgramItem) => !this.ranked.some((old: ProgramItem) => old.id === item.id))
        this.ranked = this.ranked.concat(added)
        this.listOffset += incoming.length
        this.more = !!result.more && added.length > 0
      } else {
        const result = await RadioService.stations(this.mode, this.category, this.listOffset)
        if (generation !== this.token) { return }
        const added = result.items.filter((item: DjRadioItem) => !this.stations.some((old: DjRadioItem) => old.id === item.id))
        this.stations = this.stations.concat(added)
        this.listOffset += result.items.length
        this.more = result.more && added.length > 0
      }
    } catch (error) {
      if (generation === this.token) { this.message = error instanceof Error ? error.message : '电台加载失败' }
    } finally {
      if (generation === this.token) { this.loading = false }
    }
  }

  private chooseMode(mode: string): void {
    if (mode === this.mode) { return }
    this.motionDirection = SecondaryTabMotion.direction(this.mode, mode, ['recommend', 'hot', 'new', 'programs'])
    this.getUIContext().animateTo({ duration: SecondaryTabMotion.DURATION, curve: Curve.EaseOut }, () => this.mode = mode)
    this.query = ''
    this.loadList(true)
  }

  private chooseCategory(id: number, name: string): void {
    this.categoryVisible = false
    this.motionDirection = id > this.category ? -1 : 1
    this.getUIContext().animateTo({ duration: SecondaryTabMotion.DURATION, curve: Curve.EaseOut }, () => {
      this.category = id
      this.categoryName = name
      if (this.mode === 'new' || this.mode === 'programs') { this.mode = 'recommend' }
    })
    this.query = ''
    this.loadList(true)
  }

  private openStation(id: number, name: string = '', cover: string = ''): void {
    const param: RadioPageParam = { id: String(id), name: name, cover: cover }
    this.pageStack.pushPathByName('RadioDetailPage', param)
  }

  private async play(programs: ProgramItem[], index: number = 0): Promise<void> {
    if (this.playing) { return }
    this.playing = true
    try {
      await RadioPlayback.play(programs, index)
      this.pageStack.pushPathByName('PlayPage', null)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败') }
    finally { this.playing = false }
  }

  private openProgram(program: ProgramItem): void {
    const param: RadioPageParam = { id: String(program.id), name: program.name, cover: RadioService.cover(program) }
    this.pageStack.pushPathByName('RadioProgramPage', param)
  }

  private visibleStations(): DjRadioItem[] {
    const query = this.query.trim().toLowerCase()
    return this.stations.filter((item: DjRadioItem) => !query ||
      (item.name + ' ' + (item.dj?.nickname || '')).toLowerCase().includes(query))
  }

  @Builder
  private skin_CategoriesSheet() {
    SheetSkinFrame() {
      this.CategoriesSheet()
    }
  }

  @Builder
  private CategoriesSheet() {
    Column({ space: 16 }) {
      Row() {
        Text('电台分类').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary()).layoutWeight(1)
        Text('关闭').fontSize(14).fontColor(TC.textSecondary()).onClick(() => this.categoryVisible = false)
      }.width('100%')
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          Text('全部分类').fontSize(14).fontColor(this.category === 0 ? TC.accentSoft() : TC.textSecondary())
            .padding(12).onClick(() => this.chooseCategory(0, '全部分类'))
          ForEach(this.categories, (item: RadioCategory) => {
            Text(item.name).fontSize(14).fontColor(this.category === item.id ? TC.accentSoft() : TC.textSecondary())
              .padding(12).onClick(() => this.chooseCategory(item.id, item.name))
          }, (item: RadioCategory) => String(item.id))
        }.width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(22)
  }

  @Builder
  private EntryCard(icon: Resource, title: string, subtitle: string, action: () => void) {
    Column({ space: 6 }) {
      Row() {
        SymbolGlyph(icon).fontSize(22).fontColor([TC.accentSoft()])
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([TC.textTertiary()])
      }.width('100%')
      Text(title).width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
      Text(subtitle).width('100%').fontSize(10).fontColor(TC.textQuaternary()).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding(14)
    .borderRadius(18)
    .backgroundColor(TC.surfaceCard())
    .alignItems(HorizontalAlign.Start)
    .onClick(action)
  }

  @Builder
  private Header() {
    if (!this.embedded) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()]).onClick(() => this.pageStack.pop())
        Text('播客').fontSize(23).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
      }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 17, top: this.topAvoidHeight })
    }
    Row({ space: 12 }) {
      this.EntryCard($r('sys.symbol.podcast'), '音乐电台', 'DIFM · 电音 / 古典 / 爵士',
        () => this.pageStack.pushPathByName('DifmPage', null))
      this.EntryCard($r('sys.symbol.mic_fill'), '精选节目', '编辑精选 · 每期都值得一听',
        () => this.pageStack.pushPathByName('RadioProgramsPage', null))
    }.width('92%').margin({ top: 12, bottom: 16 })
    Scroll() {
      Row({ space: 22 }) {
        Text(this.categoryName + ' ▾').fontSize(13).fontColor(TC.accentSoft()).onClick(() => this.categoryVisible = true)
        ForEach(this.categories.slice(0, 8), (item: RadioCategory) => {
          Text(item.name).fontSize(13).fontColor(this.category === item.id ? TC.accentSoft() : TC.textSecondary())
            .onClick(() => this.chooseCategory(item.id, item.name))
        }, (item: RadioCategory) => String(item.id))
      }.padding({ left: 17, right: 17, top: 8, bottom: 8 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    if (this.homeMessage) { Text(this.homeMessage).fontSize(11).fontColor(TC.textSecondary()).padding(12) }
  }

  @Builder
  private Content() {
    Column() {
    SecondaryTabContent({ value: `${this.mode}:${this.category}`, motionDirection: this.motionDirection, fill: true }) {
      this.RadioFeed()
    }
    }.width('100%').height('100%')
  }

  @Builder
  private RadioFeed() {
    Refresh({ refreshing: this.refreshing }) {
      List() {
        ListItem() { Column() { this.Header() }.width('100%') }
        ListItem() {
          Row({ space: 24 }) {
            ForEach(this.category > 0 ? ['recommend', 'hot'] : ['recommend', 'hot', 'new', 'programs'], (mode: string) => {
              Text(mode === 'recommend' ? '推荐电台' : mode === 'hot' ? '热门' : mode === 'new' ? '新晋' : '节目榜')
                .fontSize(14).fontWeight(this.mode === mode ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.mode === mode ? TC.textPrimary() : TC.textTertiary()).onClick(() => this.chooseMode(mode))
            })
          }.width('100%').padding({ left: 17, right: 17, top: 20, bottom: 14 })
        }
        if (this.mode !== 'programs') {
          ListItem() {
            Search({ value: this.query, placeholder: '筛选已加载电台' }).margin({ left: 17, right: 17, bottom: 10 })
              .fontColor(TC.textBody()).backgroundColor(TC.surfaceRaised()).onChange((value: string) => this.query = value)
          }
          ForEach(this.visibleStations(), (station: DjRadioItem) => {
            ListItem() { RadioStationCard({ station: station, onOpen: () => this.openStation(station.id, station.name, station.picUrl) }) }
          }, (station: DjRadioItem) => String(station.id))
        } else {
          ForEach(this.ranked, (program: ProgramItem, index: number) => {
            ListItem() { RadioProgramRow({ program: program, rank: index + 1,
              onPlay: () => this.play(this.ranked, index), onDetails: () => this.openProgram(program) }) }
          }, (program: ProgramItem) => String(program.id))
        }
        ListItem() {
          Column({ space: 12 }) {
            if (this.loading) { LoadingProgress().width(30).height(30).color(TC.accent()) }
            else if (this.message) {
              Text(this.message).fontSize(13).fontColor(TC.accentSoft())
              Button('重试').backgroundColor(TC.surfaceRaised()).onClick(() => { this.message = ''; this.loadList() })
            } else {
              Text((this.mode === 'programs' ? this.ranked.length === 0 : this.visibleStations().length === 0) ?
                '暂无内容' : this.more ? '加载更多' : '已经到底了').fontSize(12).fontColor(TC.textTertiary())
                .onClick(() => this.loadList())
            }
          }.width('100%').padding({ top: 20, bottom: this.embedded ? 145 : 40 })
        }
      }.width('100%').height('100%').scrollBar(BarState.Off).onReachEnd(() => this.loadList())
    }.width('100%').height('100%').backgroundColor(TC.pageBackground())
      .onRefreshing(async () => { this.refreshing = true; await this.loadHome(); this.refreshing = false })
      .bindSheet(this.categoryVisible, this.skin_CategoriesSheet(), {
        height: '62%', backgroundColor: TC.sheetBackground(), showClose: false, dragBar: true,
        onDisappear: () => this.categoryVisible = false
      })
  }

  build() {
    if (this.embedded) { this.Content() }
    else {
      NavDestination() {
        SkinBackdrop()
        this.Content()
      }.hideTitleBar(true).backgroundColor(TC.pageBackground())
    }
  }
}
