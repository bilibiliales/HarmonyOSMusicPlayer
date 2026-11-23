import { common } from '@kit.AbilityKit'
import { LyricExportService } from '../services/LyricExportService'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { LyricMarkEditorParam, LyricMarkVO } from '../models/lyricmark'
import { songItemType } from '../models/music'
import { LyricMarkService } from '../services/LyricMarkService'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'
import { BubbleTip } from '../services/BubbleTip'
import { Responsive } from '../services/Responsive'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { TC } from '../services/ThemeColors'

const PAGE_SIZE: number = 20

/**
 * 歌词本：我摘录过的歌词。
 * 手机一行一张卡片，平板一行两张；每张卡片依次是时间、歌词、音/译词、播放组件。
 */
@Component
export struct LyricBookPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @Consume('playerStore') playerStore: PlayerStore

  @State marks: LyricMarkVO[] = []
  @State loading: boolean = false
  @State loadingMore: boolean = false
  @State hasMore: boolean = false
  @State message: string = ''
  @State viewWidth: number = 0
  private cursor: number = 0
  private requestSeq: number = 0
  private wasLoggedIn: boolean = false

  aboutToAppear(): void {
    this.wasLoggedIn = this.authStore.loggedIn
    if (this.authStore.loggedIn) {
      this.refresh()
    }
  }

  private async refresh(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.marks = []
      this.message = ''
      return
    }
    const seq = ++this.requestSeq
    this.loading = true
    this.message = ''
    try {
      const page = await LyricMarkService.mine(PAGE_SIZE, 0)
      if (seq !== this.requestSeq) {
        return
      }
      this.marks = page.markVOList
      this.cursor = page.offset
      this.hasMore = page.hasMore
    } catch (error) {
      if (seq === this.requestSeq) {
        this.message = error instanceof Error ? error.message : '歌词本加载失败'
      }
    } finally {
      if (seq === this.requestSeq) {
        this.loading = false
      }
    }
  }

  private async loadMore(): Promise<void> {
    if (this.loading || this.loadingMore || !this.hasMore) {
      return
    }
    const seq = this.requestSeq
    this.loadingMore = true
    try {
      const page = await LyricMarkService.mine(PAGE_SIZE, this.cursor)
      if (seq !== this.requestSeq) {
        return
      }
      const merged: LyricMarkVO[] = this.marks.slice()
      for (let i = 0; i < page.markVOList.length; i++) {
        const next = page.markVOList[i]
        if (!merged.some((item: LyricMarkVO) => item.markId === next.markId)) {
          merged.push(next)
        }
      }
      this.marks = merged
      this.cursor = page.offset
      this.hasMore = page.hasMore
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '加载更多失败')
    } finally {
      this.loadingMore = false
    }
  }

  private columns(): number {
    return this.viewWidth >= Responsive.MEDIUM ? 2 : 1
  }

  private markTime(mark: LyricMarkVO): string {
    const stamp = mark.createTime || mark.updateTime || 0
    if (stamp <= 0) {
      return ''
    }
    return this.formatDate(stamp)
  }

  private formatDate(ms: number): string {
    const date = new Date(ms)
    const month = date.getMonth() + 1
    const day = date.getDate()
    const hour = date.getHours()
    const minute = date.getMinutes()
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value)
    return `${date.getFullYear()}-${pad(month)}-${pad(day)} ${pad(hour)}:${pad(minute)}`
  }

  /** 歌词在歌曲里的时间点，例如 01:27。 */
  private stampText(mark: LyricMarkVO): string {
    const detail = mark.detailList && mark.detailList.length > 0 ? mark.detailList[0] : undefined
    const ms = detail ? detail.startTimeStamp : 0
    if (!ms || ms <= 0) {
      return ''
    }
    const total = Math.floor(ms / 1000)
    const minute = Math.floor(total / 60)
    const second = total % 60
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value)
    return `${pad(minute)}:${pad(second)}`
  }

  private original(mark: LyricMarkVO): string {
    const detail = mark.detailList && mark.detailList.length > 0 ? mark.detailList[0] : undefined
    return detail ? (detail.originalLyricsText || '') : ''
  }

  private translateType(mark: LyricMarkVO): number {
    const detail = mark.detailList && mark.detailList.length > 0 ? mark.detailList[0] : undefined
    return detail ? (detail.translateType || 0) : 0
  }

  private translateText(mark: LyricMarkVO): string {
    const detail = mark.detailList && mark.detailList.length > 0 ? mark.detailList[0] : undefined
    if (!detail || detail.translateType === 0) {
      return ''
    }
    return detail.translateLyricsText || ''
  }

  private translateLabel(mark: LyricMarkVO): string {
    return this.translateType(mark) === 2 ? '音' : '译'
  }

  private songOf(mark: LyricMarkVO): songItemType {
    return LyricMarkService.toSong(mark)
  }

  private async play(mark: LyricMarkVO): Promise<void> {
    const song = this.songOf(mark)
    const queue = this.playerStore.queue.slice()
    let index = queue.findIndex((item: songItemType) => item.id === song.id)
    if (index < 0) {
      queue.push(song)
      index = queue.length - 1
    }
    try {
      await playerController.setQueue(queue, index, true)
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败')
    }
  }

  private shareOptions(mark: LyricMarkVO): MenuElement[] {
    return [
      { value: '下载歌词', action: () => { this.exportLyrics(mark, 'download') } },
      { value: '复制歌词', action: () => { this.exportLyrics(mark, 'copy') } },
      { value: '分享歌词', action: () => { this.exportLyrics(mark, 'share') } }
    ]
  }

  private async exportLyrics(mark: LyricMarkVO, action: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (action === 'copy') {
        await LyricExportService.copy(mark)
        BubbleTip.show(this.getUIContext(), '歌词已复制')
      } else if (action === 'download') {
        if (await LyricExportService.download(context, mark)) {
          BubbleTip.show(this.getUIContext(), '歌词已保存')
        }
      } else {
        await LyricExportService.share(context, mark)
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '歌词导出失败')
    }
  }

  private openEditor(mark: LyricMarkVO): void {
    const param: LyricMarkEditorParam = {
      mark: mark,
      onSaved: () => { this.refresh() }
    }
    this.pageStack.pushPathByName('LyricMarkEditorPage', param)
  }

  private confirmRemove(mark: LyricMarkVO): void {
    this.getUIContext().showAlertDialog({
      title: '删除摘录',
      message: `「${this.original(mark)}」将从歌词本中移除，此操作无法撤销。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: TC.accent(),
        action: () => { this.remove(mark) }
      }
    })
  }

  private async remove(mark: LyricMarkVO): Promise<void> {
    try {
      await LyricMarkService.remove(mark.markId)
      this.marks = this.marks.filter((item: LyricMarkVO) => item.markId !== mark.markId)
      BubbleTip.show(this.getUIContext(), '已删除')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '删除失败')
    }
  }

  @Builder
  private CardActions(mark: LyricMarkVO) {
    Row({ space: 0 }) {
      SymbolGlyph($r('sys.symbol.share')).fontSize(15).fontColor([TC.textTertiary()])
        .padding(7).accessibilityText('分享歌词').bindMenu(this.shareOptions(mark))
      SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(15).fontColor([TC.textTertiary()])
        .padding(7).onClick(() => this.openEditor(mark))
      SymbolGlyph($r('sys.symbol.trash')).fontSize(15).fontColor([TC.textTertiary()])
        .padding(7).onClick(() => this.confirmRemove(mark))
    }.margin({ top: -6 })
  }

  @Builder
  private PlayerRow(mark: LyricMarkVO) {
    Row({ space: 10 }) {
      if (this.songOf(mark).img.length > 0) {
        Image(resizeImageUrl(this.songOf(mark).img, 96, 96)).width(42).height(42)
          .sourceSize({ width: 96, height: 96 }).borderRadius(10).objectFit(ImageFit.Cover)
      } else {
        Stack() { SymbolGlyph($r('sys.symbol.music')).fontSize(20).fontColor([TC.textQuaternary()]) }
          .width(42).height(42).borderRadius(10).backgroundColor(TC.surfaceRaised())
      }
      Column({ space: 3 }) {
        Text(this.songOf(mark).name).width('100%').fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(TC.textBody()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.songOf(mark).author).width('100%').fontSize(10).fontColor(TC.textTertiary())
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(22).fontColor([TC.textPrimary()])
    }
    .width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 })
    .backgroundColor(TC.surfaceInset()).borderRadius(12)
    .onClick(() => this.play(mark))
  }

  @Builder
  private MarkCard(mark: LyricMarkVO) {
    Column({ space: 9 }) {
      Row() {
        Row({ space: 5 }) {
          if (this.markTime(mark).length > 0) {
            Text(this.markTime(mark)).fontSize(10).fontColor(TC.textQuaternary())
          }
          if (this.markTime(mark).length > 0 && this.stampText(mark).length > 0) {
            Text('·').fontSize(10).fontColor(TC.textQuaternary())
          }
          if (this.stampText(mark).length > 0) {
            Text(this.stampText(mark)).fontSize(10).fontColor(TC.textQuaternary())
          }
        }.layoutWeight(1)

        this.CardActions(mark)
      }.width('100%').alignItems(VerticalAlign.Top)

      Text(this.original(mark))
        .width('100%').fontSize(15).lineHeight(23).fontWeight(FontWeight.Medium)
        .fontColor(TC.textPrimary()).maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ minHeight: 46 })

      if (this.translateText(mark).length > 0) {
        Row({ space: 6 }) {
          Text(this.translateLabel(mark)).fontSize(9).fontColor(TC.accent())
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor(TC.accentContainer()).borderRadius(4)
          Text(this.translateText(mark)).fontSize(11).lineHeight(17).fontColor(TC.accentSoft())
            .layoutWeight(1).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').alignItems(VerticalAlign.Top)
      }

      this.PlayerRow(mark)
    }
    .width('100%').padding(14).backgroundColor(TC.surfaceCard()).borderRadius(16)
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.text_alignleft')).fontSize(34).fontColor([TC.textQuaternary()])
      Text('还没有摘录的歌词').fontSize(14).fontColor(TC.textSecondary())
      Text('在歌曲里摘录喜欢的歌词，会出现在这里').fontSize(11).fontColor(TC.textTertiary())
    }.width('100%').padding({ top: 80 })
  }

  @Builder
  private LoginState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.text_alignleft')).fontSize(34).fontColor([TC.textQuaternary()])
      Text('登录后查看我的歌词本').fontSize(14).fontColor(TC.textSecondary())
      Text('登录')
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(TC.textOnAccent())
        .padding({ left: 22, right: 22, top: 9, bottom: 9 })
        .backgroundColor(TC.accent()).borderRadius(18)
        .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
    }.width('100%').padding({ top: 80 })
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('歌词本').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(22).fontColor([TC.textTertiary()])
            .onClick(() => this.refresh())
        }.height(56).constraintSize({ minHeight: 56 }).width('100%').padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 0 }) {
            if (!this.authStore.loggedIn) {
              this.LoginState()
            } else if (this.loading && this.marks.length === 0) {
              LoadingProgress().width(32).height(32).color(TC.accent())
                .alignSelf(ItemAlign.Center).padding({ top: 60 })
            } else if (this.marks.length === 0) {
              if (this.message.length > 0) {
                Column({ space: 10 }) {
                  Text(this.message).fontSize(13).fontColor(TC.textSecondary()).textAlign(TextAlign.Center)
                  Text('重新加载').fontSize(12).fontColor(TC.accent())
                    .padding({ top: 4, bottom: 4, left: 8, right: 8 })
                    .onClick(() => this.refresh())
                }.width('100%').padding({ top: 60 })
              } else {
                this.EmptyState()
              }
            } else {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                ForEach(this.marks, (mark: LyricMarkVO) => {
                  Column() {
                    this.MarkCard(mark)
                  }
                  .width(Responsive.itemPercent(this.columns()))
                  .margin({ bottom: 12 })
                }, (mark: LyricMarkVO) => `${mark.markId}-${mark.updateTime || 0}`)
              }.width('100%')

              if (this.loadingMore) {
                LoadingProgress().width(22).height(22).color(TC.accent())
                  .alignSelf(ItemAlign.Center).margin({ top: 4, bottom: 10 })
              } else if (!this.hasMore) {
                Text('没有更多摘录了').width('100%').fontSize(11).fontColor(TC.textTertiary())
                  .textAlign(TextAlign.Center).padding({ top: 6, bottom: 16 })
              }
            }
          }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 20 })
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .onReachEnd(() => this.loadMore())
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width)
        if (width !== this.viewWidth) {
          this.viewWidth = width
        }
      })

    }.hideTitleBar(true).onShown(() => {
      // 从登录页返回时补一次加载
      if (this.authStore.loggedIn && !this.wasLoggedIn) {
        this.wasLoggedIn = true
        this.refresh()
      }
    })
  }
}
