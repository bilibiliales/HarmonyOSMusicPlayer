import { common } from '@kit.AbilityKit'
import { fileUri } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { BubbleTip } from '../services/BubbleTip'
import { RingtoneService, RINGTONE_TYPE_TITLES } from '../services/RingtoneService'
import { SongMetadataCache } from '../services/SongMetadataCache'
import { TC } from '../services/ThemeColors'
import { QualityOption, songItemType } from '../models/music'

export interface RingtonePageParam {
  song: songItemType
}

interface RingtoneLyric {
  time: number
  text: string
}

const BAR_COUNT: number = 56

@Component
export struct RingtonePage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State pageParam: RingtonePageParam = { song: {} as songItemType }
  @State typeIndex: number = 0
  @State maxSeconds: number = 60
  @State qualities: QualityOption[] = []
  @State qualityIndex: number = 0
  @State startSec: number = 0
  @State endSec: number = 60
  @State durationSec: number = 0
  @State preparing: boolean = false
  @State progress: number = 0
  @State message: string = ''
  @State audioPath: string = ''
  @State bars: number[] = []
  @State lyrics: RingtoneLyric[] = []
  @State lyricHeight: number = 0
  @State waveWidth: number = 0
  @State saving: boolean = false
  @State applying: boolean = false
  @State previewing: boolean = false

  private previewPlayer?: media.AVPlayer
  private clipPath: string = ''
  private clipKey: string = ''
  private dragBaseStart: number = 0
  private dragBaseEnd: number = 0

  aboutToAppear(): void {
    const song = this.pageParam.song
    if (!song || !song.id) {
      this.message = '没有可用的歌曲信息'
      return
    }
    this.typeIndex = 0
    this.maxSeconds = RingtoneService.maxSeconds(this.typeIndex)
    this.loadQualities()
  }

  aboutToDisappear(): void {
    this.stopPreview()
  }

  private song(): songItemType {
    return this.pageParam.song
  }

  private async loadQualities(): Promise<void> {
    this.preparing = true
    this.message = ''
    this.progress = 0
    try {
      const options = await RingtoneService.availableQualities(this.song())
      this.qualities = options
      this.qualityIndex = 0
      await this.loadAudio()
    } catch (error) {
      this.message = error instanceof Error ? error.message : '铃声准备失败'
      this.preparing = false
    }
  }

  private async loadAudio(): Promise<void> {
    const option = this.qualities.length > 0 ? this.qualities[this.qualityIndex] : undefined
    const level = option ? option.level : 'standard'
    this.preparing = true
    this.message = ''
    this.progress = 0
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const audio = await RingtoneService.prepare(context, this.song(), level,
        (percent: number) => { this.progress = percent })
      this.audioPath = audio.path
      this.durationSec = Math.max(1, Math.round(audio.durationMs / 1000))
      this.clipKey = ''
      this.startSec = 0
      this.endSec = Math.min(this.maxSeconds, this.durationSec)
      this.bars = await RingtoneService.waveform(audio.path, BAR_COUNT)
      await this.loadLyrics()
    } catch (error) {
      this.audioPath = ''
      this.message = error instanceof Error ? error.message : '音频准备失败'
    } finally {
      this.preparing = false
    }
  }

  private async loadLyrics(): Promise<void> {
    this.lyrics = []
    try {
      const response = await SongMetadataCache.lyrics(this.song())
      const raw = response.lrc?.lyric || ''
      if (!raw) { return }
      const rows = raw.split('\n')
      const result: RingtoneLyric[] = []
      for (let i = 0; i < rows.length; i++) {
        const line = this.parseLyricLine(rows[i])
        if (line) { result.push(line) }
      }
      result.sort((left: RingtoneLyric, right: RingtoneLyric) => left.time - right.time)
      this.lyrics = result
    } catch (_error) {
      this.lyrics = []
    }
  }

  private parseLyricLine(raw: string): RingtoneLyric | undefined {
    const row = raw.trim()
    if (row.length < 6 || row.charAt(0) !== '[') { return undefined }
    const close = row.indexOf(']')
    if (close < 0) { return undefined }
    const stamp = row.substring(1, close)
    const text = row.substring(close + 1).trim()
    if (!text) { return undefined }
    const parts = stamp.split(':')
    if (parts.length < 2) { return undefined }
    const minutes = Number(parts[0])
    const seconds = Number(parts[1])
    if (!Number.isFinite(minutes) || !Number.isFinite(seconds)) { return undefined }
    return { time: Math.round((minutes * 60 + seconds) * 1000), text: text }
  }

  private windowLyrics(): RingtoneLyric[] {
    const from = this.startSec * 1000 - 400
    const to = this.endSec * 1000
    const result: RingtoneLyric[] = []
    for (let i = 0; i < this.lyrics.length; i++) {
      const line = this.lyrics[i]
      if (line.time >= from && line.time < to) {
        result.push(line)
        if (result.length >= 40) { break }
      }
    }
    return result
  }

  private clampSelection(): void {
    const maxEnd = Math.min(this.durationSec, this.startSec + this.maxSeconds)
    if (this.endSec > maxEnd) { this.endSec = maxEnd }
    if (this.endSec - this.startSec < 1) {
      this.endSec = Math.min(this.durationSec, this.startSec + 1)
      if (this.endSec - this.startSec < 1) {
        this.startSec = Math.max(0, this.endSec - 1)
      }
    }
    if (this.startSec < 0) { this.startSec = 0 }
  }

  private setStart(value: number): void {
    const limit = Math.max(0, this.endSec - 1)
    this.startSec = Math.min(limit, Math.max(0, value))
    this.clipKey = ''
  }

  private setEnd(value: number): void {
    const floor = this.startSec + 1
    const ceiling = Math.min(this.durationSec, this.startSec + this.maxSeconds)
    this.endSec = Math.max(floor, Math.min(ceiling, value))
    this.clipKey = ''
  }

  private selectType(index: number): void {
    if (this.typeIndex === index) { return }
    this.typeIndex = index
    this.maxSeconds = RingtoneService.maxSeconds(index)
    this.clampSelection()
    this.clipKey = ''
  }

  private async selectQuality(index: number): Promise<void> {
    if (this.qualityIndex === index || this.preparing) { return }
    this.qualityIndex = index
    this.stopPreview()
    await this.loadAudio()
  }

  private timeText(seconds: number): string {
    const total = Math.max(0, Math.round(seconds))
    const mm = Math.floor(total / 60)
    const ss = total % 60
    return `${mm < 10 ? '0' : ''}${mm}:${ss < 10 ? '0' : ''}${ss}`
  }

  private selectedSeconds(): number {
    return Math.max(0, this.endSec - this.startSec)
  }

  private async buildClip(): Promise<string> {
    if (!this.audioPath) { return '' }
    const key = `${this.audioPath}:${Math.round(this.startSec * 1000)}:${Math.round(this.endSec * 1000)}`
    if (this.clipPath && key === this.clipKey) { return this.clipPath }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const clip = await RingtoneService.renderClip(context, this.audioPath,
      Math.round(this.startSec * 1000), Math.round(this.endSec * 1000))
    this.clipPath = clip.path
    this.clipKey = key
    return clip.path
  }

  private async togglePreview(): Promise<void> {
    if (this.previewing) {
      await this.stopPreview()
      return
    }
    try {
      const path = await this.buildClip()
      if (!path) { return }
      const player = await media.createAVPlayer()
      this.previewPlayer = player
      player.on('stateChange', (state: media.AVPlayerState) => {
        if (player !== this.previewPlayer) { return }
        if (state === 'initialized') {
          player.prepare().catch(() => this.stopPreview())
        } else if (state === 'prepared') {
          player.loop = true
          player.play().catch(() => this.stopPreview())
        }
      })
      player.on('error', () => {
        this.stopPreview()
      })
      player.url = fileUri.getUriFromPath(path)
      this.previewing = true
    } catch (error) {
      this.previewing = false
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '试听失败')
    }
  }

  private async stopPreview(): Promise<void> {
    const player = this.previewPlayer
    this.previewPlayer = undefined
    this.previewing = false
    if (player) {
      try {
        await player.release()
      } catch (_error) {
      }
    }
  }

  private async saveAudio(): Promise<void> {
    if (this.saving || this.preparing) { return }
    this.saving = true
    await this.stopPreview()
    try {
      const path = await this.buildClip()
      if (!path) { return }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const label = RingtoneService.safeName(this.song().name || '铃声')
      const saved = await RingtoneService.saveCopy(context, path, `${label}-铃声.mp3`)
      BubbleTip.show(this.getUIContext(), saved ? `已保存 ${saved}` : '已取消保存')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '保存失败')
    } finally {
      this.saving = false
    }
  }

  private async applyRingtone(): Promise<void> {
    if (this.applying || this.preparing) { return }
    this.applying = true
    await this.stopPreview()
    try {
      const path = await this.buildClip()
      if (!path) { return }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const label = RingtoneService.safeName(this.song().name || '铃声')
      const chosen = await RingtoneService.apply(context, path, `${label}.mp3`)
      BubbleTip.show(this.getUIContext(), `已设为${RingtoneService.typeTitle(chosen)}`)
    } catch (error) {
      const message = error instanceof Error ? error.message : '设置铃声失败'
      if (message.indexOf('cancel') < 0 && message.indexOf('取消') < 0) {
        BubbleTip.show(this.getUIContext(), message)
      }
    } finally {
      this.applying = false
    }
  }

  private startX(): number {
    if (this.durationSec <= 0 || this.waveWidth <= 0) { return 0 }
    return Math.min(this.waveWidth, Math.max(0, this.startSec / this.durationSec * this.waveWidth))
  }

  private endX(): number {
    if (this.durationSec <= 0 || this.waveWidth <= 0) { return 0 }
    return Math.min(this.waveWidth, Math.max(0, this.endSec / this.durationSec * this.waveWidth))
  }

  @Builder
  private TypeChips() {
    Row({ space: 8 }) {
      ForEach(RINGTONE_TYPE_TITLES, (title: string, index: number) => {
        Text(title)
          .fontSize(12)
          .fontColor(this.typeIndex === index ? TC.textOnAccent() : TC.textSecondary())
          .backgroundColor(this.typeIndex === index ? TC.accent() : TC.chipBackground())
          .borderRadius(15)
          .height(30)
          .padding({ left: 12, right: 12 })
          .textAlign(TextAlign.Center)
          .onClick(() => this.selectType(index))
      })
    }
    .width('100%')
  }

  @Builder
  private QualityRow() {
    Scroll() {
      Row({ space: 8 }) {
        Text('音质').fontSize(11).fontColor(TC.textTertiary()).margin({ right: 2 })
        ForEach(this.qualities, (option: QualityOption, index: number) => {
          Text(option.title)
            .fontSize(11)
            .fontColor(this.qualityIndex === index ? TC.textPrimary() : TC.textTertiary())
            .backgroundColor(this.qualityIndex === index ? TC.chipBackground() : Color.Transparent)
            .borderRadius(12)
            .height(26)
            .padding({ left: 10, right: 10 })
            .border({
              width: 1,
              color: this.qualityIndex === index ? TC.borderSubtle() : 'rgba(128,128,128,0.22)'
            })
            .onClick(() => this.selectQuality(index))
        })
      }
      .height(40)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(40)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  private MarkerTag(label: string, time: string) {
    Row({ space: 4 }) {
      Text(time).fontSize(10).fontColor(TC.textOnAccent())
      Text(label).fontSize(10).fontColor(TC.textOnAccent()).fontWeight(FontWeight.Medium)
    }
    .height(18)
    .padding({ left: 8, right: 8 })
    .backgroundColor(TC.accent())
    .borderRadius(9)
  }

  @Builder
  private LyricWindow() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.windowLyrics().length > 0) {
        Scroll() {
          Column({ space: 14 }) {
            ForEach(this.windowLyrics(), (line: RingtoneLyric) => {
              Text(line.text)
                .width('100%')
                .fontSize(15)
                .lineHeight(21)
                .fontColor(TC.textBody())
                .textAlign(TextAlign.Center)
            })
          }
          .width('100%')
          .padding({ top: 30, bottom: 30, left: 6, right: 6 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .scrollable(ScrollDirection.Vertical)
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(26).fontColor([TC.textQuaternary()])
          Text(this.lyrics.length > 0 ? '该片段内没有歌词' : '这首歌暂无歌词')
            .fontSize(12).fontColor(TC.textTertiary())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      // 顶部「开始」标签：上下拖动 = 粗调开始位置
      Row() {
        Row()
          .layoutWeight(1)
          .height(1)
          .border({ width: { top: 1 }, color: 'rgba(128,128,128,0.5)', style: BorderStyle.Dashed })
        this.MarkerTag('开始', this.timeText(this.startSec))
      }
      .width('100%')
      .height(26)
      .alignItems(VerticalAlign.Center)
      .position({ x: 0, y: 0 })
      .gesture(
        PanGesture()
          .onActionStart(() => { this.dragBaseStart = this.startSec })
          .onActionUpdate((event: GestureEvent) => {
            this.setStart(this.dragBaseStart + event.offsetY * 0.12)
          })
      )

      // 底部「结束」标签：上下拖动 = 粗调结束位置
      Row() {
        Row()
          .layoutWeight(1)
          .height(1)
          .border({ width: { top: 1 }, color: 'rgba(128,128,128,0.5)', style: BorderStyle.Dashed })
        this.MarkerTag('结束', this.timeText(this.endSec))
      }
      .width('100%')
      .height(26)
      .alignItems(VerticalAlign.Center)
      .position({ x: 0, y: Math.max(0, this.lyricHeight - 26) })
      .gesture(
        PanGesture()
          .onActionStart(() => { this.dragBaseEnd = this.endSec })
          .onActionUpdate((event: GestureEvent) => {
            this.setEnd(this.dragBaseEnd + event.offsetY * 0.12)
          })
      )
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .onAreaChange((_old: Area, area: Area) => {
      this.lyricHeight = Number(area.height)
    })
  }

  @Builder
  private WaveformStrip() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 1 }) {
        ForEach(this.bars, (value: number, index: number) => {
          Column()
            .width(2)
            .height(Math.max(4, Math.round(value * 44)))
            .borderRadius(1)
            .backgroundColor(TC.textTertiary())
            .opacity(0.55)
        })
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      Column()
        .width(Math.max(0, this.endX() - this.startX()))
        .height(48)
        .backgroundColor('rgba(255,255,255,0.10)')
        .border({ width: { left: 1, right: 1 }, color: TC.accent() })
        .position({ x: this.startX(), y: 0 })

      Column()
        .width(3)
        .height(52)
        .borderRadius(2)
        .backgroundColor(TC.accent())
        .position({ x: Math.max(0, this.startX() - 1), y: 0 })
        .gesture(
          PanGesture()
            .onActionStart(() => { this.dragBaseStart = this.startSec })
            .onActionUpdate((event: GestureEvent) => {
              if (this.waveWidth <= 0) { return }
              this.setStart(this.dragBaseStart + event.offsetX / this.waveWidth * this.durationSec)
            })
        )

      Column()
        .width(3)
        .height(52)
        .borderRadius(2)
        .backgroundColor(TC.accent())
        .position({ x: Math.max(0, this.endX() - 1), y: 0 })
        .gesture(
          PanGesture()
            .onActionStart(() => { this.dragBaseEnd = this.endSec })
            .onActionUpdate((event: GestureEvent) => {
              if (this.waveWidth <= 0) { return }
              this.setEnd(this.dragBaseEnd + event.offsetX / this.waveWidth * this.durationSec)
            })
        )
    }
    .width('100%')
    .height(52)
    .onAreaChange((_old: Area, area: Area) => {
      this.waveWidth = Math.max(0, Number(area.width))
    })
  }

  @Builder
  private PrepareOverlay() {
    Column({ space: 14 }) {
      LoadingProgress().width(38).height(38).color(TC.accent())
      Text(this.progress > 0 ? `正在准备音频 ${this.progress}%` : '正在准备音频…')
        .fontSize(12).fontColor(TC.textTertiary())
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorPanel() {
    Column({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(34).fontColor([TC.textTertiary()])
      Text(this.message).fontSize(13).fontColor(TC.textSecondary()).textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
      Button('重新准备')
        .height(38)
        .fontSize(14)
        .fontColor(TC.textOnAccent())
        .backgroundColor(TC.accent())
        .onClick(() => this.loadQualities())
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('设为铃声').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.bell_fill')).fontSize(14).fontColor([TC.textSecondary()])
            Text('更多铃声').fontSize(12).fontColor(TC.textSecondary())
          }
          .onClick(() => BubbleTip.show(this.getUIContext(), '可在系统设置中更换已有铃声'))
        }
        .width('100%')
        .height(52)
        .padding({ left: 12, right: 12 })

        if (this.preparing) {
          this.PrepareOverlay()
        } else if (!this.audioPath) {
          this.ErrorPanel()
        } else {
          Column({ space: 10 }) {
            this.TypeChips()
            this.QualityRow()
            this.LyricWindow()
            Text(`已选 ${this.timeText(this.selectedSeconds())}（最高可选 ${this.maxSeconds} 秒）`)
              .width('100%').fontSize(11).fontColor(TC.textTertiary()).textAlign(TextAlign.Center)
            Column() {
              this.WaveformStrip()
            }
            .width('100%')
            .padding({ left: 18, right: 18 })
            Row() {
              Row({ space: 6 }) {
                SymbolGlyph(this.previewing ? $r('sys.symbol.pause_circle_fill') : $r('sys.symbol.play_circle'))
                  .fontSize(18).fontColor([TC.textPrimary()])
                Text(this.previewing ? '停止试听' : '试听铃声').fontSize(13).fontColor(TC.textPrimary())
              }
              .onClick(() => this.togglePreview())
            }
            .width('100%')
            .height(34)
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 18, right: 18, top: 6 })

          Row({ space: 12 }) {
            Button() {
              Row({ space: 6 }) {
                if (this.saving) {
                  LoadingProgress().width(16).height(16).color(TC.textPrimary())
                } else {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(16).fontColor([TC.textPrimary()])
                }
                Text(this.saving ? '保存中…' : '保存音频').fontSize(15).fontColor(TC.textPrimary())
              }
            }
            .layoutWeight(1)
            .height(46)
            .backgroundColor(TC.chipBackground())
            .borderRadius(23)
            .enabled(!this.saving)
            .onClick(() => this.saveAudio())

            Button() {
              Row({ space: 6 }) {
                if (this.applying) {
                  LoadingProgress().width(16).height(16).color(TC.textOnAccent())
                } else {
                  SymbolGlyph($r('sys.symbol.bell_fill')).fontSize(16).fontColor([TC.textOnAccent()])
                }
                Text(this.applying ? '设置中…' : '设为铃声').fontSize(15).fontColor(TC.textOnAccent())
              }
            }
            .layoutWeight(1)
            .height(46)
            .backgroundColor(TC.accent())
            .borderRadius(23)
            .enabled(!this.applying)
            .onClick(() => this.applyRingtone())
          }
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 12 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
