import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
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

/** 时间轴上的一行歌词：y 为相对歌词窗口顶部的 vp 位置。 */
interface LyricRow {
  time: number
  text: string
  y: number
  inRange: boolean
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
  private previewFd: number = -1
  private previewPath: string = ''
  private previewFallback: boolean = false
  private clipPath: string = ''
  private clipKey: string = ''
  private dragBaseStart: number = 0
  private dragBaseEnd: number = 0
  private dragBaseLength: number = 0

  // ---- 歌词时间轴 ----
  // 歌词按「秒 → vp」线性铺开，组件逻辑高度 = 整首歌时长 * pxPerSec，
  // 窗口只显示选区中点附近的一段；两条横线恰好圈出 startSec~endSec 的歌词。

  /** 让「最大可选时长」占窗口 68%，因此选区再长也不会撑出歌词窗口。 */
  private pxPerSec(): number {
    if (this.lyricHeight < 60) { return 4 }
    return Math.max(1.5, this.lyricHeight * 0.68 / Math.max(1, this.maxLength()))
  }

  /** 视窗中心时间 = 选区中点；拖标签 / 滑歌词都会改变它，歌词因此跟着滚动。 */
  private centerSec(): number {
    return (this.startSec + this.endSec) / 2
  }

  /** 拖标签时中心也移动一半，标签视觉位移 = Δ秒/2 * p，故系数取 2/p 才能跟手。 */
  private markerSecondsPerVp(): number {
    return 2 / this.pxPerSec()
  }

  /** 滑动歌词时内容位移 = Δ秒 * p，系数取 1/p；向下拖 = 看更早的歌词。 */
  private scrollSecondsPerVp(): number {
    return 1 / this.pxPerSec()
  }

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

  /**
   * 只构建落在视窗（含上下缓冲）里的歌词行，避免整首歌几百行全量渲染。
   * y 按真实时间轴计算，密集歌词用最小行距推开以免重叠。
   */
  private lyricRows(): LyricRow[] {
    const p = this.pxPerSec()
    const center = this.centerSec()
    const half = this.lyricHeight / 2
    const rows: LyricRow[] = []
    let lastY = -10000
    for (const line of this.lyrics) {
      const timeSec = line.time / 1000
      let y = half + (timeSec - center) * p
      if (y < -50 || y > this.lyricHeight + 50) { continue }
      if (y < lastY + 26) { y = lastY + 26 }
      lastY = y
      const row: LyricRow = {
        time: line.time, text: line.text, y: y,
        inRange: timeSec >= this.startSec && timeSec < this.endSec
      }
      rows.push(row)
    }
    return rows
  }

  /** 片段最大长度：不能超过当前铃声类型的上限，也不能超过歌曲本身长度。 */
  private maxLength(): number {
    const songLength = this.durationSec > 0 ? this.durationSec : this.maxSeconds
    return Math.max(1, Math.min(this.maxSeconds, songLength))
  }

  /** 三处拖动共用的统一约束：0 <= start < end <= duration，且长度 <= 类型上限。 */
  private clampSelection(): void {
    const maxLen = this.maxLength()
    if (this.startSec < 0) { this.startSec = 0 }
    if (this.endSec > this.durationSec) { this.endSec = this.durationSec }
    if (this.endSec - this.startSec > maxLen) {
      this.endSec = this.startSec + maxLen
    }
    if (this.endSec > this.durationSec) {
      this.endSec = this.durationSec
      this.startSec = Math.max(0, this.endSec - maxLen)
    }
    if (this.endSec - this.startSec < 1) {
      this.endSec = Math.min(this.durationSec, this.startSec + 1)
      this.startSec = Math.max(0, this.endSec - 1)
    }
  }

  /** 选区变化后让裁剪缓存失效（预览与保存都重新生成片段）。 */
  private invalidateClip(): void {
    this.clipKey = ''
  }

  private setStart(value: number): void {
    // 下界由「end - 最大长度」决定：往左拖也不会让片段超出类型上限
    const floor = Math.max(0, this.endSec - this.maxLength())
    const ceiling = Math.max(floor, this.endSec - 1)
    this.startSec = Math.min(ceiling, Math.max(floor, value))
    this.invalidateClip()
  }

  private setEnd(value: number): void {
    const ceiling = Math.min(this.durationSec, this.startSec + this.maxLength())
    const floor = Math.min(ceiling, this.startSec + 1)
    this.endSec = Math.max(floor, Math.min(ceiling, value))
    this.invalidateClip()
  }

  /** 三处拖动共用的起点记录：拖动开始即停掉正在播放的旧片段。 */
  private beginDrag(): void {
    this.dragBaseStart = this.startSec
    this.dragBaseEnd = this.endSec
    this.dragBaseLength = Math.max(1, this.endSec - this.startSec)
    this.invalidateClip()
    this.stopPreview()
  }

  /** 拖歌词区域：整体平移选区，保持已选长度不变。 */
  private moveWindow(deltaSeconds: number): void {
    const length = Math.max(1, this.dragBaseLength)
    const maxStart = Math.max(0, this.durationSec - length)
    const start = Math.min(maxStart, Math.max(0, this.dragBaseStart + deltaSeconds))
    this.startSec = start
    this.endSec = Math.min(this.durationSec, start + length)
    this.invalidateClip()
  }

  /** 两条横线以选区中点为中心上下展开，间距 = 已选秒数 * pxPerSec。 */
  private startMarkerY(): number {
    const half = this.lyricHeight / 2
    const span = (this.endSec - this.startSec) * this.pxPerSec() / 2
    return Math.max(0, Math.min(this.lyricHeight - 28, half - span))
  }

