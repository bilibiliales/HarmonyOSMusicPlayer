import { SkinService } from './SkinService'
import { ThemeService } from './ThemeService'
import { DecoColor } from './DecorationColor'
import { DecorationStore } from './DecorationStore'
import {
  DecoKind,
  DockConfig,
  HeartConfig,
  HomeBgConfig,
  ImageOnlyConfig,
  PlayerStyleConfig,
  SidebarConfig,
  SkinConfig,
  StartupConfig,
  VipBadgeConfig
} from '../models/decoration'

/** 装扮运行时发布到 AppStorage 的键（组件用 @StorageProp 订阅）。 */
export class DecoKeys {
  // 皮肤 / 全局背景
  static readonly SKIN_BG: string = 'decoSkinBg'
  static readonly SKIN_BG_OPACITY: string = 'decoSkinBgOpacity'
  static readonly SKIN_BG_BLUR: string = 'decoSkinBgBlur'
  static readonly SKIN_BG_COLOR: string = 'decoSkinBgColor'
  static readonly SKIN_SCRIM: string = 'decoSkinScrim'
  // 底部导航
  static readonly DOCK_ICONS: string = 'decoDockIcons'
  static readonly DOCK_ICON_COLOR: string = 'decoDockIconColor'
  static readonly DOCK_ACTIVE_COLOR: string = 'decoDockActiveColor'
  static readonly DOCK_TEXT_COLOR: string = 'decoDockTextColor'
  static readonly DOCK_TEXT_SIZE: string = 'decoDockTextSize'
  static readonly DOCK_BG: string = 'decoDockBg'
  static readonly DOCK_BG_IMAGE: string = 'decoDockBgImage'
  static readonly DOCK_INDICATOR: string = 'decoDockIndicator'
  static readonly DOCK_SHOW_TEXT: string = 'decoDockShowText'
  // 侧边栏
  static readonly SIDEBAR_BG: string = 'decoSidebarBg'
  static readonly SIDEBAR_BG_OPACITY: string = 'decoSidebarBgOpacity'
  static readonly SIDEBAR_BG_BLUR: string = 'decoSidebarBgBlur'
  static readonly SIDEBAR_BG_COLOR: string = 'decoSidebarBgColor'
  static readonly SIDEBAR_TEXT_COLOR: string = 'decoSidebarTextColor'
  static readonly SIDEBAR_TEXT_SIZE: string = 'decoSidebarTextSize'
  static readonly SIDEBAR_ICON_COLOR: string = 'decoSidebarIconColor'
  // 个人主页背景
  static readonly HOME_BG: string = 'decoHomeBg'
  static readonly HOME_BG_BLUR: string = 'decoHomeBgBlur'
  static readonly HOME_BG_OPACITY: string = 'decoHomeBgOpacity'
  static readonly HOME_BG_FADE: string = 'decoHomeBgFade'
  // 红心 / 启动 / 头像框 / 会员卡 / 等级贴图
  static readonly HEART_COLOR: string = 'decoHeartColor'
  static readonly HEART_COUNT: string = 'decoHeartCount'
  static readonly HEART_SIZE: string = 'decoHeartSize'
  static readonly HEART_DURATION: string = 'decoHeartDuration'
  static readonly STARTUP_MEDIA: string = 'decoStartupMedia'
  static readonly STARTUP_TYPE: string = 'decoStartupType'
  static readonly STARTUP_DURATION: string = 'decoStartupDuration'
  static readonly STARTUP_SKIP: string = 'decoStartupSkip'
  static readonly AVATAR_FRAME: string = 'decoAvatarFrame'
  static readonly VIP_CARD: string = 'decoVipCard'
  static readonly VIP_BADGES: string = 'decoVipBadges'
  static readonly APP_ICON: string = 'decoAppIcon'
  // 播放器样式
  static readonly PLAYER_STYLE: string = 'decoPlayerStyle'
  static readonly PLAYER_VERSION: string = 'decoPlayerVersion'
}

