import { common } from '@kit.AbilityKit'
import { BubbleTip } from '../services/BubbleTip'
import { DecorationMedia } from '../services/DecorationMedia'
import { DecorationStore } from '../services/DecorationStore'
import {
  DecoMember,
  DecoKind,
  DecoRatio,
  DecorationItem,
  DockConfig,
  HeartConfig,
  HomeBgConfig,
  ImageOnlyConfig,
  PlayerLayer,
  PlayerStyleConfig,
  SidebarConfig,
  SkinConfig,
  StartupConfig,
  SuitConfig,
  VipBadgeConfig,
  ImageCropPageParam
} from '../models/decoration'
import { TC } from '../services/ThemeColors'
import { DecoColor } from '../services/DecorationColor'
import { DecoCard, DecoColorPicker, DecoMediaPicker, DecoSlider, DecoToggleRow } from '../components/DecoControls'

/** 装扮编辑器入参。 */
export class DecorationEditorParam {
  kind: string = ''
}

/**
 * 装扮编辑器。
 *
 * 一个页面覆盖 12 类装扮：顶部是「该类已保存的装扮」横向列表（可切换/新建/删除），
 * 下面是按类型渲染的表单。所有改动先落在 @State 草稿上，点保存才写库并发布到运行时，
 * 避免拖动滑杆时反复写盘。
 *
 * 播放器样式带一个真实比例的舞台预览：图层可点选、可直接拖动，也可用滑杆精调；
 * 黑胶与封面是舞台上的独立组件，各自有尺寸/位移/透明度/圆角参数。
 */
@Component
export struct DecorationEditorPage {
  pageParam: DecorationEditorParam = new DecorationEditorParam()
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @StorageProp('skinVersion') skinVersionObs: number = 0

  // ---- 列表状态 ----
  @State private kind: string = ''
  @State private items: DecorationItem[] = []
  @State private activeId: string = ''
  @State private editingId: string = ''
  @State private name: string = ''

  // ---- 皮肤 ----
  @State private skinBgImage: string = ''
  @State private skinBgOpacity: number = 100
  @State private skinBgBlur: number = 0
  @State private skinScrim: number = 38
  @State private skinPageColor: string = ''
  @State private skinThemeColor: string = ''
  @State private skinAccentColor: string = ''
  @State private skinTextColor: string = ''

  // ---- 播放器样式 ----
  @State private playerBgImage: string = ''
  @State private playerBgVideo: string = ''
  @State private playerBgColor: string = ''
  @State private playerBgOpacity: number = 100
  @State private playerBgBlur: number = 0
  @State private playerBgScrim: number = 45
  @State private playerLayers: PlayerLayer[] = []
  @State private selectedLayerId: string = ''
  @State private vinylImage: string = ''
  @State private vinylSize: number = 0
  @State private vinylX: number = 0
  @State private vinylY: number = 0
  @State private vinylOpacity: number = 100
  @State private coverRatio: number = 63
  @State private coverX: number = 0
  @State private coverY: number = 0
  @State private coverRadius: number = 50
  @State private playerControlColor: string = ''
  @State private playerProgressColor: string = ''
  @State private playerIconColor: string = ''
  @State private playerTextColor: string = ''
  @State private stageW: number = 360
  @State private stageH: number = 580
  private dragStartX: number = 0
  private dragStartY: number = 0

  // ---- 底部导航 ----
  @State private dockIcons: string[] = ['', '', '', '']
  @State private dockIconColor: string = ''
  @State private dockActiveColor: string = ''
  @State private dockTextColor: string = ''
  @State private dockTextSize: number = 10
  @State private dockBgColor: string = ''
  @State private dockBgImage: string = ''
  @State private dockShowText: boolean = true

  // ---- 侧边栏 ----
  @State private sideBgImage: string = ''
  @State private sideBgOpacity: number = 100
  @State private sideBgBlur: number = 0
  @State private sideBgColor: string = ''
  @State private sideTextColor: string = ''
  @State private sideTextSize: number = 16
  @State private sideIconColor: string = ''

  // ---- 个人主页背景 ----
  @State private homeImage: string = ''
  @State private homeBlur: number = 0
  @State private homeOpacity: number = 100
  @State private homeFade: number = 100

  // ---- 红心 ----
  @State private heartColor: string = '#ef233c'
  @State private heartCount: number = 7
  @State private heartSize: number = 22
  @State private heartDuration: number = 1200

  // ---- 启动资源 ----
  @State private startupMedia: string = ''
  @State private startupType: string = 'image'
  @State private startupDuration: number = 3000
  @State private startupSkip: boolean = true

  // ---- 单图类 ----
  @State private singleImage: string = ''

  // ---- VIP 等级贴图 ----
  @State private badgeImages: string[] = ['', '', '', '', '', '', '']

  // ---- 套装 ----
  @State private suitPick: string[] = ['', '', '', '', '', '', '', '', '', '', '']

  // =========================================================================
  // 生命周期与数据
  // =========================================================================

  aboutToAppear(): void {
    this.kind = this.pageParam.kind ? this.pageParam.kind : DecoKind.SKIN
    this.refreshList()
    const active = DecorationStore.activeItem(this.kind)
    const first = this.items.length > 0 ? this.items[0] : undefined
    if (active) {
      this.loadDraft(active)
    } else if (first) {
      this.loadDraft(first)
    } else {
      this.resetDraft()
    }
  }

  private refreshList(): void {
    this.items = DecorationStore.list(this.kind)
    this.activeId = DecorationStore.activeId(this.kind)
  }

  private defaultName(): string {
    const title = DecoKind.title(this.kind)
    const list = DecorationStore.list(this.kind)
    return `${title} ${list.length + 1}`
  }

  /** 清空草稿到默认值。 */
  private resetDraft(): void {
    this.editingId = ''
    this.name = this.defaultName()

    this.skinBgImage = ''
    this.skinBgOpacity = 100
    this.skinBgBlur = 0
    this.skinScrim = 38
    this.skinPageColor = ''
    this.skinThemeColor = ''
    this.skinAccentColor = ''
    this.skinTextColor = ''

    this.playerBgImage = ''
    this.playerBgVideo = ''
    this.playerBgColor = ''
    this.playerBgOpacity = 100
    this.playerBgBlur = 0
    this.playerBgScrim = 45
    this.playerLayers = []
    this.selectedLayerId = ''
    this.vinylImage = ''
    this.vinylSize = 0
    this.vinylX = 0
    this.vinylY = 0
    this.vinylOpacity = 100
    this.coverRatio = 63
    this.coverX = 0
    this.coverY = 0
    this.coverRadius = 50
    this.playerControlColor = ''
    this.playerProgressColor = ''
    this.playerIconColor = ''
    this.playerTextColor = ''

    this.dockIcons = ['', '', '', '']
    this.dockIconColor = ''
    this.dockActiveColor = ''
    this.dockTextColor = ''
    this.dockTextSize = 10
    this.dockBgColor = ''
    this.dockBgImage = ''
    this.dockShowText = true

    this.sideBgImage = ''
    this.sideBgOpacity = 100
    this.sideBgBlur = 0
    this.sideBgColor = ''
    this.sideTextColor = ''
    this.sideTextSize = 16
    this.sideIconColor = ''

    this.homeImage = ''
    this.homeBlur = 0
    this.homeOpacity = 100
    this.homeFade = 100

    this.heartColor = '#ef233c'
    this.heartCount = 7
    this.heartSize = 22
    this.heartDuration = 1200

    this.startupMedia = ''
    this.startupType = 'image'
    this.startupDuration = 3000
    this.startupSkip = true

    this.singleImage = ''
    this.badgeImages = ['', '', '', '', '', '', '']
    this.suitPick = ['', '', '', '', '', '', '', '', '', '', '']
  }

