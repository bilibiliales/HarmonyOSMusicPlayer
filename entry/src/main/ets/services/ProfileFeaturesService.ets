import { ApiClient } from './ApiClient'
import { OperationResponse } from '../models/api'

export interface UserMedal {
  medalCode: string
  medalName: string
  medalPicUrl?: string
  levelMedalPicUrl?: string
  medalLevel?: number
  acceptCondition?: string
  descriptionText?: string
  status?: string
  wear?: boolean
}
export interface MedalGroup { categoryTitle: string; medalVOS?: UserMedal[]; subGroups?: MedalSubGroup[] }
export interface MedalSubGroup { subGroupTitle?: string; medals?: UserMedal[] }
export interface MedalData { medalNum?: number; obtainMedals?: UserMedal[]; categoryMedalBlockVos?: MedalGroup[] }
interface MedalResponse { code: number; message?: string; data?: MedalData }
interface SocialResponse { code: number; message?: string; data?: Object }
export interface SocialStatus { type: string; iconUrl: string; content: string; actionUrl: string }
export interface StatusUser { uid: string; nickname: string; avatarUrl: string }

export class ProfileFeaturesService {
  static async medals(uid: string): Promise<MedalData> {
    if (!uid) { throw new Error('请先登录') }
    const response = await ApiClient.get<MedalResponse>('/user/medal', [{ key: 'uid', value: uid }])
    if (response.code !== 200 || !response.data) { throw new Error(response.message || '徽章加载失败') }
    return response.data
  }

  static medalItems(data: MedalData, category: number): UserMedal[] {
    if (category === 0) { return data.obtainMedals || [] }
    const group = data.categoryMedalBlockVos?.[category - 1]
    const medals: UserMedal[] = []
    const seen: Set<string> = new Set()
    const all = (group?.medalVOS || []).concat((group?.subGroups || []).reduce(
      (items: UserMedal[], sub: MedalSubGroup) => items.concat(sub.medals || []), [] as UserMedal[]))
    for (const medal of all) {
      if (!seen.has(medal.medalCode)) { seen.add(medal.medalCode); medals.push(medal) }
    }
    return medals
  }

  /** 状态接口可能返回分组；保留编辑接口要求的四个字段。 */
  static statuses(raw: Object | undefined): SocialStatus[] {
    const result: SocialStatus[] = []
    const seen: Set<string> = new Set()
    ProfileFeaturesService.collectStatuses(raw, '', result, seen, 0)
    return result
  }

  private static collectStatuses(raw: Object | undefined, parentType: string,
    result: SocialStatus[], seen: Set<string>, depth: number): void {
    if (!raw || depth > 8 || typeof raw !== 'object') { return }
    if (Array.isArray(raw)) {
      for (const child of raw as Object[]) { ProfileFeaturesService.collectStatuses(child, parentType, result, seen, depth + 1) }
      return
    }
    const node = raw as Record<string, Object>
    const typeValue = node['type'] ?? node['statusType']
    const type = typeof typeValue === 'string' || typeof typeValue === 'number' ? String(typeValue) : parentType
    const contentValue = node['content'] ?? node['statusName'] ?? node['name']
    const iconValue = node['iconUrl'] ?? node['icon']
    const actionValue = node['actionUrl']
    if (typeof contentValue === 'string' && type && (typeof iconValue === 'string' || node['content'] !== undefined)) {
      const status: SocialStatus = { type: type, content: contentValue,
        iconUrl: typeof iconValue === 'string' ? iconValue : '', actionUrl: typeof actionValue === 'string' ? actionValue : '' }
      const key = status.type + ':' + status.content + ':' + status.iconUrl
      if (!seen.has(key)) { seen.add(key); result.push(status) }
    }
    for (const key of Object.keys(node)) {
      ProfileFeaturesService.collectStatuses(node[key], type, result, seen, depth + 1)
    }
  }

  static async currentStatus(uid: string): Promise<SocialStatus[]> {
    const response = await ApiClient.get<SocialResponse>('/user/social/status', [
      { key: 'uid', value: uid }, { key: 'timestamp', value: String(Date.now()) }
    ])
    if (response.code !== 200) { throw new Error(response.message || '当前状态加载失败') }
    return ProfileFeaturesService.statuses(response.data)
  }

  static async supportedStatuses(): Promise<SocialStatus[]> {
    const response = await ApiClient.get<SocialResponse>('/user/social/status/support')
    if (response.code !== 200) { throw new Error(response.message || '可用状态加载失败') }
    return ProfileFeaturesService.statuses(response.data)
  }

  static async editStatus(status: SocialStatus): Promise<void> {
    const response = await ApiClient.get<OperationResponse>('/user/social/status/edit', [
      { key: 'type', value: status.type }, { key: 'iconUrl', value: status.iconUrl },
      { key: 'content', value: status.content }, { key: 'actionUrl', value: status.actionUrl }
    ])
    if (response.code !== 200) { throw new Error(response.message || '状态设置失败') }
    AppStorage.setOrCreate<number>('socialStatusRevision', (AppStorage.get<number>('socialStatusRevision') || 0) + 1)
  }

  static async sameStatusUsers(): Promise<StatusUser[]> {
    const response = await ApiClient.get<SocialResponse>('/user/social/status/rcmd', [{ key: 'timestamp', value: String(Date.now()) }])
    if (response.code !== 200) { throw new Error(response.message || '同状态用户加载失败') }
    return ProfileFeaturesService.statusUsers(response.data)
  }

  static statusUsers(raw: Object | undefined): StatusUser[] {
    const result: StatusUser[] = []
    const seen: Set<string> = new Set()
    ProfileFeaturesService.collectUsers(raw, result, seen, 0)
    return result
  }

  private static collectUsers(raw: Object | undefined, result: StatusUser[], seen: Set<string>, depth: number): void {
    if (!raw || depth > 8 || typeof raw !== 'object') { return }
    if (Array.isArray(raw)) {
      for (const child of raw as Object[]) { ProfileFeaturesService.collectUsers(child, result, seen, depth + 1) }
      return
    }
    const node = raw as Record<string, Object>
    const id = node['userId'] ?? node['uid']
    const name = node['nickname'] ?? node['nickName']
    const avatar = node['avatarUrl'] ?? node['avatar']
    if ((typeof id === 'string' || typeof id === 'number') && typeof name === 'string' && !seen.has(String(id))) {
      seen.add(String(id))
      result.push({ uid: String(id), nickname: name, avatarUrl: typeof avatar === 'string' ? avatar : '' })
    }
    for (const key of Object.keys(node)) { ProfileFeaturesService.collectUsers(node[key], result, seen, depth + 1) }
  }
}
