import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'

const STORE_NAME: string = 'skin_settings'
const KEY_COLORS: string = 'color_overrides'
const AS_VERSION: string = 'skinVersion'

/**
 * 装扮皮肤服务 —— 装扮中心的「颜色层」运行时底座。
 *
 * 全局色彩解析优先级（全 App 唯一规则）：
 *   皮肤覆盖（本服务）  >  深浅色资源（color.json 的 base/dark）
 *
 * 即：皮肤一旦为某个语义 token（如 page_background）指定了固定颜色，
 * TC 将永远返回该固定值，无论系统是深色还是浅色、无论用户怎么切换主题，
 * 该颜色都不会再变化；皮肤没有指定的 token 则继续正常跟随深浅色主题。
 *
 * 配套约定：
 *   - 页面/组件取色只允许走 TC.xxx()（见 ThemeColors.ets），
 *     不直接写 $r('app.color.*')、不写硬编码 hex；
 *   - 需要在「应用皮肤时原地刷新」的组件，声明一行
 *     @StorageProp('skinVersion') skinVersionObs: number = 0
 *     （本服务在皮肤变化时递增该值，订阅它的组件会自动重渲染）。
 *
 * 后续装扮中心的皮肤编辑器只需调用 applyColors()/clearColors()，
 * 全 App 的颜色立即按上述优先级生效，无需逐页改动。
 */
export class SkinService {
  private static context: common.Context | undefined = undefined
  private static overrides: Map<string, string> = new Map<string, string>()
  private static version: number = 0

  /** 同步读取持久化的皮肤覆盖，保证首帧即生效（与 ThemeService.init 一同调用）。 */
  static init(context: common.Context): void {
    SkinService.context = context
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME })
      const raw: string = store.getSync(KEY_COLORS, '') as string
      SkinService.overrides = SkinService.decode(raw)
    } catch (_error) {
      SkinService.overrides = new Map<string, string>()
    }
    AppStorage.setOrCreate<number>(AS_VERSION, SkinService.version)
  }

  /** 供 TC 查询：皮肤是否覆盖了某个语义色 token；未覆盖返回 undefined。 */
  static colorOverride(token: string): string | undefined {
    if (SkinService.overrides.has(token)) {
      return SkinService.overrides.get(token)
    }
    return undefined
  }

  /** 是否有任一颜色被皮肤接管。 */
  static isActive(): boolean {
    return SkinService.overrides.size > 0
  }

  /** 当前覆盖表快照（供装扮中心「我的装扮」展示/编辑）。 */
  static currentColors(): Map<string, string> {
    const copy = new Map<string, string>()
    SkinService.overrides.forEach((value: string, key: string) => {
      copy.set(key, value)
    })
    return copy
  }

  /** 应用一整套皮肤颜色覆盖（装扮中心保存皮肤时调用）。 */
  static async applyColors(colors: Map<string, string>): Promise<void> {
    SkinService.overrides = colors
    await SkinService.persist()
    SkinService.bump()
  }

  /** 取消全部皮肤颜色覆盖，恢复纯主题取色。 */
  static async clearColors(): Promise<void> {
    SkinService.overrides = new Map<string, string>()
    await SkinService.persist()
    SkinService.bump()
  }

  private static bump(): void {
    SkinService.version++
    AppStorage.setOrCreate<number>(AS_VERSION, SkinService.version)
  }

  private static async persist(): Promise<void> {
    if (!SkinService.context) { return }
    try {
      const store = await preferences.getPreferences(SkinService.context, STORE_NAME)
      await store.put(KEY_COLORS, SkinService.encode(SkinService.overrides))
      await store.flush()
    } catch (_error) {
      // 持久化失败不阻断本次生效，仅丢失下次启动的恢复
    }
  }

  /**
   * 覆盖表序列化为 `token=value;token=value`。
   * token 仅含 [a-z_]，value 为 #hex / rgba(...)，均不含分隔符，无需 JSON 转义。
   */
  private static encode(map: Map<string, string>): string {
    const parts: string[] = []
    map.forEach((value: string, key: string) => {
      parts.push(key + '=' + value)
    })
    return parts.join(';')
  }

  private static decode(raw: string): Map<string, string> {
    const map = new Map<string, string>()
    if (!raw) { return map }
    const parts: string[] = raw.split(';')
    for (const part of parts) {
      const idx: number = part.indexOf('=')
      if (idx <= 0) { continue }
      map.set(part.substring(0, idx), part.substring(idx + 1))
    }
    return map
  }
}
