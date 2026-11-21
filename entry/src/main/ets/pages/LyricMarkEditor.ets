import { SkinBackdrop } from '../components/SkinBackdrop'
import { LyricMarkDetail, LyricMarkDraft, LyricMarkEditorParam, LyricMarkVO } from '../models/lyricmark'
import { songItemType } from '../models/music'
import { LyricMarkService } from '../services/LyricMarkService'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'

/** 编辑一条歌词摘录：原文、译文/音译与时间点。 */
@Component
export struct LyricMarkEditorPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number

  pageParam: LyricMarkEditorParam = {
    mark: { markId: 0, songId: 0, songData: { id: 0, name: '' }, detailList: [] },
    onSaved: () => {}
  }

  @State original: string = ''
  @State translate: string = ''
  @State translateType: number = 0
  @State stamp: string = '00:00'
  @State saving: boolean = false

  aboutToAppear(): void {
    const details = this.pageParam.mark.detailList || []
    const detail: LyricMarkDetail | undefined = details.length > 0 ? details[0] : undefined
    this.original = detail ? (detail.originalLyricsText || '') : ''
    this.translateType = detail ? (detail.translateType || 0) : 0
    this.translate = detail && detail.translateLyricsText ? detail.translateLyricsText : ''
    this.stamp = this.formatStamp(detail ? detail.startTimeStamp : 0)
  }

  private song(): songItemType {
    return LyricMarkService.toSong(this.pageParam.mark)
  }

  private formatStamp(ms: number): string {
    const total = Math.floor(Math.max(0, ms) / 1000)
    const minute = Math.floor(total / 60)
    const second = total % 60
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value)
    return `${pad(minute)}:${pad(second)}`
  }

  /** mm:ss / mm:ss.SSS / 纯秒数 → 毫秒；格式不对返回 -1。 */
  private parseStamp(text: string): number {
    const clean = text.trim().replace('：', ':')
    if (clean.length === 0) {
      return 0
    }
    const parts = clean.split(':')
    if (parts.length === 1) {
      const seconds = Number(parts[0])
      return Number.isFinite(seconds) && seconds >= 0 ? Math.round(seconds * 1000) : -1
    }
    if (parts.length !== 2) {
      return -1
    }
    const minutes = Number(parts[0])
    const seconds = Number(parts[1].replace(':', '.'))
    if (!Number.isFinite(minutes) || !Number.isFinite(seconds) || minutes < 0 || seconds < 0) {
      return -1
    }
    return Math.round(minutes * 60000 + seconds * 1000)
  }

  private async play(): Promise<void> {
    try {
      await playerController.setQueue([this.song()], 0, true)
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败')
    }
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return
    }
    const original = this.original.trim()
    if (original.length === 0) {
      BubbleTip.show(this.getUIContext(), '歌词内容不能为空')
      return
    }
    const stamp = this.parseStamp(this.stamp)
    if (stamp < 0) {
      BubbleTip.show(this.getUIContext(), '时间格式应为 分:秒，例如 01:27')
      return
    }
    const translateText = this.translate.trim()
    const type = translateText.length > 0 ? this.translateType : 0

    this.saving = true
    try {
      const draft: LyricMarkDraft = {
        songId: String(this.pageParam.mark.songId),
        markId: this.pageParam.mark.markId,
        startTimeStamp: stamp,
        originalLyricsText: original,
        translateType: type,
        translateLyricsText: type === 0 ? '' : translateText
      }
      await LyricMarkService.save(draft)

      const detail: LyricMarkDetail = {
        startTimeStamp: stamp,
        originalLyricsText: original,
        translateType: type,
        translateLyricsText: type === 0 ? '' : translateText
      }
      const details: LyricMarkDetail[] = [detail]
      const updated: LyricMarkVO = {
        markId: this.pageParam.mark.markId,
        songId: this.pageParam.mark.songId,
        songData: this.pageParam.mark.songData,
        canShare: this.pageParam.mark.canShare,
        createTime: this.pageParam.mark.createTime,
        updateTime: Date.now(),
        detailList: details
      }
      this.pageParam.onSaved(updated)
      BubbleTip.show(this.getUIContext(), '摘录已保存')
      this.pageStack.pop()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '摘录保存失败')
    } finally {
      this.saving = false
    }
  }

  @Builder
  private TypeChip(type: number, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.translateType === type ? TC.textOnAccent() : TC.textSecondary())
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.translateType === type ? TC.accent() : TC.chipBackground())
      .borderRadius(14)
      .onClick(() => this.translateType = type)
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('编辑摘录').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          Text(this.saving ? '保存中…' : '保存')
            .fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.saving ? TC.textTertiary() : TC.accent())
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .enabled(!this.saving)
            .onClick(() => this.save())
        }.height(56).constraintSize({ minHeight: 56 }).width('100%').padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 16 }) {
            Row({ space: 12 }) {
              if (this.song().img.length > 0) {
                Image(resizeImageUrl(this.song().img, 128, 128)).width(52).height(52)
                  .sourceSize({ width: 128, height: 128 }).borderRadius(12).objectFit(ImageFit.Cover)
              } else {
                Stack() { SymbolGlyph($r('sys.symbol.music')).fontSize(22).fontColor([TC.textQuaternary()]) }
                  .width(52).height(52).borderRadius(12).backgroundColor(TC.surfaceRaised())
              }
              Column({ space: 4 }) {
                Text(this.song().name).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(TC.textPrimary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.song().author).width('100%').fontSize(11).fontColor(TC.textSecondary())
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(26).fontColor([TC.textPrimary()])
                .onClick(() => this.play())
            }.width('100%').padding(14).backgroundColor(TC.surfaceCard()).borderRadius(16)

            Column({ space: 8 }) {
              Row() {
                Text('歌词原文').fontSize(13).fontWeight(FontWeight.Medium).fontColor(TC.textPrimary())
                Text('*').fontSize(13).fontColor(TC.accent())
              }.width('100%')
              TextArea({ text: this.original, placeholder: '摘录的歌词内容' })
                .width('100%').height(96).fontSize(15).fontColor(TC.textPrimary())
                .placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceCardAlt())
                .borderRadius(12).onChange((value: string) => this.original = value)
            }.width('100%').padding(14).backgroundColor(TC.surfaceCard()).borderRadius(16)

            Column({ space: 10 }) {
              Row() {
                Text('译文 / 音译').fontSize(13).fontWeight(FontWeight.Medium).fontColor(TC.textPrimary())
                Blank()
                Text('可留空').fontSize(11).fontColor(TC.textTertiary())
              }.width('100%')
              Row({ space: 8 }) {
                this.TypeChip(0, '不添加')
                this.TypeChip(1, '译文')
                this.TypeChip(2, '音译')
              }.width('100%')
              if (this.translateType !== 0) {
                TextArea({
                  text: this.translate,
                  placeholder: this.translateType === 2 ? '罗马音，例如 yi zei yei yv guong zong' : '中文翻译'
                })
                  .width('100%').height(80).fontSize(13).fontColor(TC.textPrimary())
                  .placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceCardAlt())
                  .borderRadius(12).onChange((value: string) => this.translate = value)
              }
            }.width('100%').padding(14).backgroundColor(TC.surfaceCard()).borderRadius(16)

            Column({ space: 10 }) {
              Text('歌词时间点').fontSize(13).fontWeight(FontWeight.Medium).fontColor(TC.textPrimary())
                .width('100%')
              TextInput({ text: this.stamp, placeholder: '01:27' })
                .width('100%').height(42).fontSize(14).fontColor(TC.textPrimary())
                .placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceCardAlt())
                .borderRadius(12).type(InputType.Normal)
                .onChange((value: string) => this.stamp = value)
              Text('对应歌词在歌曲中的位置，格式为 分:秒；改动后歌词本里显示的时间点同步更新。')
                .width('100%').fontSize(11).lineHeight(16).fontColor(TC.textTertiary())
            }.width('100%').padding(14).backgroundColor(TC.surfaceCard()).borderRadius(16)

            Text('摘录会同步到网易云的「我的歌词本」。')
              .width('100%').fontSize(11).fontColor(TC.textTertiary())
              .textAlign(TextAlign.Center).padding({ top: 2, bottom: 20 })
          }
          .width('100%').padding({ left: 16, right: 16, top: 8 })
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true)
  }
}
