import { LyricPreferences } from '../models/lyricPreferences'
import { AppSettings } from '../services/AppSettings'
import { BubbleTip } from '../services/BubbleTip'

@Component
export struct LyricSettingsSheet {
  value: LyricPreferences = new LyricPreferences()
  onPreview: (value: LyricPreferences) => void = () => {}
  onClose: () => void = () => {}
  @State lyricSize: number = 19
  @State horizontal: number = 0
  @State spacing: number = 23
  @State amplitude: number = 1
  @State timeOffset: number = 0
  @State color: string = '#ef233c'
  @State saving: boolean = false

  aboutToAppear(): void {
    this.lyricSize = this.value.fontSize
    this.horizontal = this.value.horizontal
    this.spacing = this.value.spacing
    this.amplitude = this.value.amplitude
    this.timeOffset = this.value.offset
    this.color = this.value.highlight
  }

  private current(): LyricPreferences {
    return { fontSize: this.lyricSize, horizontal: this.horizontal, spacing: this.spacing,
      amplitude: this.amplitude, offset: this.timeOffset, highlight: this.color }
  }

  private async save(): Promise<void> {
    this.saving = true
    try { await AppSettings.saveLyrics(this.current()); this.onClose() }
    catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '保存失败') }
    finally { this.saving = false }
  }

  @Builder
  private Control(title: string, value: number, min: number, max: number, step: number,
    change: (value: number) => void) {
    Column() {
      Text(title).width('100%').fontSize(13).fontColor('#d9d9df')
      Slider({ value: value, min: min, max: max, step: step })
        .selectedColor(this.color).onChange((value: number) => { change(value); this.onPreview(this.current()) })
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Text('歌词显示设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#ffffff')
      Scroll() {
        Column({ space: 8 }) {
          this.Control('字号 · ' + this.lyricSize, this.lyricSize, 14, 32, 1, (v: number) => this.lyricSize = v)
          this.Control('左右位置 · ' + this.horizontal, this.horizontal, -16, 60, 1, (v: number) => this.horizontal = v)
          this.Control('行间距 · ' + this.spacing, this.spacing, 4, 48, 1, (v: number) => this.spacing = v)
          this.Control('动画幅度 · ' + this.amplitude.toFixed(1), this.amplitude, 0, 2, 0.1, (v: number) => this.amplitude = v)
          this.Control('时间偏移 · ' + this.timeOffset.toFixed(1) + ' 秒', this.timeOffset, -4, 4, 0.1,
            (v: number) => this.timeOffset = Math.round(v * 10) / 10)
          Text('正值提前显示歌词，负值延后显示').fontSize(11).fontColor('#96969f')
          Text('高亮颜色').width('100%').fontSize(13).fontColor('#d9d9df')
          Row({ space: 16 }) {
            ForEach(['#ef233c', '#ffffff', '#ffd166', '#66ddaa', '#69b9ff', '#cda0ff'], (color: string) => {
              Circle().width(30).height(30).fill(color).stroke(this.color === color ? '#ffffff' : '#55555d')
                .strokeWidth(this.color === color ? 3 : 1)
                .onClick(() => { this.color = color; this.onPreview(this.current()) })
            })
          }
        }.width('100%')
      }.layoutWeight(1)
      Button(this.saving ? '保存中…' : '保存').width('100%').enabled(!this.saving)
        .backgroundColor('#ef233c').onClick(() => this.save())
    }.width('100%').height('100%').padding(20)
  }
}
