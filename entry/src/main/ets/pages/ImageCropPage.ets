import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { DecoRatio, ImageCropPageParam } from '../models/decoration'
import { DecorationMedia } from '../services/DecorationMedia'
import { TC } from '../services/ThemeColors'

interface CropPreset {
  label: string
  aspect: number
}

/** 自由矩形：角点拖拽时不锁比例（与「不进裁剪页」的 DecoRatio.FREE=0 含义不同）。 */
const CROP_FREE: number = -1

/** 常用比例；推荐比例若不在其中，会在初始化时额外插一项。 */
const CROP_PRESETS: CropPreset[] = [
  { label: '原图', aspect: DecoRatio.FREE },
  { label: '自由', aspect: CROP_FREE },
  { label: '1:1', aspect: DecoRatio.SQUARE },
  { label: '3:4', aspect: DecoRatio.PORTRAIT },
  { label: '9:16', aspect: DecoRatio.SCREEN },
  { label: '4:3', aspect: 4 / 3 },
  { label: '16:9', aspect: 16 / 9 },
  { label: '3:1', aspect: DecoRatio.CARD }
]

/**
 * 装扮素材裁剪页。
 *
 * 流程：读沙箱原图 → ImageSource 解码取原始像素宽高 → 等比适配编辑区 →
 * 捏合缩放 / 单指拖动调图、拖四角改裁剪框 → vp 坐标换算成像素 Region →
 * cropSync + ImagePacker 存回沙箱 → 回传路径。
 *
 * 旋转 / 翻转是「预处理」：rotateSync / flipSync 立刻生成一张新图并重新载入，
 * 所以裁剪坐标系永远只对应当前显示的那张图，不必在坐标换算里叠加变换矩阵。
 * 显示直接用文件路径（Image 自己解码，动图也能预览），PixelMap 只在真正处理时
 * 临时创建并立即 release，规避 @State 代理 native 对象与大图常驻内存。
 */
