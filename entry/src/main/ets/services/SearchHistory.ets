import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'

/**
 * 搜索历史：只存本机 preferences，不上传、不依赖账号。
 * 数组以 JSON 字符串落盘，参照 DecorationStore 的同步读 / 异步写模式。
 */
export class SearchHistory {
  private static readonly STORE_NAME: string = 'search_history_store'
  private static readonly KEY_WORDS: string = 'keywords'
  static readonly MAX: number = 20

  static load(context: common.Context): string[] {
    try {
      const store = preferences.getPreferencesSync(context, { name: SearchHistory.STORE_NAME })
      const raw = store.getSync(SearchHistory.KEY_WORDS, '') as string
      if (!raw) { return [] }
      const parsed = JSON.parse(raw) as string[]
      if (!Array.isArray(parsed)) { return [] }
      return parsed.filter((item: string) => typeof item === 'string' && item.length > 0)
        .slice(0, SearchHistory.MAX)
    } catch (_error) {
      return []
    }
  }

  static async save(context: common.Context, words: string[]): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, SearchHistory.STORE_NAME)
      await store.put(SearchHistory.KEY_WORDS, JSON.stringify(words.slice(0, SearchHistory.MAX)))
      await store.flush()
    } catch (_error) {
      // 本地历史写失败不影响搜索
    }
  }

  /** 置顶去重，返回新数组。 */
  static add(words: string[], word: string): string[] {
    const key = word.trim()
    if (!key) { return words }
    const next = [key]
    words.forEach((item: string) => {
      if (item !== key && next.length < SearchHistory.MAX) { next.push(item) }
    })
    return next
  }
}