/**
 * 装扮运行时 —— 把「当前生效表」翻译成界面真正消费的东西：
 *   · 颜色 → SkinService 覆盖表（TC 取色时最高优先，深浅色切换不再影响该色）；
 *   · 图片/尺寸/开关 → AppStorage 键（组件 @StorageProp 订阅）；
 *   · 播放器样式 → 一段 JSON + 递增版本号（Play 页解析成结构体使用）。
 *
 * 所有入口都是 applyAll()：幂等、无副作用顺序要求，切换/取消/删除都走它。
 */
export class DecorationRuntime {
  static applyAll(): void {
    DecorationRuntime.applySkin()
    DecorationRuntime.applyDock()
    DecorationRuntime.applySidebar()
    DecorationRuntime.applyHomeBg()
    DecorationRuntime.applySimple()
    DecorationRuntime.applyPlayerStyle()
    AppStorage.setOrCreate<number>('decorationActiveCount', DecorationStore.activeCount())
  }

  // -------------------------------------------------------------------------
  // 皮肤：颜色 + 全局背景图
  // -------------------------------------------------------------------------

  private static applySkin(): void {
    const raw = DecorationStore.payload(DecoKind.SKIN)
    const cfg = raw ? SkinConfig.from(raw) : undefined
    const map = new Map<string, string>()
    if (cfg) {
      const dark: boolean = ThemeService.isDark()
      const baseColor: string = cfg.pageColor ? cfg.pageColor : (dark ? '#121215' : '#f4f4f7')
      const baseDark: boolean = cfg.pageColor ? DecoColor.isDark(cfg.pageColor) : dark
      const hasImage: boolean = cfg.bgImage.length > 0

      // 背景图模式下页面底色透明，露出 Index 里的全局背景层
      if (hasImage) {
        map.set('page_background', '#00000000')
        map.set('nav_background', '#00000000')
      } else if (cfg.pageColor) {
        map.set('page_background', cfg.pageColor)
        map.set('nav_background', cfg.pageColor)
      }

      // 背景一旦被用户接管，卡片/输入框/胶囊都改成半透明层，避免整块死白/死黑
      if (hasImage || cfg.pageColor) {
        map.set('surface_card', baseDark ? 'rgba(38,38,45,0.88)' : 'rgba(255,255,255,0.9)')
        map.set('surface_card_alt', baseDark ? 'rgba(46,46,54,0.88)' : 'rgba(251,251,253,0.9)')
        map.set('surface_inset', baseDark ? 'rgba(255,255,255,0.09)' : 'rgba(0,0,0,0.05)')
        map.set('surface_raised', baseDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.09)')
        map.set('chip_background', baseDark ? 'rgba(255,255,255,0.13)' : 'rgba(0,0,0,0.06)')
        map.set('sheet_background', baseDark ? 'rgba(27,27,32,0.96)' : 'rgba(255,255,255,0.97)')
        map.set('divider', baseDark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.08)')
        map.set('border_subtle', baseDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.07)')
      }

      if (cfg.textColor) {
        map.set('text_primary', cfg.textColor)
        map.set('text_body', cfg.textColor)
        map.set('text_secondary', DecoColor.alpha(cfg.textColor, 0.66))
        map.set('text_tertiary', DecoColor.alpha(cfg.textColor, 0.5))
        map.set('text_quaternary', DecoColor.alpha(cfg.textColor, 0.38))
      } else if (hasImage || cfg.pageColor) {
        map.set('text_primary', baseDark ? '#ffffff' : '#111114')
        map.set('text_body', baseDark ? '#ededf0' : '#2b2b31')
        map.set('text_secondary', baseDark ? '#92929a' : '#6b6b75')
        map.set('text_tertiary', baseDark ? '#77777f' : '#8c8c96')
        map.set('text_quaternary', baseDark ? '#66666e' : '#a0a0a8')
      }

      if (cfg.themeColor) {
        map.set('accent', cfg.themeColor)
        map.set('accent_container', DecoColor.alpha(cfg.themeColor, baseDark ? 0.22 : 0.12))
        if (!cfg.accentColor) {
          map.set('accent_soft', cfg.themeColor)
        }
      }
      if (cfg.accentColor) {
        map.set('accent_soft', cfg.accentColor)
      }
      // 背景图模式下头图渐变会让整页蒙白/蒙黑，直接交给背景层控制
      if (hasImage) {
        map.set('header_scrim_top', '#00000000')
        map.set('header_scrim_mid', '#00000000')
      }
    }

    if (map.size > 0) {
      SkinService.applyColors(map).catch(() => {})
    } else {
      SkinService.clearColors().catch(() => {})
    }

    AppStorage.setOrCreate<string>(DecoKeys.SKIN_BG, cfg ? cfg.bgImage : '')
    AppStorage.setOrCreate<number>(DecoKeys.SKIN_BG_OPACITY, cfg ? cfg.bgOpacity : 100)
    AppStorage.setOrCreate<number>(DecoKeys.SKIN_BG_BLUR, cfg ? cfg.bgBlur : 0)
    AppStorage.setOrCreate<string>(DecoKeys.SKIN_BG_COLOR, cfg ? cfg.pageColor : '')
    AppStorage.setOrCreate<number>(DecoKeys.SKIN_SCRIM, cfg ? cfg.scrim : 0)
  }