  private endMarkerY(): number {
    const half = this.lyricHeight / 2
    const span = (this.endSec - this.startSec) * this.pxPerSec() / 2
    return Math.min(this.lyricHeight - 28, Math.max(this.startMarkerY() + 28, half + span))
  }

  private selectType(index: number): void {
    if (this.typeIndex === index) { return }
    this.typeIndex = index
    this.maxSeconds = RingtoneService.maxSeconds(index)
    this.clampSelection()
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

  @Builder
  private LyricWindow(startSec: number, endSec: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      // 歌词按时间轴铺开：组件逻辑高度 = 整首歌时长 * pxPerSec，
      // 窗口只显示选区中点附近的一段，横线之间就是实际截取的歌词。
      if (this.lyrics.length > 0) {
        ForEach(this.lyricRows(), (row: LyricRow) => {
          Text(row.text)
            .width('100%')
            .fontSize(14)
            .lineHeight(20)
            .fontColor(row.inRange ? TC.textBody() : TC.textTertiary())
            .opacity(row.inRange ? 1 : 0.6)
            .textAlign(TextAlign.Center)
            .position({ x: 0, y: row.y - 10 })
            .hitTestBehavior(HitTestMode.None)
        }, (row: LyricRow) => `${row.time}-${row.text}`)
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(26).fontColor([TC.textQuaternary()])
          Text('这首歌暂无歌词').fontSize(12).fontColor(TC.textTertiary())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }

      // 透明拖动层：滑动歌词 = 平移选区，歌词跟着滚动（类似歌词预览）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .gesture(
          PanGesture()
            .onActionStart(() => { this.beginDrag() })
            .onActionUpdate((event: GestureEvent) => {
              this.moveWindow(-event.offsetY * this.scrollSecondsPerVp())
            })
        )

      // 两条横线之间 = 截取片段的实际长度
      Column()
        .width('100%')
        .height(Math.max(0, this.endMarkerY() - this.startMarkerY()))
        .backgroundColor('rgba(255,255,255,0.045)')
        .position({ x: 0, y: this.startMarkerY() })
        .hitTestBehavior(HitTestMode.None)

      // 「开始」横线：数字与下方第一个光标共用 startSec（内联避免 @Builder 按值传参不刷新）
      Row() {
        Row()
          .layoutWeight(1)
          .height(1)
          .border({ width: { top: 1 }, color: 'rgba(128,128,128,0.5)', style: BorderStyle.Dashed })
        Row({ space: 4 }) {
          Text(this.timeText(startSec)).fontSize(10).fontColor(TC.textOnAccent())
          Text('开始').fontSize(10).fontColor(TC.textOnAccent()).fontWeight(FontWeight.Medium)
        }
        .height(18)
        .padding({ left: 8, right: 8 })
        .backgroundColor(TC.accent())
        .borderRadius(9)
      }
      .width('100%')
      .height(28)
      .alignItems(VerticalAlign.Center)
      .position({ x: 0, y: this.startMarkerY() })
      .hitTestBehavior(HitTestMode.Block)
      .gesture(
        PanGesture()
          .onActionStart(() => { this.beginDrag() })
          .onActionUpdate((event: GestureEvent) => {
            this.setStart(this.dragBaseStart + event.offsetY * this.markerSecondsPerVp())
          })
      )

      // 「结束」横线：数字与下方第二个光标共用 endSec
      Row() {
        Row()
          .layoutWeight(1)
          .height(1)
          .border({ width: { top: 1 }, color: 'rgba(128,128,128,0.5)', style: BorderStyle.Dashed })
        Row({ space: 4 }) {
          Text(this.timeText(endSec)).fontSize(10).fontColor(TC.textOnAccent())
          Text('结束').fontSize(10).fontColor(TC.textOnAccent()).fontWeight(FontWeight.Medium)
        }
        .height(18)
        .padding({ left: 8, right: 8 })
        .backgroundColor(TC.accent())
        .borderRadius(9)
      }
      .width('100%')
      .height(28)
      .alignItems(VerticalAlign.Center)
      .position({ x: 0, y: this.endMarkerY() })
      .hitTestBehavior(HitTestMode.Block)
      .gesture(
        PanGesture()
          .onActionStart(() => { this.beginDrag() })
          .onActionUpdate((event: GestureEvent) => {
            this.setEnd(this.dragBaseEnd + event.offsetY * this.markerSecondsPerVp())
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
  private WaveformStrip(startSec: number, endSec: number) {
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
        .width(Math.max(0, this.endX(endSec) - this.startX(startSec)))
        .height(48)
        .backgroundColor('rgba(255,255,255,0.10)')
        .border({ width: { left: 1, right: 1 }, color: TC.accent() })
        .position({ x: this.startX(startSec), y: 0 })

      Column()
        .width(3)
        .height(52)
        .borderRadius(2)
        .backgroundColor(TC.accent())
        .position({ x: Math.max(0, this.startX(startSec) - 1), y: 0 })
        .hitTestBehavior(HitTestMode.Block)
        .gesture(
          PanGesture()
            .onActionStart(() => { this.beginDrag() })
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
        .position({ x: Math.max(0, this.endX(endSec) - 1), y: 0 })
        .hitTestBehavior(HitTestMode.Block)
        .gesture(
          PanGesture()
            .onActionStart(() => { this.beginDrag() })
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
            this.LyricWindow(this.startSec, this.endSec)
            Text(`已选 ${this.timeText(this.selectedSeconds())}（最高可选 ${this.maxSeconds} 秒）`)
              .width('100%').fontSize(11).fontColor(TC.textTertiary()).textAlign(TextAlign.Center)
            Column() {
              this.WaveformStrip(this.startSec, this.endSec)
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
