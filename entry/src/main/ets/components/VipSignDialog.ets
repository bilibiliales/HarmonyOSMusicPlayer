import { common } from '@kit.AbilityKit'
import { LikeListResponse, OperationResponse } from '../models/api'
import { songItemType } from '../models/music'
import { VipSignInfo, VipSignPrize } from '../models/vipSign'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { ApiClient } from '../services/ApiClient'
import { DailyExtraService } from '../services/DailyExtraService'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'
import { SystemShareService } from '../services/SystemShareService'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'
import { HeartLike } from './HeartLike'

/** 大封面、寄语日历和本月权益；卡片底色由同一封面高度模糊后叠加蒙版得到。 */
@CustomDialog
export struct VipSignDialog {
  controller?: CustomDialogController
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop info: VipSignInfo = new VipSignInfo()
  @ObjectLink playerStore: PlayerStore
  @ObjectLink @Watch('authChanged') authStore: AuthStore
  onLogin: () => void = () => {}
  onOpenSong: (song: songItemType) => void = () => {}
  @State private cardWidth: number = 340
  @State private coverFailed: boolean = false
  @State private rewardsExpanded: boolean = false
  @State private songLiked: boolean = false
  @State private likedKnown: boolean = false
  @State private liking: boolean = false
  @State private playPending: boolean = false
  private likeOwner: string = ''
  private likeGeneration: number = 0
  private alive: boolean = true

  aboutToAppear(): void { this.alive = true; this.loadLiked() }
  aboutToDisappear(): void { this.alive = false; this.likeGeneration++ }

  private authChanged(): void {
    this.likeGeneration++
    this.songLiked = false
    this.likedKnown = false
    this.likeOwner = ''
    if (this.alive) { this.loadLiked() }
  }

  private heroSize(): number { return Math.max(160, this.cardWidth - 28) }
  private cardHeight(): number { return this.heroSize() + 271 + (this.rewardsExpanded ? this.info.prizes.length * 50 + 8 : 0) }
  private isPlaying(): boolean { return this.playerStore.currentSong.id === this.info.song.id && this.playerStore.isPlaying }

  private isLiked(): boolean {
    if (!this.authStore.loggedIn || this.likeOwner !== this.authStore.userId) { return false }
    return this.playerStore.currentSong.id === this.info.song.id && this.likedKnown && this.playerStore.currentSong.liked !== undefined
      ? !!this.playerStore.currentSong.liked : this.songLiked
  }

  private async loadLiked(): Promise<void> {
    if (!this.authStore.loggedIn || !this.info.song.id) { return }
    const owner = this.authStore.userId
    const generation = ++this.likeGeneration
    try {
      const response = await ApiClient.get<LikeListResponse>('/likelist', [{ key: 'uid', value: owner }])
      if (!this.alive || generation !== this.likeGeneration || owner !== this.authStore.userId || !this.authStore.loggedIn) { return }
      if (response.code !== 200) { return }
      this.songLiked = (response.ids || []).some((id: number) => String(id) === this.info.song.id)
      this.likeOwner = owner
      this.likedKnown = true
      playerController.updateLiked(this.info.song.id, this.songLiked)
    } catch (_error) {}
  }

