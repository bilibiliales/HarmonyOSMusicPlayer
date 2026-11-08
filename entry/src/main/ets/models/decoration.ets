/**
 * 装扮中心数据模型。
 *
 * 设计原则：
 *  - 每一类装扮都是「配置对象 + 序列化 JSON」，存本地，不依赖任何接口；
 *  - 配置类全部字段带默认值，`from(raw)` 做一次显式合并，避免旧数据缺字段；
 *  - 运行时不直接读这里，统一由 DecorationRuntime 解释成 AppStorage / SkinService；
 *  - 新增一类装扮只需：加一个 Config 类 + 在 DecoKind.META 里加一行 + 在编辑器里加一段 UI。
 */

/** 装扮类型（12 类）。 */
export class DecoKind {
  static readonly SKIN: string = 'skin'
  static readonly PLAYER: string = 'player'
  static readonly DOCK: string = 'dock'
  static readonly SIDEBAR: string = 'sidebar'
  static readonly HOME_BG: string = 'home_bg'
  static readonly HEART: string = 'heart'
  static readonly STARTUP: string = 'startup'
  static readonly AVATAR_FRAME: string = 'avatar_frame'
  static readonly VIP_CARD: string = 'vip_card'
  static readonly APP_ICON: string = 'app_icon'
  static readonly VIP_BADGE: string = 'vip_badge'
  static readonly SUIT: string = 'suit'

  static title(kind: string): string {
    if (kind === DecoKind.SKIN) { return '自定义皮肤' }
    if (kind === DecoKind.PLAYER) { return '播放器样式' }
    if (kind === DecoKind.DOCK) { return '底部导航' }
    if (kind === DecoKind.SIDEBAR) { return '侧边栏' }
    if (kind === DecoKind.HOME_BG) { return '个人主页背景' }
    if (kind === DecoKind.HEART) { return '红心特效' }
    if (kind === DecoKind.STARTUP) { return '启动资源' }
    if (kind === DecoKind.AVATAR_FRAME) { return '头像框' }
    if (kind === DecoKind.VIP_CARD) { return '会员身份卡' }
    if (kind === DecoKind.APP_ICON) { return '应用图标' }
    if (kind === DecoKind.VIP_BADGE) { return 'VIP 等级贴图' }
    if (kind === DecoKind.SUIT) { return '套装' }
    return kind
  }

  static desc(kind: string): string {
    if (kind === DecoKind.SKIN) { return '页面背景图、背景色、强调色与字体色' }
    if (kind === DecoKind.PLAYER) { return '全屏背景、自由图层、黑胶与封面' }
    if (kind === DecoKind.DOCK) { return '底部图标、文字与底板' }
    if (kind === DecoKind.SIDEBAR) { return '侧边栏背景图与文字样式' }
    if (kind === DecoKind.HOME_BG) { return '个人主页头图与模糊度' }
    if (kind === DecoKind.HEART) { return '点赞时上飘的红心颜色与数量' }
    if (kind === DecoKind.STARTUP) { return '冷启动图片或视频，可跳过' }
    if (kind === DecoKind.AVATAR_FRAME) { return '个人主页头像外框' }
    if (kind === DecoKind.VIP_CARD) { return '侧边栏会员卡底板' }
    if (kind === DecoKind.APP_ICON) { return '桌面图标样式（需应用市场支持）' }
    if (kind === DecoKind.VIP_BADGE) { return '逐级上传的等级贴图' }
    if (kind === DecoKind.SUIT) { return '一键切换整套装扮' }
    return ''
  }

