import { DjRadioItem } from '../models/api'
import { ProgramItem } from '../models/home'
import { RadioCategory, RadioPageParam } from '../models/radio'
import { RadioService } from '../services/RadioService'
import { RadioPlayback } from '../services/RadioPlayback'
import { BubbleTip } from '../services/BubbleTip'
import { RadioStationCard, RadioProgramRow } from '../components/RadioCards'

@Component
export struct RadioPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  embedded: boolean = false
  @State categories: RadioCategory[] = []
  @State recommendations: ProgramItem[] = []
  @State stations: DjRadioItem[] = []
  @State ranked: ProgramItem[] = []
  @State category: number = 0
  @State categoryName: string = '全部分类'
  @State mode: string = 'recommend'
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
      RadioService.recommendedPrograms().then((items: ProgramItem[]) => {
        if (generation === this.homeToken) { this.recommendations = items }
      }).catch(() => { if (generation === this.homeToken) { this.recommendations = [] } }),
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
    this.mode = mode
    this.query = ''
    this.loadList(true)
  }

  private chooseCategory(id: number, name: string): void {
    this.categoryVisible = false
    this.category = id
    this.categoryName = name
    if (this.mode === 'new' || this.mode === 'programs') { this.mode = 'recommend' }
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
  private CategoriesSheet() {
    Column({ space: 16 }) {
      Row() {
        Text('电台分类').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#ffffff').layoutWeight(1)
        Text('关闭').fontSize(14).fontColor('#9999a4').onClick(() => this.categoryVisible = false)
      }.width('100%')
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          Text('全部分类').fontSize(14).fontColor(this.category === 0 ? '#ff6577' : '#bbbbC5')
            .padding(12).onClick(() => this.chooseCategory(0, '全部分类'))
          ForEach(this.categories, (item: RadioCategory) => {
            Text(item.name).fontSize(14).fontColor(this.category === item.id ? '#ff6577' : '#bbbbC5')
              .padding(12).onClick(() => this.chooseCategory(item.id, item.name))
          }, (item: RadioCategory) => String(item.id))
        }.width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(22)
  }

  @Builder
  private Header() {
    if (!this.embedded) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
        Text('电台').fontSize(23).fontWeight(FontWeight.Bold).fontColor('#ffffff')
      }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 17, top: this.topAvoidHeight })
    }
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text('音乐电台').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text('DIFM · 电音 / 古典 / 爵士').fontSize(12).fontColor('#aaaaB5')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.podcast')).fontSize(28).fontColor(['#ff6577'])
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor(['#9999a4'])
    }.width('92%').padding(18).borderRadius(18).backgroundColor('#202027').margin({ top: 12, bottom: 16 })
      .onClick(() => this.pageStack.pushPathByName('DifmPage', null))
    Scroll() {
      Row({ space: 22 }) {
        Text(this.categoryName + ' ▾').fontSize(13).fontColor('#ff6577').onClick(() => this.categoryVisible = true)
        ForEach(this.categories.slice(0, 8), (item: RadioCategory) => {
          Text(item.name).fontSize(13).fontColor(this.category === item.id ? '#ff6577' : '#a0a0aa')
            .onClick(() => this.chooseCategory(item.id, item.name))
        }, (item: RadioCategory) => String(item.id))
      }.padding({ left: 17, right: 17, top: 8, bottom: 8 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    if (this.homeMessage) { Text(this.homeMessage).fontSize(11).fontColor('#9999a4').padding(12) }
  }

  @Builder
  private RecommendedPrograms() {
    if (this.category === 0 && this.mode === 'recommend' && this.recommendations.length > 0) {
      Row() {
        Text('精选节目').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ffffff').layoutWeight(1)
        Text(this.playing ? '准备播放…' : '播放全部').fontSize(12).fontColor('#ff6577')
          .enabled(!this.playing).onClick(() => this.play(this.recommendations))
      }.width('100%').padding({ left: 17, right: 17, top: 18, bottom: 8 })
      ForEach(this.recommendations, (program: ProgramItem, index: number) => {
        RadioProgramRow({ program: program, onPlay: () => this.play(this.recommendations, index),
          onDetails: () => this.openProgram(program) })
      }, (program: ProgramItem) => String(program.id))
    }
  }

  @Builder
  private Content() {
    Refresh({ refreshing: this.refreshing }) {
      List() {
        ListItem() { Column() { this.Header(); this.RecommendedPrograms() }.width('100%') }
        ListItem() {
          Row({ space: 24 }) {
            ForEach(this.category > 0 ? ['recommend', 'hot'] : ['recommend', 'hot', 'new', 'programs'], (mode: string) => {
              Text(mode === 'recommend' ? '推荐电台' : mode === 'hot' ? '热门' : mode === 'new' ? '新晋' : '节目榜')
                .fontSize(14).fontWeight(this.mode === mode ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.mode === mode ? '#ffffff' : '#85858f').onClick(() => this.chooseMode(mode))
            })
          }.width('100%').padding({ left: 17, right: 17, top: 20, bottom: 14 })
        }
        if (this.mode !== 'programs') {
          ListItem() {
            Search({ value: this.query, placeholder: '筛选已加载电台' }).margin({ left: 17, right: 17, bottom: 10 })
              .fontColor('#eeeeF2').backgroundColor('#222229').onChange((value: string) => this.query = value)
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
            if (this.loading) { LoadingProgress().width(30).height(30).color('#ef233c') }
            else if (this.message) {
              Text(this.message).fontSize(13).fontColor('#ff6577')
              Button('重试').backgroundColor('#303038').onClick(() => { this.message = ''; this.loadList() })
            } else {
              Text((this.mode === 'programs' ? this.ranked.length === 0 : this.visibleStations().length === 0) ?
                '暂无内容' : this.more ? '加载更多' : '已经到底了').fontSize(12).fontColor('#85858f')
                .onClick(() => this.loadList())
            }
          }.width('100%').padding({ top: 20, bottom: this.embedded ? 145 : 40 })
        }
      }.width('100%').height('100%').scrollBar(BarState.Off).onReachEnd(() => this.loadList())
    }.width('100%').height('100%').backgroundColor('#121215')
      .onRefreshing(async () => { this.refreshing = true; await this.loadHome(); this.refreshing = false })
      .bindSheet(this.categoryVisible, this.CategoriesSheet(), {
        height: '62%', backgroundColor: '#19191f', showClose: false, dragBar: true,
        onDisappear: () => this.categoryVisible = false
      })
  }

  build() {
    if (this.embedded) { this.Content() }
    else { NavDestination() { this.Content() }.hideTitleBar(true).backgroundColor('#121215') }
  }
}
