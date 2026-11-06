import { ApiClient } from './ApiClient'
import { ApiParam, EventInfo, EventPicture, UserEventItem } from '../models/api'

export interface FanClubGroup {
  fansGroupId: string
  headId: number
  headIdType: string
  headAvatarUrl: string
  fansGroupName: string
  fansGroupPureName: string
  fansNameplate: string
  headHomepageUrl: string
  brief: string
  artistName: string
  activeMembersCount: number
  totalMembersCount: number
  showMsg: string
  userActive: boolean
}

export interface FanClubDetail {
  fansGroupId: string
  headId: number
  headIdType: string
  headAvatarUrl: string
  fansGroupName: string
  fansGroupPureName: string
  headHomepageUrl: string
  brief: string
  artistName: string
  mainState: boolean
  activeMembersCount: number
  totalMembersCount: number
  newMembersThisWeekCount: number
  fansNoteUpdateCount: number
}

export interface FanClubFeedResult {
  records: UserEventItem[]
  more: boolean
  cursor: string
}

interface GroupListData {
  groups?: FanClubGroup[]
}
interface GroupListResponse {
  code: number
  data: GroupListData
}

interface GroupDetailData {
  fansGroupInfo?: FanClubDetail | null
}
interface GroupDetailResponse {
  code: number
  data: GroupDetailData
}

interface FeedPage {
  size?: number
  cursor?: string
  more?: boolean
}
interface FeedData {
  records?: object[]
  page?: FeedPage
}
interface FeedResponse {
  code: number
  data: FeedData
}

export class FanClubService {
  // 我加入的乐迷团
  static async getMyGroups(): Promise<FanClubGroup[]> {
    const resp = await ApiClient.get<GroupListResponse>('/fans/group/user/groups')
    const groups = (resp?.data?.groups || []) as FanClubGroup[]
    return groups.map((group: FanClubGroup) => FanClubService.normalizeGroup(group))
  }

  // 乐迷团详情
  static async getGroupDetail(groupId: string): Promise<FanClubDetail | null> {
    const resp = await ApiClient.get<GroupDetailResponse>('/fans/group/detail', [
      { key: 'groupId', value: groupId }
    ])
    const info = resp?.data?.fansGroupInfo
    if (!info) { return null }
    return FanClubService.normalizeDetail(info)
  }

  // 乐迷团动态 / 笔记（复用通用动态组件渲染，故映射为 UserEventItem）
  static async getGroupFeed(groupId: string, cursor: string = '0', size: number = 20): Promise<FanClubFeedResult> {
    const params: ApiParam[] = [
      { key: 'fansGroupId', value: groupId },
      { key: 'size', value: size.toString() },
      { key: 'cursor', value: cursor }
    ]
    const resp = await ApiClient.get<FeedResponse>('/fans/group/feed/recommend', params)
    const data = resp?.data
    const rawRecords: object[] = (data && data.records) ? data.records : []
    const page = (data && data.page) ? data.page : undefined
    return {
      records: rawRecords.map((item: object) => FanClubService.toUserEvent(item)),
      more: !!(page && page.more),
      cursor: (page && page.cursor) || ''
    }
  }

  private static normalizeGroup(group: FanClubGroup): FanClubGroup {
    return {
      fansGroupId: String(group.fansGroupId || ''),
      headId: Number(group.headId || 0),
      headIdType: String(group.headIdType || ''),
      headAvatarUrl: String(group.headAvatarUrl || ''),
      fansGroupName: String(group.fansGroupName || group.fansGroupPureName || '乐迷团'),
      fansGroupPureName: String(group.fansGroupPureName || ''),
      fansNameplate: String(group.fansNameplate || ''),
      headHomepageUrl: String(group.headHomepageUrl || ''),
      brief: String(group.brief || ''),
      artistName: String(group.artistName || ''),
      activeMembersCount: Number(group.activeMembersCount || 0),
      totalMembersCount: Number(group.totalMembersCount || 0),
      showMsg: String(group.showMsg || ''),
      userActive: !!group.userActive
    }
  }

  private static normalizeDetail(info: FanClubDetail): FanClubDetail {
    return {
      fansGroupId: String(info.fansGroupId || ''),
      headId: Number(info.headId || 0),
      headIdType: String(info.headIdType || ''),
      headAvatarUrl: String(info.headAvatarUrl || ''),
      fansGroupName: String(info.fansGroupName || info.fansGroupPureName || '乐迷团'),
      fansGroupPureName: String(info.fansGroupPureName || ''),
      headHomepageUrl: String(info.headHomepageUrl || ''),
      brief: String(info.brief || ''),
      artistName: String(info.artistName || ''),
      mainState: !!info.mainState,
      activeMembersCount: Number(info.activeMembersCount || 0),
      totalMembersCount: Number(info.totalMembersCount || 0),
      newMembersThisWeekCount: Number(info.newMembersThisWeekCount || 0),
      fansNoteUpdateCount: Number(info.fansNoteUpdateCount || 0)
    }
  }

  // 将乐迷团动态原始对象映射为通用动态组件所需的 UserEventItem（防御式拷贝）
  private static toUserEvent(raw: object): UserEventItem {
    const item = raw as Record<string, Object>
    const rawUser = (item['user'] || {}) as Record<string, Object>
    const rawInfo = (item['info'] || {}) as Record<string, Object>
    const id = Number(item['id'] || 0)
    const eventTime = Number(item['eventTime'] || item['showTime'] || 0)
    const showTime = Number(item['showTime'] || item['eventTime'] || 0)
    const jsonValue = item['json']
    const json: string = typeof jsonValue === 'string' ? jsonValue : JSON.stringify(jsonValue || {})
    const info: EventInfo = {
      commentCount: Number(rawInfo['commentCount'] || 0),
      likedCount: Number(rawInfo['likedCount'] || 0),
      shareCount: Number(rawInfo['shareCount'] || 0),
      threadId: typeof rawInfo['threadId'] === 'string' ? rawInfo['threadId'] as string : undefined,
      liked: !!rawInfo['liked']
    }
    const pictures = (item['pics'] as EventPicture[] | undefined) || undefined
    return {
      id: id,
      type: typeof item['type'] === 'number' ? item['type'] as number : undefined,
      eventTime: eventTime,
      showTime: showTime,
      json: json,
      user: {
        userId: Number(rawUser['userId'] || 0),
        nickname: String(rawUser['nickname'] || ''),
        avatarUrl: String(rawUser['avatarUrl'] || ''),
        userType: typeof rawUser['userType'] === 'number' ? rawUser['userType'] as number : 0,
        followed: !!rawUser['followed'],
        mutual: !!rawUser['mutual']
      },
      info: info,
      pics: pictures,
      actName: typeof item['actName'] === 'string' ? item['actName'] as string : undefined
    }
  }
}

export interface FanClubDetailParam {
  groupId: string
}
