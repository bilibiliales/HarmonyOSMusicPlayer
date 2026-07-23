import {
  ApiParam,
  CommentApiItem,
  CommentResponse,
  EventCommentItem,
  EventCommentResponse,
  EventDetailPageParam,
  EventForwardData,
  EventJsonData,
  EventPicture,
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

@Component
export struct EventDetailPage {
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
  @State comments: EventCommentItem[] = []
  @State commentsLoading: boolean = false
  @State commentSheetVisible: boolean = false
  @State commentType: number = 6
  @State commentInput: string = ''
  @State commentSubmitting: boolean = false
  @State songLiked: boolean = false
  @State previewPictureIndex: number = -1
  @State previewPictureVisible: boolean = false
  @State previewPictureMounted: boolean = false
  private previewPictureClosing: boolean = false

  aboutToAppear(): void {
    this.event = this.pageParam.event
    this.previewPictureIndex = -1
    this.previewPictureVisible = false
    this.previewPictureMounted = false
    this.previewPictureClosing = false
    this.loadSongLikedState()
  }

  aboutToDisappear(): void {
    this.previewPictureVisible = false
    this.previewPictureMounted = false
    this.previewPictureIndex = -1
    this.previewPictureClosing = false
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
    const param: EventDetailPageParam = { event: sourceItem, canDelete: false }
    this.pageStack.pushPathByName('EventDetailPage', param)
  }

  private song(): songItemType | null {
    const data = this.data()
    return data.song ? mapApiSong(data.song) : null
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

  private pictureUrl(picture: EventPicture): string {
    return picture.originUrl || picture.rectangleUrl || picture.squareUrl || picture.pcSquareUrl || ''
  }

  @Builder
  private SourceEventCard(source: EventForwardData) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Image(source.user?.avatarUrl || '').width(28).height(28).borderRadius(14).objectFit(ImageFit.Cover)
        Text(source.user?.nickname || '源动态作者').fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor('#ffffff').maxLines(1)
      }.width('100%')
      Text(this.sourceContent(source)).width('100%').fontSize(13).lineHeight(20).fontColor('#aaaab2')
        .maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis })
      if ((source.pics || []).length > 0) {
        Scroll() {
          Row({ space: 7 }) {
            ForEach(source.pics || [], (picture: EventPicture) => {
              Image(this.pictureUrl(picture)).width(92).height(92).borderRadius(9).objectFit(ImageFit.Cover)
            })
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      if (this.sourceResourceTitle(source)) {
        Row({ space: 9 }) {
          if (this.sourceResourceImage(source)) {
            Image(this.sourceResourceImage(source)).width(44).height(44).borderRadius(8).objectFit(ImageFit.Cover)
          }
          Column({ space: 3 }) {
            Text(this.sourceResourceKind(source)).fontSize(9).fontColor('#ff7587')
            Text(this.sourceResourceTitle(source)).fontSize(12).fontColor('#dedee2').maxLines(1)
            if (this.sourceResourceSubtitle(source)) {
              Text(this.sourceResourceSubtitle(source)).fontSize(9).fontColor('#77777f').maxLines(1)
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding(9).backgroundColor('#202026').borderRadius(10)
      }
    }
    .width('100%').padding(12).backgroundColor('#19191e').borderRadius(13)
    .onClick(() => this.openSourceEvent(source))
  }

  private pictureAspectRatio(picture: EventPicture): number {
    if (picture.width && picture.height && picture.width > 0 && picture.height > 0) {
      return picture.width / picture.height
    }
    return 1
  }

  private pictureTransitionId(index: number): string {
    return `event-picture-${this.event.id}-${index}`
  }

  private previewPicture(): EventPicture {
    return (this.event.pics || [])[this.previewPictureIndex] || {}
  }

  private showPicture(index: number): void {
    if (this.previewPictureClosing) {
      return
    }
    this.previewPictureIndex = index
    this.previewPictureMounted = true
    this.getUIContext().animateTo({ duration: 360, curve: Curve.EaseInOut }, () => {
      this.previewPictureVisible = true
    })
  }

  private closePicture(): void {
    if (!this.previewPictureVisible || !this.previewPictureMounted || this.previewPictureIndex < 0 ||
      this.previewPictureClosing) {
      return
    }
    this.previewPictureClosing = true
    this.getUIContext().animateTo({
      duration: 360,
      curve: Curve.EaseInOut,
      onFinish: () => {
        this.previewPictureMounted = false
        this.previewPictureIndex = -1
        this.previewPictureClosing = false
      }
    }, () => {
      this.previewPictureVisible = false
    })
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
    const nextLiked = !(this.event.info.liked || false)
    try {
      const response = await ApiClient.get<OperationResponse>('/resource/like', [
        { key: 'type', value: '6' },
        { key: 'threadId', value: this.threadId() },
        { key: 't', value: nextLiked ? '1' : '0' }
      ])
      if (response.code === 200) {
        this.event.info.liked = nextLiked
        this.event.info.likedCount = Math.max(0, this.event.info.likedCount + (nextLiked ? 1 : -1))
        this.event = this.event
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '动态点赞失败')
    }
  }

  private async forwardEvent(): Promise<void> {
    try {
      const response = await ApiClient.get<OperationResponse>('/event/forward', [
        { key: 'evId', value: this.event.id.toString() },
        { key: 'uid', value: this.event.user.userId.toString() },
        { key: 'forwards', value: '转发动态' }
      ])
      if (response.code === 200) {
        this.event.info.shareCount += 1
        this.event = this.event
        BubbleTip.show(this.getUIContext(), '动态已转发')
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '动态转发失败')
    }
  }

  private async deleteEvent(): Promise<void> {
    try {
      const response = await ApiClient.get<OperationResponse>('/event/del', [
        { key: 'evId', value: this.event.id.toString() }
      ])
      if (response.code === 200) {
        this.pageParam.event.id = 0
        this.event.id = 0
        this.event = this.event
        this.pageStack.pop()
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '动态删除失败')
    }
  }

  private async openEventComments(): Promise<void> {
    this.commentType = 6
    this.commentSheetVisible = true
    this.commentsLoading = true
    try {
      const response = await ApiClient.get<EventCommentResponse>('/comment/event', [
        { key: 'threadId', value: this.threadId() },
        { key: 'limit', value: '50' }
      ])
      this.comments = (response.hotComments || []).concat(response.comments || [])
    } catch (_error) {
      this.comments = []
    } finally {
      this.commentsLoading = false
    }
  }

  private async openSongComments(): Promise<void> {
    const song = this.song()
    if (!song) {
      return
    }
    this.commentType = 0
    this.commentSheetVisible = true
    this.commentsLoading = true
    try {
      const response = await ApiClient.get<CommentResponse>('/comment/music', [
        { key: 'id', value: song.id },
        { key: 'limit', value: '50' }
      ])
      const source = (response.hotComments || []).concat(response.comments || [])
      this.comments = source.map((comment: CommentApiItem) => {
        return {
          commentId: comment.commentId,
          content: comment.content,
          time: 0,
          timeStr: comment.timeStr,
          likedCount: comment.likedCount,
          liked: comment.liked || false,
          user: { userId: 0, nickname: comment.user.nickname, avatarUrl: comment.user.avatarUrl,
            followed: false, mutual: false }
        } as EventCommentItem
      })
    } catch (_error) {
      this.comments = []
    } finally {
      this.commentsLoading = false
    }
  }

  private commentParams(comment: EventCommentItem, nextLiked: boolean): ApiParam[] {
    const params: ApiParam[] = [
      { key: 'type', value: this.commentType.toString() },
      { key: 'cid', value: comment.commentId.toString() },
      { key: 't', value: nextLiked ? '1' : '0' }
    ]
    if (this.commentType === 6) {
      params.push({ key: 'threadId', value: this.threadId() })
    } else {
      params.push({ key: 'id', value: this.song()?.id || '' })
    }
    return params
  }

  private async toggleCommentLike(comment: EventCommentItem): Promise<void> {
    const nextLiked = !(comment.liked || false)
    try {
      const response = await ApiClient.get<OperationResponse>('/comment/like', this.commentParams(comment, nextLiked))
      if (response.code === 200) {
        comment.liked = nextLiked
        comment.likedCount = Math.max(0, comment.likedCount + (nextLiked ? 1 : -1))
        this.comments = this.comments.map((item: EventCommentItem) => item)
      }
    } catch (_error) {
    }
  }

  private async submitComment(): Promise<void> {
    const content = this.commentInput.trim()
    if (!content || this.commentSubmitting) {
      return
    }
    const params: ApiParam[] = [
      { key: 't', value: '1' },
      { key: 'type', value: this.commentType.toString() },
      { key: 'content', value: content }
    ]
    if (this.commentType === 6) {
      params.push({ key: 'threadId', value: this.threadId() })
    } else {
      params.push({ key: 'id', value: this.song()?.id || '' })
    }
    this.commentSubmitting = true
    try {
      const response = await ApiClient.get<OperationResponse>('/comment', params)
      if (response.code === 200) {
        this.commentInput = ''
        if (this.commentType === 6) {
          this.event.info.commentCount += 1
          this.event = this.event
          await this.openEventComments()
        } else {
          await this.openSongComments()
        }
      }
    } catch (_error) {
    } finally {
      this.commentSubmitting = false
    }
  }

  @Builder
  private CommentSheet() {
    Column() {
      Row() {
        Text(this.commentType === 6 ? `动态评论 · ${this.event.info.commentCount}` : '歌曲评论')
          .layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor(['#686870'])
          .onClick(() => this.commentSheetVisible = false)
      }
      .height(60).padding({ left: 18, right: 18 })
      if (this.commentsLoading) {
        LoadingProgress().layoutWeight(1).width(42).color('#ef233c')
      } else {
        List({ space: 14 }) {
          ForEach(this.comments, (comment: EventCommentItem) => {
            ListItem() {
              Row({ space: 10 }) {
                Image(comment.user.avatarUrl).width(36).height(36)
                  .sourceSize({ width: 80, height: 80 }).borderRadius(18).objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Row() {
                    Text(comment.user.nickname).layoutWeight(1).fontSize(12).fontColor('#aaaab2')
                    Row({ space: 4 }) {
                      SymbolGlyph(comment.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                        .fontSize(14).fontColor([comment.liked ? '#ef233c' : '#77777f'])
                      Text(`${comment.likedCount}`).fontSize(9).fontColor(comment.liked ? '#ef233c' : '#77777f')
                    }.onClick(() => this.toggleCommentLike(comment))
                  }
                  Text(comment.content).fontSize(13).lineHeight(20).fontColor('#ededf0')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.padding({ left: 16, right: 16 })
            }
          })
        }.layoutWeight(1)
      }
      Row({ space: 9 }) {
        TextInput({ text: this.commentInput, placeholder: '写下你的评论…' })
          .layoutWeight(1).height(42).fontColor('#ffffff').placeholderColor('#66666e')
          .backgroundColor('#25252b').borderRadius(18).onChange((value: string) => this.commentInput = value)
        Button(this.commentSubmitting ? '发送中' : '发送').height(40).backgroundColor('#ef233c')
          .enabled(!this.commentSubmitting && this.commentInput.trim().length > 0)
          .onClick(() => this.submitComment())
      }.padding({ left: 14, right: 14, top: 8, bottom: 12 })
    }.width('100%').height('100%')
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          Column().width('100%').height(this.topAvoidHeight)
          Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('动态详情').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          if (this.pageParam.canDelete) {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor(['#ff6577'])
              .onClick(() => this.deleteEvent())
          } else {
            Blank().width(20)
          }
          }.height(56).padding({ left: 16, right: 16 })
          Scroll() {
            Column({ space: 14 }) {
            Row({ space: 11 }) {
              Image(this.event.user.avatarUrl).width(46).height(46)
                .sourceSize({ width: 96, height: 96 }).borderRadius(23).objectFit(ImageFit.Cover)
              Column({ space: 4 }) {
                Text(this.event.user.nickname).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                  .onClick(() => this.openUserProfile())
                Text(this.formatTime(this.event.showTime || this.event.eventTime || 0)).fontSize(10).fontColor('#66666e')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%')
            Text(this.content()).width('100%').fontSize(15).lineHeight(24).fontColor('#dedee2')
            if (this.sourceEvent()) {
              this.SourceEventCard(this.sourceEvent()!)
            }
            if ((this.event.pics || []).length > 0) {
              ForEach(this.event.pics || [], (picture: EventPicture, index: number) => {
                if (this.previewPictureVisible && this.previewPictureIndex === index) {
                  Column().width('100%').aspectRatio(this.pictureAspectRatio(picture))
                } else {
                  Image(this.pictureUrl(picture)).width('100%').aspectRatio(this.pictureAspectRatio(picture))
                    .borderRadius(14).objectFit(ImageFit.Contain)
                    .geometryTransition(this.pictureTransitionId(index), { follow: true })
                    .onClick(() => this.showPicture(index))
                }
              }, (_picture: EventPicture, index: number) => `${this.event.id}-${index}`)
            }
            if (this.song()) {
              Row({ space: 11 }) {
                Image(this.song()?.img || '').width(66).height(66)
                  .sourceSize({ width: 144, height: 144 }).borderRadius(12).objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Text(this.song()?.name || '').fontSize(14).fontColor('#ffffff').maxLines(1)
                  Text(this.song()?.author || '').fontSize(11).fontColor('#77777f').maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph(this.songLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(21).fontColor([this.songLiked ? '#ef233c' : '#77777f'])
                  .onClick(() => this.toggleSongLike())
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(21).fontColor(['#77777f'])
                  .onClick(() => this.openSongComments())
                SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(25).fontColor(['#ffffff'])
                  .onClick(() => this.playSong())
              }.width('100%').padding(12).backgroundColor('#24242a').borderRadius(14)
            }
            if (this.data().mv) {
              Row({ space: 11 }) {
                Image(this.data().mv?.imgurl16v9 || this.data().mv?.imgurl || '')
                  .width(112).height(64).sourceSize({ width: 240, height: 136 })
                  .borderRadius(10).objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Text(this.data().mv?.name || 'MV').width('100%').fontSize(14).fontColor('#ffffff').maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.data().mv?.artistName || '').width('100%').fontSize(11).fontColor('#77777f').maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(27).fontColor(['#ffffff'])
              }.width('100%').padding(11).backgroundColor('#24242a').borderRadius(14)
                .onClick(() => this.openMv())
            }
            Row() {
              Row({ space: 5 }) {
                SymbolGlyph($r('sys.symbol.arrow_right_up_and_square')).fontSize(18).fontColor(['#77777f'])
                Text(`${this.event.info.shareCount}`).fontSize(11).fontColor('#77777f')
              }.layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.forwardEvent())
              Row({ space: 5 }) {
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(18).fontColor(['#77777f'])
                Text(`${this.event.info.commentCount}`).fontSize(11).fontColor('#77777f')
              }.layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.openEventComments())
              Row({ space: 5 }) {
                SymbolGlyph(this.event.info.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(18).fontColor([this.event.info.liked ? '#ef233c' : '#77777f'])
                Text(`${this.event.info.likedCount}`).fontSize(11)
                  .fontColor(this.event.info.liked ? '#ef233c' : '#77777f')
              }.layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.toggleEventLike())
            }.width('100%').height(50).backgroundColor('#1b1b20').borderRadius(14)
            }.padding({ left: 16, right: 16, top: 16, bottom: 28 })
          }.layoutWeight(1).scrollBar(BarState.Off)
        }.width('100%').height('100%').backgroundColor('#121215')
        .bindSheet(this.commentSheetVisible, this.CommentSheet(), {
          height: '68%', backgroundColor: '#19191f', showClose: false, dragBar: true,
          onDisappear: () => this.commentSheetVisible = false
        })
        if (this.previewPictureMounted && this.previewPictureIndex >= 0) {
          Stack() {
            Column().width('100%').height('100%').backgroundColor('#000000')
              .opacity(this.previewPictureVisible ? 1 : 0)
              .animation({ duration: 240, curve: Curve.EaseInOut })
            if (this.previewPictureVisible) {
              Image(this.pictureUrl(this.previewPicture())).width('100%').height('100%')
                .objectFit(ImageFit.Contain)
                .geometryTransition(this.pictureTransitionId(this.previewPictureIndex), { follow: true })
            }
          }
          .width('100%').height('100%')
          .onClick(() => this.closePicture())
        }
      }.width('100%').height('100%')
    }.hideTitleBar(true)
  }
}
