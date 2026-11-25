import { EventDetailPageParam, OperationResponse, UserEventItem, UserProfilePageParam } from '../models/api'
import { AuthStore } from '../stores/AuthStore'
import { EventPresentation } from '../services/EventPresentation'
import { EventTilePresentation } from '../services/EventTilePresentation'
import { ApiClient } from '../services/ApiClient'
import { resizeImageUrl } from '../services/ImageUrl'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'
import { HeartLike } from './HeartLike'
import { ShareSheet } from './ShareSheet'

@Component
export struct EventTile {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('authStore') authStore: AuthStore
  @Prop item: UserEventItem = EventPresentation.empty()
  @Prop cardWidth: number = 180
  @State sharing: boolean = false
  @State liking: boolean = false
  @State deleting: boolean = false
  onChanged: (item: UserEventItem, deleted: boolean) => void = () => {}

  private open(): void {
    const param: EventDetailPageParam = { event: this.item,
      onChanged: (event: UserEventItem, deleted: boolean) => this.onChanged(event, deleted) }
    this.pageStack.pushPathByName('EventDetailPage', param)
  }

  private openUser(): void {
    const param: UserProfilePageParam = { uid: this.item.user.userId.toString() }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private owned(): boolean {
    return this.authStore.loggedIn && this.item.user.userId.toString() === this.authStore.userId
  }

  private moreOptions(): MenuElement[] {
    const options: MenuElement[] = [{ value: '分享', action: () => this.sharing = true }]
    if (this.owned()) { options.push({ value: '删除', action: () => this.confirmDelete() }) }
    return options
  }

  private confirmDelete(): void {
    if (!this.owned() || this.deleting) { return }
    this.getUIContext().showAlertDialog({ title: '删除动态', message: '确定删除这条动态？删除后无法恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: TC.accent(), action: () => { this.deleteEvent() } } })
  }

  private async deleteEvent(): Promise<void> {
    if (!this.owned() || this.deleting) { return }
    this.deleting = true
    const item = this.item
    try {
      const response = await ApiClient.get<OperationResponse>('/event/del', [{ key: 'evId', value: String(item.id) }])
      if (response.code !== 200) { throw new Error(response.message || '动态删除失败') }
      this.onChanged(item, true)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '动态删除失败') }
    finally { this.deleting = false }
  }

  private async like(): Promise<void> {
    if (!this.authStore.loggedIn) { this.pageStack.pushPathByName('LoginPage', null); return }
    if (this.liking) { return }
    this.liking = true
    const userId = this.authStore.userId
    const item = this.item
    const liked = !item.info.liked
    try {
      const response = await ApiClient.get<OperationResponse>('/resource/like', [
        { key: 'type', value: '6' },
        { key: 'threadId', value: item.info.threadId || `A_EV_2_${item.id}_${item.user.userId}` },
        { key: 't', value: liked ? '1' : '0' }
      ])
      if (response.code !== 200) { throw new Error(response.message || '动态点赞失败') }
      if (userId !== this.authStore.userId || item.id !== this.item.id) { return }
      const updated = EventPresentation.copy(this.item)
      updated.info.liked = liked
      updated.info.likedCount = Math.max(0, (updated.info.likedCount || 0) + (liked ? 1 : -1))
      this.item = updated
      this.onChanged(updated, false)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '动态点赞失败') }
    finally { this.liking = false }
  }

  private likeText(): string {
    const count = this.item.info.likedCount || 0
    return count >= 10000 ? (count / 10000).toFixed(1) + '万' : count > 0 ? String(count) : '赞'
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: EventPresentation.share(this.item), visible: true,
      onClose: () => this.sharing = false,
      onShared: () => {
        const updated = EventPresentation.copy(this.item)
        updated.info.shareCount = (updated.info.shareCount || 0) + 1
        this.item = updated
        this.onChanged(updated, false)
      } })
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (EventTilePresentation.media(this.item).image) {
          Image(resizeImageUrl(EventTilePresentation.media(this.item).image, 480, 680))
            .width('100%').height('100%').sourceSize({ width: 480, height: 680 }).objectFit(ImageFit.Cover)
            .onClick(() => this.open())
        } else {
          Text(EventTilePresentation.media(this.item).text).width('100%').height('100%')
            .fontSize(15).lineHeight(22).fontColor('#202024').backgroundColor('#ffffff')
            .padding({ left: 14, right: 14, top: 34, bottom: 14 }).maxLines(7)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).onClick(() => this.open())
        }
        if (EventTilePresentation.media(this.item).video) {
          SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(32).fontColor([TC.textOnMedia()])
            .position({ x: '42%', y: '42%' }).hitTestBehavior(HitTestMode.None)
        }
        if (EventTilePresentation.media(this.item).pictureCount > 1) {
          Text(`${EventTilePresentation.media(this.item).pictureCount} 图`).fontSize(9).fontColor(TC.textOnMedia())
            .padding(5).borderRadius(8).backgroundColor('rgba(0,0,0,0.45)')
            .position({ left: 8, top: 8 }).hitTestBehavior(HitTestMode.None)
        }
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(17).fontColor([TC.textOnMedia()])
        }.width(26).height(26).borderRadius(13).backgroundColor('rgba(0,0,0,0.4)')
          .position({ right: 7, top: 7 })
          .accessibilityText('更多').enabled(!this.deleting).bindMenu(this.moreOptions())
      }.width('100%').height(EventTilePresentation.mediaHeight(this.item, this.cardWidth)).clip(true)
      if (EventTilePresentation.media(this.item).image || EventPresentation.data(this.item).event) {
        Text(EventTilePresentation.title(this.item)).width('100%')
          .height(EventTilePresentation.titleHeight(this.item, this.cardWidth)).fontSize(13).lineHeight(18)
          .fontColor(TC.textPrimary()).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 10, right: 10, top: 8, bottom: 8 }).onClick(() => this.open())
      }
      Row({ space: 5 }) {
        Row({ space: 5 }) {
          Image(resizeImageUrl(this.item.user.avatarUrl, 64, 64)).width(20).height(20).borderRadius(10).objectFit(ImageFit.Cover)
          Text(this.item.user.nickname).layoutWeight(1).fontSize(10).fontColor(TC.textSecondary())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).onClick(() => this.openUser())
        Row({ space: 3 }) {
          HeartLike({ liked: this.item.info.liked, iconSize: 14,
            iconColor: this.item.info.liked ? TC.accent() : TC.textTertiary() })
          Text(this.likeText()).fontSize(10).fontColor(this.item.info.liked ? TC.accent() : TC.textTertiary()).maxLines(1)
        }.constraintSize({ maxWidth: 56 }).enabled(!this.liking).onClick(() => this.like())
      }.width('100%').height(42).padding({ left: 10, right: 10, bottom: 8 })
    }.width(this.cardWidth).height(EventTilePresentation.height(this.item, this.cardWidth))
      .backgroundColor(TC.surfaceCard()).borderRadius(12).clip(true)
      .bindContentCover(this.sharing, this.ShareOptions(), { modalTransition: ModalTransition.NONE,
        backgroundColor: Color.Transparent, onDisappear: () => this.sharing = false })
  }
}