  /** 把一条已保存的装扮载入草稿。 */
  private loadDraft(item: DecorationItem): void {
    this.resetDraft()
    this.editingId = item.id
    this.name = item.name
    const raw = item.payload

    if (this.kind === DecoKind.SKIN) {
      const cfg = SkinConfig.from(raw)
      this.skinBgImage = cfg.bgImage
      this.skinBgOpacity = cfg.bgOpacity
      this.skinBgBlur = cfg.bgBlur
      this.skinScrim = cfg.scrim
      this.skinPageColor = cfg.pageColor
      this.skinThemeColor = cfg.themeColor
      this.skinAccentColor = cfg.accentColor
      this.skinTextColor = cfg.textColor
      return
    }
    if (this.kind === DecoKind.PLAYER) {
      const cfg = PlayerStyleConfig.from(raw)
      this.playerBgImage = cfg.bgImage
      this.playerBgVideo = cfg.bgVideo
      this.playerBgColor = cfg.bgColor
      this.playerBgOpacity = cfg.bgOpacity
      this.playerBgBlur = cfg.bgBlur
      this.playerBgScrim = cfg.bgScrim
      this.playerLayers = cfg.layers
      this.selectedLayerId = cfg.layers.length > 0 ? cfg.layers[0].id : ''
      this.vinylImage = cfg.vinylImage
      this.vinylSize = cfg.vinylSize
      this.vinylX = cfg.vinylX
      this.vinylY = cfg.vinylY
      this.vinylOpacity = cfg.vinylOpacity
      this.coverRatio = cfg.coverRatio
      this.coverX = cfg.coverX
      this.coverY = cfg.coverY
      this.coverRadius = cfg.coverRadius
      this.playerControlColor = cfg.controlColor
      this.playerProgressColor = cfg.progressColor
      this.playerIconColor = cfg.iconColor
      this.playerTextColor = cfg.textColor
      return
    }
    if (this.kind === DecoKind.DOCK) {
      const cfg = DockConfig.from(raw)
      this.dockIcons = cfg.icons
      this.dockIconColor = cfg.iconColor
      this.dockActiveColor = cfg.activeColor
      this.dockTextColor = cfg.textColor
      this.dockTextSize = cfg.textSize
      this.dockBgColor = cfg.bgColor
      this.dockBgImage = cfg.bgImage
      this.dockShowText = cfg.showText
      return
    }
    if (this.kind === DecoKind.SIDEBAR) {
      const cfg = SidebarConfig.from(raw)
      this.sideBgImage = cfg.bgImage
      this.sideBgOpacity = cfg.bgOpacity
      this.sideBgBlur = cfg.bgBlur
      this.sideBgColor = cfg.bgColor
      this.sideTextColor = cfg.textColor
      this.sideTextSize = cfg.textSize
      this.sideIconColor = cfg.iconColor
      return
    }
    if (this.kind === DecoKind.HOME_BG) {
      const cfg = HomeBgConfig.from(raw)
      this.homeImage = cfg.image
      this.homeBlur = cfg.blur
      this.homeOpacity = cfg.opacity
      this.homeFade = cfg.fade
      return
    }
    if (this.kind === DecoKind.HEART) {
      const cfg = HeartConfig.from(raw)
      this.heartColor = cfg.color
      this.heartCount = cfg.count
      this.heartSize = cfg.size
      this.heartDuration = cfg.duration
      return
    }
    if (this.kind === DecoKind.STARTUP) {
      const cfg = StartupConfig.from(raw)
      this.startupMedia = cfg.media
      this.startupType = cfg.type
      this.startupDuration = cfg.duration
      this.startupSkip = cfg.allowSkip
      return
    }
    if (this.kind === DecoKind.VIP_BADGE) {
      this.badgeImages = VipBadgeConfig.from(raw).images
      return
    }
    if (this.kind === DecoKind.SUIT) {
      const cfg = SuitConfig.from(raw)
      const kinds = DecoKind.pickable()
      const next: string[] = []
      for (let i = 0; i < kinds.length; i++) {
        let picked = ''
        for (const member of cfg.members) {
          if (member.kind === kinds[i]) { picked = member.id }
        }
        next.push(picked)
      }
      this.suitPick = next
      return
    }
    this.singleImage = ImageOnlyConfig.from(raw).image
  }

  /** 由草稿生成配置 JSON。 */
  private buildPayload(): string {
    if (this.kind === DecoKind.SKIN) {
      const cfg = new SkinConfig()
      cfg.bgImage = this.skinBgImage
      cfg.bgOpacity = this.skinBgOpacity
      cfg.bgBlur = this.skinBgBlur
      cfg.scrim = this.skinScrim
      cfg.pageColor = this.skinPageColor
      cfg.themeColor = this.skinThemeColor
      cfg.accentColor = this.skinAccentColor
      cfg.textColor = this.skinTextColor
      return JSON.stringify(cfg)
    }
    if (this.kind === DecoKind.PLAYER) {
      const cfg = new PlayerStyleConfig()
      cfg.bgImage = this.playerBgImage
      cfg.bgVideo = this.playerBgVideo
      cfg.bgColor = this.playerBgColor
      cfg.bgOpacity = this.playerBgOpacity
      cfg.bgBlur = this.playerBgBlur
      cfg.bgScrim = this.playerBgScrim
      cfg.layers = this.playerLayers
      cfg.vinylImage = this.vinylImage
      cfg.vinylSize = this.vinylSize
      cfg.vinylX = this.vinylX
      cfg.vinylY = this.vinylY
      cfg.vinylOpacity = this.vinylOpacity
      cfg.coverRatio = this.coverRatio
      cfg.coverX = this.coverX
      cfg.coverY = this.coverY
      cfg.coverRadius = this.coverRadius
      cfg.controlColor = this.playerControlColor
      cfg.progressColor = this.playerProgressColor
      cfg.iconColor = this.playerIconColor
      cfg.textColor = this.playerTextColor
      return JSON.stringify(cfg)
    }
    if (this.kind === DecoKind.DOCK) {
      const cfg = new DockConfig()
      cfg.icons = this.dockIcons
      cfg.iconColor = this.dockIconColor
      cfg.activeColor = this.dockActiveColor
      cfg.textColor = this.dockTextColor
      cfg.textSize = this.dockTextSize
      cfg.bgColor = this.dockBgColor
      cfg.bgImage = this.dockBgImage
      cfg.showText = this.dockShowText
      return JSON.stringify(cfg)
    }
    if (this.kind === DecoKind.SIDEBAR) {
      const cfg = new SidebarConfig()
      cfg.bgImage = this.sideBgImage
      cfg.bgOpacity = this.sideBgOpacity
      cfg.bgBlur = this.sideBgBlur
      cfg.bgColor = this.sideBgColor
      cfg.textColor = this.sideTextColor
      cfg.textSize = this.sideTextSize
      cfg.iconColor = this.sideIconColor
      return JSON.stringify(cfg)
    }
    if (this.kind === DecoKind.HOME_BG) {
      const cfg = new HomeBgConfig()
      cfg.image = this.homeImage
      cfg.blur = this.homeBlur
      cfg.opacity = this.homeOpacity
      cfg.fade = this.homeFade
      return JSON.stringify(cfg)
    }
    if (this.kind === DecoKind.HEART) {
      const cfg = new HeartConfig()
      cfg.color = this.heartColor
      cfg.count = this.heartCount
      cfg.size = this.heartSize
      cfg.duration = this.heartDuration
      return JSON.stringify(cfg)
    }
    if (this.kind === DecoKind.STARTUP) {
      const cfg = new StartupConfig()
      cfg.media = this.startupMedia
      cfg.type = this.startupType
      cfg.duration = this.startupDuration
      cfg.allowSkip = this.startupSkip
      return JSON.stringify(cfg)
    }
    if (this.kind === DecoKind.VIP_BADGE) {
      const cfg = new VipBadgeConfig()
      cfg.images = this.badgeImages
      return JSON.stringify(cfg)
    }
    if (this.kind === DecoKind.SUIT) {
      const cfg = new SuitConfig()
      const kinds = DecoKind.pickable()
      const members: DecoMember[] = []
      for (let i = 0; i < kinds.length; i++) {
        const id = i < this.suitPick.length ? this.suitPick[i] : ''
        if (!id) { continue }
        const member = new DecoMember()
        member.kind = kinds[i]
        member.id = id
        members.push(member)
      }
      cfg.members = members
      return JSON.stringify(cfg)
    }
    const cfg = new ImageOnlyConfig()
    cfg.image = this.singleImage
    return JSON.stringify(cfg)
  }