  // -------------------------------------------------------------------------
  // 底部导航
  // -------------------------------------------------------------------------

  private static applyDock(): void {
    const raw = DecorationStore.payload(DecoKind.DOCK)
    const cfg = raw ? DockConfig.from(raw) : undefined
    AppStorage.setOrCreate<string>(DecoKeys.DOCK_ICONS, cfg ? cfg.icons.join('\n') : '')
    AppStorage.setOrCreate<string>(DecoKeys.DOCK_ICON_COLOR, cfg ? cfg.iconColor : '')
    AppStorage.setOrCreate<string>(DecoKeys.DOCK_ACTIVE_COLOR, cfg ? cfg.activeColor : '')
    AppStorage.setOrCreate<string>(DecoKeys.DOCK_TEXT_COLOR, cfg ? cfg.textColor : '')
    AppStorage.setOrCreate<number>(DecoKeys.DOCK_TEXT_SIZE, cfg ? cfg.textSize : 10)
    AppStorage.setOrCreate<string>(DecoKeys.DOCK_BG, cfg ? cfg.bgColor : '')
    AppStorage.setOrCreate<string>(DecoKeys.DOCK_BG_IMAGE, cfg ? cfg.bgImage : '')
    AppStorage.setOrCreate<string>(DecoKeys.DOCK_INDICATOR, cfg ? cfg.indicatorColor : '')
    AppStorage.setOrCreate<boolean>(DecoKeys.DOCK_SHOW_TEXT, cfg ? cfg.showText : true)
  }

  // -------------------------------------------------------------------------
  // 侧边栏
  // -------------------------------------------------------------------------

  private static applySidebar(): void {
    const raw = DecorationStore.payload(DecoKind.SIDEBAR)
    const cfg = raw ? SidebarConfig.from(raw) : undefined
    AppStorage.setOrCreate<string>(DecoKeys.SIDEBAR_BG, cfg ? cfg.bgImage : '')
    AppStorage.setOrCreate<number>(DecoKeys.SIDEBAR_BG_OPACITY, cfg ? cfg.bgOpacity : 100)
    AppStorage.setOrCreate<number>(DecoKeys.SIDEBAR_BG_BLUR, cfg ? cfg.bgBlur : 0)
    AppStorage.setOrCreate<string>(DecoKeys.SIDEBAR_BG_COLOR, cfg ? cfg.bgColor : '')
    AppStorage.setOrCreate<string>(DecoKeys.SIDEBAR_TEXT_COLOR, cfg ? cfg.textColor : '')
    AppStorage.setOrCreate<number>(DecoKeys.SIDEBAR_TEXT_SIZE, cfg ? cfg.textSize : 16)
    AppStorage.setOrCreate<string>(DecoKeys.SIDEBAR_ICON_COLOR, cfg ? cfg.iconColor : '')
  }

