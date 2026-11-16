import { LyricPreferences } from '../models/lyricPreferences'
import { AppSettings } from '../services/AppSettings'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'
import { DecoColorPicker } from './DecoControls'

@Component
export struct LyricSettingsSheet {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  value: LyricPreferences = new LyricPreferences()
  onPreview: (value: LyricPreferences) => void = () => {}
  onClose: () => void = () => {}
  @State lyricSize: number = 19
  @State horizontal: number = 0
  @State spacing: number = 23
  @State amplitude: number = 1
  @State timeOffset: number = 0
  @State color: string = '#ef233c'
  @State pendingColor: string = 'rgba(255,255,255,0.62)'
  @State otherLineColor: string = 'rgba(255,255,255,0.46)'
  @State alignMode: number = 0
  @State saving: boolean = false

  aboutToAppear(): void {
    this.lyricSize = this.value.fontSize
    this.horizontal = this.value.horizontal
    this.spacing = this.value.spacing
    this.amplitude = this.value.amplitude
    this.timeOffset = this.value.offset
    this.color = this.value.highlight
    this.pendingColor = this.value.pendingColor
    this.otherLineColor = this.value.otherLineColor
    this.alignMode = this.value.align === 1 ? 1 : 0
  }

  private current(): LyricPreferences {
    return { fontSize: this.lyricSize, horizontal: this.horizontal, spacing: this.spacing,
      amplitude: this.amplitude, offset: this.timeOffset, highlight: this.color,
      pendingColor: this.pendingColor, otherLineColor: this.otherLineColor, align: this.alignMode }
  }

  private async save(): Promise<void> {
    this.saving = true
    try { await AppSettings.saveLyrics(this.current()); this.onClose() }
    catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '保存失败') }
    finally { this.saving = false }
  }

  private confirmRestore(): void {
    this.getUIContext().showAlertDialog({
      title: '恢复默认设置',
      message: '确定将歌词显示设置恢复为默认值？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '恢复', fontColor: TC.accent(), action: () => { this.restoreDefaults() } }
    })
  }

  private restoreDefaults(): void {
    const defaults = new LyricPreferences()
    this.lyricSize = defaults.fontSize
    this.horizontal = defaults.horizontal
    this.spacing = defaults.spacing
    this.amplitude = defaults.amplitude
    this.timeOffset = defaults.offset
    this.color = defaults.highlight
    this.pendingColor = defaults.pendingColor
    this.otherLineColor = defaults.otherLineColor
    this.alignMode = defaults.align
    this.onPreview(this.current())
    this.save()
  }

  @Builder
  private Control(title: string, value: number, min: number, max: number, step: number,
    change: (value: number) => void) {
    Column() {
      Text(title).width('100%').fontSize(13).fontColor(TC.textBody())
      Slider({ value: value, min: min, max: max, step: step })
        .selectedColor(this.color).onChange((value: number) => { change(value); this.onPreview(this.current()) })
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('歌词显示设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        Blank()
        SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
          .fontSize(22)
          .fontColor([TC.textSecondary()])
          .padding({ left: 14, right: 2, top: 6, bottom: 6 })
          .onClick(() => this.confirmRestore())
      }.width('100%')
      Scroll() {
        Column({ space: 8 }) {
          this.Control('字号 · ' + this.lyricSize, this.lyricSize, 14, 32, 1, (v: number) => this.lyricSize = v)
          Row({ space: 8 }) {
            Text('对齐方式').fontSize(13).fontColor(TC.textBody()).layoutWeight(1)
            ForEach([0, 1], (mode: number) => {
              Text(mode === 0 ? '居左' : '居中')
                .fontSize(12)
                .fontColor(this.alignMode === mode ? TC.textOnAccent() : TC.textBody())
                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                .backgroundColor(this.alignMode === mode ? this.color : TC.chipBackground())
                .borderRadius(14)
                .onClick(() => {
                  this.alignMode = mode
                  this.onPreview(this.current())
                })
            }, (mode: number) => `lyric_align_${mode}`)
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
          this.Control('左右位置 · ' + this.horizontal, this.horizontal, -16, 60, 1, (v: number) => this.horizontal = v)
          this.Control('行间距 · ' + this.spacing, this.spacing, 4, 48, 1, (v: number) => this.spacing = v)
          this.Control('动画幅度 · ' + this.amplitude.toFixed(1), this.amplitude, 0, 2, 0.1, (v: number) => this.amplitude = v)
          this.Control('时间偏移 · ' + this.timeOffset.toFixed(1) + ' 秒', this.timeOffset, -4, 4, 0.1,
            (v: number) => this.timeOffset = Math.round(v * 10) / 10)
          Text('正值提前显示歌词，负值延后显示').fontSize(11).fontColor(TC.textSecondary())
          Text('三种歌词颜色分别设置：当前行已高亮、当前行未高亮、其它行')
            .fontSize(11).fontColor(TC.textSecondary()).width('100%')
            .padding({ top: 4 })
          // 高亮颜色：禁透明度，恒输出 #RRGGBB，与旧存档格式一致
          DecoColorPicker({
            label: '当前行已高亮 · 高亮颜色',
            value: this.color,
            allowEmpty: false,
            withAlpha: false,
            onChange: (color: string) => {
              this.color = color
              this.onPreview(this.current())
            }
          })
          // 逐字歌词里，当前行还没唱到的那些字
          DecoColorPicker({
            label: '当前行未高亮 · 字色',
            value: this.pendingColor,
            allowEmpty: false,
            withAlpha: true,
            onChange: (color: string) => {
              this.pendingColor = color
              this.onPreview(this.current())
            }
          })
          // 不在当前行的所有歌词
          DecoColorPicker({
            label: '其它行歌词 · 颜色',
            value: this.otherLineColor,
            allowEmpty: false,
            withAlpha: true,
            onChange: (color: string) => {
              this.otherLineColor = color
              this.onPreview(this.current())
            }
          })
        }.width('100%')
      }.layoutWeight(1)
      Button(this.saving ? '保存中…' : '保存').width('100%').enabled(!this.saving)
        .fontColor(TC.textOnAccent()).backgroundColor(TC.accent()).onClick(() => this.save())
    }.width('100%').height('100%').padding(20)
  }
}