  static icon(kind: string): Resource {
    if (kind === DecoKind.SKIN) { return $r('sys.symbol.square_and_pencil') }
    if (kind === DecoKind.PLAYER) { return $r('sys.symbol.play_circle_fill') }
    if (kind === DecoKind.DOCK) { return $r('sys.symbol.square_grid_2x2') }
    if (kind === DecoKind.SIDEBAR) { return $r('sys.symbol.line_3_horizontal') }
    if (kind === DecoKind.HOME_BG) { return $r('sys.symbol.camera_fill') }
    if (kind === DecoKind.HEART) { return $r('sys.symbol.heart_fill') }
    if (kind === DecoKind.STARTUP) { return $r('sys.symbol.play_circle') }
    if (kind === DecoKind.AVATAR_FRAME) { return $r('sys.symbol.person_crop_circle_fill') }
    if (kind === DecoKind.VIP_CARD) { return $r('sys.symbol.bookmark_fill') }
    if (kind === DecoKind.APP_ICON) { return $r('sys.symbol.square_grid_2x2') }
    if (kind === DecoKind.VIP_BADGE) { return $r('sys.symbol.checkmark_circle_fill') }
    return $r('sys.symbol.wand_and_stars')
  }

  /** 有「我的装扮」条目可选的类型（套装单独管理）。 */
  static pickable(): string[] {
    return [
      DecoKind.SKIN, DecoKind.PLAYER, DecoKind.DOCK, DecoKind.SIDEBAR, DecoKind.HOME_BG,
      DecoKind.HEART, DecoKind.STARTUP, DecoKind.AVATAR_FRAME, DecoKind.VIP_CARD,
      DecoKind.APP_ICON, DecoKind.VIP_BADGE
    ]
  }
}

/** 一条装扮记录。 */
export class DecorationItem {
  id: string = ''
  kind: string = ''
  name: string = ''
  /** 列表/我的装扮里的预览图（可为空）。 */
  cover: string = ''
  /** 各类配置的 JSON。 */
  payload: string = ''
  updatedAt: number = 0
}

/** 套装成员：指向某一类里的某个具体装扮。 */
export class DecoMember {
  kind: string = ''
  id: string = ''
}

// ---------------------------------------------------------------------------
// 1. 自定义皮肤
// ---------------------------------------------------------------------------

export class SkinConfig {
  /** 全局页面背景图（动图/GIF 也可，Image 支持）。 */
  bgImage: string = ''
  /** 背景图不透明度 0-100。 */
  bgOpacity: number = 100
  /** 背景图模糊半径（vp）。 */
  bgBlur: number = 0
  /** 页面背景色；为空表示跟随深浅色主题。 */
  pageColor: string = ''
  /** 主题色（按钮、选中、进度等主色）；为空跟随主题。 */
  themeColor: string = ''
  /** 强调色（次级高亮、弱化强调）；为空跟随主题。 */
  accentColor: string = ''
  /** 字体色（主/正文）；为空按背景亮度自动推导。 */
  textColor: string = ''
  /** 背景图上的暗化/亮化蒙版强度 0-100，保证文字可读。 */
  scrim: number = 38