  /** 恢复默认：把当前类型的表单值重置为出厂默认，保留名称与已保存条目的绑定，保存后才生效。 */
  private restoreDefaults(): void {
    const keepId = this.editingId
    const keepName = this.name
    this.resetDraft()
    this.editingId = keepId
    this.name = keepName
    BubbleTip.show(this.getUIContext(), '已恢复默认，保存后生效')
  }

  private async save(activate: boolean): Promise<void> {
    const item = new DecorationItem()
    item.kind = this.kind
    item.name = this.name.trim() ? this.name.trim() : DecoKind.title(this.kind)
    item.payload = this.buildPayload()
    item.cover = ''
    if (this.editingId) {
      item.id = this.editingId
    }
    const saved = await DecorationStore.save(item)
    this.editingId = saved.id
    this.name = saved.name
    const shouldApply = activate || (this.kind !== DecoKind.SUIT && !DecorationStore.activeId(this.kind))
    if (shouldApply) {
      if (this.kind === DecoKind.SUIT) {
        await DecorationStore.applySuit(saved)
      } else {
        await DecorationStore.activate(saved)
      }
    }
    this.refreshList()
    BubbleTip.show(this.getUIContext(), activate ? '已启用' : '已保存')
  }

  private async removeCurrent(): Promise<void> {
    if (!this.editingId) {
      this.resetDraft()
      return
    }
    await DecorationStore.remove(this.editingId)
    this.refreshList()
    const first = this.items.length > 0 ? this.items[0] : undefined
    if (first) {
      this.loadDraft(first)
    } else {
      this.resetDraft()
    }
    BubbleTip.show(this.getUIContext(), '已删除')
  }

  // =========================================================================
  // 播放器：图层与舞台
  // =========================================================================

