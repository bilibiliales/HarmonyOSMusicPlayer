import { SheetSkinFrame } from '../components/SheetSkin'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { ResourceComments } from '../components/ResourceComments'
import { CommentResource } from '../models/CommentResource'
import { CommentService } from '../services/CommentService'
import { ApiUser, DjRadioItem, SharePageParam, UserProfilePageParam } from '../models/api'
import { ProgramItem } from '../models/home'
import { RadioPageParam } from '../models/radio'
import { RadioService } from '../services/RadioService'
import { RadioPlayback } from '../services/RadioPlayback'
import { PodcastService } from '../services/PodcastService'
import { AuthStore } from '../stores/AuthStore'
import { BubbleTip } from '../services/BubbleTip'
import { ProgramMenuRow } from '../components/RadioCards'
import { DetailTopBar } from '../components/DetailTopBar'
import { ShareSheet } from '../components/ShareSheet'
import { HeartLike } from '../components/HeartLike'
import { NoMoreFooter } from '../components/NoMoreFooter'
import { PlaylistCoverPreviewPageParam } from './PlaylistCoverPreview'
import { TC } from '../services/ThemeColors'

/** 播客详情：版式与专辑页一致——模糊头图 + 悬浮顶栏 + 吸附操作行 + 左对齐简介。 */
@Component
export struct RadioDetailPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') @Watch('subscriptionAuthChanged') authStore: AuthStore
  pageParam: RadioPageParam = { id: '' }
  @State commentsVisible: boolean = false
  @State commentCount: number = 0
  @State station?: DjRadioItem = undefined
  @State subscribed: boolean = false
  @State subscribing: boolean = false
  @State programs: ProgramItem[] = []
  @State loading: boolean = true
  @State more: boolean = true
  @State asc: boolean = false
  @State expanded: boolean = false
  @State playing: boolean = false
  @State message: string = ''
  @State scrollOffset: number = 0
  @State private frozen: boolean = false
  @State shareVisible: boolean = false
  @State shareParam: SharePageParam = { type: 'djradio', id: '', name: '', img: '' }
  private token: number = 0
  private detailToken: number = 0
  private alive: boolean = true
  private listOffset: number = 0
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.shareParam = { type: 'djradio', id: this.pageParam.id, name: this.pageParam.name || '',
      img: this.pageParam.cover || '' }
    this.loadDetail()
    this.loadPrograms(true)
    this.loadCommentSummary()
  }

  aboutToDisappear(): void { this.alive = false; this.token++; this.detailToken++ }

  private subscriptionAuthChanged(): void { if (this.alive) { this.loadDetail() } }

  private stationName(): string { return this.station?.name || this.pageParam.name || '播客' }
  private stationCover(): string { return this.station?.picUrl || this.pageParam.cover || '' }
  private authorUser(): ApiUser | undefined { return this.station?.dj || this.station?.creator }
  private authorName(): string { return this.authorUser()?.nickname || '' }
  private authorId(): string { return String(this.authorUser()?.userId || '') }

  private async loadDetail(): Promise<void> {
    const token = ++this.detailToken
    const owner = this.authStore.userId
    try {
      const station = await RadioService.detail(this.pageParam.id)
      if (this.alive && token === this.detailToken && owner === this.authStore.userId) {
        this.station = station
        this.subscribed = !!station.subed
        this.shareParam = { type: 'djradio', id: this.pageParam.id, name: station.name,
          img: station.picUrl || '', author: station.dj?.nickname || station.creator?.nickname || '' }
      }
    } catch (error) {
      if (this.alive && token === this.detailToken) {
        this.message = error instanceof Error ? error.message : '详情加载失败'
      }
    }
  }

  private async loadPrograms(reset: boolean = false): Promise<void> {
    if (!reset && (this.loading || !this.more)) { return }
    const generation = ++this.token
    if (reset) { this.listOffset = 0; this.programs = []; this.more = true }
    this.loading = true
    try {
      const response = await RadioService.programs(this.pageParam.id, this.listOffset, this.asc)
      if (generation !== this.token || !this.alive) { return }
      const incoming = response.programs || []
      const added = incoming.filter((program: ProgramItem) =>
        !this.programs.some((old: ProgramItem) => old.id === program.id))
      this.programs = this.programs.concat(added)
      this.listOffset += incoming.length
      this.more = (response.more ?? incoming.length >= RadioService.PAGE_SIZE) && added.length > 0
    } catch (error) {
      if (generation === this.token) { this.message = error instanceof Error ? error.message : '节目加载失败' }
    } finally { if (generation === this.token) { this.loading = false } }
  }

  private async play(index: number): Promise<void> {
    if (this.playing || this.programs.length === 0) { return }
    this.playing = true
    try {
      await RadioPlayback.play(this.programs, index)
      this.pageStack.pushPathByName('PlayPage', null)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败') }
    finally { this.playing = false }
  }

  private openProgram(program: ProgramItem): void {
    const param: RadioPageParam = { id: String(program.id), name: program.name, cover: RadioService.cover(program) }
    this.pageStack.pushPathByName('RadioProgramPage', param)
  }

  private shareProgram(program: ProgramItem): void {
    this.shareParam = { type: 'program', id: String(program.id), name: program.name,
      img: RadioService.cover(program), author: RadioService.author(program) }
    this.shareVisible = true
  }

  private openUser(uid: string): void {
    if (!uid || uid === '0') { return }
    const param: UserProfilePageParam = { uid: uid }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private previewTags(): string[] {
    const tags: string[] = []
    const category = `${this.station?.category ?? ''}`
    const second = `${this.station?.secondCategory ?? ''}`
    if (category.length > 0 && category !== '0') { tags.push(category) }
    if (second.length > 0 && second !== '0') { tags.push(second) }
    return tags
  }

  private previewCover(): void {
    if (this.stationCover().length === 0) { return }
    const param: PlaylistCoverPreviewPageParam = {
      playlist: { id: this.pageParam.id, name: this.stationName(), cover: this.stationCover(),
        count: this.station?.programCount || 0, creator: this.authorName() },
      playCount: this.station?.playCount || 0,
      collectCount: this.station?.subCount || 0,
      commentCount: this.commentCount,
      tags: this.previewTags(),
      description: this.station?.desc || '',
      contentType: 'podcast'
    }
    this.pageStack.pushPathByName('PlaylistCoverPreviewPage', param)
  }

  private async toggleSubscription(): Promise<void> {
    if (!this.authStore.loggedIn) { this.pageStack.pushPathByName('LoginPage', null); return }
    if (this.subscribing || !this.station) { return }
    const owner = this.authStore.userId
    const subscribed = !this.subscribed
    this.subscribing = true
    try {
      await PodcastService.subscribe(this.pageParam.id, subscribed)
      if (this.alive && owner === this.authStore.userId && this.authStore.loggedIn) {
        this.subscribed = subscribed
        if (this.station) {
          this.station.subed = subscribed
          this.station.subCount = Math.max(0, this.station.subCount + (subscribed ? 1 : -1))
        }
      }
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '订阅失败') }
    finally { this.subscribing = false }
  }

  private commentResource(): CommentResource {
    return { id: this.pageParam.id, type: 7, title: this.stationName() }
  }

  private async loadCommentSummary(): Promise<void> {
    try {
      const total = await CommentService.count(this.commentResource())
      if (this.alive) { this.commentCount = total }
    } catch (_error) {}
  }

  private formatCount(value: number): string { return RadioService.count(value) }

  private actionBarBaseY(): number { return 320 + this.topAvoidHeight }
  private freezeThreshold(): number { return this.actionBarBaseY() - this.topAvoidHeight - 54 }

  @Builder
  private skin_CommentsSheet() {
    SheetSkinFrame() {
      this.CommentsSheet()
    }
  }

  @Builder
  private CommentsSheet() {
    ResourceComments({
      resource: this.commentResource(),
      onClose: () => this.commentsVisible = false,
      onCountChange: (total: number) => this.commentCount = total
    })
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: this.shareParam, visible: true, onClose: () => this.shareVisible = false })
  }

  @Builder
  private ActionBar() {
    Row({ space: 10 }) {
      Button() {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(14).fontColor([TC.textOnAccent()])
          Text(this.playing ? '准备播放…' : `播放全部${this.programs.length > 0 ? ` (${this.programs.length})` : ''}`)
            .fontSize(13).fontColor(TC.textOnAccent()).fontWeight(FontWeight.Medium).maxLines(1)
        }
      }
      .layoutWeight(1)
      .height(38)
      .backgroundColor(TC.accent())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .enabled(!this.playing && this.programs.length > 0)
      .onClick(() => this.play(0))

      Button() {
        Row({ space: 4 }) {
          HeartLike({ liked: this.subscribed, iconSize: 14, iconColor: this.subscribed ? TC.accent() : TC.textPrimary() })
          Text(this.subscribed ? '已订阅' : '订阅')
            .fontSize(12).fontColor(this.subscribed ? TC.accent() : TC.textPrimary())
        }
      }
      .height(38)
      .backgroundColor(this.subscribed ? 'rgba(239,35,60,0.12)' : TC.surfaceInset())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .padding({ left: 12, right: 12 })
      .enabled(!this.subscribing && !!this.station)
      .onClick(() => this.toggleSubscription())

      Button() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(14).fontColor([TC.textBody()])
          Text(this.formatCount(this.commentCount)).fontSize(11).fontColor(TC.textBody())
        }
      }
      .height(38)
      .backgroundColor(TC.surfaceRaised())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .padding({ left: 12, right: 12 })
      .onClick(() => this.commentsVisible = true)

      Button() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.share')).fontSize(14).fontColor([TC.textBody()])
          Text('分享').fontSize(11).fontColor(TC.textBody())
        }
      }
      .height(38)
      .backgroundColor(TC.surfaceRaised())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .padding({ left: 12, right: 12 })
      .onClick(() => this.shareVisible = true)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  private FlowActionBar() {
    Column() { this.ActionBar() }.width('100%').opacity(this.frozen ? 0 : 1)
  }

  @Builder
  private FrozenActionBar() {
    Column() { this.ActionBar() }
      .width('100%')
      .backgroundColor(Color.Transparent)
      .backdropBlur(30)
      .position({ x: 0, y: this.topAvoidHeight + 54 })
      .zIndex(3)
  }

  @Builder
  private Header() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image(this.stationCover()).width('100%').height(320 + this.topAvoidHeight)
        .objectFit(ImageFit.Cover).blur(60).opacity(0.4)
      Column().width('100%').height(320 + this.topAvoidHeight)
        .linearGradient({ angle: 180, colors: [['#00000000', 0], [TC.pageBackground(), 1]] })
      Row({ space: 16 }) {
        Image(this.stationCover()).width(120).height(120).borderRadius(12).objectFit(ImageFit.Cover)
          .shadow({ radius: 16, color: 'rgba(0,0,0,0.35)', offsetY: 4 })
          .onClick(() => this.previewCover())
        Column({ space: 6 }) {
          Text(this.stationName()).fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.authorName().length > 0) {
            Text(this.authorName()).fontSize(12).fontColor(TC.textBody()).maxLines(1)
              .onClick(() => this.openUser(this.authorId()))
          }
          Text(`${this.station?.programCount || 0} 期 · ${this.formatCount(this.station?.subCount || 0)} 人订阅`)
            .fontSize(10).fontColor(TC.textTertiary())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 20 })
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .height(320 + this.topAvoidHeight)
    .alignContent(Alignment.Bottom)
  }

  @Builder
  private Description() {
    if ((this.station?.desc || '').length > 0) {
      Column() {
        Text(this.station?.desc || '')
          .fontSize(12).fontColor(TC.textSecondary()).lineHeight(18)
          .maxLines(this.expanded ? 100 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ minHeight: this.expanded ? 0 : 54 })
          .width('100%')
          .textAlign(TextAlign.Start)
        if ((this.station?.desc || '').length > 78) {
          Text(this.expanded ? '收起' : '展开').fontSize(11).fontColor(TC.accent())
            .margin({ top: 4 })
            .onClick(() => this.expanded = !this.expanded)
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 4, bottom: 8 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      if (this.loading && this.programs.length === 0 && !this.station) {
        Column() { LoadingProgress().width(42).height(42).color(TC.accent()) }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Scroll(this.scroller) {
            Column() {
              this.Header()
              this.FlowActionBar()
              this.Description()

              Row() {
                Text(`声音 ${this.station?.programCount || this.programs.length}`)
                  .fontSize(13).fontColor(TC.textPrimary()).fontWeight(FontWeight.Medium)
                Text(this.asc ? '最早优先' : '最新优先')
                  .fontSize(11).fontColor(TC.accentSoft()).layoutWeight(1).textAlign(TextAlign.End)
                  .onClick(() => { this.asc = !this.asc; this.loadPrograms(true) })
              }
              .width('100%')
              .padding({ left: 18, right: 18, top: 8, bottom: 4 })

              List({ space: 0 }) {
                ForEach(this.programs, (program: ProgramItem, index: number) => {
                  ListItem() {
                    ProgramMenuRow({ program: program, index: index + 1,
                      onPlay: () => this.play(index),
                      onDetail: () => this.openProgram(program),
                      onShare: () => this.shareProgram(program) })
                  }
                }, (program: ProgramItem) => String(program.id))
              }
              .width('100%')

              Column({ space: 10 }) {
                if (this.loading) {
                  LoadingProgress().width(30).height(30).color(TC.accent())
                } else if (this.message.length > 0) {
                  Text(this.message).fontSize(12).fontColor(TC.accentSoft())
                  Button('重试').fontSize(12).backgroundColor(TC.surfaceRaised()).fontColor(TC.textBody())
                    .onClick(() => { this.message = ''; this.loadPrograms() })
                } else if (this.programs.length === 0) {
                  Text('暂无声音').fontSize(12).fontColor(TC.textTertiary())
                } else {
                  NoMoreFooter()
                }
              }
              .width('100%').padding({ top: 12, bottom: 40 })
            }
            .width('100%')
            .constraintSize({ minHeight: '100%' })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .onDidScroll(() => {
            const y = this.scroller.currentOffset().yOffset
            const barOffset = y > 170 ? 170 : y
            if (barOffset !== this.scrollOffset) { this.scrollOffset = barOffset }
            const f = y >= this.freezeThreshold()
            if (f !== this.frozen) { this.frozen = f }
          })
          .onReachEnd(() => this.loadPrograms())

          DetailTopBar({
            title: this.stationName(),
            scrollOffset: this.scrollOffset,
            onShare: () => this.shareVisible = true
          })
          if (this.frozen) {
            this.FrozenActionBar()
          }
          // 分享面板内联在页面上：节目行菜单里点分享时，弹出的模态会被菜单收起动作吞掉。
          if (this.shareVisible) {
            this.ShareOptions()
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet(this.commentsVisible, this.skin_CommentsSheet(), {
          height: '72%', backgroundColor: TC.sheetBackground(), showClose: false, dragBar: true,
          onDisappear: () => this.commentsVisible = false
        })
      }
    }.hideTitleBar(true).backgroundColor(TC.pageBackground())
  }
}

/** 节目详情：与播客详情同一套头部、操作行与封面预览。 */
@Component
export struct RadioProgramPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: RadioPageParam = { id: '' }
  @State commentsVisible: boolean = false
  @State commentCount: number = 0
  @State program?: ProgramItem = undefined
  @State message: string = ''
  @State loading: boolean = true
  @State playing: boolean = false
  @State expanded: boolean = false
  @State scrollOffset: number = 0
  @State private frozen: boolean = false
  @State shareVisible: boolean = false
  @State shareParam: SharePageParam = { type: 'program', id: '', name: '', img: '' }
  private alive: boolean = true
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.shareParam = { type: 'program', id: this.pageParam.id, name: this.pageParam.name || '',
      img: this.pageParam.cover || '' }
    this.load()
    this.loadCommentSummary()
  }

  aboutToDisappear(): void { this.alive = false }

  private title(): string { return this.program?.name || this.pageParam.name || '节目' }
  private cover(): string { return this.program ? RadioService.cover(this.program) : (this.pageParam.cover || '') }
  private authorName(): string { return this.program ? RadioService.author(this.program) : '' }
  private authorId(): string { return String(this.program?.dj?.userId || '') }

  private async load(): Promise<void> {
    this.loading = true
    this.message = ''
    try {
      const program = await RadioService.program(this.pageParam.id)
      if (this.alive) {
        this.program = program
        this.shareParam = { type: 'program', id: this.pageParam.id, name: program.name,
          img: RadioService.cover(program), author: RadioService.author(program) }
      }
    } catch (error) {
      if (this.alive) { this.message = error instanceof Error ? error.message : '节目加载失败' }
    } finally { if (this.alive) { this.loading = false } }
  }

  private async play(): Promise<void> {
    if (!this.program || this.playing) { return }
    this.playing = true
    try {
      await RadioPlayback.play([this.program])
      this.pageStack.pushPathByName('PlayPage', null)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败') }
    finally { this.playing = false }
  }

  private openRadio(): void {
    const radio = this.program?.radio
    if (!radio?.id) { return }
    const param: RadioPageParam = { id: String(radio.id), name: radio.name, cover: radio.picUrl }
    this.pageStack.pushPathByName('RadioDetailPage', param)
  }

  private openUser(uid: string): void {
    if (!uid || uid === '0') { return }
    const param: UserProfilePageParam = { uid: uid }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private previewTags(): string[] {
    const name = this.program?.radio?.name
    return name ? [name] : []
  }

  private previewCover(): void {
    if (this.cover().length === 0) { return }
    const param: PlaylistCoverPreviewPageParam = {
      playlist: { id: this.pageParam.id, name: this.title(), cover: this.cover(),
        count: 1, creator: this.authorName() },
      playCount: this.program?.listenerCount || 0,
      collectCount: this.program?.likedCount || 0,
      commentCount: this.commentCount,
      tags: this.previewTags(),
      description: this.program?.description || '',
      contentType: 'program'
    }
    this.pageStack.pushPathByName('PlaylistCoverPreviewPage', param)
  }

  private commentResource(): CommentResource {
    return { id: this.pageParam.id, type: 4, title: this.title() }
  }

  private async loadCommentSummary(): Promise<void> {
    try {
      const total = await CommentService.count(this.commentResource())
      if (this.alive) { this.commentCount = total }
    } catch (_error) {}
  }

  private actionBarBaseY(): number { return 320 + this.topAvoidHeight }
  private freezeThreshold(): number { return this.actionBarBaseY() - this.topAvoidHeight - 54 }

  @Builder
  private skin_CommentsSheet() {
    SheetSkinFrame() {
      this.CommentsSheet()
    }
  }

  @Builder
  private CommentsSheet() {
    ResourceComments({
      resource: this.commentResource(),
      onClose: () => this.commentsVisible = false,
      onCountChange: (total: number) => this.commentCount = total
    })
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: this.shareParam, visible: true, onClose: () => this.shareVisible = false })
  }

  @Builder
  private ActionBar() {
    Row({ space: 10 }) {
      Button() {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(14).fontColor([TC.textOnAccent()])
          Text(this.playing ? '准备播放…' : '播放节目')
            .fontSize(13).fontColor(TC.textOnAccent()).fontWeight(FontWeight.Medium)
        }
      }
      .layoutWeight(1)
      .height(38)
      .backgroundColor(TC.accent())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .enabled(!this.playing && !!this.program)
      .onClick(() => this.play())

      Button() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(14).fontColor([TC.textBody()])
          Text(String(this.commentCount)).fontSize(11).fontColor(TC.textBody())
        }
      }
      .height(38)
      .backgroundColor(TC.surfaceRaised())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .padding({ left: 12, right: 12 })
      .onClick(() => this.commentsVisible = true)

      Button() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.share')).fontSize(14).fontColor([TC.textBody()])
          Text('分享').fontSize(11).fontColor(TC.textBody())
        }
      }
      .height(38)
      .backgroundColor(TC.surfaceRaised())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .padding({ left: 12, right: 12 })
      .onClick(() => this.shareVisible = true)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  private FlowActionBar() {
    Column() { this.ActionBar() }.width('100%').opacity(this.frozen ? 0 : 1)
  }

  @Builder
  private FrozenActionBar() {
    Column() { this.ActionBar() }
      .width('100%')
      .backgroundColor(Color.Transparent)
      .backdropBlur(30)
      .position({ x: 0, y: this.topAvoidHeight + 54 })
      .zIndex(3)
  }

  @Builder
  private Header() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image(this.cover()).width('100%').height(320 + this.topAvoidHeight)
        .objectFit(ImageFit.Cover).blur(60).opacity(0.4)
      Column().width('100%').height(320 + this.topAvoidHeight)
        .linearGradient({ angle: 180, colors: [['#00000000', 0], [TC.pageBackground(), 1]] })
      Row({ space: 16 }) {
        Image(this.cover()).width(120).height(120).borderRadius(12).objectFit(ImageFit.Cover)
          .shadow({ radius: 16, color: 'rgba(0,0,0,0.35)', offsetY: 4 })
          .onClick(() => this.previewCover())
        Column({ space: 6 }) {
          Text(this.title()).fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.authorName().length > 0) {
            Text(this.authorName()).fontSize(12).fontColor(TC.textBody()).maxLines(1)
              .onClick(() => this.openUser(this.authorId()))
          }
          if (this.program?.radio?.name) {
            Text(`来自「${this.program?.radio?.name || ''}」`)
              .fontSize(10).fontColor(TC.accentSoft()).maxLines(1)
              .onClick(() => this.openRadio())
          }
          Text(`${RadioService.duration(this.program?.duration || 0)} · ${RadioService.count(this.program?.listenerCount || 0)} 次收听`)
            .fontSize(10).fontColor(TC.textTertiary())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 20 })
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .height(320 + this.topAvoidHeight)
    .alignContent(Alignment.Bottom)
  }

  @Builder
  private Description() {
    if ((this.program?.description || '').length > 0) {
      Column() {
        Text(this.program?.description || '')
          .fontSize(12).fontColor(TC.textSecondary()).lineHeight(18)
          .maxLines(this.expanded ? 100 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ minHeight: this.expanded ? 0 : 54 })
          .width('100%')
          .textAlign(TextAlign.Start)
        if ((this.program?.description || '').length > 78) {
          Text(this.expanded ? '收起' : '展开').fontSize(11).fontColor(TC.accent())
            .margin({ top: 4 })
            .onClick(() => this.expanded = !this.expanded)
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 4, bottom: 8 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      if (this.loading && !this.program) {
        Column() { LoadingProgress().width(42).height(42).color(TC.accent()) }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.message.length > 0 && !this.program) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(38).fontColor([TC.textQuaternary()])
          Text(this.message).fontSize(13).fontColor(TC.textTertiary())
          Button('重试').fontSize(12).backgroundColor(TC.surfaceRaised()).fontColor(TC.textBody())
            .onClick(() => this.load())
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Scroll(this.scroller) {
            Column() {
              this.Header()
              this.FlowActionBar()
              this.Description()
              NoMoreFooter()
            }
            .width('100%')
            .constraintSize({ minHeight: '100%' })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .onDidScroll(() => {
            const y = this.scroller.currentOffset().yOffset
            const barOffset = y > 170 ? 170 : y
            if (barOffset !== this.scrollOffset) { this.scrollOffset = barOffset }
            const f = y >= this.freezeThreshold()
            if (f !== this.frozen) { this.frozen = f }
          })

          DetailTopBar({
            title: this.title(),
            scrollOffset: this.scrollOffset,
            onShare: () => this.shareVisible = true
          })
          if (this.frozen) {
            this.FrozenActionBar()
          }
          // 分享面板内联在页面上：节目行菜单里点分享时，弹出的模态会被菜单收起动作吞掉。
          if (this.shareVisible) {
            this.ShareOptions()
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet(this.commentsVisible, this.skin_CommentsSheet(), {
          height: '72%', backgroundColor: TC.sheetBackground(), showClose: false, dragBar: true,
          onDisappear: () => this.commentsVisible = false
        })
      }
    }.hideTitleBar(true).backgroundColor(TC.pageBackground())
  }
}