  static from(raw: string): SkinConfig {
    const out = new SkinConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as SkinConfig
      out.bgImage = src.bgImage ?? ''
      out.bgOpacity = src.bgOpacity ?? 100
      out.bgBlur = src.bgBlur ?? 0
      out.pageColor = src.pageColor ?? ''
      out.themeColor = src.themeColor ?? ''
      out.accentColor = src.accentColor ?? ''
      out.textColor = src.textColor ?? ''
      out.scrim = src.scrim ?? 38
    } catch (_error) {
      return new SkinConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 2. 播放器样式
// ---------------------------------------------------------------------------

/** 播放页上的一个自由图层（相对舞台的百分比坐标，适配任意屏幕）。 */
export class PlayerLayer {
  id: string = ''
  /** 图片/GIF 本地路径。 */
  src: string = ''
  /** 左上角 x，百分比 0-100。 */
  x: number = 0
  /** 左上角 y，百分比 0-100。 */
  y: number = 0
  /** 宽度，百分比 0-200（按舞台宽度）。 */
  w: number = 30
  /** 高度，百分比 0-200（按舞台宽度，保证等比）。 */
  h: number = 30
  /** 旋转角度。 */
  rotation: number = 0
  /** 不透明度 0-100。 */
  opacity: number = 100
}

export class PlayerStyleConfig {
  /** 全屏背景：图片或 GIF。 */
  bgImage: string = ''
  /** 全屏背景：视频（循环、静音）。bgVideo 优先于 bgImage。 */
  bgVideo: string = ''
  /** 背景色（无背景媒体时铺满；有媒体时垫在下面）。空=跟随主题。 */
  bgColor: string = ''
  /** 背景媒体不透明度 0-100。 */
  bgOpacity: number = 100
  /** 背景媒体模糊半径（vp）。 */
  bgBlur: number = 0
  /** 背景暗化蒙版 0-100，保证控件可读。 */
  bgScrim: number = 45
  /** 自由图层（从下到上）。 */
  layers: PlayerLayer[] = []
  /** 黑胶底图；空=默认唱片。 */
  vinylImage: string = ''
  /** 黑胶直径（vp）；0 = 按屏幕自动适配。 */
  vinylSize: number = 0
  /** 黑胶相对舞台中心的偏移（vp）。 */
  vinylX: number = 0
  vinylY: number = 0
  /** 黑胶不透明度 0-100。 */
  vinylOpacity: number = 100
  /** 唱片封面相对黑胶的比例 0-100（默认 63）。 */
  coverRatio: number = 63
  /** 封面中心相对黑胶中心的偏移（vp）。 */
  coverX: number = 0
  coverY: number = 0
  /** 封面圆角百分比 0-50（50=圆形）。 */
  coverRadius: number = 50
  /** 控件颜色（进度条、播放按钮等）；空=跟随主题。 */
  controlColor: string = ''
  /** 图标颜色；空=跟随主题。 */
  iconColor: string = ''
  /** 文字颜色；空=跟随主题。 */
  textColor: string = ''

  static from(raw: string): PlayerStyleConfig {
    const out = new PlayerStyleConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as PlayerStyleConfig
      out.bgImage = src.bgImage ?? ''
      out.bgVideo = src.bgVideo ?? ''
      out.bgColor = src.bgColor ?? ''
      out.bgOpacity = src.bgOpacity ?? 100
      out.bgBlur = src.bgBlur ?? 0
      out.bgScrim = src.bgScrim ?? 45
      out.layers = DecorationCodec.parseLayers(src.layers)
      out.vinylImage = src.vinylImage ?? ''
      out.vinylSize = src.vinylSize ?? 0
      out.vinylX = src.vinylX ?? 0
      out.vinylY = src.vinylY ?? 0
      out.vinylOpacity = src.vinylOpacity ?? 100
      out.coverRatio = src.coverRatio ?? 63
      out.coverX = src.coverX ?? 0
      out.coverY = src.coverY ?? 0
      out.coverRadius = src.coverRadius ?? 50
      out.controlColor = src.controlColor ?? ''
      out.iconColor = src.iconColor ?? ''
      out.textColor = src.textColor ?? ''
    } catch (_error) {
      return new PlayerStyleConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 3. 底部导航
// ---------------------------------------------------------------------------

export class DockConfig {
  /** 四个页签的自定义图标（本地路径），空串=默认图标。顺序：推荐/发现/动态/我的。 */
  icons: string[] = ['', '', '', '']
  iconColor: string = ''
  activeColor: string = ''
  textColor: string = ''
  textSize: number = 10
  /** 底板颜色；空=跟随主题。 */
  bgColor: string = ''
  /** 选中指示块颜色；空=主题色。 */
  indicatorColor: string = ''
  /** 是否显示文字。 */
  showText: boolean = true

  static from(raw: string): DockConfig {
    const out = new DockConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as DockConfig
      const icons: string[] = src.icons ?? []
      out.icons = ['', '', '', '']
      for (let i = 0; i < 4; i++) {
        out.icons[i] = i < icons.length ? (icons[i] ?? '') : ''
      }
      out.iconColor = src.iconColor ?? ''
      out.activeColor = src.activeColor ?? ''
      out.textColor = src.textColor ?? ''
      out.textSize = src.textSize ?? 10
      out.bgColor = src.bgColor ?? ''
      out.indicatorColor = src.indicatorColor ?? ''
      out.showText = src.showText ?? true
    } catch (_error) {
      return new DockConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 4. 侧边栏
// ---------------------------------------------------------------------------

export class SidebarConfig {
  bgImage: string = ''
  bgOpacity: number = 100
  bgBlur: number = 0
  /** 侧边栏底色；空=跟随主题。 */
  bgColor: string = ''
  textColor: string = ''
  textSize: number = 16
  iconColor: string = ''

  static from(raw: string): SidebarConfig {
    const out = new SidebarConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as SidebarConfig
      out.bgImage = src.bgImage ?? ''
      out.bgOpacity = src.bgOpacity ?? 100
      out.bgBlur = src.bgBlur ?? 0
      out.bgColor = src.bgColor ?? ''
      out.textColor = src.textColor ?? ''
      out.textSize = src.textSize ?? 16
      out.iconColor = src.iconColor ?? ''
    } catch (_error) {
      return new SidebarConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 5. 个人主页背景
// ---------------------------------------------------------------------------

export class HomeBgConfig {
  image: string = ''
  blur: number = 0
  opacity: number = 100
  /** 顶部到底部的过渡强度 0-100（0=不压暗，100=完全压成页面底色）。 */
  fade: number = 100

  static from(raw: string): HomeBgConfig {
    const out = new HomeBgConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as HomeBgConfig
      out.image = src.image ?? ''
      out.blur = src.blur ?? 0
      out.opacity = src.opacity ?? 100
      out.fade = src.fade ?? 100
    } catch (_error) {
      return new HomeBgConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 6. 红心特效
// ---------------------------------------------------------------------------

export class HeartConfig {
  color: string = '#ef233c'
  /** 每次点赞喷出的红心数量 1-20。 */
  count: number = 7
  /** 单个红心字号。 */
  size: number = 22
  /** 动画时长（毫秒）。 */
  duration: number = 1200

  static from(raw: string): HeartConfig {
    const out = new HeartConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as HeartConfig
      out.color = src.color ?? '#ef233c'
      out.count = src.count ?? 7
      out.size = src.size ?? 22
      out.duration = src.duration ?? 1200
    } catch (_error) {
      return new HeartConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 7. 启动资源
// ---------------------------------------------------------------------------

export class StartupConfig {
  /** 图片或视频路径。 */
  media: string = ''
  /** image | video */
  type: string = 'image'
  /** 展示时长（毫秒），视频到时长或播完即止。 */
  duration: number = 3000
  /** 是否显示右下角跳过。 */
  allowSkip: boolean = true

  static from(raw: string): StartupConfig {
    const out = new StartupConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as StartupConfig
      out.media = src.media ?? ''
      out.type = src.type ?? 'image'
      out.duration = src.duration ?? 3000
      out.allowSkip = src.allowSkip ?? true
    } catch (_error) {
      return new StartupConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 8. 头像框 / 9. 会员卡 / 10. 应用图标
// ---------------------------------------------------------------------------

export class ImageOnlyConfig {
  image: string = ''

  static from(raw: string): ImageOnlyConfig {
    const out = new ImageOnlyConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as ImageOnlyConfig
      out.image = src.image ?? ''
    } catch (_error) {
      return new ImageOnlyConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 11. VIP 等级贴图（1-7 级逐级上传）
// ---------------------------------------------------------------------------

export class VipBadgeConfig {
  /** 下标 0 对应 1 级，依此类推。 */
  images: string[] = ['', '', '', '', '', '', '']

  static from(raw: string): VipBadgeConfig {
    const out = new VipBadgeConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as VipBadgeConfig
      const images: string[] = src.images ?? []
      out.images = ['', '', '', '', '', '', '']
      for (let i = 0; i < 7; i++) {
        out.images[i] = i < images.length ? (images[i] ?? '') : ''
      }
    } catch (_error) {
      return new VipBadgeConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 12. 套装
// ---------------------------------------------------------------------------

export class SuitConfig {
  members: DecoMember[] = []

  static from(raw: string): SuitConfig {
    const out = new SuitConfig()
    if (!raw) { return out }
    try {
      const src = JSON.parse(raw) as SuitConfig
      const members: DecoMember[] = src.members ?? []
      out.members = []
      for (const member of members) {
        if (!member.kind || !member.id) { continue }
        const copy = new DecoMember()
        copy.kind = member.kind
        copy.id = member.id
        out.members.push(copy)
      }
    } catch (_error) {
      return new SuitConfig()
    }
    return out
  }
}

// ---------------------------------------------------------------------------
// 序列化辅助
// ---------------------------------------------------------------------------

export class DecorationCodec {
  static parseLayers(raw: PlayerLayer[] | null | undefined): PlayerLayer[] {
    const out: PlayerLayer[] = []
    if (!raw) { return out }
    for (const src of raw) {
      if (!src || !src.src) { continue }
      const layer = new PlayerLayer()
      layer.id = src.id ?? ''
      layer.src = src.src ?? ''
      layer.x = src.x ?? 0
      layer.y = src.y ?? 0
      layer.w = src.w ?? 30
      layer.h = src.h ?? 30
      layer.rotation = src.rotation ?? 0
      layer.opacity = src.opacity ?? 100
      out.push(layer)
    }
    return out
  }

  static encode(value: Object): string {
    try {
      return JSON.stringify(value)
    } catch (_error) {
      return ''
    }
  }

  /** 每个配置类的空实例（用于「新增」时初始化）。 */
  static blank(kind: string): string {
    if (kind === DecoKind.SKIN) { return DecorationCodec.encode(new SkinConfig()) }
    if (kind === DecoKind.PLAYER) { return DecorationCodec.encode(new PlayerStyleConfig()) }
    if (kind === DecoKind.DOCK) { return DecorationCodec.encode(new DockConfig()) }
    if (kind === DecoKind.SIDEBAR) { return DecorationCodec.encode(new SidebarConfig()) }
    if (kind === DecoKind.HOME_BG) { return DecorationCodec.encode(new HomeBgConfig()) }
    if (kind === DecoKind.HEART) { return DecorationCodec.encode(new HeartConfig()) }
    if (kind === DecoKind.STARTUP) { return DecorationCodec.encode(new StartupConfig()) }
    if (kind === DecoKind.AVATAR_FRAME) { return DecorationCodec.encode(new ImageOnlyConfig()) }
    if (kind === DecoKind.VIP_CARD) { return DecorationCodec.encode(new ImageOnlyConfig()) }
    if (kind === DecoKind.APP_ICON) { return DecorationCodec.encode(new ImageOnlyConfig()) }
    if (kind === DecoKind.VIP_BADGE) { return DecorationCodec.encode(new VipBadgeConfig()) }
    if (kind === DecoKind.SUIT) { return DecorationCodec.encode(new SuitConfig()) }
    return '{}'
  }

  /** 装扮卡片预览图：优先用户上传的 cover，其次在配置里找一张图。 */
  static previewImage(item: DecorationItem): string {
    if (item.cover) { return item.cover }
    if (item.kind === DecoKind.SKIN) { return SkinConfig.from(item.payload).bgImage }
    if (item.kind === DecoKind.PLAYER) {
      const cfg = PlayerStyleConfig.from(item.payload)
      if (cfg.bgImage) { return cfg.bgImage }
      if (cfg.layers.length > 0) { return cfg.layers[0].src }
      return cfg.vinylImage
    }
    if (item.kind === DecoKind.SIDEBAR) { return SidebarConfig.from(item.payload).bgImage }
    if (item.kind === DecoKind.HOME_BG) { return HomeBgConfig.from(item.payload).image }
    if (item.kind === DecoKind.STARTUP) { return StartupConfig.from(item.payload).media }
    if (item.kind === DecoKind.AVATAR_FRAME || item.kind === DecoKind.VIP_CARD ||
      item.kind === DecoKind.APP_ICON) {
      return ImageOnlyConfig.from(item.payload).image
    }
    if (item.kind === DecoKind.DOCK) { return DockConfig.from(item.payload).icons[0] ?? '' }
    if (item.kind === DecoKind.VIP_BADGE) {
      const images = VipBadgeConfig.from(item.payload).images
      for (const image of images) {
        if (image) { return image }
      }
    }
    return ''
  }
}
