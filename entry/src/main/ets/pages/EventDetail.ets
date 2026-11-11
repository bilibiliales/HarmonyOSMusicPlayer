import { ShareSheet } from '../components/ShareSheet'
import { DetailTopBar } from '../components/DetailTopBar'
import { NoMoreFooter } from '../components/NoMoreFooter'
import { EventImages } from '../components/EventImages'
import { ResourceComments } from '../components/ResourceComments'
import { CommentResource } from '../models/CommentResource'
import { EventPresentation, EventResourceView } from '../services/EventPresentation'
import {
  EventDetailPageParam,
  EventForwardData,
  EventJsonData,
  LikeListResponse,
  mapApiSong,
  MvPlayerPageParam,
  OperationResponse,
  UserEventItem
} from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { UserProfilePageParam } from '../models/api'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'

@Component
export struct EventDetailPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @Consume('playerStore') playerStore: PlayerStore
  pageParam: EventDetailPageParam = {
    event: {
      id: 0,
      json: '',
      user: { userId: 0, nickname: '', avatarUrl: '', followed: false, mutual: false },
      info: { commentCount: 0, likedCount: 0, shareCount: 0 }
    }
  }

  @State event: UserEventItem = this.pageParam.event
  @State commentSheetVisible: boolean = false
  @State commentType: number = 6
  @State shareVisible: boolean = false
  @State songLiked: boolean = false
  @State eventLikeBusy: boolean = false
  @State deletingEvent: boolean = false
  @State scrollOffset: number = 0
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.event = this.pageParam.event
    this.loadSongLikedState()
    if (this.pageParam.openComments) { this.openEventComments() }
  }


  private data(): EventJsonData {
    try {
      return JSON.parse(this.event.json) as EventJsonData
    } catch (_error) {
      return { msg: '' }
    }
  }

  private content(): string {
    const data = this.data()
    return data.msg || data.title || this.event.actName || '分享了一条音乐动态'
  }

  private sourceEvent(): EventForwardData | null {
    return this.data().event || null
  }

  private sourceData(source: EventForwardData): EventJsonData {
    try {
      return JSON.parse(source.json || '') as EventJsonData
    } catch (_error) {
      return { msg: '' }
    }
  }

  private sourceContent(source: EventForwardData): string {
    const data = this.sourceData(source)
    return data.msg || data.title || source.actName || '源动态'
  }

  private sourceResourceTitle(source: EventForwardData): string {
    const data = this.sourceData(source)
    return data.song?.name || data.playlist?.name || data.album?.name || data.mv?.name || data.video?.title ||
      data.program?.name || data.djRadio?.name || data.resource?.name || data.resource?.title || ''
  }

  private sourceResourceSubtitle(source: EventForwardData): string {
    const data = this.sourceData(source)
    if (data.song) {
      return (data.song.ar || data.song.artists || []).map((artist) => artist.name).join(' / ')
    }
    return data.playlist?.creator?.nickname || data.album?.artist?.name || data.mv?.artistName ||
      data.video?.creator?.nickname || data.program?.description || data.djRadio?.description ||
      data.resource?.description || ''
  }

  private sourceResourceImage(source: EventForwardData): string {
    const data = this.sourceData(source)
    return data.song?.al?.picUrl || data.song?.album?.picUrl || data.song?.picUrl ||
      data.playlist?.coverImgUrl || data.playlist?.picUrl || data.album?.picUrl ||
      data.mv?.imgurl16v9 || data.mv?.imgurl || data.video?.coverUrl || data.program?.picUrl ||
      data.djRadio?.picUrl || data.resource?.picUrl || data.resource?.coverUrl || ''
  }

  private sourceResourceKind(source: EventForwardData): string {
    const data = this.sourceData(source)
    if (data.song) return '歌曲'
    if (data.playlist) return '歌单'
    if (data.album) return '专辑'
    if (data.mv) return 'MV'
    if (data.video) return '视频'
    if (data.program) return '播客节目'
    if (data.djRadio) return '播客'
    return data.resource ? '分享内容' : ''
  }

  private openSourceEvent(source: EventForwardData): void {
    if (!source.id) {
      return
    }
    const sourceItem: UserEventItem = {
      id: source.id,
      type: source.type,
      eventTime: source.eventTime,
      showTime: source.showTime,
      json: source.json || '',
      user: source.user || { userId: 0, nickname: '', avatarUrl: '', followed: false, mutual: false },
      info: source.info || { commentCount: 0, likedCount: 0, shareCount: 0 },
      pics: source.pics,
      actName: source.actName
    }
    const param: EventDetailPageParam = {
      event: sourceItem,
      onChanged: (item: UserEventItem, deleted: boolean) => {
        const updated = EventPresentation.changeList([this.event], item, deleted)
        if (updated.length > 0) { this.event = updated[0] }
        this.pageParam.onChanged?.(item, deleted)
        this.pageParam.onChanged?.(this.event, false)
      }
    }
    this.pageStack.pushPathByName('EventDetailPage', param)
  }

  private song(): songItemType | null {
    const data = this.data()
    return data.song ? mapApiSong(data.song) : null
  }

  private attachedResource(): EventResourceView {
    return EventPresentation.resource(this.event)
  }

  private hasAttachedResource(): boolean {
    const resource = EventPresentation.resource(this.event)
    return !!(resource.title && (resource.playlist || resource.album))
  }

  private openAttachedResource(): void {
    const resource = EventPresentation.resource(this.event)
    if (resource.playlist) {
      this.pageStack.pushPathByName('PlaylistDetailPage', resource.playlist)
    } else if (resource.album) {
      this.pageStack.pushPathByName('AlbumDetailPage', resource.album)
    }
  }

  private threadId(): string {
    return this.event.info.threadId || `A_EV_2_${this.event.id}_${this.event.user.userId}`
  }

  private openUserProfile(): void {
    if (!this.event.user.userId) {
      return
    }
    const param: UserProfilePageParam = { uid: this.event.user.userId.toString() }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }


  @Builder
  private SourceEventCard(source: EventForwardData) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Image(source.user?.avatarUrl || '').width(28).height(28).borderRadius(14).objectFit(ImageFit.Cover)
        Text(source.user?.nickname || '源动态作者').fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(TC.textPrimary()).maxLines(1)
      }.width('100%')
      Text(this.sourceContent(source)).width('100%').fontSize(13).lineHeight(20).fontColor(TC.textBody())
        .maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis })
      if ((source.pics || []).length > 0) {
        EventImages({ pictures: source.pics || [] })
      }
      if (this.sourceResourceTitle(source)) {
        Row({ space: 9 }) {
          if (this.sourceResourceImage(source)) {
            Image(this.sourceResourceImage(source)).width(44).height(44).borderRadius(8).objectFit(ImageFit.Cover)
          }
          Column({ space: 3 }) {
            Text(this.sourceResourceKind(source)).fontSize(9).fontColor(TC.accentSoft())
            Text(this.sourceResourceTitle(source)).fontSize(12).fontColor(TC.textBody()).maxLines(1)
            if (this.sourceResourceSubtitle(source)) {
              Text(this.sourceResourceSubtitle(source)).fontSize(9).fontColor(TC.textTertiary()).maxLines(1)
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding(9).backgroundColor(TC.surfaceCardAlt()).borderRadius(10)
      }
    }
    .width('100%').padding(12).backgroundColor(TC.surfaceCard()).borderRadius(13)
    .onClick(() => this.openSourceEvent(source))
  }

  private formatTime(value: number): string {
    if (!value) {
      return ''
    }
    const date = new Date(value)
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
  }

  private async loadSongLikedState(): Promise<void> {
    const song = this.song()
    if (!song || !this.authStore.userId) {
      return
    }
    try {
      const response = await ApiClient.get<LikeListResponse>('/likelist', [
        { key: 'uid', value: this.authStore.userId }
      ])
      this.songLiked = (response.ids || []).includes(Number(song.id))
    } catch (_error) {
    }
  }

  private async playSong(): Promise<void> {
    const song = this.song()
    if (!song) {
      return
    }
    const queue = this.playerStore.queue.map((item: songItemType) => item)
    let index = queue.findIndex((item: songItemType) => item.id === song.id)
    if (index < 0) {
      queue.push(song)
      index = queue.length - 1
    }
    await playerController.setQueue(queue, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private openMv(): void {
    const mv = this.data().mv
    if (!mv?.id) {
      return
    }
    const param: MvPlayerPageParam = {
      id: mv.id.toString(),
      name: mv.name || 'MV',
      cover: mv.imgurl16v9 || mv.imgurl || '',
      artistName: mv.artistName || '',
      duration: mv.duration,
      playCount: mv.playCount
    }
    this.pageStack.pushPathByName('MvPlayerPage', param)
  }

  private async toggleSongLike(): Promise<void> {
    const song = this.song()
    if (!song) {
      return
    }
    const nextLiked = !this.songLiked
    try {
      const response = await ApiClient.get<OperationResponse>('/like', [
        { key: 'id', value: song.id },
        { key: 'like', value: nextLiked.toString() }
      ])
      if (response.code === 200) {
        this.songLiked = nextLiked
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '歌曲喜欢操作失败')
    }
  }

  private async toggleEventLike(): Promise<void> {
    if (!this.authStore.loggedIn) {
      BubbleTip.show(this.getUIContext(), '请先登录')
      return
    }
    if (this.eventLikeBusy) { return }
    const account = this.authStore.userId
    const nextLiked = !this.event.info.liked
    this.eventLikeBusy = true
    try {
      const response = await ApiClient.get<OperationResponse>('/resource/like', [
        { key: 'type', value: '6' },
        { key: 'threadId', value: this.threadId() },
        { key: 't', value: nextLiked ? '1' : '0' }
      ])
      if (response.code !== 200) { throw new Error(response.message || '动态点赞失败') }
      if (!this.authStore.loggedIn || account !== this.authStore.userId) { return }
      const updated = EventPresentation.copy(this.event)
      updated.info.liked = nextLiked
      updated.info.likedCount = Math.max(0, this.event.info.likedCount + (nextLiked ? 1 : -1))
      this.event = updated
      this.pageParam.onChanged?.(this.event, false)
      BubbleTip.show(this.getUIContext(), nextLiked ? '已点赞' : '已取消点赞')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '动态点赞失败')
    } finally {
      this.eventLikeBusy = false
    }
  }

  private openShare(): void {
    this.shareVisible = true
  }

  private confirmDeleteEvent(): void {
    this.getUIContext().showAlertDialog({
      title: '删除动态',
      message: '确定删除这条动态？删除后无法恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: TC.accent(), action: () => { this.deleteEvent() } }
    })
  }

  private async deleteEvent(): Promise<void> {
    if (this.deletingEvent) { return }
    this.deletingEvent = true
    try {
      const response = await ApiClient.get<OperationResponse>('/event/del', [
        { key: 'evId', value: this.event.id.toString() }
      ])
      if (response.code !== 200) { throw new Error(response.message || '动态删除失败') }
      BubbleTip.show(this.getUIContext(), '动态已删除')
      this.pageParam.onChanged?.(this.event, true)
      this.pageStack.pop()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '动态删除失败')
    } finally {
      this.deletingEvent = false
    }
  }

  private moreOptions(): MenuElement[] {
    const options: MenuElement[] = [{ value: '分享', action: () => this.openShare() }]
    if (this.authStore.loggedIn && this.event.user.userId.toString() === this.authStore.userId) {
      options.push({ value: '删除', action: () => this.confirmDeleteEvent() })
    }
    return options
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: EventPresentation.share(this.event), visible: true,
      onClose: () => this.shareVisible = false,
      onShared: () => {
        const updated = EventPresentation.copy(this.event)
        updated.info.shareCount = (this.event.info.shareCount || 0) + 1
        this.event = updated
        this.pageParam.onChanged?.(this.event, false)
      }
    })
  }

  private openEventComments(): void {
    this.commentType = 6
    this.commentSheetVisible = true
  }

  private openSongComments(): void {
    if (!this.song()) { return }
    this.commentType = 0
    this.commentSheetVisible = true
  }

  private commentResource(): CommentResource {
    return this.commentType === 6 ?
      { id: this.event.id.toString(), type: 6, threadId: this.threadId(), title: '动态评论' } :
      { id: this.song()?.id || '', type: 0, title: '歌曲评论' }
  }

  private updateCommentCount(total: number): void {
    if (this.commentType !== 6 || total === this.event.info.commentCount) { return }
    const updated = EventPresentation.copy(this.event)
    updated.info.commentCount = total
    this.event = updated
    this.pageParam.onChanged?.(this.event, false)
  }

  @Builder
  private CommentSheet() {
    ResourceComments({
      resource: this.commentResource(),
      onClose: () => this.commentSheetVisible = false,
      onCountChange: (total: number) => this.updateCommentCount(total)
    })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Scroll(this.scroller) {
            Column({ space: 14 }) {
            // 占位放进滚动内容里，让内容能滚到顶栏后面，常驻模糊才有效果
            Column().width('100%').height(this.topAvoidHeight + 54)
            Row({ space: 11 }) {
              Image(this.event.user.avatarUrl).width(46).height(46)
                .sourceSize({ width: 96, height: 96 }).borderRadius(23).objectFit(ImageFit.Cover)
              Column({ space: 4 }) {
                Text(this.event.user.nickname).fontSize(14).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                  .onClick(() => this.openUserProfile())
                Text(this.formatTime(this.event.showTime || this.event.eventTime || 0)).fontSize(10).fontColor(TC.textQuaternary())
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%')
            Text(this.content()).width('100%').fontSize(15).lineHeight(24).fontColor(TC.textBody())
            if (this.sourceEvent()) {
              this.SourceEventCard(this.sourceEvent()!)
            }
            if ((this.event.pics || []).length > 0) {
              EventImages({ pictures: this.event.pics || [] })
            }
            if (this.song()) {
              Row({ space: 11 }) {
                Image(this.song()?.img || '').width(66).height(66)
                  .sourceSize({ width: 144, height: 144 }).borderRadius(12).objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Text(this.song()?.name || '').fontSize(14).fontColor(TC.textPrimary()).maxLines(1)
                  Text(this.song()?.author || '').fontSize(11).fontColor(TC.textTertiary()).maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph(this.songLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(21).fontColor([this.songLiked ? TC.accent() : TC.textTertiary()])
                  .onClick(() => this.toggleSongLike())
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(21).fontColor([TC.textTertiary()])
                  .onClick(() => this.openSongComments())
                SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(25).fontColor([TC.textPrimary()])
                  .onClick(() => this.playSong())
              }.width('100%').padding(12).backgroundColor(TC.surfaceInset()).borderRadius(14)
            }
            if (this.hasAttachedResource()) {
              Row({ space: 11 }) {
                if (this.attachedResource().image) {
                  Image(this.attachedResource().image).width(58).height(58)
                    .borderRadius(11).objectFit(ImageFit.Cover)
                } else {
                  Stack() {
                    SymbolGlyph($r('sys.symbol.music')).fontSize(25).fontColor([TC.textQuaternary()])
                  }.width(58).height(58).borderRadius(11).backgroundColor(TC.surfaceRaised())
                }
                Column({ space: 5 }) {
                  Text(this.attachedResource().kind).fontSize(9).fontColor(TC.accentSoft())
                  Text(this.attachedResource().title).fontSize(13).fontWeight(FontWeight.Medium)
                    .fontColor(TC.textBody()).maxLines(1)
                  if (this.attachedResource().subtitle) {
                    Text(this.attachedResource().subtitle).fontSize(10).fontColor(TC.textTertiary()).maxLines(1)
                  }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([TC.textQuaternary()])
              }.width('100%').padding(11).backgroundColor(TC.surfaceInset()).borderRadius(13)
                .onClick(() => this.openAttachedResource())
            }
            if (this.data().mv) {
              Row({ space: 11 }) {
                Image(this.data().mv?.imgurl16v9 || this.data().mv?.imgurl || '')
                  .width(112).height(64).sourceSize({ width: 240, height: 136 })
                  .borderRadius(10).objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Text(this.data().mv?.name || 'MV').width('100%').fontSize(14).fontColor(TC.textPrimary()).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.data().mv?.artistName || '').width('100%').fontSize(11).fontColor(TC.textTertiary()).maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(27).fontColor([TC.textPrimary()])
              }.width('100%').padding(11).backgroundColor(TC.surfaceInset()).borderRadius(14)
                .onClick(() => this.openMv())
            }
            Row() {
              Row({ space: 5 }) {
                SymbolGlyph($r('sys.symbol.arrow_right_up_and_square')).fontSize(18).fontColor([TC.textTertiary()])
                Text(`${this.event.info.shareCount}`).fontSize(11).fontColor(TC.textTertiary())
              }.layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.openShare())
              Row({ space: 5 }) {
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(18).fontColor([TC.textTertiary()])
                Text(`${this.event.info.commentCount}`).fontSize(11).fontColor(TC.textTertiary())
              }.layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.openEventComments())
              Row({ space: 5 }) {
                SymbolGlyph(this.event.info.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(18).fontColor([this.event.info.liked ? TC.accent() : TC.textTertiary()])
                Text(`${this.event.info.likedCount}`).fontSize(11)
                  .fontColor(this.event.info.liked ? TC.accent() : TC.textTertiary())
              }.layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.toggleEventLike())
            }.width('100%').height(50).backgroundColor(TC.surfaceCard()).borderRadius(14)
            NoMoreFooter()
            }.padding({ left: 16, right: 16, top: 16, bottom: 28 })
            .constraintSize({ minHeight: '100%' })
          }.layoutWeight(1).scrollBar(BarState.Off)
            .onDidScroll(() => {
              const y = this.scroller.currentOffset().yOffset
              // 顶栏只用到 0~160 这段做渐显，钳住后长列表滚动时不再逐帧刷新页面
              const barOffset = y > 170 ? 170 : y
              if (barOffset !== this.scrollOffset) {
                this.scrollOffset = barOffset
              }
            })
        }.width('100%').height('100%').backgroundColor(TC.pageBackground())
        .bindSheet(this.commentSheetVisible, this.CommentSheet(), {
          height: '68%', backgroundColor: TC.sheetBackground(), showClose: false, dragBar: true,
          onDisappear: () => this.commentSheetVisible = false
        })
        DetailTopBar({
          title: '动态详情',
          scrollOffset: this.scrollOffset,
          alwaysBlur: true,
          shareEnabled: false
        }) {
          Row() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(18).fontColor([TC.textOnMedia()])
          }
          .width(36).height(36).borderRadius(18)
          .backgroundColor('rgba(0,0,0,0.35)')
          .justifyContent(FlexAlign.Center)
          .bindMenu(this.moreOptions())
        }
        if (this.shareVisible) { this.ShareOptions() }
      }.width('100%').height('100%')
    }.hideTitleBar(true)
  }
}
