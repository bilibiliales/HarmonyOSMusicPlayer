import { audio } from '@kit.AudioKit'
import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { TC } from '../services/ThemeColors'
import { BubbleTip } from '../services/BubbleTip'
import { playerController } from '../services/PlayerController'
import { AudioMatchService, MatchedSong } from '../services/AudioMatchService'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { AudioFingerprintHost } from '../services/AudioFingerprintWeb'

/**
 * 内录（采集其它应用正在播放的声音）依赖 API 26 才有的
 * playbackCaptureMode / requestPlaybackCaptureStart()，当前 SDK 6.1.1(24) 只有已废弃的
 * playbackCaptureConfig，实测拿不到可用音频。功能暂时下线，
 * 等 2027 年初把版本下限抬到 API 26 后，把这里改成 true 即可接回
 * （页面会自动多出「内录识曲」入口，mode=2 走内录采集）。
 */
const PLAYBACK_CAPTURE_ENABLED: boolean = false
/** 媒体选择器最多接受的音频文件体积（base64 传输，太大容易拖慢）。 */
const MAX_AUDIO_FILE_BYTES: number = 16 * 1024 * 1024

/**
 * 听歌识曲：
 * - 麦克风识曲：采集周围声音，三次采样、每次 5 秒，取前 3 秒生成 AFP；
 * - 本机文件：用媒体选择器选一段音频文件，交给离线引擎解码后取 3 秒生成 AFP。
 * 指纹在隐藏的离线网页引擎里计算，查询走 /audio/match。
 */
