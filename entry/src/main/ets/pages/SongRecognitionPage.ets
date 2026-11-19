import { audio } from '@kit.AudioKit'
import { abilityAccessCtrl } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { TC } from '../services/ThemeColors'
import { BubbleTip } from '../services/BubbleTip'
import { playerController } from '../services/PlayerController'
import { AudioMatchService, MatchedSong } from '../services/AudioMatchService'

/**
 * 听歌识曲：原生采集 8kHz 单声道 PCM，本地生成音频指纹后查询匹配结果。
 * 不嵌网页，保持与应用其它页面一致的交互和主题。
 */
@Component
export struct SongRecognitionPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State private status: string = '点击下方按钮，开始识别周围的音乐'
  @State private progress: number = 0
  @State private busy: boolean = false
  @State private results: MatchedSong[] = []

  private capturer?: audio.AudioCapturer
  private chunks: ArrayBuffer[] = []
  private bytes: number = 0
  private recognizing: boolean = false
  private finishTimer: number = -1

  aboutToAppear(): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      atManager.requestPermissionsFromUser(this.getUIContext().getHostContext(),
        ['ohos.permission.MICROPHONE'])
        .catch((error: BusinessError) => {
          BubbleTip.show(this.getUIContext(), `麦克风权限申请失败：${error.message}`)
        })
    } catch (_error) {
    }
  }

  aboutToDisappear(): void {
    this.recognizing = false
    if (this.finishTimer >= 0) { clearTimeout(this.finishTimer) }
    const capturer = this.capturer
    this.capturer = undefined
    if (capturer) {
      capturer.stop().catch(() => {}).then(() => capturer.release().catch(() => {}))
    }
  }

  private async startRecognize(): Promise<void> {
    if (this.busy) { return }
    this.busy = true
    this.results = []
    this.chunks = []
    this.bytes = 0
    this.progress = 0
    this.status = '正在采集音频…'
    try {
      const streamInfo: audio.AudioStreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_8000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_F32LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      }
      const capturerInfo: audio.AudioCapturerInfo = {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
      const options: audio.AudioCapturerOptions = { streamInfo: streamInfo, capturerInfo: capturerInfo }
      const capturer = await audio.createAudioCapturer(options)
      this.capturer = capturer
      this.recognizing = true
      const targetBytes = AudioMatchService.SAMPLE_COUNT * 4
      capturer.on('readData', (buffer: ArrayBuffer) => {
        if (!this.recognizing) { return }
        // 底层缓冲区会复用，跨回调前必须复制一份
        const copy = buffer.slice(0)
        this.chunks.push(copy)
        this.bytes += copy.byteLength
        this.progress = Math.min(100, Math.floor(this.bytes / targetBytes * 100))
        if (this.bytes >= targetBytes) { this.finish() }
      })
      await capturer.start()
      // 麦克风采样不足 5 秒时也要收尾，避免一直停在采集中
      this.finishTimer = setTimeout(() => this.finish(), 8000)
    } catch (error) {
      this.recognizing = false
      this.busy = false
      this.status = error instanceof Error ? error.message : '录音启动失败'
    }
  }

  private async finish(): Promise<void> {
    if (!this.recognizing) { return }
    this.recognizing = false
    if (this.finishTimer >= 0) { clearTimeout(this.finishTimer); this.finishTimer = -1 }
    const capturer = this.capturer
    this.capturer = undefined
    if (capturer) {
      try { await capturer.stop() } catch (_error) {}
      try { await capturer.release() } catch (_error) {}
    }
    this.status = '正在识别…'
    try {
      const pcm = new Float32Array(AudioMatchService.SAMPLE_COUNT)
      let offset = 0
      for (const chunk of this.chunks) {
        const view = new Float32Array(chunk)
        const count = Math.min(view.length, pcm.length - offset)
        if (count > 0) {
          pcm.set(view.subarray(0, count), offset)
          offset += count
        }
        if (offset >= pcm.length) { break }
      }
      if (offset < AudioMatchService.SAMPLE_COUNT) {
        throw new Error('采集时间不足，请靠近音源重试')
      }
      this.results = await AudioMatchService.recognize(pcm)
      this.status = this.results.length > 0
        ? `识别到 ${this.results.length} 个结果`
        : '没有识别到歌曲，请靠近音源重试'
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
          Column({ space: 20 }) {
            Column({ space: 14 }) {
              Stack() {
                Circle().width(150).height(150)
                  .backgroundColor(TC.accentSoft()).opacity(0.16)
                SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(56).fontColor([TC.accent()])
              }
              .width(150).height(150)

              Text(this.status).fontSize(13).fontColor(TC.textBody())
                .textAlign(TextAlign.Center).padding({ left: 24, right: 24 })
              if (this.busy && this.progress > 0) {
                Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
                  .width('60%').height(4).color(TC.accent())
              }
              Button(this.busy ? '识别中…' : '开始识别')
                .width(180).height(44).fontSize(15)
                .fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
                .borderRadius(22).enabled(!this.busy)
                .onClick(() => this.startRecognize())
              Text('需要麦克风权限 · 采集约 5 秒').fontSize(10).fontColor(TC.textQuaternary())
            }
            .width('100%')
            .padding({ top: 30, bottom: 24 })

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
