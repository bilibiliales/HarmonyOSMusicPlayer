import { AlbumPageParam, EventDetailPageParam, OperationResponse, UserEventItem, UserProfilePageParam } from '../models/api'
import { songItemType } from '../models/music'
import { EventPresentation, EventResourceView } from '../services/EventPresentation'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'
import { BubbleTip } from '../services/BubbleTip'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { ShareSheet } from './ShareSheet'
import { EventImages } from './EventImages'
import { ResourceComments } from './ResourceComments'
import { CommentResource } from '../models/CommentResource'

@Component
export struct EventCard {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('authStore') authStore: AuthStore
  @Consume('playerStore') playerStore: PlayerStore
  @Prop item: UserEventItem = EventPresentation.empty()
  @State sharing: boolean = false
  @State liking: boolean = false
  onChanged: (item: UserEventItem, deleted: boolean) => void = () => {}
  @State commentsVisible: boolean = false

  private open(item: UserEventItem = this.item, comments: boolean = false): void {
    const param: EventDetailPageParam = { event: item, openComments: comments,
      onChanged: (changed: UserEventItem, deleted: boolean) => {
        this.item = EventPresentation.change(this.item, changed, deleted)
        this.onChanged(changed, deleted)
      } }
    this.pageStack.pushPathByName('EventDetailPage', param)
  }

  private openUser(id: number): void {
    const param: UserProfilePageParam = { uid: id.toString() }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private async like(): Promise<void> {
    if (!this.authStore.loggedIn) { this.pageStack.pushPathByName('LoginPage', null); return }
    if (this.liking) { return }
    this.liking = true
    const userId = this.authStore.userId
    const liked = !this.item.info.liked
    try {
      const response = await ApiClient.get<OperationResponse>('/resource/like', [
        { key: 'type', value: '6' },
        { key: 'threadId', value: this.item.info.threadId || 'A_EV_2_' + this.item.id + '_' + this.item.user.userId },
        { key: 't', value: liked ? '1' : '0' }
      ])
      if (response.code !== 200) { throw new Error(response.message || '动态点赞失败') }
      if (userId !== this.authStore.userId) { return }
      const updated = EventPresentation.copy(this.item)
      updated.info.liked = liked
      updated.info.likedCount = Math.max(0, (updated.info.likedCount || 0) + (liked ? 1 : -1))
      this.item = updated
      this.onChanged(this.item, false)
      BubbleTip.show(this.getUIContext(), liked ? '点赞成功' : '已取消点赞')
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '动态点赞失败') }
    finally { this.liking = false }
  }

  private async openResource(resource: EventResourceView): Promise<void> {
    if (resource.song) {
      const queue = this.playerStore.queue.slice()
      let index = queue.findIndex((song: songItemType) => song.id === resource.song!.id)
      if (index < 0) { queue.push(resource.song); index = queue.length - 1 }
      await playerController.setQueue(queue, index, true)
    } else if (resource.playlist) {
      this.pageStack.pushPathByName('PlaylistDetailPage', resource.playlist)
    } else if (resource.album) {
      this.pageStack.pushPathByName('AlbumDetailPage', resource.album as AlbumPageParam)
    } else if (resource.mv) {
      this.pageStack.pushPathByName('MvPlayerPage', resource.mv)
    } else { this.open() }
  }

