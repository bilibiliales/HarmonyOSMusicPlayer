import { SkinBackdrop } from '../components/SkinBackdrop'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { BubbleTip } from '../services/BubbleTip'
import { RingtoneService, RINGTONE_TYPE_TITLES } from '../services/RingtoneService'
import { SongMetadataCache } from '../services/SongMetadataCache'
import { TC } from '../services/ThemeColors'
import { QualityOption, songItemType } from '../models/music'
import curves from '@ohos.curves'

export interface RingtonePageParam {
  song: songItemType
}

interface RingtoneLyric {
  time: number
  text: string
}

const BAR_COUNT: number = 56
/** 歌词一行的高度与行距（与 List.space 一致）。 */
const LYRIC_LINE_VP: number = 22
const LYRIC_ROW_VP: number = LYRIC_LINE_VP + 8
/** 标签行高度：虚线 / 胶囊都在这个高度里垂直居中，不占歌词高度。 */
const LYRIC_TAG_VP: number = 28

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
  /** 标签拖拽时的临时偏移；松手后用弹簧动画归到吸附位置。 */
  @State startTagDragY: number = 0
  @State endTagDragY: number = 0
  @State saving: boolean = false
  @State applying: boolean = false
  @State previewing: boolean = false

  private previewPlayer?: media.AVPlayer
  private previewFd: number = -1
  private previewPath: string = ''
  private previewFallback: boolean = false
  private clipPath: string = ''
  private clipKey: string = ''
  private lyricScroller: Scroller = new Scroller()
  private dragBaseSec: number = 0
  private dragTagBaseBoundary: number = 0
  private snapTimer: number = -1
  private limitNotified: boolean = false

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
    if (this.snapTimer >= 0) {
      clearTimeout(this.snapTimer)
      this.snapTimer = -1
    }
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

  /** 当前这句歌词是否落在选区内（纯文本歌词只用颜色区分）。 */
  private lineSelected(index: number): boolean {
    const line = this.lyrics[index]
    if (!line) { return false }
    const sec = line.time / 1000
    return sec >= this.startSec && sec < this.endSec
  }

  /** 片段最大长度：不能超过当前铃声类型的上限，也不能超过歌曲本身长度。 */
  private maxLength(): number {
    const songLength = this.durationSec > 0 ? this.durationSec : this.maxSeconds
    return Math.max(1, Math.min(this.maxSeconds, songLength))
  }

  /**
   * 统一兜底：超出「类型最大时长」时优先保开始，结束自动落到 开始 + 限时。
   * 每次拖动只提醒一次，避免手势每帧弹气泡。
   */
  private enforceLimit(tip: boolean): void {
    const maxLen = this.maxLength()
    if (this.startSec < 0) { this.startSec = 0 }
    if (this.startSec > this.durationSec - 1) { this.startSec = Math.max(0, this.durationSec - 1) }
    if (this.endSec - this.startSec > maxLen) {
      this.endSec = Math.min(this.durationSec, this.startSec + maxLen)
      if (tip && !this.limitNotified) {
        this.limitNotified = true
        BubbleTip.show(this.getUIContext(), `最长 ${maxLen} 秒，结束时间已自动调整`)
      }
    }
    if (this.endSec > this.durationSec) { this.endSec = this.durationSec }
    if (this.endSec - this.startSec < 1) {
      this.endSec = Math.min(this.durationSec, this.startSec + 1)
      this.startSec = Math.max(0, this.endSec - 1)
    }
  }

  /** 选区变化后让裁剪缓存失效（预览与保存都重新生成片段）。 */
  private invalidateClip(): void {
    this.clipKey = ''
  }

  /** 波形手柄主控：精确到秒（整数），超限保开始并提醒。 */
  private setStart(value: number, tip: boolean = true): void {
    this.startSec = Math.max(0, Math.min(this.durationSec - 1, Math.round(value)))
    if (this.endSec <= this.startSec) { this.endSec = this.startSec + 1 }
    this.enforceLimit(tip)
    this.invalidateClip()
  }

  private setEnd(value: number, tip: boolean = true): void {
    this.endSec = Math.max(1, Math.min(this.durationSec, Math.round(value)))
    this.enforceLimit(tip)
    this.invalidateClip()
  }

  /** 拖动滑块前重置「超限提醒」并停掉旧试听。 */
  private beginDrag(): void {
    this.limitNotified = false
    this.invalidateClip()
    this.stopPreview()
  }

  private selectType(index: number): void {
    if (this.typeIndex === index) { return }
    this.typeIndex = index
    this.maxSeconds = RingtoneService.maxSeconds(index)
    this.limitNotified = false
    this.enforceLimit(true)
    this.invalidateClip()
    this.stopPreview()
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

  /** 帧级裁剪直接在内存里生成，预览不经过文件 URI。 */
  private clipData(): ArrayBuffer {
    if (!this.audioPath) { return new ArrayBuffer(0) }
    return RingtoneService.clipBytes(this.audioPath,
      Math.round(this.startSec * 1000), Math.round(this.endSec * 1000))
  }

  private attachPreviewHandlers(player: media.AVPlayer): void {
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (player !== this.previewPlayer) { return }
      console.info(`[Ringtone] preview state: ${state}`)
      if (state === 'initialized') {
        player.prepare().catch((error: Error) => {
          console.error(`[Ringtone] prepare failed: ${error.message}`)
          this.stopPreview()
        })
      } else if (state === 'prepared') {
        player.loop = true
        player.play().catch((error: Error) => {
          console.error(`[Ringtone] play failed: ${error.message}`)
          this.stopPreview()
        })
      }
    })
    player.on('error', (error: BusinessError) => {
      // 切换到 fdSrc 兜底后，旧实例可能还会补发 error，忽略避免误停新播放器
      if (player !== this.previewPlayer) { return }
      console.error(`[Ringtone] AVPlayer error ${error.code}: ${error.message}`)
      this.onPreviewError(`${error.code} ${error.message}`)
    })
  }

  private onPreviewError(reason: string): void {
    if (!this.previewFallback && this.previewPath.length > 0) {
      this.previewFallback = true
      console.info('[Ringtone] fallback to fdSrc preview')
      this.startFdPreview(this.previewPath)
      return
    }
    this.stopPreview()
    BubbleTip.show(this.getUIContext(), `试听失败：${reason}`)
  }

  /** 主路径：内存字节交给 AVPlayer.dataSrc，边播边按顺序喂数据。 */
  private async startMemoryPreview(data: ArrayBuffer): Promise<void> {
    const bytes = new Uint8Array(data)
    let cursor = 0
    const player = await media.createAVPlayer()
    this.previewPlayer = player
    this.attachPreviewHandlers(player)
    const descriptor: media.AVDataSrcDescriptor = {
      fileSize: -1,
      callback: (buffer: ArrayBuffer, length: number): number => {
        if (cursor >= bytes.length) { return -1 }
        const count = Math.min(length, bytes.length - cursor)
        new Uint8Array(buffer, 0, count).set(bytes.subarray(cursor, cursor + count))
        cursor += count
        return count
      }
    }
    player.dataSrc = descriptor
    this.previewing = true
  }

  /** 兜底：内存源解析不了时，改用已裁剪文件的 fdSrc 播放。 */
  private async startFdPreview(path: string): Promise<void> {
    await this.stopPreview()
    try {
      const player = await media.createAVPlayer()
      this.previewPlayer = player
      this.attachPreviewHandlers(player)
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      this.previewFd = file.fd
      const size = fileIo.statSync(path).size
      const fdSrc: media.AVFileDescriptor = { fd: this.previewFd, offset: 0, length: size }
      player.fdSrc = fdSrc
      this.previewing = true
    } catch (error) {
      this.stopPreview()
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '试听失败')
    }
  }

  private async togglePreview(): Promise<void> {
    if (this.previewing) {
      await this.stopPreview()
      return
    }
    await this.stopPreview()
    this.previewFallback = false
    try {
      const data = this.clipData()
      if (data.byteLength === 0) {
        throw new Error('裁剪结果为空，请调整开始/结束位置')
      }
      // 同时落一份文件：保存/设铃声复用，也作为内存播放失败时的兜底
      this.previewPath = await this.buildClip()
      await this.startMemoryPreview(data)
    } catch (error) {
      this.stopPreview()
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
    if (this.previewFd >= 0) {
      const fd = this.previewFd
      this.previewFd = -1
      try {
        fileIo.closeSync(fd)
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

  /** 波形光标位置由传入的秒数决定，与上方标签共用同一份 startSec/endSec。 */
  private startX(sec: number): number {
    if (this.durationSec <= 0 || this.waveWidth <= 0) { return 0 }
    return Math.min(this.waveWidth, Math.max(0, sec / this.durationSec * this.waveWidth))
  }

  private endX(sec: number): number {
    if (this.durationSec <= 0 || this.waveWidth <= 0) { return 0 }
    return Math.min(this.waveWidth, Math.max(0, sec / this.durationSec * this.waveWidth))
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

  /** 选中区间的第一句 / 最后一句歌词，用来把标签贴到亮暗交界处。 */
  private firstSelectedLyric(): number {
    for (let i = 0; i < this.lyrics.length; i++) {
      if (this.lyrics[i].time / 1000 >= this.startSec) { return i }
    }
    return Math.max(0, this.lyrics.length - 1)
  }

  private lastSelectedLyric(): number {
    let index = 0
    for (let i = 0; i < this.lyrics.length; i++) {
      if (this.lyrics[i].time / 1000 < this.endSec) { index = i }
    }
    return index
  }

  /**
   * 第 k 条边界对应的时间：k=0 在第一行之前，k= lyrics.length 在最后一行之后，
   * 其余取相邻两句歌词时间的中间值，让分隔线真的落在两行之间。
   */
  private boundaryTime(k: number): number {
    if (this.lyrics.length === 0) { return 0 }
    if (k <= 0) { return Math.max(0, Math.floor(this.lyrics[0].time / 1000) - 1) }
    if (k >= this.lyrics.length) {
      return Math.round(this.lyrics[this.lyrics.length - 1].time / 1000) + 1
    }
    const prev = this.lyrics[k - 1].time / 1000
    const next = this.lyrics[k].time / 1000
    return Math.round((prev + next) / 2)
  }

  private beginTagDrag(isStart: boolean): void {
    if (this.snapTimer >= 0) {
      clearTimeout(this.snapTimer)
      this.snapTimer = -1
      this.startTagDragY = 0
      this.endTagDragY = 0
    }
    this.dragTagBaseBoundary = isStart ? this.firstSelectedLyric() : this.lastSelectedLyric() + 1
    if (isStart) { this.startTagDragY = 0 }
    else { this.endTagDragY = 0 }
    this.beginDrag()
  }

  private updateTagDrag(isStart: boolean, offsetY: number): void {
    if (isStart) { this.startTagDragY = offsetY }
    else { this.endTagDragY = offsetY }
  }

  /** 松手：先弹簧滑到最近的两行中间，动画结束后再提交时间，视觉上无缝衔接。 */
  private finishTagDrag(isStart: boolean): void {
    const current = isStart ? this.startTagDragY : this.endTagDragY
    const maxK = this.lyrics.length
    const targetK = Math.max(0, Math.min(maxK,
      this.dragTagBaseBoundary + Math.round(current / LYRIC_ROW_VP)))
    const targetPx = (targetK - this.dragTagBaseBoundary) * LYRIC_ROW_VP
    const time = this.boundaryTime(targetK)
    animateTo({
      duration: 330,
      curve: curves.springMotion(0.55, 0.76, 0.24)
    }, () => {
      if (isStart) { this.startTagDragY = targetPx }
      else { this.endTagDragY = targetPx }
    })
    this.snapTimer = setTimeout(() => {
      if (isStart) { this.setStart(time, true); this.startTagDragY = 0 }
      else { this.setEnd(time, true); this.endTagDragY = 0 }
      this.snapTimer = -1
    }, 340)
  }

  /**
   * 开始 / 结束标签作为「歌词行的一部分」浮在行边界上，不占歌词高度。
   * 它们随 ListItem 一起滚动，所以不需要监听 onScroll 或做任何坐标换算。
   * 所有动态值都直接读 @State，ForEach 不重建也能跟着滑块刷新。
   */
  @Builder
  private StartTag(index: number) {
    Row() {
      Row({ space: 4 }) {
        Text(this.timeText(this.startSec)).fontSize(10).fontColor(TC.textOnAccent())
        Text('开始').fontSize(10).fontColor(TC.textOnAccent()).fontWeight(FontWeight.Medium)
      }
      .height(20)
      .padding({ left: 9, right: 9 })
      .backgroundColor(TC.accent())
      .borderRadius(10)
      .hitTestBehavior(HitTestMode.Block)
      .gesture(
        PanGesture({ distance: 1 })
          .onActionStart(() => this.beginTagDrag(true))
          .onActionUpdate((event: GestureEvent) => this.updateTagDrag(true, event.offsetY))
          .onActionEnd(() => this.finishTagDrag(true))
      )
      Row()
        .layoutWeight(1)
        .height(1)
        .margin({ left: 8, right: 12 })
        .border({ width: { top: 1 }, color: 'rgba(128,128,128,0.45)', style: BorderStyle.Dashed })
    }
    .width('100%')
    .height(LYRIC_TAG_VP)
    .padding({ left: 10 })
    .alignItems(VerticalAlign.Center)
    // 中心压在这一行的上边缘
    .position({ x: 0, y: -LYRIC_TAG_VP / 2 })
    .translate({ y: this.startTagDragY })
    .opacity(this.firstSelectedLyric() === index ? 1 : 0)
    .zIndex(2)
    .hitTestBehavior(this.firstSelectedLyric() === index ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  private EndTag(index: number) {
    Row() {
      Row({ space: 4 }) {
        Text(this.timeText(this.endSec)).fontSize(10).fontColor(TC.textOnAccent())
        Text('结束').fontSize(10).fontColor(TC.textOnAccent()).fontWeight(FontWeight.Medium)
      }
      .height(20)
      .padding({ left: 9, right: 9 })
      .backgroundColor(TC.accent())
      .borderRadius(10)
      .hitTestBehavior(HitTestMode.Block)
      .gesture(
        PanGesture({ distance: 1 })
          .onActionStart(() => this.beginTagDrag(false))
          .onActionUpdate((event: GestureEvent) => this.updateTagDrag(false, event.offsetY))
          .onActionEnd(() => this.finishTagDrag(false))
      )
      Row()
        .layoutWeight(1)
        .height(1)
        .margin({ left: 8, right: 12 })
        .border({ width: { top: 1 }, color: 'rgba(128,128,128,0.45)', style: BorderStyle.Dashed })
    }
    .width('100%')
    .height(LYRIC_TAG_VP)
    .padding({ left: 10 })
    .alignItems(VerticalAlign.Center)
    // 中心压在这一行的下边缘
    .position({ x: 0, y: LYRIC_LINE_VP - LYRIC_TAG_VP / 2 })
    .translate({ y: this.endTagDragY })
    .opacity(this.lastSelectedLyric() === index ? 1 : 0)
    .zIndex(2)
    .hitTestBehavior(this.lastSelectedLyric() === index ? HitTestMode.Transparent : HitTestMode.None)
  }

  /**
   * 歌词组件：普通文本列表，不做缩放/透明动画。开始 / 结束标签是歌词行内部的浮动层，
   * 自然跟随滚动，位置始终对应亮暗交界那两行。
   */
  @Builder
  private LyricWindow() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(20)
        .backgroundColor('rgba(128,128,128,0.06)')
        .border({ width: 1, color: 'rgba(128,128,128,0.14)' })

      if (this.lyrics.length > 0) {
        List({ space: 8, scroller: this.lyricScroller }) {
          ForEach(this.lyrics, (line: RingtoneLyric, index: number) => {
            ListItem() {
              Stack({ alignContent: Alignment.TopStart }) {
                Text(line.text)
                  .width('100%')
                  .fontSize(15)
                  .lineHeight(LYRIC_LINE_VP)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor(this.lineSelected(index) ? TC.textBody() : TC.textTertiary())
                  .textAlign(TextAlign.Center)
                  .padding({ left: 18, right: 18 })
                this.StartTag(index)
                this.EndTag(index)
              }
              .width('100%')
              .height(LYRIC_LINE_VP)
            }
          }, (line: RingtoneLyric, index: number) => `${line.time}-${index}`)
        }
        .width('100%')
        .height('100%')
        .padding({ top: 4, bottom: 4 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(26).fontColor([TC.textQuaternary()])
          Text('这首歌暂无歌词').fontSize(12).fontColor(TC.textTertiary())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .onAreaChange((_old: Area, area: Area) => {
      this.lyricHeight = Number(area.height)
    })
  }

  /** 两个手柄的中点：轨道左半边抓开始，右半边抓结束。 */
  private thumbMidX(): number {
    if (this.waveWidth <= 0) { return 0 }
    return Math.max(0, Math.min(this.waveWidth,
      (this.startX(this.startSec) + this.endX(this.endSec)) / 2))
  }

  /** SDK 的 GestureEvent 没有 localX，偏移用项目里通用的 offsetX。 */
  private dragDelta(offsetX: number): number {
    if (this.waveWidth <= 0) { return 0 }
    return offsetX / this.waveWidth * this.durationSec
  }

  /**
   * 双向范围滑块：按两个手柄的中点把轨道分成左右两个触摸区，
   * 左边拖开始、右边拖结束，两头都能滑；波形、选区、手柄只画不参与命中测试。
   */
  @Builder
  private RangeSlider() {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row({ space: 1 }) {
          ForEach(this.bars, (value: number, index: number) => {
            Column()
              .width(2)
              .height(Math.max(4, Math.round(value * 40)))
              .borderRadius(1)
              .backgroundColor(TC.textTertiary())
              .opacity(0.55)
          })
        }
        .width('100%')
        .height(44)
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.None)

        Column()
          .width(Math.max(0, this.endX(this.endSec) - this.startX(this.startSec)))
          .height(44)
          .backgroundColor('rgba(255,255,255,0.10)')
          .position({ x: this.startX(this.startSec), y: 0 })
          .hitTestBehavior(HitTestMode.None)

        // 开始手柄
        Column()
          .width(6)
          .height(44)
          .borderRadius(3)
          .backgroundColor(TC.accent())
          .position({ x: Math.max(0, this.startX(this.startSec) - 3), y: 0 })
          .hitTestBehavior(HitTestMode.None)
        // 结束手柄
        Column()
          .width(6)
          .height(44)
          .borderRadius(3)
          .backgroundColor(TC.accent())
          .position({ x: Math.max(0, this.endX(this.endSec) - 3), y: 0 })
          .hitTestBehavior(HitTestMode.None)
        // 两个透明触摸区：左半边拖开始，右半边拖结束，各自只认自己的 offsetX
        Column()
          .width(this.thumbMidX())
          .height(44)
          .backgroundColor(Color.Transparent)
          .position({ x: 0, y: 0 })
          .hitTestBehavior(HitTestMode.Block)
          .gesture(
            PanGesture({ distance: 1 })
              .onActionStart(() => {
                this.dragBaseSec = this.startSec
                this.beginDrag()
              })
              .onActionUpdate((event: GestureEvent) => {
                this.setStart(this.dragBaseSec + this.dragDelta(event.offsetX), true)
              })
          )
        Column()
          .width(Math.max(0, this.waveWidth - this.thumbMidX()))
          .height(44)
          .backgroundColor(Color.Transparent)
          .position({ x: this.thumbMidX(), y: 0 })
          .hitTestBehavior(HitTestMode.Block)
          .gesture(
            PanGesture({ distance: 1 })
              .onActionStart(() => {
                this.dragBaseSec = this.endSec
                this.beginDrag()
              })
              .onActionUpdate((event: GestureEvent) => {
                this.setEnd(this.dragBaseSec + this.dragDelta(event.offsetX), true)
              })
          )
      }
      .width('100%')
      .height(44)
      .onAreaChange((_old: Area, area: Area) => {
        this.waveWidth = Math.max(0, Number(area.width))
      })

      Row() {
        Text(`开始 ${this.timeText(this.startSec)}`).fontSize(10).fontColor(TC.textSecondary())
        Text(`结束 ${this.timeText(this.endSec)}`).fontSize(10).fontColor(TC.textSecondary())
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
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
      SkinBackdrop()
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
              this.RangeSlider()
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
          .padding({ left: 18, right: 18, bottom: 24 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