@Component
export struct ImageCropPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: ImageCropPageParam = {
    sourcePath: '', aspect: DecoRatio.FREE, title: '裁剪图片',
    onComplete: (_path: string) => {}
  }

  @State editorW: number = 0
  @State editorH: number = 0
  @State imgWidth: number = 0
  @State imgHeight: number = 0
  @State fitWidth: number = 0
  @State fitHeight: number = 0
  @State scale: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  @State aspect: number = DecoRatio.FREE
  @State ratioIndex: number = 0
  @State presets: CropPreset[] = []
  // 裁剪框在编辑区里的 vp 坐标与尺寸（可拖四角改变）
  @State cropX: number = 0
  @State cropY: number = 0
  @State cropW: number = 0
  @State cropH: number = 0
  @State currentPath: string = ''
  @State resultPath: string = ''
  @State resultSize: string = ''
  @State tip: string = '正在读取图片…'
  @State busy: boolean = false
  @State loaded: boolean = false

  private baseScale: number = 1
  private baseX: number = 0
  private baseY: number = 0
  private baseCropX: number = 0
  private baseCropY: number = 0
  private baseCropW: number = 0
  private baseCropH: number = 0
  private pinchActive: boolean = false
  private boxDragging: boolean = false
  private imageSource: image.ImageSource | undefined = undefined
  private workingCopies: string[] = []
  private finished: boolean = false
  private readonly pngFormat: string = 'image/png'

  async aboutToAppear(): Promise<void> {
    this.currentPath = this.pageParam.sourcePath
    this.aspect = this.pageParam.aspect
    this.buildPresets()
    await this.loadImage()
  }

  aboutToDisappear(): void {
    // 系统返回键不会走 cancel，这里兜底清理中间文件
    if (!this.finished) {
      this.cleanup('')
    }
    const source = this.imageSource
    this.imageSource = undefined
    if (source) {
      source.release().catch(() => {})
    }
  }

  private buildPresets(): void {
    const list: CropPreset[] = CROP_PRESETS.slice()
    const recommended = this.pageParam.aspect
    if (recommended > 0 && !list.some((item: CropPreset) => Math.abs(item.aspect - recommended) < 0.001)) {
      list.splice(2, 0, { label: '推荐', aspect: recommended })
    }
    this.presets = list
    let index = 0
    for (let i = 0; i < list.length; i++) {
      if (Math.abs(list[i].aspect - this.aspect) < 0.001) {
        index = i
        break
      }
    }
    this.ratioIndex = index
  }

  private async readBytes(path: string): Promise<ArrayBuffer> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY)
    try {
      const size = (await fileIo.stat(file.fd)).size
      const buffer = new ArrayBuffer(size)
      await fileIo.read(file.fd, buffer)
      return buffer
    } finally {
      await fileIo.close(file)
    }
  }

  /** 读当前图并解码，拿原始像素尺寸；变换后重新调用即可刷新宽高。 */
  private async loadImage(): Promise<void> {
    try {
      const buffer = await this.readBytes(this.currentPath)
      const previous = this.imageSource
      this.imageSource = undefined
      if (previous) {
        previous.release().catch(() => {})
      }
      this.imageSource = image.createImageSource(buffer)
      const info: image.ImageInfo = await this.imageSource.getImageInfo()
      this.imgWidth = info.size.width
      this.imgHeight = info.size.height
      if (this.imgWidth <= 0 || this.imgHeight <= 0) {
        throw new Error('图片尺寸无效')
      }
      this.loaded = true
      if (!this.finished) {
        this.tip = this.currentPath.toLowerCase().endsWith('.gif')
          ? '动图经过变换或裁剪会变成静态首帧，想保留动画请点「跳过裁剪」'
          : '双指缩放 / 拖动图片，拖四角改裁剪框'
      }
      if (this.editorW > 0) {
        this.recomputeFit()
      }
    } catch (error) {
      this.tip = `图片读取失败：${error instanceof Error ? error.message : '未知错误'}`
    }
  }

  // ---------------------------------------------------------------------------
  // 尺寸与坐标
  // ---------------------------------------------------------------------------

  /** 初始化裁剪框用的比例：0 / 自由都取原图比例。 */
  private initialAspect(): number {
    if (this.aspect > 0) { return this.aspect }
    if (this.imgWidth > 0 && this.imgHeight > 0) { return this.imgWidth / this.imgHeight }
    return 1
  }

  private boxLeft(): number { return this.cropX }
  private boxTop(): number { return this.cropY }
  private boxWidth(): number { return this.cropW }
  private boxHeight(): number { return this.cropH }

  private resetCropBox(): void {
    const a = this.initialAspect()
    const maxW = Math.max(40, this.editorW - 32)
    const maxH = Math.max(40, this.editorH - 32)
    let w = 0
    let h = 0
    if (a >= 1) {
      w = Math.min(maxW, maxH * a)
      h = w / a
    } else {
      h = Math.min(maxH, maxW / a)
      w = h * a
    }
    this.cropW = w
    this.cropH = h
    this.cropX = (this.editorW - w) / 2
    this.cropY = (this.editorH - h) / 2
  }

  private dispWidth(): number { return this.fitWidth * this.scale }
  private dispHeight(): number { return this.fitHeight * this.scale }

  /** 图片左上角（相对编辑区，vp）。 */
  private imageLeft(): number {
    return (this.editorW - this.dispWidth()) / 2 + this.offsetX
  }

  private imageTop(): number {
    return (this.editorH - this.dispHeight()) / 2 + this.offsetY
  }

  /** 图片至少要盖住整个裁剪框，否则 cropSync 会越界。 */
  private minScale(): number {
    if (this.fitWidth <= 0 || this.fitHeight <= 0) { return 1 }
    return Math.max(this.cropW / this.fitWidth, this.cropH / this.fitHeight, 1)
  }

  private maxScale(): number {
    return Math.max(this.minScale() * 6, 5)
  }

  private recomputeFit(): void {
    if (this.imgWidth <= 0 || this.imgHeight <= 0 || this.editorW <= 0 || this.editorH <= 0) {
      return
    }
    const ratio = Math.min(this.editorW / this.imgWidth, this.editorH / this.imgHeight)
    this.fitWidth = this.imgWidth * ratio
    this.fitHeight = this.imgHeight * ratio
    this.resetCropBox()
    this.scale = this.minScale()
    this.offsetX = 0
    this.offsetY = 0
  }

  /** 拖动/缩放后把图片夹到「裁剪框始终在图片内」的范围。 */
  private clampOffset(): void {
    const dispW = this.dispWidth()
    const dispH = this.dispHeight()
    if (dispW <= 0 || dispH <= 0) { return }
    const centerX = (this.editorW - dispW) / 2
    const centerY = (this.editorH - dispH) / 2
    const minX = this.cropX + this.cropW - dispW - centerX
    const maxX = this.cropX - centerX
    const minY = this.cropY + this.cropH - dispH - centerY
    const maxY = this.cropY - centerY
    this.offsetX = minX <= maxX ? Math.max(minX, Math.min(maxX, this.offsetX)) : (minX + maxX) / 2
    this.offsetY = minY <= maxY ? Math.max(minY, Math.min(maxY, this.offsetY)) : (minY + maxY) / 2
  }

  /** 裁剪框被拖大后，自动把图片放大到仍能盖住它。 */
  private enforceCover(): void {
    const need = this.minScale()
    if (this.scale < need) { this.scale = need }
    this.clampOffset()
  }

  private onEditorArea(area: Area): void {
    const w = px2vp(Number(area.width))
    const h = px2vp(Number(area.height))
    if (w <= 0 || h <= 0) { return }
    if (Math.abs(w - this.editorW) < 0.5 && Math.abs(h - this.editorH) < 0.5) { return }
    this.editorW = w
    this.editorH = h
    if (this.imgWidth > 0) {
      this.recomputeFit()
    }
  }

  private setAspect(aspect: number, index: number): void {
    this.aspect = aspect
    this.ratioIndex = index
    this.discardResult()
    this.resetCropBox()
    this.scale = Math.max(this.minScale(), Math.min(this.scale, this.maxScale()))
    this.clampOffset()
  }

  private resetView(): void {
    this.discardResult()
    this.resetCropBox()
    this.scale = this.minScale()
    this.offsetX = 0
    this.offsetY = 0
    this.tip = '双指缩放 / 拖动图片，拖四角改裁剪框'
  }

  // ---------------------------------------------------------------------------
  // 四角拖拽：改裁剪框大小
  // ---------------------------------------------------------------------------

  private startBoxDrag(): void {
    this.baseCropX = this.cropX
    this.baseCropY = this.cropY
    this.baseCropW = this.cropW
    this.baseCropH = this.cropH
  }

  /** corner: 0 左上 / 1 右上 / 2 左下 / 3 右下；锁比例时以位移较大的轴为主导。 */
  private resizeBox(corner: number, dx: number, dy: number): void {
    this.discardResult()
    const margin = 8
    const minSize = 60
    const locked = this.aspect !== CROP_FREE
    const ratio = this.initialAspect()
    let left = this.baseCropX
    let top = this.baseCropY
    let right = this.baseCropX + this.baseCropW
    let bottom = this.baseCropY + this.baseCropH

    if (corner === 0) { left += dx; top += dy }
    else if (corner === 1) { right += dx; top += dy }
    else if (corner === 2) { left += dx; bottom += dy }
    else { right += dx; bottom += dy }

    let w = right - left
    let h = bottom - top
    if (locked) {
      if (Math.abs(dx) >= Math.abs(dy)) {
        w = Math.max(minSize, w)
        h = w / ratio
      } else {
        h = Math.max(minSize, h)
        w = h * ratio
      }
    } else {
      w = Math.max(minSize, w)
      h = Math.max(minSize, h)
    }

    // 尺寸上限：锁比例时两维一起缩，避免破坏比例
    const maxW = this.editorW - margin * 2
    const maxH = this.editorH - margin * 2
    if (w > maxW) {
      const k = maxW / w
      w = maxW
      h = locked ? h * k : h
    }
    if (h > maxH) {
      const k = maxH / h
      h = maxH
      w = locked ? w * k : w
    }

    // 贴回固定的那个角
    if (corner === 0) { left = right - w; top = bottom - h }
    else if (corner === 1) { right = left + w; top = bottom - h }
    else if (corner === 2) { left = right - w; bottom = top + h }
    else { right = left + w; bottom = top + h }

    // 整体平移进编辑区，尺寸与比例都不变
    if (left < margin) { right += margin - left; left = margin }
    if (top < margin) { bottom += margin - top; top = margin }
    if (right > this.editorW - margin) {
      left -= right - (this.editorW - margin)
      right = this.editorW - margin
    }
    if (bottom > this.editorH - margin) {
      top -= bottom - (this.editorH - margin)
      bottom = this.editorH - margin
    }

    this.cropW = Math.max(minSize, right - left)
    this.cropH = Math.max(minSize, bottom - top)
    this.cropX = left
    this.cropY = top
    this.enforceCover()
  }

  // ---------------------------------------------------------------------------
  // 旋转与翻转（预处理：生成新图后重新载入）
  // ---------------------------------------------------------------------------

  private async transform(rotateAngle: number, flipH: boolean, flipV: boolean): Promise<void> {
    if (this.busy || !this.currentPath) { return }
    this.busy = true
    let source: image.ImageSource | undefined = undefined
    let pixel: image.PixelMap | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const buffer = await this.readBytes(this.currentPath)
      source = image.createImageSource(buffer)
      pixel = await source.createPixelMap()
      if (rotateAngle !== 0) {
        pixel.rotateSync(rotateAngle)
      }
      if (flipH || flipV) {
        pixel.flipSync(flipH, flipV)
      }
      packer = image.createImagePacker()
      const data = await packer.packing(pixel, { format: this.pngFormat, quality: 100 })
      const previous = this.currentPath
      const next = DecorationMedia.saveCropped(context, data, '.png')
      this.workingCopies.push(next)
      this.currentPath = next
      if (previous !== this.pageParam.sourcePath) {
        DecorationMedia.removeFile(previous)
      }
      this.discardResult()
      await this.loadImage()
      this.tip = '已应用变换，可继续裁剪'
    } catch (error) {
      this.tip = `变换失败：${error instanceof Error ? error.message : '未知错误'}`
    } finally {
      try { await packer?.release() } catch (_error) {}
      try { await pixel?.release() } catch (_error) {}
      try { await source?.release() } catch (_error) {}
      this.busy = false
    }
  }

  // ---------------------------------------------------------------------------
  // 裁剪与文件清理
  // ---------------------------------------------------------------------------

  private async doCrop(): Promise<void> {
    if (!this.imageSource || this.busy || this.imgWidth <= 0 || this.cropW <= 0) {
      return
    }
    this.busy = true
    let pixel: image.PixelMap | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    try {
      const dispW = this.dispWidth()
      const dispH = this.dispHeight()
      // 裁剪框 vp 坐标 → 当前图像素坐标
      const rawX = Math.floor((this.cropX - this.imageLeft()) / dispW * this.imgWidth)
      const rawY = Math.floor((this.cropY - this.imageTop()) / dispH * this.imgHeight)
      let rawW = Math.floor(this.cropW / dispW * this.imgWidth)
      let rawH = Math.floor(this.cropH / dispH * this.imgHeight)
      const x = Math.max(0, Math.min(rawX, this.imgWidth - 1))
      const y = Math.max(0, Math.min(rawY, this.imgHeight - 1))
      rawW = Math.max(1, Math.min(rawW, this.imgWidth - x))
      rawH = Math.max(1, Math.min(rawH, this.imgHeight - y))
      const region: image.Region = { x: x, y: y, size: { width: rawW, height: rawH } }

      // 每次从当前图重新解码，cropSync 是原地裁剪，不能复用上一次的 PixelMap
      pixel = await this.imageSource.createPixelMap()
      pixel.cropSync(region)
      packer = image.createImagePacker()
      const data = await packer.packing(pixel, { format: this.pngFormat, quality: 100 })
      this.discardResult()
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      this.resultPath = DecorationMedia.saveCropped(context, data, '.png')
      this.resultSize = `${rawW} × ${rawH}`
      this.tip = `裁剪完成 ${this.resultSize}，确认后使用`
    } catch (error) {
      this.tip = `裁剪失败：${error instanceof Error ? error.message : '未知错误'}`
    } finally {
      try { await packer?.release() } catch (_error) {}
      try { await pixel?.release() } catch (_error) {}
      this.busy = false
    }
  }

  private discardResult(): void {
    if (this.resultPath) {
      DecorationMedia.removeFile(this.resultPath)
      this.resultPath = ''
      this.resultSize = ''
    }
  }

  /** 只保留最终采用的那个文件，其余中间图 / 裁剪结果 / 临时源图全部删掉。 */
  private cleanup(except: string): void {
    this.workingCopies.forEach((path: string) => {
      if (path !== except) {
        DecorationMedia.removeFile(path)
      }
    })
    this.workingCopies = []
    // 只删「没被采用」的裁剪结果；except === resultPath 时必须保留
    if (this.resultPath && this.resultPath !== except) {
      DecorationMedia.removeFile(this.resultPath)
    }
    this.resultPath = ''
    this.resultSize = ''
    if (this.pageParam.sourcePath !== except && this.pageParam.discardSource === true) {
      DecorationMedia.removeFile(this.pageParam.sourcePath)
    }
  }

  private confirm(path: string): void {
    this.finished = true
    this.cleanup(path)
    this.pageStack.pop()
    this.pageParam.onComplete(path)
  }

  private cancel(): void {
    this.finished = true
    this.cleanup('')
    this.pageStack.pop()
  }

  // ---------------------------------------------------------------------------
  // 视图
  // ---------------------------------------------------------------------------

  @Builder
  private ToolChip(label: string, action: () => void) {
    Text(label)
      .fontSize(11)
      .fontColor(TC.textBody())
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(TC.chipBackground())
      .onClick(() => action())
  }

  /** 角点拖拽热区：盖在四角上，40vp 见方，视觉给一个小白点。 */
  @Builder
  private CornerHandle(corner: number) {
    Stack() {
      Column()
        .width(10).height(10).borderRadius(5)
        .backgroundColor(Color.White)
        .opacity(0.9)
        .hitTestBehavior(HitTestMode.None)
    }
    .width(40)
    .height(40)
    .position({
      x: (corner === 0 || corner === 2 ? this.cropX : this.cropX + this.cropW) - 20,
      y: (corner === 0 || corner === 1 ? this.cropY : this.cropY + this.cropH) - 20
    })
    .gesture(
      PanGesture({ fingers: 1 })
        .onActionStart(() => {
          this.boxDragging = true
          this.startBoxDrag()
        })
        .onActionUpdate((event: GestureEvent) => {
          this.resizeBox(corner, event.offsetX, event.offsetY)
        })
        .onActionEnd(() => { this.boxDragging = false })
    )
  }

  /** 四条半透明遮罩 + 裁剪框 + 九宫格 + 四角标记。 */
  @Builder
  private CropOverlay() {
    // 上
    Column()
      .width(this.editorW).height(Math.max(0, this.cropY))
      .backgroundColor('#99000000')
      .position({ x: 0, y: 0 })
      .hitTestBehavior(HitTestMode.None)
    // 下
    Column()
      .width(this.editorW).height(Math.max(0, this.editorH - this.cropY - this.cropH))
      .backgroundColor('#99000000')
      .position({ x: 0, y: this.cropY + this.cropH })
      .hitTestBehavior(HitTestMode.None)
    // 左
    Column()
      .width(Math.max(0, this.cropX)).height(this.cropH)
      .backgroundColor('#99000000')
      .position({ x: 0, y: this.cropY })
      .hitTestBehavior(HitTestMode.None)
    // 右
    Column()
      .width(Math.max(0, this.editorW - this.cropX - this.cropW))
      .height(this.cropH)
      .backgroundColor('#99000000')
      .position({ x: this.cropX + this.cropW, y: this.cropY })
      .hitTestBehavior(HitTestMode.None)

    // 九宫格
    Column().width(1).height(this.cropH).backgroundColor('#66FFFFFF')
      .position({ x: this.cropX + this.cropW / 3, y: this.cropY })
      .hitTestBehavior(HitTestMode.None)
    Column().width(1).height(this.cropH).backgroundColor('#66FFFFFF')
      .position({ x: this.cropX + this.cropW * 2 / 3, y: this.cropY })
      .hitTestBehavior(HitTestMode.None)
    Column().width(this.cropW).height(1).backgroundColor('#66FFFFFF')
      .position({ x: this.cropX, y: this.cropY + this.cropH / 3 })
      .hitTestBehavior(HitTestMode.None)
    Column().width(this.cropW).height(1).backgroundColor('#66FFFFFF')
      .position({ x: this.cropX, y: this.cropY + this.cropH * 2 / 3 })
      .hitTestBehavior(HitTestMode.None)

    // 边框
    Column()
      .width(this.cropW).height(this.cropH)
      .border({ width: 1.5, color: Color.White })
      .position({ x: this.cropX, y: this.cropY })
      .hitTestBehavior(HitTestMode.None)

    // 四角 L 形
    Column().width(20).height(2).backgroundColor(Color.White)
      .position({ x: this.cropX, y: this.cropY }).hitTestBehavior(HitTestMode.None)
    Column().width(2).height(20).backgroundColor(Color.White)
      .position({ x: this.cropX, y: this.cropY }).hitTestBehavior(HitTestMode.None)
    Column().width(20).height(2).backgroundColor(Color.White)
      .position({ x: this.cropX + this.cropW - 20, y: this.cropY })
      .hitTestBehavior(HitTestMode.None)
    Column().width(2).height(20).backgroundColor(Color.White)
      .position({ x: this.cropX + this.cropW - 2, y: this.cropY })
      .hitTestBehavior(HitTestMode.None)
    Column().width(20).height(2).backgroundColor(Color.White)
      .position({ x: this.cropX, y: this.cropY + this.cropH - 2 })
      .hitTestBehavior(HitTestMode.None)
    Column().width(2).height(20).backgroundColor(Color.White)
      .position({ x: this.cropX, y: this.cropY + this.cropH - 20 })
      .hitTestBehavior(HitTestMode.None)
    Column().width(20).height(2).backgroundColor(Color.White)
      .position({ x: this.cropX + this.cropW - 20, y: this.cropY + this.cropH - 2 })
      .hitTestBehavior(HitTestMode.None)
    Column().width(2).height(20).backgroundColor(Color.White)
      .position({ x: this.cropX + this.cropW - 2, y: this.cropY + this.cropH - 20 })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)

        Row({ space: 12 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([TC.textPrimary()])
          }
          .width(36).height(36).borderRadius(18)
          .backgroundColor(TC.surfaceRaised())
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.cancel())

          Text(`裁剪 · ${this.pageParam.title}`)
            .layoutWeight(1).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text('重置').fontSize(12).fontColor(TC.accent())
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .onClick(() => this.resetView())
        }
        .width('100%').height(54).padding({ left: 16, right: 16 })

        // 比例切换
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.presets, (preset: CropPreset, index: number) => {
              Text(preset.label)
                .fontSize(12)
                .fontColor(this.ratioIndex === index ? TC.textOnAccent() : TC.textBody())
                .padding({ left: 13, right: 13, top: 6, bottom: 6 })
                .borderRadius(15)
                .backgroundColor(this.ratioIndex === index ? TC.accent() : TC.chipBackground())
                .onClick(() => this.setAspect(preset.aspect, index))
            }, (preset: CropPreset) => preset.label)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .width('100%')

        // 旋转 / 翻转
        Scroll() {
          Row({ space: 8 }) {
            this.ToolChip('左转 90°', () => { this.transform(270, false, false) })
            this.ToolChip('右转 90°', () => { this.transform(90, false, false) })
            this.ToolChip('水平翻转', () => { this.transform(0, true, false) })
            this.ToolChip('垂直翻转', () => { this.transform(0, false, true) })
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: 6 })

        Text(this.tip)
          .width('100%').fontSize(11).fontColor(TC.textTertiary())
          .padding({ left: 16, right: 16, top: 8, bottom: 4 })
          .maxLines(2)

        // 编辑区
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.loaded && this.dispWidth() > 0) {
            Image(this.currentPath)
              .width(this.dispWidth())
              .height(this.dispHeight())
              .objectFit(ImageFit.Fill)
              .interpolation(ImageInterpolation.High)
              .position({ x: this.imageLeft(), y: this.imageTop() })
              .hitTestBehavior(HitTestMode.None)
          }
          if (this.editorW > 0 && this.cropW > 0 && this.cropH > 0) {
            this.CropOverlay()
            this.CornerHandle(0)
            this.CornerHandle(1)
            this.CornerHandle(2)
            this.CornerHandle(3)
          }
          if (this.busy) {
            LoadingProgress().width(40).height(40).color(TC.accent())
              .position({ x: this.editorW / 2 - 20, y: this.editorH / 2 - 20 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)
        .backgroundColor('#101014')
        .onAreaChange((_old: Area, area: Area) => this.onEditorArea(area))
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.discardResult()
                this.pinchActive = true
                this.baseScale = this.scale
              })
              .onActionUpdate((event: GestureEvent) => {
                const pinch = Number(event.scale)
                if (Number.isNaN(pinch) || pinch <= 0) { return }
                this.scale = Math.max(this.minScale(), Math.min(this.baseScale * pinch, this.maxScale()))
                this.clampOffset()
              })
              .onActionEnd(() => { this.pinchActive = false }),
            PanGesture({ fingers: 1 })
              .onActionStart(() => {
                this.discardResult()
                this.baseX = this.offsetX
                this.baseY = this.offsetY
              })
              .onActionUpdate((event: GestureEvent) => {
                if (this.pinchActive || this.boxDragging) { return }
                this.offsetX = this.baseX + event.offsetX
                this.offsetY = this.baseY + event.offsetY
                this.clampOffset()
              })
          )
        )

        // 裁剪结果预览
        if (this.resultPath) {
          Row({ space: 12 }) {
            Image(this.resultPath)
              .height(54).width(54).borderRadius(8).objectFit(ImageFit.Contain)
              .backgroundColor(TC.surfaceInset())
            Column({ space: 3 }) {
              Text('裁剪结果').fontSize(12).fontColor(TC.textBody())
              Text(this.resultSize).fontSize(11).fontColor(TC.textTertiary())
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('重新调整').fontSize(12).fontColor(TC.accent())
              .onClick(() => this.discardResult())
          }
          .width('100%').height(70).padding({ left: 16, right: 16 })
        }

        // 底部操作
        Row({ space: 12 }) {
          Button('跳过裁剪')
            .layoutWeight(1).height(44).fontSize(13)
            .fontColor(TC.textPrimary()).backgroundColor(TC.chipBackground())
            .borderRadius(22)
            .enabled(!this.busy && this.loaded)
            .onClick(() => this.confirm(this.currentPath))
          Button(this.busy ? '处理中…' : (this.resultPath ? '使用这张' : '裁剪'))
            .layoutWeight(1.4).height(44).fontSize(13)
            .fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
            .borderRadius(22)
            .enabled(!this.busy && this.loaded)
            .onClick(() => {
              if (this.resultPath) {
                this.confirm(this.resultPath)
              } else {
                this.doCrop()
              }
            })
        }
        .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 20 })
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
