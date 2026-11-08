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

/** 颜色选择：预设色板 + 手填色值 + 恢复跟随主题。 */
@Component
export struct DecoColorPicker {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop label: string = ''
  @Prop @Watch('syncText') value: string = ''
  onChange: (value: string) => void = () => {}
  @State private text: string = ''

  aboutToAppear(): void {
    this.text = this.value
  }

  private syncText(): void {
    this.text = this.value
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.label).fontSize(13).fontColor(TC.textBody()).layoutWeight(1)
        if (this.value) {
          Text('恢复跟随主题')
            .fontSize(11)
            .fontColor(TC.accent())
            .onClick(() => {
              this.text = ''
              this.onChange('')
            })
        } else {
          Text('跟随主题').fontSize(11).fontColor(TC.textTertiary())
        }
      }
      .width('100%')

      Scroll() {
        Row({ space: 10 }) {
          ForEach(PRESET_COLORS, (color: string) => {
            Stack() {
              if (this.value.toUpperCase() === color.toUpperCase()) {
                Column()
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .border({ width: 2, color: TC.accent() })
              }
              Column()
                .width(24)
                .height(24)
                .borderRadius(12)
                .backgroundColor(color)
                .border({ width: 1, color: TC.borderSubtle() })
            }
            .width(32)
            .height(32)
            .onClick(() => {
              this.text = color
              this.onChange(color)
            })
          }, (color: string) => color)
        }
        .padding({ left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      TextInput({ text: this.text, placeholder: '色值，如 #EF233C 或 rgba(0,0,0,0.4)' })
        .height(42)
        .fontSize(12)
        .fontColor(TC.textPrimary())
        .placeholderColor(TC.textQuaternary())
        .backgroundColor(TC.surfaceInset())
        .borderRadius(12)
        .onChange((value: string) => {
          this.text = value
          const normalized = DecoColor.normalize(value)
          if (normalized) {
            this.onChange(normalized)
          }
        })
    }
    .width('100%')
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
