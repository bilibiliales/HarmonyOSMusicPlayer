import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { DecoMember, DecoKind, DecorationItem, SuitConfig } from '../models/decoration'
import { DecorationRuntime } from './DecorationRuntime'

const STORE_NAME: string = 'decoration_store'
const KEY_ITEMS: string = 'items'
const KEY_ACTIVE: string = 'active'
const AS_COUNT: string = 'decorationActiveCount'

/**
 * 装扮仓库 —— 纯本地存储（preferences）。
 *
 * 数据分两块：
 *   items   ：所有已创建/已导入的装扮（每类可多个，可增删改）；
 *   active  ：每类当前生效的那一个（kind -> id），套装会一次性改写多项。
 *
 * 任何写操作后都会调用 DecorationRuntime.applyAll()，把「当前生效表」
 * 重新解释成 SkinService 颜色覆盖 + AppStorage 运行时配置，并递增
 * skinVersion，全 App 立刻刷新。
 */
export class DecorationStore {
  private static context: common.Context | undefined = undefined
  private static items: DecorationItem[] = []
  /** kind -> item id */
  private static activeIds: Map<string, string> = new Map<string, string>()

  /** 同步读取（EntryAbility.onCreate 调用），保证首帧就是用户装扮。 */
  static init(context: common.Context): void {
    DecorationStore.context = context
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME })
      DecorationStore.items = DecorationStore.decodeItems(store.getSync(KEY_ITEMS, '') as string)
      DecorationStore.activeIds = DecorationStore.decodeActive(store.getSync(KEY_ACTIVE, '') as string)
    } catch (_error) {
      DecorationStore.items = []
      DecorationStore.activeIds = new Map<string, string>()
    }
    DecorationRuntime.applyAll()
  }

  static all(): DecorationItem[] {
    return DecorationStore.items
  }

  static list(kind: string): DecorationItem[] {
    const result: DecorationItem[] = []
    for (const item of DecorationStore.items) {
      if (item.kind === kind) {
        result.push(item)
      }
    }
    return result
  }

  static find(id: string): DecorationItem | undefined {
    for (const item of DecorationStore.items) {
      if (item.id === id) { return item }
    }
    return undefined
  }

  static activeId(kind: string): string {
    const id = DecorationStore.activeIds.get(kind)
    return id === undefined ? '' : id
  }

  static activeItem(kind: string): DecorationItem | undefined {
    const id = DecorationStore.activeId(kind)
    return id ? DecorationStore.find(id) : undefined
  }

  /** 当前生效装扮的配置 JSON；未启用返回空串。 */
  static payload(kind: string): string {
    const item = DecorationStore.activeItem(kind)
    return item === undefined ? '' : item.payload
  }

  static activeName(kind: string): string {
    const item = DecorationStore.activeItem(kind)
    return item === undefined ? '' : item.name
  }

  static activeCount(): number {
    return DecorationStore.activeIds.size
  }

  static isActive(id: string): boolean {
    const item = DecorationStore.find(id)
    if (!item) { return false }
    return DecorationStore.activeId(item.kind) === id
  }

  /** 新增或更新一条装扮；返回落库后的对象。 */
  static async save(item: DecorationItem): Promise<DecorationItem> {
    if (!item.id) {
      item.id = DecorationStore.newId(item.kind)
    }
    item.updatedAt = Date.now()
    let replaced = false
    for (let i = 0; i < DecorationStore.items.length; i++) {
      if (DecorationStore.items[i].id === item.id) {
        DecorationStore.items[i] = item
        replaced = true
        break
      }
    }
    if (!replaced) {
      DecorationStore.items.push(item)
    }
    await DecorationStore.persist()
    DecorationRuntime.applyAll()
    return item
  }

  static async remove(id: string): Promise<void> {
    const kept: DecorationItem[] = []
    let removedKind = ''
    for (const item of DecorationStore.items) {
      if (item.id === id) {
        removedKind = item.kind
      } else {
        kept.push(item)
      }
    }
    DecorationStore.items = kept
    if (removedKind && DecorationStore.activeIds.get(removedKind) === id) {
      DecorationStore.activeIds.delete(removedKind)
    }
    // 套装里引用了被删条目：一并摘掉，避免套装指向空对象
    DecorationStore.pruneSuits(id)
    await DecorationStore.persist()
    DecorationRuntime.applyAll()
  }

  static async activate(item: DecorationItem): Promise<void> {
    DecorationStore.activeIds.set(item.kind, item.id)
    await DecorationStore.persist()
    DecorationRuntime.applyAll()
  }

  static async deactivate(kind: string): Promise<void> {
    DecorationStore.activeIds.delete(kind)
    await DecorationStore.persist()
    DecorationRuntime.applyAll()
  }

  /** 一键取消全部装扮（保留已创建的条目，只清空生效表）。 */
  static async deactivateAll(): Promise<void> {
    DecorationStore.activeIds = new Map<string, string>()
    await DecorationStore.persist()
    DecorationRuntime.applyAll()
  }

  /** 应用套装：一次性把成员逐个设为生效。 */
  static async applySuit(suit: DecorationItem): Promise<void> {
    const config = SuitConfig.from(suit.payload)
    for (const member of config.members) {
      if (DecorationStore.find(member.id)) {
        DecorationStore.activeIds.set(member.kind, member.id)
      }
    }
    await DecorationStore.persist()
    DecorationRuntime.applyAll()
  }

  static suitMembers(suit: DecorationItem): DecoMember[] {
    return SuitConfig.from(suit.payload).members
  }

  private static pruneSuits(removedId: string): void {
    for (const item of DecorationStore.items) {
      if (item.kind !== DecoKind.SUIT) { continue }
      const config = SuitConfig.from(item.payload)
      const kept: DecoMember[] = []
      let changed = false
      for (const member of config.members) {
        if (member.id === removedId) {
          changed = true
        } else {
          kept.push(member)
        }
      }
      if (changed) {
        config.members = kept
        item.payload = JSON.stringify(config)
      }
    }
  }

  private static newId(kind: string): string {
    return `${kind}_${Date.now().toString(36)}${Math.floor(Math.random() * 10000).toString(36)}`
  }

  private static async persist(): Promise<void> {
    AppStorage.setOrCreate<number>(AS_COUNT, DecorationStore.activeIds.size)
    if (!DecorationStore.context) { return }
    try {
      const store = await preferences.getPreferences(DecorationStore.context, STORE_NAME)
      await store.put(KEY_ITEMS, JSON.stringify(DecorationStore.items))
      await store.put(KEY_ACTIVE, DecorationStore.encodeActive())
      await store.flush()
    } catch (_error) {
      // 持久化失败不阻断本次生效
    }
  }

  /** kind=id;kind=id —— id 里不含分隔符。 */
  private static encodeActive(): string {
    const parts: string[] = []
    DecorationStore.activeIds.forEach((id: string, kind: string) => {
      parts.push(`${kind}=${id}`)
    })
    return parts.join(';')
  }

  private static decodeActive(raw: string): Map<string, string> {
    const map = new Map<string, string>()
    if (!raw) { return map }
    for (const part of raw.split(';')) {
      const idx = part.indexOf('=')
      if (idx <= 0) { continue }
      map.set(part.substring(0, idx), part.substring(idx + 1))
    }
    return map
  }

  private static decodeItems(raw: string): DecorationItem[] {
    if (!raw) { return [] }
    try {
      const parsed = JSON.parse(raw) as DecorationItem[]
      const items: DecorationItem[] = []
      for (const src of parsed) {
        if (!src || !src.id || !src.kind) { continue }
        const item = new DecorationItem()
        item.id = src.id
        item.kind = src.kind
        item.name = src.name ?? ''
        item.cover = src.cover ?? ''
        item.payload = src.payload ?? ''
        item.updatedAt = src.updatedAt ?? 0
        items.push(item)
      }
      return items
    } catch (_error) {
      return []
    }
  }
}
