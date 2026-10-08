import { DifmService, DifmSource, DifmStyle, DifmChannel, DifmTrack } from '../services/DifmService'
import { RadioService } from '../services/RadioService'
import { playerController } from '../services/PlayerController'
import { BubbleTip } from '../services/BubbleTip'

@Component
export struct DifmPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State catalog: DifmSource[] = []
  @State source: number = 0
  @State styleId: number = 0
  @State loading: boolean = true
  @State message: string = ''
  @State query: string = ''
  @State channel?: DifmChannel = undefined
  @State tracks: DifmTrack[] = []
  @State sheetVisible: boolean = false
  @State tracksLoading: boolean = false
  @State trackMessage: string = ''
  @State playing: boolean = false
  private token: number = 0
  private alive: boolean = true

  aboutToAppear(): void { this.load() }
  aboutToDisappear(): void { this.alive = false; this.token++ }

  private async load(): Promise<void> {
    this.loading = true
    this.message = ''
    try {
      const catalog = await DifmService.catalog()
      if (this.alive) { this.catalog = catalog }
    } catch (error) { if (this.alive) { this.message = error instanceof Error ? error.message : '加载失败' } }
    finally { if (this.alive) { this.loading = false } }
  }

  private styles(): DifmStyle[] { return this.catalog.find((item: DifmSource) => item.source === this.source)?.styles || [] }

  private channels(): DifmChannel[] {
    const seen = new Set<number>()
    const result: DifmChannel[] = []
    const query = this.query.trim().toLowerCase()
    for (const style of this.styles()) {
      if (this.styleId > 0 && style.id !== this.styleId) { continue }
      for (const channel of style.channels || []) {
        if (seen.has(channel.id) || (query && !(channel.name + ' ' + (channel.chineseName || '')).toLowerCase().includes(query))) { continue }
        seen.add(channel.id)
        result.push(channel)
      }
    }
    return result
  }

  private async openChannel(channel: DifmChannel): Promise<void> {
    const generation = ++this.token
    this.channel = channel
    this.tracks = []
    this.trackMessage = ''
    this.sheetVisible = true
    this.tracksLoading = true
    try {
      const tracks = await DifmService.tracks(channel)
      if (generation === this.token) { this.tracks = tracks }
    } catch (error) {
      if (generation === this.token) { this.trackMessage = error instanceof Error ? error.message : '曲目加载失败' }
    } finally { if (generation === this.token) { this.tracksLoading = false } }
  }

  private async play(index: number): Promise<void> {
    if (!this.channel || this.playing || this.tracks.length === 0) { return }
    this.playing = true
    const channel = this.channel
    try {
      await playerController.setQueue(this.tracks.map((track: DifmTrack) => DifmService.song(track, channel)), index, true)
      this.sheetVisible = false
      this.pageStack.pushPathByName('PlayPage', null)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败，请刷新频道曲目') }
    finally { this.playing = false }
  }

  @Builder
  private ChannelSheet() {
    Column({ space: 14 }) {
      Row() {
        Text(this.channel?.chineseName || this.channel?.name || '频道曲目').fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor('#ffffff').layoutWeight(1).maxLines(2)
        Text('关闭').fontSize(14).fontColor('#9999a4').onClick(() => this.sheetVisible = false)
      }.width('100%')
      Scroll() {
        Column({ space: 12 }) {
          if (this.channel?.description) {
            Text(this.channel.description).width('100%').fontSize(13).lineHeight(22).fontColor('#9999a4')
          }
          Row() {
            Text(this.playing ? '准备播放…' : '播放全部').fontSize(15).fontColor('#ffffff').layoutWeight(1)
              .enabled(this.tracks.length > 0 && !this.playing).onClick(() => this.play(0))
            Text('刷新曲目').fontSize(12).fontColor('#ff6577').enabled(!this.tracksLoading)
              .onClick(() => { if (this.channel) { this.openChannel(this.channel) } })
          }.width('100%').height(44)
          if (this.tracksLoading) { LoadingProgress().width(32).height(32).color('#ef233c') }
          else if (this.trackMessage || this.tracks.length === 0) {
            Text(this.trackMessage || '该频道暂时没有可播放曲目').fontSize(13).fontColor('#9999a4').padding(18)
          }
          ForEach(this.tracks, (track: DifmTrack, index: number) => {
            Row({ space: 12 }) {
              Image(track.cover || this.channel?.cover || '').width(52).height(52).objectFit(ImageFit.Cover).borderRadius(9)
              Column({ space: 5 }) {
                Text(track.name).fontSize(14).fontColor('#eeeeF2').maxLines(2)
                Text((track.artist || '') + ' · ' + RadioService.duration((track.duration || 0) * 1000))
                  .fontSize(11).fontColor('#85858f').maxLines(1)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.play_circle')).fontSize(24).fontColor(['#bbbbC5'])
            }.width('100%').padding({ top: 7, bottom: 7 }).onClick(() => this.play(index))
          }, (track: DifmTrack, index: number) => String(track.id) + ':' + index)
        }.width('100%').padding({ bottom: 24 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 10, bottom: 16 })
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
          Text('音乐电台 · DIFM').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 17, top: this.topAvoidHeight })
        Row({ space: 30 }) {
          ForEach([0, 1, 2], (source: number) => {
            Text(source === 0 ? '电音' : source === 1 ? '古典' : '爵士').fontSize(16)
              .fontColor(this.source === source ? '#ff6577' : '#9999a4').padding({ top: 12, bottom: 12 })
              .onClick(() => { this.source = source; this.styleId = 0; this.query = '' })
          })
        }.width('100%').padding({ left: 17 })
        Search({ value: this.query, placeholder: '搜索频道' }).margin({ left: 17, right: 17, bottom: 10 })
          .fontColor('#eeeeF2').backgroundColor('#222229').onChange((value: string) => this.query = value)
        Scroll() {
          Row({ space: 20 }) {
            Text('全部').fontSize(12).fontColor(this.styleId === 0 ? '#ff6577' : '#9999a4').onClick(() => this.styleId = 0)
            ForEach(this.styles(), (style: DifmStyle) => {
              Text(style.chineseName || style.name).fontSize(12).fontColor(this.styleId === style.id ? '#ff6577' : '#9999a4')
                .onClick(() => this.styleId = style.id)
            }, (style: DifmStyle) => this.source + ':' + style.id)
          }.padding({ left: 17, right: 17, top: 12, bottom: 12 })
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        if (this.loading) { LoadingProgress().width(38).height(38).color('#ef233c').margin(40) }
        else if (this.message) {
          Text(this.message).fontSize(13).fontColor('#ff6577').padding(20)
          Button('重试').backgroundColor('#303038').onClick(() => this.load())
        } else {
          List() {
            ForEach(this.channels(), (channel: DifmChannel) => {
              ListItem() {
                Row({ space: 13 }) {
                  Image(channel.cover || '').width(66).height(66).objectFit(ImageFit.Cover).borderRadius(13)
                  Column({ space: 6 }) {
                    Text(channel.chineseName || channel.name).fontSize(16).fontColor('#eeeeF2').maxLines(2)
                    Text(channel.chineseName ? channel.name : channel.description || '查看频道曲目')
                      .fontSize(11).fontColor('#85858f').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor(['#85858f'])
                }.width('100%').padding({ left: 17, right: 17, top: 9, bottom: 9 }).onClick(() => this.openChannel(channel))
              }
            }, (channel: DifmChannel) => this.source + ':' + channel.id)
            if (this.channels().length === 0) { ListItem() { Text('暂无匹配频道').fontSize(13).fontColor('#85858f').padding(24) } }
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        }
      }.width('100%').height('100%').backgroundColor('#121215')
        .bindSheet(this.sheetVisible, this.ChannelSheet(), {
          height: '75%', backgroundColor: '#19191f', showClose: false, dragBar: true,
          onDisappear: () => { this.sheetVisible = false; this.token++; this.tracksLoading = false }
        })
    }.hideTitleBar(true)
      .onBackPressed(() => { if (this.sheetVisible) { this.sheetVisible = false; return true }; return false })
  }
}
