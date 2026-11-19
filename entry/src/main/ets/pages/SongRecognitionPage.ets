import { audio } from '@kit.AudioKit'
import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { TC } from '../services/ThemeColors'
import { BubbleTip } from '../services/BubbleTip'
import { playerController } from '../services/PlayerController'
import { AudioMatchService, MatchedSong } from '../services/AudioMatchService'
import { SkinBackdrop } from '../components/SkinBackdrop'

/**
 * 听歌识曲：内录手机正在播放的音频（可选同时改用麦克风），本地生成音频指纹后查询。
 * 三次采样、每次 5 秒，取前 3 秒生成 AFP，结果去重后展示。
 */
@Component
export struct SongRecognitionPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State private status: string = '点击中间图标开始识别'
  @State private progress: number = 0
  @State private busy: boolean = false
  /** 0=听歌识曲（麦克风），1=录屏识曲（系统内音）。 */
  @State private mode: number = 0
  @State private results: MatchedSong[] = []

  private capturer?: audio.AudioCapturer
  private chunks: ArrayBuffer[] = []
  private bytes: number = 0
  private captureDone?: () => void
  private captureTimer: number = -1

  aboutToDisappear(): void {
    if (this.captureTimer >= 0) { clearTimeout(this.captureTimer) }
    const capturer = this.capturer
    this.capturer = undefined
    if (capturer) {
      capturer.stop().catch(() => {}).then(() => capturer.release().catch(() => {}))
    }
  }

  private async ensureMicPermission(): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const context = this.getUIContext().getHostContext() as common.Context
      const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE'])
      return result.authResults.length > 0 && result.authResults[0] === 0
    } catch (_error) {
      return false
    }
  }

  /** 采集一段音频并返回前 3 秒的 8k 单声道 Float32 PCM。 */
  private async captureOnce(useMic: boolean): Promise<Float32Array> {
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_8000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_F32LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    }
    const capturerInfo: audio.AudioCapturerInfo = {
      source: useMic ? audio.SourceType.SOURCE_TYPE_MIC : audio.SourceType.SOURCE_TYPE_PLAYBACK_CAPTURE,
      capturerFlags: 0
    }
    const options: audio.AudioCapturerOptions = { streamInfo: streamInfo, capturerInfo: capturerInfo }
    if (!useMic) {
      // 内录必须指定媒体音用途，否则采到的是静音帧
      options.playbackCaptureMode = audio.AudioPlaybackCaptureMode.MODE_MEDIA
    }
    const capturer = await audio.createAudioCapturer(options)
    this.capturer = capturer
    this.chunks = []
    this.bytes = 0
    const targetBytes = AudioMatchService.SAMPLE_COUNT * 4
    const runMs = 5000
    const runBytes = AudioMatchService.SAMPLE_RATE * (runMs / 1000) * 4
    await new Promise<void>((resolve) => {
      this.captureDone = resolve
      capturer.on('readData', (buffer: ArrayBuffer) => {
        if (!this.capturer) { return }
        const copy = buffer.slice(0)
        this.chunks.push(copy)
        this.bytes += copy.byteLength
        this.progress = Math.min(100, Math.floor(this.bytes / runBytes * 100))
        if (this.bytes >= runBytes) { this.captureDone?.() }
      })
      this.captureTimer = setTimeout(() => this.captureDone?.(), runMs + 1500)
      capturer.start().catch((error: BusinessError) => {
        BubbleTip.show(this.getUIContext(), `录音启动失败：${error.message}`)
        this.captureDone?.()
      })
    })
    if (this.captureTimer >= 0) { clearTimeout(this.captureTimer); this.captureTimer = -1 }
    this.captureDone = undefined
    try { await capturer.stop() } catch (_error) {}
    try { await capturer.release() } catch (_error) {}
    if (this.capturer === capturer) { this.capturer = undefined }

    const pcm = new Float32Array(AudioMatchService.SAMPLE_COUNT)
    let offset = 0
    for (const chunk of this.chunks) {
      const view = new Float32Array(chunk)
      const count = Math.min(view.length, pcm.length - offset)
      if (count > 0) { pcm.set(view.subarray(0, count), offset); offset += count }
      if (offset >= pcm.length) { break }
    }
    this.chunks = []
    if (offset < targetBytes / 4) {
      throw new Error('采集时间不足，请靠近音源重试')
    }
    return pcm
  }

  private async startRecognize(): Promise<void> {
    if (this.busy) { return }
    const useMic = this.mode === 0
    if (useMic && !(await this.ensureMicPermission())) {
      BubbleTip.show(this.getUIContext(), '需要麦克风权限才能使用麦克风识别')
      return
    }
    this.busy = true
    this.results = []
    this.progress = 0
    const all: MatchedSong[] = []
    try {
      for (let i = 0; i < 3; i++) {
        this.status = `正在采集第 ${i + 1}/3 次…`
        const pcm = await this.captureOnce(useMic)
        this.status = `正在识别第 ${i + 1}/3 次…`
        const rows = await AudioMatchService.recognize(pcm)
        all.push(...rows)
      }
      this.results = AudioMatchService.dedupe(all)
      this.status = this.results.length > 0
        ? `识别到 ${this.results.length} 首歌曲`
        : '没有识别到歌曲，请换个片段重试'
    } catch (error) {
      this.status = error instanceof Error ? error.message : '识别失败，请重试'
    } finally {
      this.busy = false
      this.progress = 0
    }
  }

  private timeText(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000))
    const minute = Math.floor(total / 60)
    const second = total % 60
    return `${minute < 10 ? '0' : ''}${minute}:${second < 10 ? '0' : ''}${second}`
  }

  private async play(item: MatchedSong): Promise<void> {
    if (!item.song) { return }
    await playerController.setQueue([item.song], 0, true)
    BubbleTip.show(this.getUIContext(), `已播放 ${item.song.name}`)
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
          Text('听歌识曲').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          Column().width(24)
        }
        .width('100%').height(52).padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 18 }) {
            Column({ space: 14 }) {
              Stack() {
                SymbolGlyph($r('sys.symbol.mic_fill'))
                  .fontSize(52)
                  .fontColor(Color.White)
              }
              .width(128).height(128)
              .borderRadius(64)
              .backgroundColor(TC.accent())
              .justifyContent(FlexAlign.Center)
              .onClick(() => this.startRecognize())

              Text(this.status).fontSize(13).fontColor(TC.textBody())
                .textAlign(TextAlign.Center).padding({ left: 24, right: 24 })
              if (this.busy && this.progress > 0) {
                Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
                  .width('60%').height(4).color(TC.accent())
              }
              Column({ space: 6 }) {
                Slider({ value: this.mode, min: 0, max: 1, step: 1 })
                  .width(220)
                  .selectedColor(TC.accent())
                  .enabled(!this.busy)
                  .onChange((value: number) => this.mode = Math.round(value))
                Row() {
                  Text('听歌识曲').fontSize(11)
                    .fontColor(this.mode === 0 ? TC.accent() : TC.textTertiary())
                  Text('录屏识曲').fontSize(11)
                    .fontColor(this.mode === 1 ? TC.accent() : TC.textTertiary())
                }
                .width(220)
                .justifyContent(FlexAlign.SpaceBetween)
              }
              Text('采集 3 次约 15 秒 · 结果自动去重').fontSize(10).fontColor(TC.textQuaternary())
            }
            .width('100%')
            .padding({ top: 24, bottom: 12 })

            if (this.results.length > 0) {
              Column({ space: 10 }) {
                Text('识别结果').width('100%').fontSize(15).fontWeight(FontWeight.Bold)
                  .fontColor(TC.textPrimary())
                ForEach(this.results, (item: MatchedSong, index: number) => {
                  Row({ space: 12 }) {
                    Text(`${index + 1}`).width(20).fontSize(12).fontColor(TC.accent())
                      .textAlign(TextAlign.Center)
                    if (item.song && item.song.img.length > 0) {
                      Image(item.song.img).width(50).height(50).borderRadius(9).objectFit(ImageFit.Cover)
                    }
                    Column({ space: 4 }) {
                      Text(item.song ? item.song.name : '未知歌曲').fontSize(14)
                        .fontColor(TC.textPrimary()).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(item.song ? `${item.song.author} · ${item.song.album ?? ''}` : '')
                        .fontSize(10).fontColor(TC.textSecondary()).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Column({ space: 2 }) {
                      Text(this.timeText(item.startTimeMs)).fontSize(10).fontColor(TC.accent())
                      SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(20).fontColor([TC.textSecondary()])
                    }
                  }
                  .width('100%').padding(10).backgroundColor(TC.surfaceCard()).borderRadius(12)
                  .onClick(() => this.play(item))
                }, (item: MatchedSong, index: number) => `${index}_${item.song ? item.song.id : ''}`)
              }
              .width('100%').padding({ left: 16, right: 16, bottom: 24 })
            }
          }
          .width('100%')
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