  private async play(): Promise<void> {
    if (this.playPending || !this.info.song.id) { return }
    this.playPending = true
    try {
      if (this.playerStore.currentSong.id === this.info.song.id) {
        await playerController.toggle()
      } else {
        const song: songItemType = { id: this.info.song.id, name: this.info.song.name, author: this.info.song.author,
          img: this.info.song.img, album: this.info.song.album, url: '', liked: this.likedKnown ? this.isLiked() : undefined }
        await playerController.setQueue([song], 0, true)
      }
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '歌曲播放失败') }
    finally { this.playPending = false }
  }

  private async like(): Promise<void> {
    if (!this.authStore.loggedIn) { this.controller?.close(); this.onLogin(); return }
    if (this.liking || !this.info.song.id) { return }
    const owner = this.authStore.userId
    this.liking = true
    try {
      if (!this.likedKnown) { await this.loadLiked() }
      if (!this.alive || owner !== this.authStore.userId || !this.authStore.loggedIn) { return }
      if (!this.likedKnown) { throw new Error('喜欢状态加载失败，请重试') }
      const liked = !this.isLiked()
      const response = await ApiClient.get<OperationResponse>('/like', [
        { key: 'id', value: this.info.song.id }, { key: 'like', value: String(liked) }
      ])
      if (response.code !== 200) { throw new Error(response.message || '喜欢操作失败') }
      if (!this.alive || owner !== this.authStore.userId || !this.authStore.loggedIn) { return }
      this.likeGeneration++
      this.songLiked = liked
      playerController.updateLiked(this.info.song.id, liked)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '喜欢操作失败') }
    finally { this.liking = false }
  }

  private async shareSong(): Promise<void> {
    try {
      await SystemShareService.showLink(this.getUIContext().getHostContext() as common.UIAbilityContext, {
        url: `https://music.163.com/song?id=${encodeURIComponent(this.info.song.id)}`,
        title: this.info.song.name, description: this.info.song.author, label: '歌曲', image: this.info.song.img
      })
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '分享失败') }
  }

  private async shareSign(): Promise<void> {
    const date = DailyExtraService.signDate(this.info)
    try {
      await SystemShareService.showText(this.getUIContext().getHostContext() as common.UIAbilityContext, {
        title: '今日乐签', label: '乐签', description: this.info.song.name, image: this.info.song.img,
        content: `${date.month}月${date.day}日 · 今日乐签\n${this.info.wishWords}\n${this.info.wishAuthor ? '— ' + this.info.wishAuthor + '\n' : ''}${this.info.song.name} · ${this.info.song.author}`
      })
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '分享失败') }
  }

  private menuOptions(): MenuElement[] {
    const items: MenuElement[] = [{ value: '分享乐签', action: () => { this.shareSign() } }]
    if (this.info.song.id) {
      items.push({ value: '分享歌曲', action: () => { this.shareSong() } })
      items.push({ value: '歌曲百科', action: () => { this.controller?.close(); this.onOpenSong(this.info.song) } })
    }
    items.push({ value: '关闭乐签', action: () => this.controller?.close() })
    return items
  }

  private toggleRewards(): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => this.rewardsExpanded = !this.rewardsExpanded)
  }

  @Builder
  private Hero() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.info.song.img && !this.coverFailed) {
        Image(resizeImageUrl(this.info.song.img, 800, 800)).width('100%').height('100%')
          .sourceSize({ width: 800, height: 800 }).objectFit(ImageFit.Cover).onError(() => this.coverFailed = true)
      } else {
        Stack() { SymbolGlyph($r('sys.symbol.music')).fontSize(62).fontColor([TC.textOnMediaTertiary()]) }
          .width('100%').height('100%').backgroundColor('#363245')
      }
      Column().width('100%').height('100%')
        .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0)', 0.55], ['rgba(0,0,0,0.65)', 1]] })
        .hitTestBehavior(HitTestMode.None)
      Row({ space: 10 }) {
        Column({ space: 5 }) {
          Text(this.info.song.name || '今日歌曲').fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textOnMedia())
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.info.song.author).fontSize(12).fontColor(TC.textOnMediaSecondary()).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Stack() { HeartLike({ liked: this.isLiked(), iconSize: 25, iconColor: this.isLiked() ? TC.accent() : TC.textOnMedia() }) }
          .width(40).height(44).accessibilityText(this.isLiked() ? '取消喜欢' : '喜欢歌曲')
          .enabled(!this.liking && !!this.info.song.id).onClick(() => this.like())
        Stack() {
          if (this.playPending || (this.playerStore.currentSong.id === this.info.song.id && this.playerStore.isLoading)) {
            LoadingProgress().width(25).height(25).color(TC.textOnMedia())
          } else {
            SymbolGlyph(this.isPlaying() ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(26).fontColor([TC.textOnMedia()])
          }
        }.width(36).height(44).accessibilityText(this.isPlaying() ? '暂停歌曲' : '播放歌曲')
          .enabled(!this.playPending && !!this.info.song.id).onClick(() => this.play())
      }.width('100%').padding({ left: 16, right: 12, bottom: 14 }).alignItems(VerticalAlign.Bottom)
      Stack() {
        Column({ space: 3 }) {
          ForEach([0, 1, 2], (_dot: number) => { Circle().width(3).height(3).fill(TC.textOnMediaSecondary()) })
        }
      }.width(36).height(36).borderRadius(18).backgroundColor('rgba(0,0,0,0.2)')
        .position({ right: 10, top: 10 }).accessibilityText('乐签更多操作').bindMenu(this.menuOptions())
    }.width('100%').height(this.heroSize()).borderRadius(16).clip(true)
  }

  @Builder
  private WishCalendar() {
    Row({ space: 18 }) {
      Column({ space: 5 }) {
        Row({ space: 3 }) {
          Text(DailyExtraService.signDate(this.info).month).fontSize(30).fontColor(TC.textPrimary()).fontWeight(FontWeight.Regular)
          Text('月').fontSize(10).fontColor(TC.textTertiary()).margin({ bottom: 5 })
        }.alignItems(VerticalAlign.Bottom)
        Row({ space: 3 }) {
          Text(DailyExtraService.signDate(this.info).day).fontSize(38).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          Text('日').fontSize(10).fontColor(TC.textTertiary()).margin({ bottom: 6 })
        }.alignItems(VerticalAlign.Bottom)
      }.width(64).alignItems(HorizontalAlign.Start)
      Column({ space: 9 }) {
        Text(this.info.wishWords || '暂无今日寄语').fontSize(16).fontWeight(FontWeight.Medium).lineHeight(24)
          .fontColor(TC.textBody()).width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.info.wishAuthor) {
          Text('— ' + this.info.wishAuthor).fontSize(11).fontColor(TC.textTertiary()).width('100%')
            .maxLines(1).textAlign(TextAlign.End).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').height(136).padding({ top: 12, bottom: 12 })
  }

  @Builder
  private Perforation() {
    Row() {
      ForEach(this.dots(), (index: number) => {
        Circle().width(3).height(3).fill(TC.textTertiary()).opacity(0.42)
      }, (index: number) => String(index))
    }.width('100%').height(14).justifyContent(FlexAlign.SpaceBetween)
  }

  private dots(): number[] {
    const dots: number[] = []
    for (let index = 0; index < Math.max(12, Math.floor(this.heroSize() / 9)); index++) { dots.push(index) }
    return dots
  }

  @Builder
  private Laurel(mirrored: boolean) {
    Stack() {
      ForEach([0, 1, 2, 3, 4], (index: number) => {
        Ellipse().width(4).height(8).fill('#b89486').rotate({ angle: -35 + index * 5 })
          .position({ x: 5 - Math.sin(index / 4 * Math.PI) * 3, y: index * 5 })
        Ellipse().width(4).height(7).fill('#b89486').rotate({ angle: 40 })
          .position({ x: 10 - Math.sin(index / 4 * Math.PI) * 4, y: index * 5 + 2 })
      })
    }.width(18).height(31).scale({ x: mirrored ? -1 : 1, y: 1 })
  }

  @Builder
  private RewardSummary() {
    Row() {
      Column({ space: 5 }) {
        Row({ space: 4 }) {
          Text(String(this.info.monthDays)).fontSize(27).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          Text('天').fontSize(12).fontColor(TC.textSecondary()).margin({ bottom: 4 })
        }.alignItems(VerticalAlign.Bottom)
        Text('本月累计打卡').fontSize(11).fontColor(TC.textTertiary())
      }.layoutWeight(1).alignItems(HorizontalAlign.Center)
      Column().width(1).height(38).backgroundColor(TC.divider()).opacity(0.5)
      Column({ space: 5 }) {
        if (DailyExtraService.nextSignPrize(this.info)) {
          Row({ space: 4 }) {
            this.Laurel(false)
            Text(DailyExtraService.nextSignPrize(this.info)?.subtitle || DailyExtraService.nextSignPrize(this.info)?.name || '签到奖励')
              .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#a77868').maxLines(1)
            this.Laurel(true)
          }
          Text(`${DailyExtraService.nextSignPrize(this.info)?.name || ''} · ${DailyExtraService.nextSignPrize(this.info)?.day || 0}天奖励 ›`)
            .fontSize(10).fontColor(TC.textTertiary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        } else { Text('暂无奖励信息').fontSize(12).fontColor(TC.textTertiary()) }
      }.layoutWeight(1).alignItems(HorizontalAlign.Center).enabled(this.info.prizes.length > 0).onClick(() => this.toggleRewards())
    }.width('100%').height(76)
  }

  @Builder
  private Rewards() {
    if (this.rewardsExpanded) {
      Column() {
        ForEach(this.info.prizes, (prize: VipSignPrize) => {
          Row({ space: 10 }) {
            Text(`${prize.day}天`).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#a77868').width(38)
            Column({ space: 3 }) {
              Text(prize.name).fontSize(13).fontColor(TC.textPrimary())
              Text(prize.subtitle).fontSize(11).fontColor(TC.textTertiary())
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text(DailyExtraService.signPrizeStatus(this.info, prize)).fontSize(11).fontColor(TC.textSecondary())
          }.width('100%').height(50)
        }, (prize: VipSignPrize) => `${prize.id}-${prize.day}`)
      }.width('100%').padding({ top: 8 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.info.song.img && !this.coverFailed) {
        Image(resizeImageUrl(this.info.song.img, 240, 240)).width('100%').height('100%')
          .sourceSize({ width: 240, height: 240 }).objectFit(ImageFit.Cover).blur(64).scale({ x: 1.25, y: 1.25 })
          .hitTestBehavior(HitTestMode.None)
      }
      Column().width('100%').height('100%').backgroundColor(TC.sheetBackground()).opacity(0.84)
        .hitTestBehavior(HitTestMode.None)
      Scroll() {
        Column() {
          this.Hero()
          Divider().strokeWidth(1).color(TC.divider()).opacity(0.5).margin({ top: 16 })
          this.WishCalendar()
          this.Perforation()
          this.RewardSummary()
          this.Rewards()
        }.width('100%').padding(14)
      }.width('100%').height('100%').scrollBar(BarState.Off)
    }.width('90%').height(this.cardHeight()).constraintSize({ maxWidth: 400, maxHeight: '84%' })
      .backgroundColor(TC.surfaceCard()).borderRadius(22).clip(true)
      .border({ width: 1, color: TC.borderSubtle() })
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.24)', offsetY: 10 })
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width)
        if (width > 0 && Math.abs(width - this.cardWidth) > 1) { this.cardWidth = width }
      })
  }
}