  private async addLayer(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const path = await DecorationMedia.pickImage(context)
      if (!path) { return }
      // 图层是自由叠图，默认给 1:1，裁剪页里可随时换成原图或其它比例
      const param: ImageCropPageParam = {
        sourcePath: path,
        aspect: DecoRatio.SQUARE,
        title: '新增图层',
        discardSource: true,
        onComplete: (cropped: string) => this.appendLayer(cropped)
      }
      this.pageStack.pushPathByName('ImageCropPage', param)
    } catch (_error) {
      BubbleTip.show(this.getUIContext(), '选择图片失败')
    }
  }

  private appendLayer(path: string): void {
    const layer = new PlayerLayer()
    layer.id = `layer_${Date.now()}`
    layer.src = path
    layer.x = 30
    layer.y = 30
    layer.w = 40
    layer.h = 40
    layer.rotation = 0
    layer.opacity = 100
    this.playerLayers = this.playerLayers.concat([layer])
    this.selectedLayerId = layer.id
  }

  private cloneLayer(src: PlayerLayer): PlayerLayer {
    const copy = new PlayerLayer()
    copy.id = src.id
    copy.src = src.src
    copy.x = src.x
    copy.y = src.y
    copy.w = src.w
    copy.h = src.h
    copy.rotation = src.rotation
    copy.opacity = src.opacity
    return copy
  }

  /** 对选中图层做一次不可变更新（触发重渲染）。 */
  private updateSelected(apply: (copy: PlayerLayer) => void): void {
    const next: PlayerLayer[] = []
    for (const layer of this.playerLayers) {
      if (layer.id === this.selectedLayerId) {
        const copy = this.cloneLayer(layer)
        apply(copy)
        next.push(copy)
      } else {
        next.push(layer)
      }
    }
    this.playerLayers = next
  }

  private moveLayer(id: string, x: number, y: number): void {
    const next: PlayerLayer[] = []
    for (const layer of this.playerLayers) {
      if (layer.id === id) {
        const copy = this.cloneLayer(layer)
        copy.x = Math.max(-20, Math.min(120, x))
        copy.y = Math.max(-20, Math.min(120, y))
        next.push(copy)
      } else {
        next.push(layer)
      }
    }
    this.playerLayers = next
  }

  private removeLayer(id: string): void {
    const next: PlayerLayer[] = []
    for (const layer of this.playerLayers) {
      if (layer.id !== id) { next.push(layer) }
    }
    this.playerLayers = next
    if (this.selectedLayerId === id) {
      this.selectedLayerId = next.length > 0 ? next[0].id : ''
    }
  }

  private moveLayerOrder(id: string, delta: number): void {
    const list = this.playerLayers.slice()
    let from = -1
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) { from = i }
    }
    if (from < 0) { return }
    const to = from + delta
    if (to < 0 || to >= list.length) { return }
    const moved = list[from]
    list.splice(from, 1)
    list.splice(to, 0, moved)
    this.playerLayers = list
  }

  private selectedLayers(): PlayerLayer[] {
    const result: PlayerLayer[] = []
    for (const layer of this.playerLayers) {
      if (layer.id === this.selectedLayerId) { result.push(layer) }
    }
    return result
  }

  // ---- 舞台预览取色：装扮优先，未指定按白字画布 ----
  private stageIcon(): string {
    return this.playerIconColor ? this.playerIconColor : '#FFFFFF'
  }

  private stageSmallIcon(): string {
    return this.playerIconColor ? this.playerIconColor : '#999999'
  }

  private stageText(): string {
    return this.playerTextColor ? this.playerTextColor : '#FFFFFF'
  }

  private stageTextDim(): string {
    return this.playerTextColor ? DecoColor.alpha(this.playerTextColor, 0.66) : '#B3FFFFFF'
  }

  private stageTextFaint(): string {
    return this.playerTextColor ? DecoColor.alpha(this.playerTextColor, 0.42) : '#6BFFFFFF'
  }

  private stageControl(): string {
    return this.playerControlColor ? this.playerControlColor : '#FFFFFF'
  }

  private stageProgress(): string {
    if (this.playerProgressColor) { return this.playerProgressColor }
    return this.stageControl()
  }

  private stageProgressTrack(): string {
    const base = this.playerProgressColor ? this.playerProgressColor : this.playerControlColor
    if (base) { return DecoColor.alpha(base, 0.24) }
    return 'rgba(255,255,255,0.22)'
  }

  private stageVinylSize(): number {
    if (this.stageW <= 0) { return 120 }
    const auto = this.stageW * 0.62
    return this.vinylSize > 0 ? this.vinylSize * (this.stageW / 360) : auto
  }

  // =========================================================================
  // 视图：公共部件
  // =========================================================================

  @Builder
  private ItemChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.items, (item: DecorationItem) => {
          Row({ space: 5 }) {
            Text(item.name)
              .fontSize(12)
              .fontColor(this.editingId === item.id ? TC.textOnAccent() : TC.textBody())
              .maxLines(1)
            if (this.activeId === item.id) {
              Text('·使用中')
                .fontSize(10)
                .fontColor(this.editingId === item.id ? TC.textOnAccent() : TC.accent())
            }
          }
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.editingId === item.id ? TC.accent() : TC.chipBackground())
          .borderRadius(16)
          .onClick(() => this.loadDraft(item))
        }, (item: DecorationItem) => item.id)

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(12).fontColor([TC.textBody()])
          Text('新建').fontSize(12).fontColor(TC.textBody())
        }
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .backgroundColor(TC.chipBackground())
        .borderRadius(16)
        .onClick(() => this.resetDraft())
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private ActionBar() {
    Row({ space: 10 }) {
      Text('恢复默认')
        .fontSize(12)
        .fontColor(TC.textTertiary())
        .padding({ left: 8, right: 8, top: 12, bottom: 12 })
        .onClick(() => this.restoreDefaults())

      Button('保存')
        .layoutWeight(1)
        .height(44)
        .fontSize(14)
        .fontColor(TC.textPrimary())
        .backgroundColor(TC.chipBackground())
        .borderRadius(22)
        .onClick(() => this.save(false))

      Button(this.kind === DecoKind.SUIT ? '应用套装' : '保存并启用')
        .layoutWeight(1.4)
        .height(44)
        .fontSize(14)
        .fontColor(TC.textOnAccent())
        .backgroundColor(TC.accent())
        .borderRadius(22)
        .onClick(() => this.save(true))

      if (this.editingId) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([TC.textTertiary()])
          .padding(10)
          .onClick(() => this.removeCurrent())
      }
    }
    .width('100%')
  }

  @Builder
  private NameField() {
    Row({ space: 10 }) {
      Text('名称').fontSize(13).fontColor(TC.textBody())
      TextInput({ text: this.name, placeholder: '给这套装扮起个名字' })
        .layoutWeight(1)
        .height(42)
        .fontSize(13)
        .fontColor(TC.textPrimary())
        .placeholderColor(TC.textQuaternary())
        .backgroundColor(TC.surfaceInset())
        .borderRadius(12)
        .onChange((value: string) => this.name = value)
    }
    .width('100%')
  }

  // =========================================================================
  // 视图：皮肤
  // =========================================================================

  @Builder
  private SkinPreview() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.skinBgImage) {
        Image(this.skinBgImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.skinBgBlur)
          .opacity(this.skinBgOpacity / 100)
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.skinBgImage
          ? `rgba(0,0,0,${this.skinScrim / 100})`
          : (this.skinPageColor ? this.skinPageColor : '#191920'))

      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Column().width(22).height(22).borderRadius(11)
            .backgroundColor(this.skinThemeColor ? this.skinThemeColor : TC.accent())
          Text('预览').fontSize(11)
            .fontColor(this.skinTextColor ? this.skinTextColor : '#FFFFFF')
        }
        Row({ space: 6 }) {
          Column().width(34).height(34).borderRadius(8)
            .backgroundColor(this.skinBgImage ? 'rgba(255,255,255,0.24)' : '#2B2B33')
          Column({ space: 4 }) {
            Column().width(56).height(6).borderRadius(3)
              .backgroundColor(this.skinTextColor ? this.skinTextColor : '#FFFFFF')
            Column().width(38).height(5).borderRadius(3)
              .backgroundColor(this.skinTextColor ? this.skinTextColor : '#FFFFFF')
              .opacity(0.5)
          }
        }
        Row({ space: 6 }) {
          Text('按钮').fontSize(9).fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(this.skinThemeColor ? this.skinThemeColor : TC.accent())
            .borderRadius(9)
          Text('选中').fontSize(9).fontColor(this.skinThemeColor ? this.skinThemeColor : TC.accent())
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(this.skinAccentColor ? this.skinAccentColor : TC.accentContainer())
            .borderRadius(9)
        }
      }
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(150)
    .borderRadius(16)
    .clip(true)
    .backgroundColor(TC.surfaceInset())
  }

  @Builder
  private SkinForm() {
    Column({ space: 12 }) {
      DecoCard({ title: '背景', hint: '支持静态图与 GIF 动图；不透明度拉低可让背景更贴合页面底色' }) {
        DecoMediaPicker({
          label: '页面背景图',
          value: this.skinBgImage,
          mediaType: 'image',
          cropAspect: DecoRatio.SCREEN,
          onChange: (path: string) => this.skinBgImage = path
        })
        DecoSlider({
          label: '背景亮度', value: this.skinBgBlur, min: 0, max: 40, step: 1, unit: 'vp',
          onChange: (v: number) => this.skinBgBlur = v
        })
        DecoSlider({
          label: '不透明度', value: this.skinBgOpacity, min: 5, max: 100, step: 1, unit: '%',
          onChange: (v: number) => this.skinBgOpacity = v
        })
        DecoSlider({
          label: '可读性蒙版', value: this.skinScrim, min: 0, max: 85, step: 1, unit: '%',
          onChange: (v: number) => this.skinScrim = v
        })
      }

      DecoCard({ title: '配色', hint: '留空表示跟随深浅色主题；填了就固定该颜色，切换深浅色不再变化' }) {
        DecoColorPicker({
          label: '页面背景色', value: this.skinPageColor,
          onChange: (v: string) => this.skinPageColor = v
        })
        DecoColorPicker({
          label: '主题色（按钮 / 选中 / 进度）', value: this.skinThemeColor,
          onChange: (v: string) => this.skinThemeColor = v
        })
        DecoColorPicker({
          label: '突出色（次级高亮）', value: this.skinAccentColor,
          onChange: (v: string) => this.skinAccentColor = v
        })
        DecoColorPicker({
          label: '字体色', value: this.skinTextColor,
          onChange: (v: string) => this.skinTextColor = v
        })
      }

      DecoCard({ title: '效果预览', hint: '按当前配色实时渲染，卡片与文字会自动适配' }) {
        this.SkinPreview()
      }
    }
    .width('100%')
  }

  // =========================================================================
  // 视图：播放器
  // =========================================================================

  @Builder
  private StageLayer(layer: PlayerLayer) {
    Image(layer.src)
      .width(this.stageW * layer.w / 100)
      .height(this.stageW * layer.h / 100)
      .objectFit(ImageFit.Contain)
      .rotate({ angle: layer.rotation })
      .opacity(layer.opacity / 100)
      .position({ x: this.stageW * layer.x / 100, y: this.stageH * layer.y / 100 })
      .border({
        width: this.selectedLayerId === layer.id ? 1 : 0,
        color: TC.accent(),
        radius: 4
      })
      .onClick(() => this.selectedLayerId = layer.id)
      .gesture(
        PanGesture()
          .onActionStart(() => {
            this.dragStartX = layer.x
            this.dragStartY = layer.y
            this.selectedLayerId = layer.id
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.stageW <= 0 || this.stageH <= 0) { return }
            const nx = this.dragStartX + event.offsetX / this.stageW * 100
            const ny = this.dragStartY + event.offsetY / this.stageH * 100
            this.moveLayer(layer.id, nx, ny)
          })
      )
  }

  @Builder
  private PlayerStage() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 背景色
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.playerBgColor ? this.playerBgColor : '#14141a')

      // 背景媒体
      if (this.playerBgVideo) {
        Video({ src: this.playerBgVideo })
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoPlay(true)
          .loop(true)
          .muted(true)
          .controls(false)
          .blur(this.playerBgBlur)
          .opacity(this.playerBgOpacity / 100)
      } else if (this.playerBgImage) {
        Image(this.playerBgImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.playerBgBlur)
          .opacity(this.playerBgOpacity / 100)
      }

      if (this.playerBgScrim > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(`rgba(0,0,0,${this.playerBgScrim / 100})`)
          .hitTestBehavior(HitTestMode.None)
      }

      // 黑胶
      Stack({ alignContent: Alignment.Center }) {
        if (this.vinylImage) {
          Image(this.vinylImage)
            .width(this.stageVinylSize())
            .height(this.stageVinylSize())
            .objectFit(ImageFit.Contain)
        } else {
          Column()
            .width(this.stageVinylSize())
            .height(this.stageVinylSize())
            .borderRadius(this.stageVinylSize() / 2)
            .backgroundColor('#111114')
            .border({ width: 1, color: 'rgba(255,255,255,0.2)' })
        }
        Column()
          .width(this.stageVinylSize() * this.coverRatio / 100)
          .height(this.stageVinylSize() * this.coverRatio / 100)
          .backgroundColor('#3a3a44')
          .borderRadius(`${this.coverRadius}%`)
          .translate({ x: this.coverX, y: this.coverY })
      }
      .width(this.stageVinylSize())
      .height(this.stageVinylSize())
      .opacity(this.vinylOpacity / 100)
      .position({
        x: this.stageW / 2 - this.stageVinylSize() / 2 + this.vinylX,
        y: this.stageH * 0.34 - this.stageVinylSize() / 2 + this.vinylY
      })

      // 用户图层
      ForEach(this.playerLayers, (layer: PlayerLayer) => {
        this.StageLayer(layer)
      }, (layer: PlayerLayer) => layer.id)

      // 顶部栏：「正在播放」
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(16)
          .fontColor([this.stageIcon()])
        Column({ space: 1 }) {
          Text('正在播放').fontSize(7).fontColor(this.stageTextDim())
          Text('网易云音乐').fontSize(9).fontColor(this.stageText())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(16)
          .fontColor([this.stageIcon()])
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8 })
      .position({ x: 0, y: 0 })
      .hitTestBehavior(HitTestMode.None)

      // 底部集群：歌名歌手 / 进度条 / 播放控制 / 四个小图标
      Column({ space: 6 }) {
        // 歌名 + 收藏/评论
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('示例歌曲名').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.stageText())
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('歌手名').fontSize(9).fontColor(this.stageTextDim())
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.heart')).fontSize(15).fontColor([this.stageIcon()])
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(14).fontColor([this.stageIcon()])
        }
        .width('100%')

        // 进度条
        Column({ space: 1 }) {
          Stack({ alignContent: Alignment.Start }) {
            Column().width('100%').height(2).borderRadius(1)
              .backgroundColor(this.stageProgressTrack())
            Column().width('38%').height(2).borderRadius(1)
              .backgroundColor(this.stageProgress())
            Column().width(7).height(7).borderRadius(4)
              .backgroundColor(this.stageProgress())
              .position({ x: '36%', y: -2.5 })
          }
          .width('100%')
          .height(8)

          Row() {
            Text('1:23').fontSize(7).fontColor(this.stageTextDim())
            Blank()
            Text('3:45').fontSize(7).fontColor(this.stageTextDim())
          }
          .width('100%')
        }
        .width('100%')

        // 播放控制
        Row() {
          SymbolGlyph($r('sys.symbol.repeat')).fontSize(13).fontColor([this.stageIcon()])
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.backward_fill')).fontSize(19).fontColor([this.stageIcon()])
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.pause_circle_fill')).fontSize(38).fontColor([this.stageControl()])
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(19).fontColor([this.stageIcon()])
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(13).fontColor([this.stageIcon()])
            .layoutWeight(1)
        }
        .width('100%')

        // 底部四个小图标
        Row() {
          SymbolGlyph($r('sys.symbol.folder_badge_plus')).fontSize(13).fontColor([this.stageSmallIcon()])
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(13).fontColor([this.stageSmallIcon()])
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.arrow_right_up_and_square')).fontSize(13).fontColor([this.stageSmallIcon()])
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.info_circle')).fontSize(13).fontColor([this.stageSmallIcon()])
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 8 })
      .position({ x: 0, y: this.stageH - 118 })
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  private PlayerStageCard() {
    Column({ space: 8 }) {
      Stack() {
        this.PlayerStage()
      }
      .width('100%')
      .aspectRatio(0.62)
      .borderRadius(16)
      .clip(true)
      .onAreaChange((_old: Area, area: Area) => {
        // onAreaChange 返回 px，position/offset 用 vp，统一换算
        this.stageW = px2vp(Number(area.width))
        this.stageH = px2vp(Number(area.height))
      })

      Text('点选图层后可拖动；滑杆可精调位置与大小')
        .fontSize(10)
        .fontColor(TC.textTertiary())
    }
    .width('100%')
  }

  @Builder
  private LayerRow(layer: PlayerLayer) {
    Row({ space: 10 }) {
      Image(layer.src)
        .width(38)
        .height(38)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .backgroundColor(TC.surfaceInset())
      Column({ space: 2 }) {
        Text(layer.id === this.selectedLayerId ? '已选中图层' : '图层')
          .fontSize(12)
          .fontColor(layer.id === this.selectedLayerId ? TC.accent() : TC.textBody())
        Text(`位置 ${Math.round(layer.x)},${Math.round(layer.y)}  大小 ${Math.round(layer.w)}%`)
          .fontSize(10)
          .fontColor(TC.textTertiary())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(15).fontColor([TC.textTertiary()])
        .onClick(() => this.moveLayerOrder(layer.id, 1))
      SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(15).fontColor([TC.textTertiary()])
        .onClick(() => this.moveLayerOrder(layer.id, -1))
      SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor([TC.textTertiary()])
        .onClick(() => this.removeLayer(layer.id))
    }
    .width('100%')
    .padding(8)
    .backgroundColor(layer.id === this.selectedLayerId ? TC.surfaceRaised() : TC.surfaceCardAlt())
    .borderRadius(12)
    .onClick(() => this.selectedLayerId = layer.id)
  }

  @Builder
  private LayerParams(layer: PlayerLayer) {
    Column({ space: 8 }) {
      DecoSlider({
        label: '左右位置', value: layer.x, min: -20, max: 120, step: 1, unit: '%',
        onChange: (v: number) => this.updateSelected((copy: PlayerLayer) => { copy.x = v })
      })
      DecoSlider({
        label: '上下位置', value: layer.y, min: -20, max: 120, step: 1, unit: '%',
        onChange: (v: number) => this.updateSelected((copy: PlayerLayer) => { copy.y = v })
      })
      DecoSlider({
        label: '宽度', value: layer.w, min: 5, max: 200, step: 1, unit: '%',
        onChange: (v: number) => this.updateSelected((copy: PlayerLayer) => { copy.w = v })
      })
      DecoSlider({
        label: '高度', value: layer.h, min: 5, max: 200, step: 1, unit: '%',
        onChange: (v: number) => this.updateSelected((copy: PlayerLayer) => { copy.h = v })
      })
      DecoSlider({
        label: '旋转', value: layer.rotation, min: -180, max: 180, step: 1, unit: '°',
        onChange: (v: number) => this.updateSelected((copy: PlayerLayer) => { copy.rotation = v })
      })
      DecoSlider({
        label: '不透明度', value: layer.opacity, min: 0, max: 100, step: 1, unit: '%',
        onChange: (v: number) => this.updateSelected((copy: PlayerLayer) => { copy.opacity = v })
      })
    }
    .width('100%')
  }

  @Builder
  private PlayerForm() {
    Column({ space: 12 }) {
      DecoCard({ title: '舞台预览', hint: '真实比例预览：背景、图层、黑胶与封面都会同步' }) {
        this.PlayerStageCard()
      }

      DecoCard({ title: '全屏背景', hint: '支持图片、GIF 与视频（视频自动循环、静音）；视频优先于图片' }) {
        DecoMediaPicker({
          label: '背景图片 / 动图', value: this.playerBgImage, mediaType: 'image',
          cropAspect: DecoRatio.SCREEN,
          onChange: (path: string) => this.playerBgImage = path
        })
        DecoMediaPicker({
          label: '背景视频', value: this.playerBgVideo, mediaType: 'video',
          onChange: (path: string) => this.playerBgVideo = path
        })
        DecoColorPicker({
          label: '背景颜色', value: this.playerBgColor,
          onChange: (v: string) => this.playerBgColor = v
        })
        DecoSlider({
          label: '背景不透明度', value: this.playerBgOpacity, min: 5, max: 100, step: 1, unit: '%',
          onChange: (v: number) => this.playerBgOpacity = v
        })
        DecoSlider({
          label: '背景模糊', value: this.playerBgBlur, min: 0, max: 60, step: 1, unit: 'vp',
          onChange: (v: number) => this.playerBgBlur = v
        })
        DecoSlider({
          label: '暗化蒙版', value: this.playerBgScrim, min: 0, max: 85, step: 1, unit: '%',
          onChange: (v: number) => this.playerBgScrim = v
        })
      }

      DecoCard({ title: '图层', hint: '像 PS 一样叠图：可加多个图层，各自位置、大小、旋转与透明度独立' }) {
        Button('添加图层（选图片 / 动图）')
          .width('100%')
          .height(42)
          .fontSize(13)
          .fontColor(TC.textPrimary())
          .backgroundColor(TC.chipBackground())
          .borderRadius(21)
          .onClick(() => this.addLayer())

        if (this.playerLayers.length === 0) {
          Text('还没有图层，添加后可以在舞台上直接拖动')
            .fontSize(11)
            .fontColor(TC.textTertiary())
        } else {
          ForEach(this.playerLayers, (layer: PlayerLayer) => {
            this.LayerRow(layer)
          }, (layer: PlayerLayer) => layer.id)

          ForEach(this.selectedLayers(), (layer: PlayerLayer) => {
            this.LayerParams(layer)
          }, (layer: PlayerLayer) => `param_${layer.id}`)
        }
      }

      DecoCard({ title: '黑胶唱片', hint: '可替换唱片底图，独立调整直径、位置与透明度' }) {
        DecoMediaPicker({
          label: '唱片底图', value: this.vinylImage, mediaType: 'image',
          cropAspect: DecoRatio.SQUARE,
          onChange: (path: string) => this.vinylImage = path
        })
        DecoSlider({
          label: '直径（0 = 自动适配）', value: this.vinylSize, min: 0, max: 400, step: 2, unit: 'vp',
          onChange: (v: number) => this.vinylSize = v
        })
        DecoSlider({
          label: '左右偏移', value: this.vinylX, min: -200, max: 200, step: 1, unit: 'vp',
          onChange: (v: number) => this.vinylX = v
        })
        DecoSlider({
          label: '上下偏移', value: this.vinylY, min: -300, max: 300, step: 1, unit: 'vp',
          onChange: (v: number) => this.vinylY = v
        })
        DecoSlider({
          label: '不透明度', value: this.vinylOpacity, min: 0, max: 100, step: 1, unit: '%',
          onChange: (v: number) => this.vinylOpacity = v
        })
      }

      DecoCard({ title: '唱片封面', hint: '封面作为独立组件：可改占比、位移与圆角（50% 为正圆）' }) {
        DecoSlider({
          label: '封面占比', value: this.coverRatio, min: 10, max: 100, step: 1, unit: '%',
          onChange: (v: number) => this.coverRatio = v
        })
        DecoSlider({
          label: '封面圆角', value: this.coverRadius, min: 0, max: 50, step: 1, unit: '%',
          onChange: (v: number) => this.coverRadius = v
        })
        DecoSlider({
          label: '左右偏移', value: this.coverX, min: -100, max: 100, step: 1, unit: 'vp',
          onChange: (v: number) => this.coverX = v
        })
        DecoSlider({
          label: '上下偏移', value: this.coverY, min: -100, max: 100, step: 1, unit: 'vp',
          onChange: (v: number) => this.coverY = v
        })
      }

      DecoCard({ title: '控件配色', hint: '留空跟随主题；压图文字默认常白，保证任何背景下都看得清' }) {
        DecoColorPicker({
          label: '控件色（播放键）', value: this.playerControlColor,
          onChange: (v: string) => this.playerControlColor = v
        })
        DecoColorPicker({
          label: '进度条色（留空跟随控件色）', value: this.playerProgressColor,
          onChange: (v: string) => this.playerProgressColor = v
        })
        DecoColorPicker({
          label: '图标色', value: this.playerIconColor,
          onChange: (v: string) => this.playerIconColor = v
        })
        DecoColorPicker({
          label: '文字色', value: this.playerTextColor,
          onChange: (v: string) => this.playerTextColor = v
        })
      }
    }
    .width('100%')
  }

  // =========================================================================
  // 视图：其它类型
  // =========================================================================

  @Builder
  private DockForm() {
    Column({ space: 12 }) {
      DecoCard({ title: '导航图标', hint: '依次对应：推荐 / 发现 / 动态 / 我的；不选则用默认图标' }) {
        DecoMediaPicker({
          label: '推荐页图标', value: this.dockIcons[0], mediaType: 'image',
          cropAspect: DecoRatio.SQUARE,
          onChange: (path: string) => this.setDockIcon(0, path)
        })
        DecoMediaPicker({
          label: '发现页图标', value: this.dockIcons[1], mediaType: 'image',
          cropAspect: DecoRatio.SQUARE,
          onChange: (path: string) => this.setDockIcon(1, path)
        })
        DecoMediaPicker({
          label: '动态页图标', value: this.dockIcons[2], mediaType: 'image',
          cropAspect: DecoRatio.SQUARE,
          onChange: (path: string) => this.setDockIcon(2, path)
        })
        DecoMediaPicker({
          label: '我的页图标', value: this.dockIcons[3], mediaType: 'image',
          cropAspect: DecoRatio.SQUARE,
          onChange: (path: string) => this.setDockIcon(3, path)
        })
      }

      DecoCard({ title: '样式' }) {
        DecoToggleRow({
          label: '显示文字', isOn: this.dockShowText,
          onChange: (v: boolean) => this.dockShowText = v
        })
        DecoSlider({
          label: '文字字号', value: this.dockTextSize, min: 8, max: 16, step: 1, unit: 'fp',
          onChange: (v: number) => this.dockTextSize = v
        })
        DecoColorPicker({
          label: '图标色', value: this.dockIconColor,
          onChange: (v: string) => this.dockIconColor = v
        })
        DecoColorPicker({
          label: '选中图标色', value: this.dockActiveColor,
          onChange: (v: string) => this.dockActiveColor = v
        })
        DecoColorPicker({
          label: '文字色', value: this.dockTextColor,
          onChange: (v: string) => this.dockTextColor = v
        })
        DecoColorPicker({
          label: '底板色', value: this.dockBgColor,
          onChange: (v: string) => this.dockBgColor = v
        })
        DecoMediaPicker({
          label: '底板背景图片（优先于底板色）', value: this.dockBgImage, mediaType: 'image',
          cropAspect: DecoRatio.WIDE,
          onChange: (path: string) => this.dockBgImage = path
        })
        if (this.dockBgImage) {
          Row({ space: 8 }) {
            Text('清除背景图').fontSize(11).fontColor(TC.accent())
              .onClick(() => this.dockBgImage = '')
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
      }

      // 效果预览
      DecoCard({ title: '效果预览' }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.dockBgImage) {
            Image(this.dockBgImage)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          }
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.dockBgImage
              ? 'rgba(0,0,0,0)'
              : (this.dockBgColor ? this.dockBgColor : TC.navBackground()))
          Row() {
            ForEach(this.dockIcons, (icon: string, index: number) => {
              Column({ space: 2 }) {
                if (icon) {
                  Image(icon).width(17).height(17).objectFit(ImageFit.Contain)
                } else {
                  SymbolGlyph(index === 0 ? $r('sys.symbol.play_circle') :
                    (index === 1 ? $r('sys.symbol.line_3_horizontal') :
                      (index === 2 ? $r('sys.symbol.camera_fill') : $r('sys.symbol.person_crop_circle_fill'))))
                    .fontSize(16)
                    .fontColor([index === 0
                      ? (this.dockActiveColor ? this.dockActiveColor : TC.textOnAccent())
                      : (this.dockIconColor ? this.dockIconColor : TC.textTertiary())])
                }
                if (this.dockShowText) {
                  Text(index === 0 ? '推荐' : (index === 1 ? '发现' : (index === 2 ? '动态' : '我的')))
                    .fontSize(this.dockTextSize)
                    .fontColor(index === 0
                      ? (this.dockTextColor ? this.dockTextColor : TC.textPrimary())
                      : (this.dockIconColor ? this.dockIconColor : TC.textTertiary()))
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)
            }, (icon: string, index: number) => `${index}_${icon}`)
          }
          .width('100%')
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .height(56)
        .borderRadius(14)
        .clip(true)
      }
    }
    .width('100%')
  }

  private setDockIcon(index: number, path: string): void {
    const next = this.dockIcons.slice()
    next[index] = path
    this.dockIcons = next
  }

  @Builder
  private SidebarForm() {
    Column({ space: 12 }) {
      DecoCard({ title: '侧边栏背景', hint: '背景图会铺在侧边栏整块区域，模糊与不透明度可调' }) {
        DecoMediaPicker({
          label: '背景图片 / 动图', value: this.sideBgImage, mediaType: 'image',
          cropAspect: DecoRatio.PORTRAIT,
          onChange: (path: string) => this.sideBgImage = path
        })
        DecoSlider({
          label: '模糊', value: this.sideBgBlur, min: 0, max: 40, step: 1, unit: 'vp',
          onChange: (v: number) => this.sideBgBlur = v
        })
        DecoSlider({
          label: '不透明度', value: this.sideBgOpacity, min: 5, max: 100, step: 1, unit: '%',
          onChange: (v: number) => this.sideBgOpacity = v
        })
        DecoColorPicker({
          label: '底色', value: this.sideBgColor,
          onChange: (v: string) => this.sideBgColor = v
        })
      }

      DecoCard({ title: '文字与图标' }) {
        DecoSlider({
          label: '文字字号', value: this.sideTextSize, min: 12, max: 22, step: 1, unit: 'fp',
          onChange: (v: number) => this.sideTextSize = v
        })
        DecoColorPicker({
          label: '文字颜色', value: this.sideTextColor,
          onChange: (v: string) => this.sideTextColor = v
        })
        DecoColorPicker({
          label: '图标颜色', value: this.sideIconColor,
          onChange: (v: string) => this.sideIconColor = v
        })
      }
    }
    .width('100%')
  }

  @Builder
  private HomeBgForm() {
    DecoCard({ title: '个人主页背景', hint: '只影响我的页顶部头图区域；可与头像框、等级贴图叠加' }) {
      DecoMediaPicker({
        label: '头图', value: this.homeImage, mediaType: 'image',
        cropAspect: DecoRatio.PORTRAIT,
        onChange: (path: string) => this.homeImage = path
      })
      DecoSlider({
        label: '模糊', value: this.homeBlur, min: 0, max: 48, step: 1, unit: 'vp',
        onChange: (v: number) => this.homeBlur = v
      })
      DecoSlider({
        label: '不透明度', value: this.homeOpacity, min: 5, max: 100, step: 1, unit: '%',
        onChange: (v: number) => this.homeOpacity = v
      })
      DecoSlider({
        label: '向下渐隐', value: this.homeFade, min: 0, max: 100, step: 1, unit: '%',
        onChange: (v: number) => this.homeFade = v
      })
    }
  }

  @Builder
  private HeartForm() {
    DecoCard({ title: '红心特效', hint: '点赞时从红心处上飘后回落渐隐' }) {
      DecoColorPicker({
        label: '红心颜色', value: this.heartColor,
        onChange: (v: string) => this.heartColor = v
      })
      DecoSlider({
        label: '每次数量', value: this.heartCount, min: 1, max: 20, step: 1, unit: '个',
        onChange: (v: number) => this.heartCount = v
      })
      DecoSlider({
        label: '红心大小', value: this.heartSize, min: 10, max: 40, step: 1, unit: 'vp',
        onChange: (v: number) => this.heartSize = v
      })
      DecoSlider({
        label: '动画时长', value: this.heartDuration, min: 600, max: 3000, step: 100, unit: 'ms',
        onChange: (v: number) => this.heartDuration = v
      })
    }
  }

  @Builder
  private StartupForm() {
    DecoCard({ title: '启动资源', hint: '冷启动时全屏展示，到时或播完自动进入首页' }) {
      Row({ space: 8 }) {
        Button('图片')
          .fontSize(12)
          .fontColor(this.startupType === 'image' ? TC.textOnAccent() : TC.textBody())
          .backgroundColor(this.startupType === 'image' ? TC.accent() : TC.chipBackground())
          .height(32)
          .borderRadius(16)
          .onClick(() => {
            this.startupType = 'image'
            this.startupMedia = ''
          })
        Button('视频')
          .fontSize(12)
          .fontColor(this.startupType === 'video' ? TC.textOnAccent() : TC.textBody())
          .backgroundColor(this.startupType === 'video' ? TC.accent() : TC.chipBackground())
          .height(32)
          .borderRadius(16)
          .onClick(() => {
            this.startupType = 'video'
            this.startupMedia = ''
          })
        Blank()
      }
      .width('100%')

      DecoMediaPicker({
        label: this.startupType === 'video' ? '启动视频' : '启动图片',
        value: this.startupMedia,
        mediaType: this.startupType,
        cropAspect: DecoRatio.SCREEN,
        onChange: (path: string) => this.startupMedia = path
      })
      DecoSlider({
        label: '展示时长', value: this.startupDuration, min: 1000, max: 8000, step: 250, unit: 'ms',
        onChange: (v: number) => this.startupDuration = v
      })
      DecoToggleRow({
        label: '显示右下角跳过', isOn: this.startupSkip,
        onChange: (v: boolean) => this.startupSkip = v
      })
    }
  }

  @Builder
  private SingleImageForm() {
    DecoCard({
      title: DecoKind.title(this.kind),
      hint: this.kind === DecoKind.AVATAR_FRAME
        ? '建议正方形 PNG，中心镂空处会正对头像'
        : (this.kind === DecoKind.VIP_CARD
          ? '建议 3:1 横图，会铺满侧边栏会员卡区域'
          : '桌面图标样式需要系统支持，部分设备可能不生效')
    }) {
      DecoMediaPicker({
        label: this.kind === DecoKind.AVATAR_FRAME ? '头像框' : (this.kind === DecoKind.VIP_CARD ? '会员卡底图' : '应用图标'),
        value: this.singleImage,
        mediaType: 'image',
        cropAspect: this.kind === DecoKind.VIP_CARD ? DecoRatio.CARD : DecoRatio.SQUARE,
        onChange: (path: string) => this.singleImage = path
      })
      if (this.singleImage) {
        Image(this.singleImage)
          .width('100%')
          .height(120)
          .objectFit(ImageFit.Contain)
          .backgroundColor(TC.surfaceInset())
          .borderRadius(14)
      }
    }
  }

  @Builder
  private BadgeForm() {
    Column({ space: 12 }) {
      DecoCard({ title: 'VIP 等级贴图', hint: '按等级逐级上传，我的页与侧边栏会显示当前等级对应的贴图' }) {
        ForEach([1, 2, 3, 4, 5, 6, 7], (level: number) => {
          DecoMediaPicker({
            label: `Lv.${level} 贴图`,
            value: level <= this.badgeImages.length ? this.badgeImages[level - 1] : '',
            mediaType: 'image',
            cropAspect: DecoRatio.SQUARE,
            onChange: (path: string) => this.setBadge(level - 1, path)
          })
        }, (level: number) => `badge_${level}`)
      }
    }
    .width('100%')
  }

  private setBadge(index: number, path: string): void {
    const next = this.badgeImages.slice()
    next[index] = path
    this.badgeImages = next
  }

  @Builder
  private SuitForm() {
    Column({ space: 12 }) {
      DecoCard({ title: '套装内容', hint: '每类挑一件，点「应用套装」一次性替换全部生效装扮' }) {
        ForEach(DecoKind.pickable(), (kind: string, index: number) => {
          Row({ space: 10 }) {
            Text(DecoKind.title(kind))
              .fontSize(13)
              .fontColor(TC.textBody())
              .width(96)
            Select(this.suitOptions(kind))
              .selected(this.suitIndex(kind))
              .value(this.suitLabel(kind))
              .font({ size: 12 })
              .fontColor(TC.textPrimary())
              .optionFont({ size: 12 })
              .selectedOptionFont({ size: 12 })
              .backgroundColor(TC.surfaceInset())
              .layoutWeight(1)
              .onSelect((selected: number) => {
                const list = DecorationStore.list(kind)
                const picked = selected > 0 && selected - 1 < list.length ? list[selected - 1].id : ''
                const next = this.suitPick.slice()
                next[index] = picked
                this.suitPick = next
              })
          }
          .width('100%')
        }, (kind: string) => `suit_${kind}`)
      }
    }
    .width('100%')
  }

  private suitOptions(kind: string): SelectOption[] {
    const options: SelectOption[] = [{ value: '不使用' }]
    for (const item of DecorationStore.list(kind)) {
      options.push({ value: item.name })
    }
    return options
  }

  private suitIndex(kind: string): number {
    const kinds = DecoKind.pickable()
    let index = -1
    for (let i = 0; i < kinds.length; i++) {
      if (kinds[i] === kind) { index = i }
    }
    if (index < 0) { return 0 }
    const picked = index < this.suitPick.length ? this.suitPick[index] : ''
    if (!picked) { return 0 }
    const list = DecorationStore.list(kind)
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === picked) { return i + 1 }
    }
    return 0
  }

  private suitLabel(kind: string): string {
    const picked = this.suitIndex(kind)
    if (picked === 0) { return '不使用' }
    const list = DecorationStore.list(kind)
    return picked - 1 < list.length ? list[picked - 1].name : '不使用'
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)

        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text(DecoKind.title(this.kind))
            .layoutWeight(1)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary())
            .textAlign(TextAlign.Center)
          Text('保存')
            .fontSize(13)
            .fontColor(TC.accent())
            .onClick(() => this.save(false))
        }
        .height(56)
        .constraintSize({ minHeight: 56 })
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 12 }) {
            this.ItemChips()
            this.NameField()

            if (this.kind === DecoKind.SKIN) {
              this.SkinForm()
            } else if (this.kind === DecoKind.PLAYER) {
              this.PlayerForm()
            } else if (this.kind === DecoKind.DOCK) {
              this.DockForm()
            } else if (this.kind === DecoKind.SIDEBAR) {
              this.SidebarForm()
            } else if (this.kind === DecoKind.HOME_BG) {
              this.HomeBgForm()
            } else if (this.kind === DecoKind.HEART) {
              this.HeartForm()
            } else if (this.kind === DecoKind.STARTUP) {
              this.StartupForm()
            } else if (this.kind === DecoKind.VIP_BADGE) {
              this.BadgeForm()
            } else if (this.kind === DecoKind.SUIT) {
              this.SuitForm()
            } else {
              this.SingleImageForm()
            }

            this.ActionBar()
            Text('装扮只保存在本机；卸载应用或清除数据后会丢失。')
              .fontSize(10)
              .fontColor(TC.textQuaternary())
              .padding({ bottom: 26 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
