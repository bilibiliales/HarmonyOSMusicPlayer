import { ResourceComments } from '../components/ResourceComments'
import { CommentResource } from '../models/CommentResource'
import { CommentService } from '../services/CommentService'
import { DjRadioItem } from '../models/api'
import { ProgramItem } from '../models/home'
import { RadioPageParam } from '../models/radio'
import { RadioService } from '../services/RadioService'
import { RadioPlayback } from '../services/RadioPlayback'
import { BubbleTip } from '../services/BubbleTip'
import { RadioProgramRow } from '../components/RadioCards'

@Component
export struct RadioDetailPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: RadioPageParam = { id: '' }
  @State commentsVisible: boolean = false
  @State commentCount: number = 0
  @State station?: DjRadioItem = undefined
  @State programs: ProgramItem[] = []
  @State loading: boolean = false
  @State more: boolean = true
  @State asc: boolean = false
  @State expanded: boolean = false
  @State playing: boolean = false
  @State message: string = ''
  @State detailMessage: string = ''
  private token: number = 0
  private alive: boolean = true
  private listOffset: number = 0

  aboutToAppear(): void { this.loadDetail(); this.loadPrograms(true); this.loadCommentSummary() }
  aboutToDisappear(): void { this.alive = false; this.token++ }

  private async loadDetail(): Promise<void> {
    this.detailMessage = ''
    try {
      const station = await RadioService.detail(this.pageParam.id)
      if (this.alive) { this.station = station }
    } catch (error) {
      if (this.alive) { this.detailMessage = error instanceof Error ? error.message : '详情加载失败' }
    }
  }

  private async loadPrograms(reset: boolean = false): Promise<void> {
    if (!reset && (this.loading || !this.more || this.message)) { return }
    const generation = ++this.token
    if (reset) { this.listOffset = 0; this.programs = []; this.more = true }
    this.loading = true
    this.message = ''
    try {
      const response = await RadioService.programs(this.pageParam.id, this.listOffset, this.asc)
      if (generation !== this.token) { return }
      const incoming = response.programs || []
      const added = incoming.filter((program: ProgramItem) => !this.programs.some((old: ProgramItem) => old.id === program.id))
      this.programs = this.programs.concat(added)
      this.listOffset += incoming.length
      this.more = (response.more ?? incoming.length >= RadioService.PAGE_SIZE) && added.length > 0
    } catch (error) {
      if (generation === this.token) { this.message = error instanceof Error ? error.message : '节目加载失败' }
    } finally { if (generation === this.token) { this.loading = false } }
  }

  private async play(index: number): Promise<void> {
    if (this.playing) { return }
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

  @Builder
  private Header() {
    Row({ space: 16 }) {
      Image(this.station?.picUrl || this.pageParam.cover || '').width(112).height(112).borderRadius(18).objectFit(ImageFit.Cover)
      Column({ space: 10 }) {
        Text(this.station?.name || this.pageParam.name || '电台').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#ffffff').maxLines(3)
        Text(this.station?.dj?.nickname || '').fontSize(13).fontColor('#aaaab5')
        Text(`${this.station?.programCount || 0} 期 · ${RadioService.count(this.station?.subCount)} 人订阅`)
          .fontSize(11).fontColor('#85858f')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ left: 17, right: 17, top: 20, bottom: 18 })
    if (this.detailMessage) {
      Text(this.detailMessage + ' · 点击重试').fontSize(12).fontColor('#ff6577').padding(17).onClick(() => this.loadDetail())
    }
    if (this.station?.desc) {
      Text(this.station.desc).width('100%').fontSize(13).lineHeight(22).fontColor('#aaaab5')
        .maxLines(this.expanded ? 1000 : 3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 17, right: 17 }).onClick(() => this.expanded = !this.expanded)
      Text(this.expanded ? '收起介绍' : '展开介绍').fontSize(11).fontColor('#ff6577').padding(12)
        .onClick(() => this.expanded = !this.expanded)
    }
    this.CommentEntry()
    Row() {
      Text(this.playing ? '准备播放…' : `播放全部 (${this.programs.length})`).fontSize(15).fontColor('#ffffff').layoutWeight(1)
        .enabled(!this.playing && this.programs.length > 0).onClick(() => this.play(0))
      Text(this.asc ? '最早优先' : '最新优先').fontSize(12).fontColor('#ff6577')
        .onClick(() => { this.asc = !this.asc; this.loadPrograms(true) })
    }.width('100%').padding(17)
  }


  private commentResource(): CommentResource {
    return { id: this.pageParam.id, type: 7, title: this.station?.name || this.pageParam.name || '' }
  }

  private async loadCommentSummary(): Promise<void> {
    try {
      const total = await CommentService.count(this.commentResource())
      if (this.alive) { this.commentCount = total }
    } catch (_error) {}
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
  private CommentEntry() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(19).fontColor(['#ffffff'])
      Text(`评论 · ${this.commentCount}`).fontSize(14).fontColor('#ededf0')
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor(['#85858f'])
    }.width('100%').height(46).padding({ left: 17, right: 17 })
      .onClick(() => this.commentsVisible = true)
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
          Text('电台详情').fontSize(18).fontColor('#ffffff')
        }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 17, top: this.topAvoidHeight })
        List() {
          ListItem() { Column() { this.Header() }.width('100%') }
          ForEach(this.programs, (program: ProgramItem, index: number) => {
            ListItem() { RadioProgramRow({ program: program, onPlay: () => this.play(index), onDetails: () => this.openProgram(program) }) }
          }, (program: ProgramItem) => String(program.id))
          ListItem() {
            Column({ space: 12 }) {
              if (this.loading) { LoadingProgress().width(30).height(30).color('#ef233c') }
              else if (this.message) {
                Text(this.message).fontColor('#ff6577').fontSize(13)
                Button('重试').backgroundColor('#303038').onClick(() => { this.message = ''; this.loadPrograms() })
              } else {
                Text(this.programs.length === 0 ? '暂无节目' : this.more ? '加载更多' : '已经到底了')
                  .fontColor('#85858f').fontSize(12).onClick(() => this.loadPrograms())
              }
            }.width('100%').padding(28)
          }
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).onReachEnd(() => this.loadPrograms())
      }.width('100%').height('100%').backgroundColor('#121215')
        .bindSheet(this.commentsVisible, this.CommentsSheet(), {
          height: '72%', backgroundColor: '#19191f', showClose: false, dragBar: true,
          onDisappear: () => this.commentsVisible = false
        })
    }.hideTitleBar(true)
  }
}