  @Builder
  private ResourceCard(resource: EventResourceView) {
    Row({ space: 11 }) {
      if (resource.image) {
        Image(resizeImageUrl(resource.image, 128, 128)).width(58).height(58)
          .sourceSize({ width: 128, height: 128 }).borderRadius(11).objectFit(ImageFit.Cover)
      } else {
        Stack() { SymbolGlyph($r('sys.symbol.music')).fontSize(25).fontColor(['#a0a0a8']) }
          .width(58).height(58).borderRadius(11).backgroundColor('#303037')
      }
      Column({ space: 5 }) {
        Text(resource.kind).fontSize(9).fontColor('#ff7587')
        Text(resource.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#ededf0').maxLines(1)
        if (resource.subtitle) { Text(resource.subtitle).fontSize(10).fontColor('#77777f').maxLines(1) }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (resource.song) {
        SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(25).fontColor(['#ffffff'])
      }
    }.width('100%').padding(11).backgroundColor('#24242a').borderRadius(13)
      .onClick(() => this.openResource(resource))
  }

  @Builder
  private SourceCard(source: UserEventItem) {
    Column({ space: 7 }) {
      Row({ space: 7 }) {
        Image(resizeImageUrl(source.user.avatarUrl, 64, 64)).width(24).height(24).borderRadius(12).objectFit(ImageFit.Cover)
        Text(source.user.nickname).fontSize(12).fontColor('#ededf0').maxLines(1)
      }.width('100%').onClick(() => this.open(source))
      Text(EventPresentation.content(source)).width('100%').fontSize(12).lineHeight(18).fontColor('#9999a1').maxLines(3)
        .onClick(() => this.open(source))
      if (source.pics?.length) { EventImages({ pictures: source.pics || [] }) }
      if (EventPresentation.resource(source).title) { this.ResourceCard(EventPresentation.resource(source)) }
    }.width('100%').padding(10).backgroundColor('#202026').borderRadius(11)
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: EventPresentation.share(this.item), visible: true,
      onClose: () => this.sharing = false,
      onDeleted: () => this.onChanged(this.item, true),
      onShared: () => {
        const updated = EventPresentation.copy(this.item)
        updated.info.shareCount = (updated.info.shareCount || 0) + 1
        this.item = updated
        this.onChanged(this.item, false)
      }
    })
  }

  private commentResource(): CommentResource {
    return { id: this.item.id.toString(), type: 6, title: '动态评论',
      threadId: this.item.info.threadId || 'A_EV_2_' + this.item.id + '_' + this.item.user.userId }
  }

  @Builder
  private Comments() {
    ResourceComments({ resource: this.commentResource(), onClose: () => this.commentsVisible = false,
      onCountChange: (total: number) => {
        const updated = EventPresentation.copy(this.item)
        updated.info.commentCount = total
        this.item = updated
        this.onChanged(this.item, false)
      }
    })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 11 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Image(resizeImageUrl(this.item.user.avatarUrl, 96, 96)).width(46).height(46)
            .sourceSize({ width: 96, height: 96 }).borderRadius(18).objectFit(ImageFit.Cover)
          if (this.item.user.userType === 4) { Image($r('app.media.ic_singer')).width(18).height(18).borderRadius(9) }
        }.width(46).height(46).onClick(() => this.openUser(this.item.user.userId))
        Column({ space: 4 }) {
          Text(this.item.user.nickname).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#ffffff').maxLines(1)
          Text(EventPresentation.time(this.item.showTime || this.item.eventTime || 0)).fontSize(10).fontColor('#66666e')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.open())
        SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(20).fontColor(['#9999a1']).padding(8)
          .onClick(() => this.sharing = true)
      }.width('100%')
      Text(EventPresentation.content(this.item)).width('100%').fontSize(13).lineHeight(20).fontColor('#b5b5bc')
        .onClick(() => this.open())
      if (EventPresentation.data(this.item).event) {
        this.SourceCard(EventPresentation.source(EventPresentation.data(this.item).event!))
      }
      if (this.item.pics?.length) { EventImages({ pictures: this.item.pics || [] }) }
      if (EventPresentation.resource(this.item).title) { this.ResourceCard(EventPresentation.resource(this.item)) }
      Row({ space: 24 }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.arrow_right_up_and_square')).fontSize(16).fontColor(['#77777f'])
          Text(String(this.item.info.shareCount || 0)).fontSize(10).fontColor('#77777f')
        }.onClick(() => this.sharing = true)
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(16).fontColor(['#77777f'])
          Text(String(this.item.info.commentCount || 0)).fontSize(10).fontColor('#77777f')
        }.onClick(() => this.commentsVisible = true)
        Row({ space: 4 }) {
          SymbolGlyph(this.item.info.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(16).fontColor([this.item.info.liked ? '#ef233c' : '#77777f'])
          Text(String(this.item.info.likedCount || 0)).fontSize(10).fontColor(this.item.info.liked ? '#ef233c' : '#77777f')
        }.enabled(!this.liking).onClick(() => this.like())
      }.width('100%')
    }.width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(16)
      .bindSheet(this.commentsVisible, this.Comments(), {
        height: '75%', backgroundColor: '#19191f', showClose: false, dragBar: false,
        onDisappear: () => this.commentsVisible = false
      })
      .bindContentCover(this.sharing, this.ShareOptions(), {
        modalTransition: ModalTransition.NONE, backgroundColor: Color.Transparent,
        onDisappear: () => this.sharing = false
      })
  }
}
