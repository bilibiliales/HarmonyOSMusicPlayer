import { common } from '@kit.AbilityKit'
import { DecorationMedia } from '../services/DecorationMedia'
import { DecoColor } from '../services/DecorationColor'
import { TC } from '../services/ThemeColors'

/**
 * 装扮编辑器通用控件。
 *
 * 全部走 TC 取色，新页面零额外适配即可同时支持深浅色与皮肤；
 * 每个控件只负责「显示 + 回传值」，状态由宿主页面持有，便于统一序列化。
 */

/** 预设色板（红系主色 + 中性色，覆盖绝大多数搭配）。 */
const PRESET_COLORS: string[] = [
  '#ef233c', '#ff6577', '#ff8a3d', '#f7c948', '#3ddc97', '#3d9bf7', '#8a5cf6',
  '#ffffff', '#d9d9e0', '#8c8c96', '#3a3a44', '#111114'
]

/** 带数值显示的滑杆。 */
@Component
export struct DecoSlider {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop label: string = ''
  @Prop value: number = 0
  @Prop min: number = 0
  @Prop max: number = 100
  @Prop step: number = 1
  @Prop unit: string = ''
  onChange: (value: number) => void = () => {}

  private display(): string {
    const rounded = Math.round(this.value * 10) / 10
    return `${rounded}${this.unit}`
  }

  build() {
    Column({ space: 2 }) {
      Row() {
        Text(this.label).fontSize(13).fontColor(TC.textBody()).layoutWeight(1)
        Text(this.display()).fontSize(12).fontColor(TC.textTertiary())
      }
      .width('100%')

      Slider({
        value: this.value,
        min: this.min,
        max: this.max,
        step: this.step,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .selectedColor(TC.accent())
        .trackColor(TC.surfaceInset())
        .blockColor(TC.accent())
        .onChange((value: number) => this.onChange(value))
    }
    .width('100%')
  }
}

/** 解析 #rgb/#rrggbb/#aarrggbb/rgba()，返回 [r,g,b,a(0-100)]；无法解析时用默认红。 */
function parseColorRGBA(color: string): number[] {
  const fallback: number[] = [239, 35, 60, 100]
  const value = color.trim()
  if (value.startsWith('#')) {
    let body = value.substring(1)
    let alphaPercent = 100
    if (body.length === 3) {
      body = `${body[0]}${body[0]}${body[1]}${body[1]}${body[2]}${body[2]}`
    } else if (body.length === 8) {
      alphaPercent = Math.round(parseInt(body.substring(0, 2), 16) / 255 * 100)
      body = body.substring(2)
    }
    if (body.length === 6) {
      const r = parseInt(body.substring(0, 2), 16)
      const g = parseInt(body.substring(2, 4), 16)
      const b = parseInt(body.substring(4, 6), 16)
      if (!Number.isNaN(r) && !Number.isNaN(g) && !Number.isNaN(b)) {
        return [r, g, b, alphaPercent]
      }
    }
    return fallback
  }
  const match = value.match(/rgba?\(([^)]+)\)/)
  if (match) {
    const parts = match[1].split(',')
    if (parts.length >= 3) {
      const r = parseInt(parts[0].trim(), 10)
      const g = parseInt(parts[1].trim(), 10)
      const b = parseInt(parts[2].trim(), 10)
      let alphaPercent = 100
      if (parts.length >= 4) {
        alphaPercent = Math.round(parseFloat(parts[3].trim()) * 100)
      }
      if (!Number.isNaN(r) && !Number.isNaN(g) && !Number.isNaN(b)) {
        return [r, g, b, alphaPercent]
      }
    }
  }
  return fallback
}

/** 0-255 转两位大写 hex。 */
function colorChannelHex(component: number): string {
  const clamped = Math.max(0, Math.min(255, Math.round(component)))
  const text = clamped.toString(16).toUpperCase()
  return text.length === 1 ? `0${text}` : text
}

/**
 * 颜色选择：RGBA 四滑块半模态（自研，替代 HdsColorPicker —— 该组件要 API 26，
 * 项目下限目前到不了 26）。行内显示当前色板，点开半模态调 红/绿/蓝/透明度，
 * 实时回传；也支持直接填 hex / rgba()。
 *
 * - allowEmpty：是否允许「恢复跟随主题」（皮肤、播放器配色用）；
 * - withAlpha：是否提供透明度滑块。false 时恒输出 #RRGGBB（歌词高亮等只收 hex 的场景）。
 */
@Component
export struct DecoColorPicker {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop label: string = ''
  @Prop @Watch('onValueChanged') value: string = ''
  @Prop allowEmpty: boolean = true
  @Prop withAlpha: boolean = true
  onChange: (value: string) => void = () => {}
  @State private sheetOpen: boolean = false
  @State private red: number = 239
  @State private green: number = 35
  @State private blue: number = 60
  @State private alpha: number = 100
  @State private hexText: string = ''