@Component
export struct RadioProgramPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: RadioPageParam = { id: '' }
  @State commentsVisible: boolean = false
  @State commentCount: number = 0
  @State program?: ProgramItem = undefined
  @State message: string = ''
  @State loading: boolean = true
  @State playing: boolean = false
  private alive: boolean = true

  aboutToAppear(): void { this.load(); this.loadCommentSummary() }
  aboutToDisappear(): void { this.alive = false }
  private async load(): Promise<void> {
    this.loading = true
    this.message = ''
    try {
      const program = await RadioService.program(this.pageParam.id)
      if (this.alive) { this.program = program }
    } catch (error) { if (this.alive) { this.message = error instanceof Error ? error.message : '节目加载失败' } }
    finally { if (this.alive) { this.loading = false } }
  }

  private async play(): Promise<void> {
    if (!this.program || this.playing) { return }
    this.playing = true
    try { await RadioPlayback.play([this.program]); this.pageStack.pushPathByName('PlayPage', null) }
    catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败') }
    finally { this.playing = false }
  }

  private openRadio(): void {
    if (!this.program?.radio?.id) { return }
    const param: RadioPageParam = { id: String(this.program.radio.id), name: this.program.radio.name, cover: this.program.radio.picUrl }
    this.pageStack.pushPathByName('RadioDetailPage', param)
  }


  private commentResource(): CommentResource {
    return { id: this.pageParam.id, type: 4, title: this.program?.name || this.pageParam.name || '' }
  }

  private async loadCommentSummary(): Promise<void> {
    try {
      const total = await CommentService.count(this.commentResource())
      if (this.alive) { this.commentCount = total }
    } catch (_error) {}
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
  private CommentEntry() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(19).fontColor(['#ffffff'])
      Text(`评论 · ${this.commentCount}`).fontSize(14).fontColor('#ededf0')
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor(['#85858f'])
    }.width('100%').height(46).padding({ left: 17, right: 17 })
      .onClick(() => this.commentsVisible = true)
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
          Text('节目详情').fontSize(18).fontColor('#ffffff')
        }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 17, top: this.topAvoidHeight })
        Scroll() {
          Column({ space: 20 }) {
            Image(this.program ? RadioService.cover(this.program) : this.pageParam.cover || '')
              .width(240).height(240).objectFit(ImageFit.Cover).borderRadius(20)
            Text(this.program?.name || this.pageParam.name || '电台节目').fontSize(23).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            if (this.loading) { LoadingProgress().width(35).height(35).color('#ef233c') }
            else if (this.message) {
              Text(this.message).fontSize(13).fontColor('#ff6577')
              Button('重试').backgroundColor('#303038').onClick(() => this.load())
            } else if (this.program) {
              Text(RadioService.author(this.program) + ' · ' + RadioService.duration(this.program.duration)).fontSize(13).fontColor('#9999a4')
              Button(this.playing ? '准备播放…' : '播放节目').backgroundColor('#ef233c').enabled(!this.playing).onClick(() => this.play())
              if (this.program.radio?.id) {
                Text('查看电台：' + (this.program.radio.name || '') + ' ›').fontSize(14).fontColor('#ff6577').onClick(() => this.openRadio())
              }
              this.CommentEntry()
              Text(this.program.description || '暂无节目介绍').width('100%').fontSize(15).lineHeight(26).fontColor('#bcbcc6')
            }
          }.width('100%').padding({ left: 22, right: 22, top: 20, bottom: 40 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').backgroundColor('#121215')
        .bindSheet(this.commentsVisible, this.CommentsSheet(), {
          height: '72%', backgroundColor: '#19191f', showClose: false, dragBar: true,
          onDisappear: () => this.commentsVisible = false
        })
    }.hideTitleBar(true)
  }
}