  // -------------------------------------------------------------------------
  // 个人主页背景
  // -------------------------------------------------------------------------

  private static applyHomeBg(): void {
    const raw = DecorationStore.payload(DecoKind.HOME_BG)
    const cfg = raw ? HomeBgConfig.from(raw) : undefined
    AppStorage.setOrCreate<string>(DecoKeys.HOME_BG, cfg ? cfg.image : '')
    AppStorage.setOrCreate<number>(DecoKeys.HOME_BG_BLUR, cfg ? cfg.blur : 0)
    AppStorage.setOrCreate<number>(DecoKeys.HOME_BG_OPACITY, cfg ? cfg.opacity : 100)
    AppStorage.setOrCreate<number>(DecoKeys.HOME_BG_FADE, cfg ? cfg.fade : 100)
  }

  // -------------------------------------------------------------------------
  // 红心 / 启动 / 头像框 / 会员卡 / 等级贴图 / 应用图标
  // -------------------------------------------------------------------------

  private static applySimple(): void {
    const heartRaw = DecorationStore.payload(DecoKind.HEART)
    const heart = heartRaw ? HeartConfig.from(heartRaw) : undefined
    AppStorage.setOrCreate<string>(DecoKeys.HEART_COLOR, heart ? heart.color : '')
    AppStorage.setOrCreate<number>(DecoKeys.HEART_COUNT, heart ? heart.count : 0)
    AppStorage.setOrCreate<number>(DecoKeys.HEART_SIZE, heart ? heart.size : 22)
    AppStorage.setOrCreate<number>(DecoKeys.HEART_DURATION, heart ? heart.duration : 1200)

    const startupRaw = DecorationStore.payload(DecoKind.STARTUP)
    const startup = startupRaw ? StartupConfig.from(startupRaw) : undefined
    AppStorage.setOrCreate<string>(DecoKeys.STARTUP_MEDIA, startup ? startup.media : '')
    AppStorage.setOrCreate<string>(DecoKeys.STARTUP_TYPE, startup ? startup.type : 'image')
    AppStorage.setOrCreate<number>(DecoKeys.STARTUP_DURATION, startup ? startup.duration : 3000)
    AppStorage.setOrCreate<boolean>(DecoKeys.STARTUP_SKIP, startup ? startup.allowSkip : true)

    const frameRaw = DecorationStore.payload(DecoKind.AVATAR_FRAME)
    AppStorage.setOrCreate<string>(DecoKeys.AVATAR_FRAME,
      frameRaw ? ImageOnlyConfig.from(frameRaw).image : '')

    const vipCardRaw = DecorationStore.payload(DecoKind.VIP_CARD)
    AppStorage.setOrCreate<string>(DecoKeys.VIP_CARD,
      vipCardRaw ? ImageOnlyConfig.from(vipCardRaw).image : '')

    const badgeRaw = DecorationStore.payload(DecoKind.VIP_BADGE)
    AppStorage.setOrCreate<string>(DecoKeys.VIP_BADGES,
      badgeRaw ? VipBadgeConfig.from(badgeRaw).images.join('\n') : '')

    const iconRaw = DecorationStore.payload(DecoKind.APP_ICON)
    AppStorage.setOrCreate<string>(DecoKeys.APP_ICON,
      iconRaw ? ImageOnlyConfig.from(iconRaw).image : '')
  }

  // -------------------------------------------------------------------------
  // 播放器样式
  // -------------------------------------------------------------------------

  private static applyPlayerStyle(): void {
    const raw = DecorationStore.payload(DecoKind.PLAYER)
    // 解析一次后重新序列化，确保旧数据/脏字段被规范化，Play 侧可直接 from()
    const normalized = raw ? JSON.stringify(PlayerStyleConfig.from(raw)) : ''
    AppStorage.setOrCreate<string>(DecoKeys.PLAYER_STYLE, normalized)
    const version = (AppStorage.get<number>(DecoKeys.PLAYER_VERSION) ?? 0) + 1
    AppStorage.setOrCreate<number>(DecoKeys.PLAYER_VERSION, version)
  }
}