@Component
export struct SongRecognitionPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State private status: string = '点击中间图标选择音频文件'
  @State private progress: number = 0
  @State private busy: boolean = false
  /** 0=麦克风识曲，1=本机文件（默认），2=内录识曲（等 API 26 再开放）。 */
  @State private mode: number = 1
  @State private results: MatchedSong[] = []

  /** 隐藏的 Web 引擎：官方 wasm 版 AFP，WebAssembly 可用，与在线 demo 行为一致。 */
  private fpHost: AudioFingerprintHost = new AudioFingerprintHost()
  private capturer?: audio.AudioCapturer
  private chunks: ArrayBuffer[] = []
  private bytes: number = 0
  private captureDone?: () => void
  private captureTimer: number = -1

  private tabTitles(): string[] {
    return PLAYBACK_CAPTURE_ENABLED ? ['麦克风识曲', '本机文件', '内录识曲'] : ['麦克风识曲', '本机文件']
  }

  private idleHint(): string {
    if (this.mode === 1) { return '点击中间图标选择音频文件' }
    if (this.mode === 2) { return '点击中间图标开始识别手机内声音' }
    return '点击中间图标开始识别'
  }

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
      // 内录必须声明要抓取的音频用途，否则采到的是静音帧。
      // 这个字段在 SDK 里叫 playbackCaptureConfig（不是 playbackCaptureMode）。
      options.playbackCaptureConfig = {
        filterOptions: {
          usages: [
            audio.StreamUsage.STREAM_USAGE_MUSIC,
            audio.StreamUsage.STREAM_USAGE_MOVIE,
            audio.StreamUsage.STREAM_USAGE_GAME,
            audio.StreamUsage.STREAM_USAGE_AUDIOBOOK
          ]
        }
      }
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
    // 内录在某些机型上会给出静音帧（尤其是其它应用的音频），
    // 直接算指纹只会得到「没有识别到歌曲」，这里先明确提示。
    let peak = 0
    for (let i = 0; i < pcm.length; i++) {
      const value = Math.abs(pcm[i])
      if (value > peak) { peak = value }
    }
    if (peak < 0.0008) {
      throw new Error(useMic ? '没有采集到声音，请调大音量后重试' : '没有采集到系统声音，请先开始播放音乐')
    }
    return pcm
  }

  /** 优先用网页引擎算指纹，失败再退回原生实现。 */
  private async fingerprint(pcm: Float32Array): Promise<string> {
    try {
      return await this.fpHost.engine.generate(pcm)
    } catch (_engineError) {
      try {
        return await AudioMatchService.fingerprintNative(pcm)
      } catch (_nativeError) {
        throw new Error('指纹引擎初始化失败，请退出页面重试')
      }
    }
  }

  /** 采集式识曲：3 次 × 5 秒，取前 3 秒识别，结果去重。useMic=false 走内录（暂未开放）。 */
  private async startRecognize(useMic: boolean): Promise<void> {
    if (this.busy) { return }
    if (!PLAYBACK_CAPTURE_ENABLED && !useMic) {
      BubbleTip.show(this.getUIContext(), '内录识曲暂未开放，请用本机文件识别')
      return
    }
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
        const audioFP = await this.fingerprint(pcm)
        const rows = await AudioMatchService.recognizeByFP(audioFP)
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

  /** 本机文件识曲：选一个音频文件，交给离线引擎解码 → 取最响的 3 秒 → 匹配。 */
  private async recognizeFile(): Promise<void> {
    if (this.busy) { return }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    let uri = ''
    try {
      const options = new picker.AudioSelectOptions()
      options.maxSelectNumber = 1
      const uris = await new picker.AudioViewPicker(context).select(options)
      if (!uris || uris.length === 0) {
        this.status = this.idleHint()
        return
      }
      uri = uris[0]
    } catch (_error) {
      this.status = '打开文件选择器失败，请重试'
      return
    }

    let name = '音频文件'
    try { name = new fileUri.FileUri(uri).name } catch (_error) {}
    this.busy = true
    this.results = []
    this.progress = 0
    this.status = `正在读取 ${name}…`
    try {
      const bytes = await this.readFile(uri)
      this.status = '正在分析音频片段…'
      const audioFP = await this.fpHost.engine.generateFromFile(bytes)
      this.status = '正在匹配歌曲…'
      const rows = await AudioMatchService.recognizeByFP(audioFP)
      this.results = AudioMatchService.dedupe(rows)
      this.status = this.results.length > 0
        ? `识别到 ${this.results.length} 首歌曲`
        : `${name} 没有匹配到歌曲，换个文件试试`
    } catch (error) {
      this.status = error instanceof Error ? error.message : '识别失败，请重试'
    } finally {
      this.busy = false
      this.progress = 0
    }
  }

  /** 通过临时授权的 uri 读入整个音频文件。 */
  private async readFile(uri: string): Promise<Uint8Array> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
    let buffer: ArrayBuffer = new ArrayBuffer(0)
    let read: number = 0
    try {
      const size = (await fileIo.stat(file.fd)).size
      if (size <= 0) { throw new Error('这个文件是空的，换一个试试') }
      if (size > MAX_AUDIO_FILE_BYTES) {
        throw new Error('音频文件太大，请选择 16MB 以内的文件')
      }
      buffer = new ArrayBuffer(size)
      read = await fileIo.read(file.fd, buffer)
    } finally {
      await fileIo.close(file)
    }
    if (read <= 0) { throw new Error('读取文件失败，请重试') }
    const exact = read === buffer.byteLength ? buffer : buffer.slice(0, read)
    return new Uint8Array(exact)
  }

  private onPrimary(): void {
    if (this.busy) { return }
    if (this.mode === 1) {
      this.recognizeFile()
    } else if (this.mode === 2) {
      this.startRecognize(false)
    } else {
      this.startRecognize(true)
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

        // 模式切换：与「最近播放」一致的顶部 Tab
        Row({ space: 28 }) {
          ForEach(this.tabTitles(), (title: string, index: number) => {
            Column({ space: 7 }) {
              Text(title)
                .fontSize(14)
                .fontColor(this.mode === index ? TC.textPrimary() : TC.textTertiary())
                .fontWeight(this.mode === index ? FontWeight.Bold : FontWeight.Regular)
              Column()
                .width(24).height(3).borderRadius(2)
                .backgroundColor(this.mode === index ? TC.accent() : Color.Transparent)
            }
            .height(46)
            .justifyContent(FlexAlign.Center)
            .enabled(!this.busy)
            .onClick(() => {
              if (this.mode !== index) {
                this.mode = index
                this.results = []
                this.status = this.idleHint()
              }
            })
          }, (title: string, index: number) => `mode_${index}_${title}`)
        }
        .width('100%').height(46).padding({ left: 18, right: 18 })

        Scroll() {
          Column({ space: 18 }) {
            Column({ space: 14 }) {
              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph(this.mode === 1 ? $r('sys.symbol.folder_badge_plus') : $r('sys.symbol.mic_fill'))
                  .fontSize(52)
                  .fontColor([Color.White])
              }
              .width(128).height(128)
              .borderRadius(64)
              .backgroundColor(TC.accent())
              .onClick(() => this.onPrimary())

              Text(this.status).fontSize(13).fontColor(TC.textBody())
                .textAlign(TextAlign.Center).padding({ left: 24, right: 24 })
              if (this.busy && this.progress > 0) {
                Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
                  .width('60%').height(4).color(TC.accent())
              } else if (this.busy) {
                LoadingProgress().width(26).height(26).color(TC.accent())
              }
              Text(this.mode === 1
                ? '选择手机里的音频文件'
                : '采集周围播放的音乐')
                .fontSize(10).fontColor(TC.textQuaternary())
                .textAlign(TextAlign.Center).padding({ left: 20, right: 20 })
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

        // 1x1 隐藏 Web：跑离线指纹引擎（rawfile/audiofp/index.html，全部内联）
        Web({ src: $rawfile('audiofp/index.html'), controller: this.fpHost.controller })
          .width(1)
          .height(1)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .zoomAccess(false)
          .javaScriptProxy({
            object: this.fpHost.engine,
            name: 'afpBridge',
            methodList: ['poll', 'onReady', 'onFp', 'onError'],
            controller: this.fpHost.controller
          })
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
