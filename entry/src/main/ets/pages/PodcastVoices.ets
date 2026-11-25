import { SkinBackdrop } from '../components/SkinBackdrop'
import { SheetSkinFrame } from '../components/SheetSkin'
import { ShareSheet } from '../components/ShareSheet'
import { SharePageParam } from '../models/api'
import { PodcastVoice, PodcastVoicesParam } from '../models/podcast'
import { AuthStore } from '../stores/AuthStore'
import { PodcastService } from '../services/PodcastService'
import { RadioService } from '../services/RadioService'
import { RadioPlayback } from '../services/RadioPlayback'
import { VoiceUploadParam } from '../services/VoiceUploadService'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'

@Component
export struct PodcastVoicesPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @StorageProp(PodcastService.REVISION_KEY) @Watch('refresh') revision: number = 0
  pageParam: PodcastVoicesParam = { list: { voiceListId: '', voiceListName: '' }, owner: '' }
  @State voices: PodcastVoice[] = []
  @State status: string = ''
  @State query: string = ''
  @State loading: boolean = false
  @State more: boolean = true
  @State message: string = ''
  @State playing: boolean = false
  @State sorting: boolean = false
  @State detailsVisible: boolean = false
  @State details?: PodcastVoice = undefined
  @State detailsLoading: boolean = false
  @State detailsMessage: string = ''
  @State sharing: boolean = false
  @State shareParam: SharePageParam = { type: 'program', id: '', name: '', img: '' }
  private listOffset: number = 0
  private requestId: number = 0
  private detailRequestId: number = 0
  private alive: boolean = true
  private readonly statuses: string[] = ['', 'ONLINE', 'AUDITING', 'ONLY_SELF_SEE', 'SCHEDULE_PUBLISH', 'FAILED', 'TRANSCODE_FAILED', 'PUBLISHING']

  aboutToAppear(): void { this.alive = true; this.load(true) }
  aboutToDisappear(): void { this.alive = false; this.requestId++; this.detailRequestId++ }
  private owned(): boolean { return this.authStore.loggedIn && this.authStore.userId === this.pageParam.owner }
  private refresh(): void { if (this.alive) { this.load(true) } }

  private async load(reset: boolean = false): Promise<void> {
    if (!this.alive || (!reset && (this.loading || !this.more))) { return }
    const request = ++this.requestId
    if (!this.owned()) { this.voices = []; this.message = '请登录该播客所属账号'; this.loading = false; return }
    if (reset) { this.listOffset = 0; this.voices = []; this.more = true }
    this.loading = true
    this.message = ''
    const offset = this.listOffset
    try {
      const page = await PodcastService.voices(String(this.pageParam.list.voiceListId), offset, this.status, this.query)
      if (request !== this.requestId || !this.alive || !this.owned()) { return }
      const added = page.items.filter((voice: PodcastVoice) => !!PodcastService.voiceId(voice) &&
        !this.voices.some((old: PodcastVoice) => PodcastService.voiceId(old) === PodcastService.voiceId(voice)))
      this.voices = this.voices.concat(added)
      this.listOffset = offset + page.items.length
      this.more = page.more && added.length > 0
    } catch (error) {
      if (request === this.requestId && this.owned()) { this.message = error instanceof Error ? error.message : '声音加载失败' }
    } finally { if (request === this.requestId) { this.loading = false } }
  }

  /** 状态筛选只换数据，不做整页切换动画。 */
  private switchStatus(status: string): void {
    if (status === this.status) { return }
    this.status = status
    this.load(true)
  }

  private async play(voice: PodcastVoice): Promise<void> {
    if (!this.owned() || this.playing) { return }
    this.playing = true
    try {
      const program = await RadioService.program(PodcastService.voiceId(voice))
      if (!this.owned() || !this.alive) { return }
      await RadioPlayback.play([program])
      if (this.alive && this.owned()) { this.pageStack.pushPathByName('PlayPage', null) }
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '声音暂时无法播放') }
    finally { this.playing = false }
  }

  private async showDetails(voice: PodcastVoice): Promise<void> {
    if (!this.owned()) { return }
    const request = ++this.detailRequestId
    this.details = voice
    this.detailsMessage = ''
    this.detailsVisible = true
    this.detailsLoading = true
    try {
      const detail = await PodcastService.voice(PodcastService.voiceId(voice))
      if (request === this.detailRequestId && this.alive && this.owned()) { this.details = detail }
    } catch (error) {
      if (request === this.detailRequestId) { this.detailsMessage = error instanceof Error ? error.message : '详情加载失败' }
    } finally { if (request === this.detailRequestId) { this.detailsLoading = false } }
  }

  private async moveToTop(voice: PodcastVoice): Promise<void> {
    if (!this.owned() || this.sorting) { return }
    this.sorting = true
    try { await PodcastService.moveToTop(PodcastService.voiceId(voice), String(this.pageParam.list.voiceListId)) }
    catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '排序失败') }
    finally { this.sorting = false }
  }

  private shareVoice(voice: PodcastVoice): void {
    const id = PodcastService.voiceId(voice)
    if (!id) { return }
    this.shareParam = { type: 'program', id: id, name: PodcastService.voiceName(voice),
      img: voice.coverUrl || this.pageParam.list.coverUrl || '',
      author: this.pageParam.list.voiceListName }
    this.sharing = true
  }

  private options(voice: PodcastVoice): MenuElement[] {
    return [{ value: '播放节目', action: () => { this.play(voice) } },
      { value: '查看详情', action: () => { this.showDetails(voice) } },
      { value: '分享', action: () => { this.shareVoice(voice) } },
      { value: '移到播客第一位', action: () => { this.moveToTop(voice) } }]
  }

  private publish(): void {
    if (!this.owned()) { return }
    const param: VoiceUploadParam = { voiceListId: String(this.pageParam.list.voiceListId) }
    this.pageStack.pushPathByName('VoiceUploadPage', param)
  }

  @Builder
  private DetailsSheet() {
    SheetSkinFrame() {
      Column({ space: 14 }) {
        Text(this.details ? PodcastService.voiceName(this.details) : '声音详情').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        if (this.detailsLoading) { LoadingProgress().width(32).height(32).color(TC.accent()) }
        Text(PodcastService.status(this.details?.displayStatus)).fontSize(13).fontColor(TC.accentSoft())
        if (this.detailsMessage) { Text(this.detailsMessage).fontSize(12).fontColor(TC.textTertiary()) }
        Scroll() { Text(this.details?.description || '暂无声音介绍').fontSize(14).lineHeight(22).fontColor(TC.textBody()).width('100%') }
          .width('100%').layoutWeight(1)
        Button('关闭').fontColor(TC.textBody()).backgroundColor(TC.surfaceRaised()).onClick(() => this.detailsVisible = false)
      }.width('100%').height('100%').padding(22)
    }
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: this.shareParam, visible: true, onClose: () => this.sharing = false })
  }

  @Builder
  private VoicesList() {
    List() {
      ForEach(this.voices, (voice: PodcastVoice) => {
        ListItem() {
          Row({ space: 12 }) {
            Image(voice.coverUrl || this.pageParam.list.coverUrl || '').width(54).height(54).borderRadius(10).objectFit(ImageFit.Cover)
            Column({ space: 5 }) {
              Text(PodcastService.voiceName(voice)).fontSize(14).fontColor(TC.textBody()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(PodcastService.status(voice.displayStatus) + (voice.duration ? ' · ' + RadioService.duration(voice.duration) : ''))
                .fontSize(11).fontColor(TC.textTertiary())
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (voice.displayStatus === 'ONLINE' || voice.displayStatus === 'ONLY_SELF_SEE') {
              SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(25).fontColor([TC.accentSoft()])
                .width(36).height(40).enabled(!this.playing).onClick(() => this.play(voice))
            }
            SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(20).fontColor([TC.textTertiary()])
              .width(28).height(40).enabled(!this.sorting).bindMenu(this.options(voice))
          }.width('100%').height(78).padding({ left: 16, right: 16 }).onClick(() => this.showDetails(voice))
        }
      }, (voice: PodcastVoice) => PodcastService.voiceId(voice))
      ListItem() {
        Column({ space: 12 }) {
          if (this.loading) { LoadingProgress().width(30).height(30).color(TC.accent()) }
          else if (this.message) {
            Text(this.message).fontSize(12).fontColor(TC.accentSoft())
            Button('重试').fontSize(12).onClick(() => this.load(this.voices.length === 0))
          } else {
            Text(this.voices.length === 0 ? '暂无符合条件的声音' : this.more ? '加载更多' : '已经到底了')
              .fontSize(12).fontColor(TC.textTertiary()).onClick(() => this.load())
          }
        }.width('100%').padding({ top: 24, bottom: 44 })
      }
    }.width('100%').height('100%').scrollBar(BarState.Off).onReachEnd(() => this.load())
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()]).onClick(() => this.pageStack.pop())
          Text(this.pageParam.list.voiceListName).layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary()).maxLines(1)
          Text('发布声音').fontSize(13).fontColor(TC.accentSoft()).onClick(() => this.publish())
        }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 16, right: 16, top: this.topAvoidHeight })
        Text('声音是播客中的单集；审核或定时发布中的声音会在这里显示状态。')
          .width('100%').fontSize(11).lineHeight(18).fontColor(TC.textTertiary()).padding({ left: 16, right: 16, bottom: 8 })
        Search({ value: this.query, placeholder: '搜索这个播客的声音' }).fontColor(TC.textBody()).backgroundColor(TC.surfaceRaised())
          .margin({ left: 16, right: 16 }).onChange((query: string) => this.query = query).onSubmit(() => this.load(true))
        Scroll() {
          Row({ space: 20 }) {
            ForEach(this.statuses, (status: string) => {
              Text(status ? PodcastService.status(status) : '全部').fontSize(13)
                .fontWeight(this.status === status ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.status === status ? TC.accentSoft() : TC.textTertiary()).onClick(() => this.switchStatus(status))
            }, (status: string) => status)
          }.padding({ left: 16, right: 16 })
        }.width('100%').height(48).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        Row() {
          Text(`${this.voices.length} 个声音`).layoutWeight(1).fontSize(12).fontColor(TC.textTertiary())
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(18).fontColor([TC.textSecondary()]).onClick(() => this.load(true))
        }.width('100%').height(36).padding({ left: 16, right: 16 })
        Column() {
          this.VoicesList()
        }.width('100%').layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
        .bindSheet(this.detailsVisible, this.DetailsSheet(), { height: '55%', showClose: false,
          backgroundColor: TC.sheetBackground(), onDisappear: () => { this.detailsVisible = false; this.detailRequestId++ } })
      // 分享面板直接铺在页面上：列表菜单里点分享时，弹出的半模态/全屏模态会被菜单收起动作吞掉。
      if (this.sharing) { this.ShareOptions() }
      }.width('100%').height('100%')
    }.hideTitleBar(true).onShown(() => this.load(true))
  }
}