  aboutToAppear(): void {
    this.loadFromValue()
  }

  private onValueChanged(): void {
    this.loadFromValue()
  }

  /** 把外部传入值拆成 RGBA 四个分量；无法解析时用默认红。 */
  private loadFromValue(): void {
    const parsed = parseColorRGBA(this.value)
    this.red = parsed[0]
    this.green = parsed[1]
    this.blue = parsed[2]
    this.alpha = parsed[3]
    this.hexText = this.value
  }

  private currentColor(): string {
    if (this.withAlpha && this.alpha < 100) {
      const a = Math.round(this.alpha) / 100
      return `rgba(${this.red},${this.green},${this.blue},${a})`
    }
    return `#${colorChannelHex(this.red)}${colorChannelHex(this.green)}${colorChannelHex(this.blue)}`
  }

  private emit(): void {
    const color = this.currentColor()
    this.hexText = color
    this.onChange(color)
  }

  @Builder
  private ChannelSlider(label: string, value: number, min: number, max: number, unit: string,
    change: (v: number) => void) {
    Row({ space: 10 }) {
      Text(label).fontSize(13).fontColor(TC.textBody()).width(52)
      Slider({ value: value, min: min, max: max, step: 1, style: SliderStyle.OutSet })
        .layoutWeight(1)
        .selectedColor(TC.accent())
        .trackColor(TC.surfaceInset())
        .blockColor(TC.accent())
        .onChange((v: number) => { change(v); this.emit() })
      Text(`${Math.round(value)}${unit}`).fontSize(12).fontColor(TC.textTertiary()).width(40)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  @Builder
  private SheetContent() {
    Column({ space: 16 }) {
      Text(this.label ? this.label : '选择颜色')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(TC.textPrimary())
        .width('100%')

      // 预览条
      Row({ space: 12 }) {
        Column()
          .width(52)
          .height(52)
          .borderRadius(14)
          .backgroundColor(this.currentColor())
          .border({ width: 1, color: TC.borderSubtle() })
        Column({ space: 4 }) {
          Text(this.currentColor()).fontSize(13).fontColor(TC.textPrimary())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('拖动滑块实时生效').fontSize(11).fontColor(TC.textTertiary())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      this.ChannelSlider('红 R', this.red, 0, 255, '', (v: number) => this.red = v)
      this.ChannelSlider('绿 G', this.green, 0, 255, '', (v: number) => this.green = v)
      this.ChannelSlider('蓝 B', this.blue, 0, 255, '', (v: number) => this.blue = v)
      if (this.withAlpha) {
        this.ChannelSlider('透明度', this.alpha, 0, 100, '%', (v: number) => this.alpha = v)
      }

      // 预设色板
      Text('常用色').fontSize(12).fontColor(TC.textTertiary()).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(PRESET_COLORS, (color: string) => {
          Column()
            .width(30)
            .height(30)
            .borderRadius(15)
            .backgroundColor(color)
            .border({ width: 1, color: TC.borderSubtle() })
            .margin({ right: 12, bottom: 12 })
            .onClick(() => {
              const parsed = parseColorRGBA(color)
              this.red = parsed[0]
              this.green = parsed[1]
              this.blue = parsed[2]
              this.alpha = 100
              this.emit()
            })
        }, (color: string) => color)
      }
      .width('100%')

      Button('完成')
        .width('100%')
        .height(44)
        .fontColor(TC.textOnAccent())
        .backgroundColor(TC.accent())
        .borderRadius(22)
        .onClick(() => this.sheetOpen = false)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text(this.label).fontSize(13).fontColor(TC.textBody()).layoutWeight(1)
        if (this.value) {
          Text(this.value)
            .fontSize(11)
            .fontColor(TC.textTertiary())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.allowEmpty && this.value) {
          Text('恢复跟随主题')
            .fontSize(11)
            .fontColor(TC.accent())
            .onClick(() => this.onChange(''))
        } else if (this.allowEmpty && !this.value) {
          Text('跟随主题').fontSize(11).fontColor(TC.textTertiary())
        }
        Column()
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor(this.value ? this.value : TC.surfaceInset())
          .border({ width: 1, color: TC.borderSubtle() })
          .onClick(() => {
            this.loadFromValue()
            this.sheetOpen = true
          })
      }
      .width('100%')

      TextInput({ text: this.hexText, placeholder: '#EF233C 或 rgba(0,0,0,0.4)' })
        .height(38)
        .fontSize(12)
        .fontColor(TC.textPrimary())
        .placeholderColor(TC.textQuaternary())
        .backgroundColor(TC.surfaceInset())
        .borderRadius(10)
        .onChange((text: string) => {
          this.hexText = text
          const normalized = DecoColor.normalize(text)
          if (normalized) {
            this.onChange(normalized)
          }
        })
    }
    .width('100%')
    .bindSheet(this.sheetOpen, this.SheetContent(), {
      height: SheetSize.MEDIUM,
      backgroundColor: TC.sheetBackground(),
      // 展开时暗化背后内容，半模态与页面区分开
      maskColor: 'rgba(0,0,0,0.45)',
      showClose: false,
      dragBar: true,
      onDisappear: () => this.sheetOpen = false
    })
  }
}

/** 媒体选择：图片 / 视频，落在沙箱里，返回持久路径。 */
@Component
export struct DecoMediaPicker {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop label: string = ''
  @Prop value: string = ''
  /** image | video */
  @Prop mediaType: string = 'image'
  onChange: (path: string) => void = () => {}
  @State private busy: boolean = false

  private async pick(): Promise<void> {
    if (this.busy) { return }
    this.busy = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const path = this.mediaType === 'video'
        ? await DecorationMedia.pickVideo(context)
        : await DecorationMedia.pickImage(context)
      if (path) {
        this.onChange(path)
      }
    } catch (_error) {
      // 用户取消或系统拒绝：保持原值
    } finally {
      this.busy = false
    }
  }

  private fileName(): string {
    if (!this.value) { return '' }
    const index = this.value.lastIndexOf('/')
    return index >= 0 ? this.value.substring(index + 1) : this.value
  }

  build() {
    Row({ space: 12 }) {
      if (this.mediaType === 'video') {
        Stack() {
          if (this.value) {
            Video({ src: this.value })
              .width(54)
              .height(54)
              .objectFit(ImageFit.Cover)
              .controls(false)
              .muted(true)
          }
          Column()
            .width(54)
            .height(54)
            .borderRadius(12)
            .backgroundColor('rgba(0,0,0,0.3)')
            .hitTestBehavior(HitTestMode.None)
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(18)
            .fontColor([TC.textOnMedia()])
            .hitTestBehavior(HitTestMode.None)
        }
        .width(54)
        .height(54)
        .borderRadius(12)
        .clip(true)
        .backgroundColor(TC.surfaceInset())
      } else if (this.value) {
        Image(this.value)
          .width(54)
          .height(54)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)
          .backgroundColor(TC.surfaceInset())
      } else {
        Stack() {
          SymbolGlyph($r('sys.symbol.camera_fill'))
            .fontSize(22)
            .fontColor([TC.textQuaternary()])
        }
        .width(54)
        .height(54)
        .borderRadius(12)
        .backgroundColor(TC.surfaceInset())
      }

      Column({ space: 4 }) {
        Text(this.label).fontSize(13).fontColor(TC.textBody())
        Text(this.value ? this.fileName() : '未选择')
          .fontSize(11)
          .fontColor(TC.textTertiary())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.busy) {
        LoadingProgress().width(24).height(24).color(TC.textTertiary())
      } else {
        Button(this.value ? '更换' : '选择')
          .fontSize(12)
          .fontColor(TC.textPrimary())
          .backgroundColor(TC.chipBackground())
          .height(32)
          .padding({ left: 14, right: 14 })
          .borderRadius(16)
          .onClick(() => this.pick())
      }

      if (this.value) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([TC.textTertiary()])
          .onClick(() => this.onChange(''))
      }
    }
    .width('100%')
  }
}

/** 一行开关。 */
@Component
export struct DecoToggleRow {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop label: string = ''
  @Prop isOn: boolean = false
  onChange: (value: boolean) => void = () => {}

  build() {
    Row({ space: 12 }) {
      Text(this.label).fontSize(13).fontColor(TC.textBody()).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(TC.accent())
        .onChange((value: boolean) => this.onChange(value))
    }
    .width('100%')
  }
}

/** 区块卡片容器。 */
@Component
export struct DecoCard {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop title: string = ''
  @Prop hint: string = ''
  @Builder
  private emptyContent() {
  }

  @BuilderParam content: () => void = this.emptyContent

  build() {
    Column({ space: 12 }) {
      if (this.title) {
        Column({ space: 3 }) {
          Text(this.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          if (this.hint) {
            Text(this.hint).fontSize(11).fontColor(TC.textTertiary()).width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      this.content()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(TC.surfaceCard())
    .borderRadius(20)
  }
}
