import { SkinBackdrop } from '../components/SkinBackdrop'
import {
  ArtistFanItem,
  ArtistPageParam,
  ArtistFanProfile,
  ArtistFansResponse,
  EventDetailPageParam,
  MixedFollowRecord,
  MixedFollowResponse,
  MvPlayerPageParam,
  OperationResponse,
  SocialUser,
  UserEventItem,
  UserFollowedsResponse,
  UserFollowsResponse,
  UserProfilePageParam
} from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'
import { BubbleTip } from '../services/BubbleTip'
import { FanClubDetailParam } from '../services/FanClubService'
import { resizeImageUrl } from '../services/ImageUrl'
import { TC } from '../services/ThemeColors'

export interface RelationshipPageParam {
  type: string
  title: string
  uid?: string
}

/** 关注场景筛选（仅「我的关注」用混合接口时出现）。 */
interface SceneOption {
  label: string
  value: number
}

const SCENES: SceneOption[] = [
  { label: '全部', value: 0 },
  { label: '歌手', value: 1 },
  { label: '用户', value: 2 }
]

/** /event?id= 的返回：单条详情用 event，列表式返回用 events。 */
interface EventByIdResponse {
  code: number
  message?: string
  event?: UserEventItem
  events?: UserEventItem[]
}

/**
 * 列表行模型：普通用户、歌手、以及混合列表里附带的最近动态，
 * 全部压成同一种结构，列表只按这一种渲染。
 */
interface RelationRow {
  /** 唯一标识（不含关注态，关注态在 rowKey() 里拼上，便于刷新单行）。 */
  key: string
  userId: number
  artistId: number
  nickname: string
  avatarUrl: string
  identityIconUrl: string
  isArtist: boolean
  userType: number
  subtitle: string
  followed: boolean
  mutual: boolean
  fansGroupId: string
  fansGroupLevel: string
  /** showContent.message，但没有可跳转资源时直接显示。 */
  showMessage: string
  /** showContent.message，带资源时渲染成气泡。 */
  bubbleMessage: string
  bubbleType: number
  bubbleId: string
  bubbleTitle: string
  bubbleCover: string
}

@Component
export struct RelationshipListPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: RelationshipPageParam = { type: 'following', title: '关注' }

  @State rows: RelationRow[] = []
  @State loading: boolean = false
  @State more: boolean = true
  @State pageOffset: number = 0
  @State cursor: string = '0'
  @State scene: number = 0
  @State message: string = ''
  /** 对方设置了隐私（接口返回 400 用户隐私无权限查看）。 */
  @State blocked: boolean = false
  @State blockedText: string = ''
  @State confirmVisible: boolean = false
  @State selectedRow: RelationRow | null = null
  private readonly pageSize: number = 20

  private isArtistFans(): boolean {
    return this.pageParam.type === 'artistFans'
  }

  private targetUid(): string {
    return this.pageParam.uid || this.authStore.userId
  }

  private isOwnRelationshipList(): boolean {
    return !this.isArtistFans() && this.targetUid() === this.authStore.userId
  }

  /** 自己的关注列表走 /user/follow/mixed（带场景筛选与最近动态）。 */
  private isMixedMode(): boolean {
    return this.pageParam.type === 'following' && this.isOwnRelationshipList()
  }

  /* ---------------- 行模型转换 ---------------- */

  private emptyRow(): RelationRow {
    return {
      key: '',
      userId: 0,
      artistId: 0,
      nickname: '',
      avatarUrl: '',
      identityIconUrl: '',
      isArtist: false,
      userType: 0,
      subtitle: '',
      followed: false,
      mutual: false,
      fansGroupId: '',
      fansGroupLevel: '',
      showMessage: '',
      bubbleMessage: '',
      bubbleType: 0,
      bubbleId: '',
      bubbleTitle: '',
      bubbleCover: ''
    }
  }

  private toRow(user: SocialUser): RelationRow {
    const row = this.emptyRow()
    row.key = `u${user.userId}`
    row.userId = user.userId
    row.nickname = user.nickname
    row.avatarUrl = user.avatarUrl
    row.userType = user.userType || 0
    row.followed = user.followed === true
    row.mutual = user.mutual === true
    const detail = user.avatarDetail
    if (detail && detail.identityIconUrl) {
      row.identityIconUrl = detail.identityIconUrl
    }
    if (user.signature && user.signature.length > 0) {
      row.subtitle = user.signature
    } else {
      row.subtitle = `${user.follows || 0} 关注 · ${user.followeds || 0} 粉丝`
    }
    return row
  }

  /** /artist/fans 的 userProfile → 行模型。 */
  private toArtistFanRow(item: ArtistFanItem): RelationRow | null {
    const profile: ArtistFanProfile | undefined = item.userProfile
    if (!profile || !profile.userId) {
      return null
    }
    return this.toRow({
      userId: profile.userId,
      nickname: profile.nickname || '',
      avatarUrl: profile.avatarUrl || '',
      signature: profile.signature || '',
      followed: profile.followed === true,
      mutual: profile.mutual === true,
      follows: profile.follows,
      followeds: profile.followeds,
      userType: profile.userType,
      authStatus: profile.authStatus,
      avatarDetail: profile.avatarDetail
    })
  }

  /** /user/follow/mixed 的一条记录 → 行模型。 */
  private toMixedRow(record: MixedFollowRecord): RelationRow | null {
    const profile = record.userProfile
    const artist = record.artistInfo
    const type: number = record.type || 1
    const hasArtist: boolean = type === 2 || type === 3

    let userId = 0
    let artistId = 0
    let nickname = ''
    let avatarUrl = ''
    let signature = ''
    let identityIconUrl = ''
    let userType = 0
    let artistName = ''

    if (profile) {
      userId = profile.userId || 0
      nickname = profile.nickname || ''
      avatarUrl = profile.avatarUrl || ''
      signature = profile.signature || ''
      userType = profile.userType || 0
      const detail = profile.avatarDetail
      if (detail && detail.identityIconUrl) {
        identityIconUrl = detail.identityIconUrl
      }
    }
    if (artist) {
      artistId = artist.id || 0
      artistName = artist.name || ''
      if (nickname.length === 0) {
        nickname = artistName
      }
      if (avatarUrl.length === 0) {
        avatarUrl = artist.picUrl || artist.img1v1Url || ''
      }
      const alias = artist.alias || []
      if (signature.length === 0 && alias.length > 0) {
        signature = alias.join(' / ')
      }
    }
    if (userId === 0 && artistId === 0) {
      return null
    }

    const isArtistRow: boolean = hasArtist && artistId > 0
    const followDay: string = record.followDay || ''
    const mutual: boolean = record.mutualFollowTime !== null && record.mutualFollowTime !== undefined

    let showMessage = ''
    let bubbleMessage = ''
    let bubbleType = 0
    let bubbleId = ''
    let bubbleTitle = ''
    let bubbleCover = ''
    const show = record.showContent
    if (show) {
      const text: string = show.message || ''
      const box = show.boxContent
      if (box) {
        bubbleMessage = text
        bubbleTitle = box.title || ''
        const resource = box.resource
        if (resource) {
          bubbleType = resource.resourceType || 0
          bubbleId = resource.resourceId || ''
          bubbleCover = resource.coverUrl || ''
        }
      } else {
        showMessage = text
      }
    }

    let fansGroupId = ''
    let fansGroupLevel = ''
    const club = record.fansGroupInfo
    if (club) {
      fansGroupId = club.fansGroupIdStr || ''
      fansGroupLevel = club.level || ''
    }

    const row = this.emptyRow()
    row.key = `m${isArtistRow ? artistId : userId}`
    row.userId = userId
    row.artistId = artistId
    row.nickname = nickname
    row.avatarUrl = avatarUrl
    row.identityIconUrl = identityIconUrl
    row.isArtist = isArtistRow
    row.userType = userType
    row.followed = true
    row.mutual = isArtistRow ? false : mutual
    row.fansGroupId = fansGroupId
    row.fansGroupLevel = fansGroupLevel
    row.showMessage = showMessage
    row.bubbleMessage = bubbleMessage
    row.bubbleType = bubbleType
    row.bubbleId = bubbleId
    row.bubbleTitle = bubbleTitle
    row.bubbleCover = bubbleCover
    if (signature.length > 0) {
      row.subtitle = signature
    } else if (followDay.length > 0) {
      row.subtitle = `已关注 ${followDay}`
    } else {
      row.subtitle = ''
    }
    return row
  }

  /** 关注态参与 key：状态一变就换 key，单行立刻重绘。 */
  private rowKey(row: RelationRow): string {
    return `${row.key}-${row.followed ? 1 : 0}${row.mutual ? 1 : 0}`
  }

  /* ---------------- 数据加载 ---------------- */

  aboutToAppear(): void {
    this.loadMore()
  }

  private async loadMore(): Promise<void> {
    if (this.loading || !this.more || !this.targetUid()) {
      return
    }
    this.loading = true
    this.message = ''
    try {
      if (this.isArtistFans()) {
        await this.loadArtistFans()
      } else if (this.isMixedMode()) {
        await this.loadMixed()
      } else if (this.pageParam.type === 'following') {
        await this.loadFollows()
      } else {
        await this.loadFolloweds()
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '列表加载失败'
    } finally {
      this.loading = false
    }
  }

  private async loadArtistFans(): Promise<void> {
    const response = await ApiClient.get<ArtistFansResponse>('/artist/fans', [
      { key: 'id', value: this.targetUid() },
      { key: 'limit', value: this.pageSize.toString() },
      { key: 'offset', value: this.pageOffset.toString() }
    ])
    if (response.code !== 200) {
      this.applyBlocked(response.message)
      return
    }
    const raw: ArtistFanItem[] = response.data || []
    const incoming: RelationRow[] = []
    raw.forEach((item: ArtistFanItem) => {
      const row = this.toArtistFanRow(item)
      if (row) {
        incoming.push(row)
      }
    })
    this.rows = this.rows.concat(incoming)
    this.pageOffset += raw.length
    // 该接口不返回 more，按整页推断
    this.more = raw.length >= this.pageSize
  }

  private async loadMixed(): Promise<void> {
    const requestScene = this.scene
    const response = await ApiClient.get<MixedFollowResponse>('/user/follow/mixed', [
      { key: 'size', value: this.pageSize.toString() },
      { key: 'cursor', value: this.cursor },
      { key: 'scene', value: requestScene.toString() }
    ])
    // 请求期间用户切了场景：这一页属于旧场景，直接丢弃
    if (requestScene !== this.scene) {
      return
    }
    if (response.code !== 200 || !response.data) {
      this.applyBlocked(response.message)
      return
    }
    const records: MixedFollowRecord[] = response.data.records || []
    const incoming: RelationRow[] = []
    records.forEach((record: MixedFollowRecord) => {
      const row = this.toMixedRow(record)
      if (row) {
        incoming.push(row)
      }
    })
    this.rows = this.rows.concat(incoming)
    const page = response.data.page
    if (page) {
      this.cursor = page.cursor || ''
      this.more = page.more === true && this.cursor.length > 0
    } else {
      this.more = records.length >= this.pageSize
    }
  }

  private async loadFollows(): Promise<void> {
    const response = await ApiClient.get<UserFollowsResponse>('/user/follows', [
      { key: 'uid', value: this.targetUid() },
      { key: 'limit', value: this.pageSize.toString() },
      { key: 'offset', value: this.pageOffset.toString() }
    ])
    if (response.code !== 200) {
      this.applyBlocked(response.message)
      return
    }
    const incoming: SocialUser[] = response.follow || []
    const mapped: RelationRow[] = []
    incoming.forEach((user: SocialUser) => {
      if (this.isOwnRelationshipList()) {
        user.followed = true
      }
      mapped.push(this.toRow(user))
    })
    this.rows = this.rows.concat(mapped)
    this.pageOffset += mapped.length
    this.more = response.more
  }

  private async loadFolloweds(): Promise<void> {
    const response = await ApiClient.get<UserFollowedsResponse>('/user/followeds', [
      { key: 'uid', value: this.targetUid() },
      { key: 'limit', value: this.pageSize.toString() },
      { key: 'offset', value: this.pageOffset.toString() }
    ])
    if (response.code !== 200) {
      this.applyBlocked(response.message)
      return
    }
    const incoming: SocialUser[] = response.followeds || []
    const mapped: RelationRow[] = []
    incoming.forEach((user: SocialUser) => {
      mapped.push(this.toRow(user))
    })
    this.rows = this.rows.concat(mapped)
    this.pageOffset += mapped.length
    this.more = response.more
  }

  /**
   * 接口拒绝（多为「用户隐私无权限查看」）：不要退化成「这里还没有用户」，
   * 否则会让人误以为对方真的没关注任何人。
   */
  private applyBlocked(rawMessage?: string): void {
    const text: string = (rawMessage || '').trim()
    this.blocked = true
    this.blockedText = text.length > 0 ? text : '对方设置了隐私保护'
    this.more = false
  }

  private changeScene(value: number): void {
    if (this.scene === value) {
      return
    }
    this.scene = value
    this.resetList()
  }

  private resetList(): void {
    this.rows = []
    this.pageOffset = 0
    this.cursor = '0'
    this.more = true
    this.blocked = false
    this.blockedText = ''
    this.message = ''
    this.loadMore()
  }

  /* ---------------- 交互 ---------------- */

  private isFollowing(row: RelationRow): boolean {
    return row.followed || row.mutual
  }

  private relationText(row: RelationRow): string {
    if (row.mutual && !row.isArtist) {
      return '互相关注'
    }
    return this.isFollowing(row) ? '已关注' : '关注'
  }

  private relationClick(row: RelationRow): void {
    if (this.isFollowing(row)) {
      this.selectedRow = row
      this.confirmVisible = true
    } else {
      this.follow(row)
    }
  }

  private followPath(row: RelationRow): string {
    return row.isArtist ? '/artist/sub' : '/follow'
  }

  private followId(row: RelationRow): number {
    return row.isArtist ? row.artistId : row.userId
  }

  private async follow(row: RelationRow): Promise<void> {
    const id = this.followId(row)
    if (id <= 0) {
      return
    }
    try {
      const response = await ApiClient.get<OperationResponse>(this.followPath(row), [
        { key: 'id', value: id.toString() },
        { key: 't', value: '1' }
      ])
      if (response.code === 200) {
        row.followed = true
        if (this.isOwnRelationshipList() && this.pageParam.type === 'followers' && !row.isArtist) {
          row.mutual = true
        }
        this.refreshRows()
      } else {
        this.message = response.message || '关注失败'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '关注失败'
    }
  }

  private async cancelFollow(): Promise<void> {
    const row = this.selectedRow
    if (!row) {
      return
    }
    const id = this.followId(row)
    try {
      const response = await ApiClient.get<OperationResponse>(this.followPath(row), [
        { key: 'id', value: id.toString() },
        { key: 't', value: '0' }
      ])
      if (response.code === 200) {
        if (this.pageParam.type === 'following') {
          this.rows = this.rows.filter((item: RelationRow) => item.key !== row.key)
        } else {
          this.rows.forEach((item: RelationRow) => {
            if (item.key === row.key) {
              item.followed = false
              item.mutual = false
            }
          })
          this.refreshRows()
        }
        this.confirmVisible = false
        this.selectedRow = null
      } else {
        this.message = response.message || '取消关注失败'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '取消关注失败'
    }
  }

  private refreshRows(): void {
    this.rows = this.rows.slice()
  }

  private openRow(row: RelationRow): void {
    if (row.isArtist && row.artistId > 0) {
      const param: ArtistPageParam = { id: row.artistId.toString(), name: row.nickname, picUrl: row.avatarUrl }
      this.pageStack.pushPathByName('ArtistPage', param)
      return
    }
    if (row.userId <= 0) {
      return
    }
    const param: UserProfilePageParam = { uid: row.userId.toString() }
    if (this.isOwnRelationshipList()) {
      if (this.pageParam.type === 'following') {
        param.followsTarget = true
        param.followedByTarget = row.mutual
      } else {
        param.followsTarget = this.isFollowing(row)
        param.followedByTarget = true
      }
    }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private openFanClub(row: RelationRow): void {
    if (row.fansGroupId.length === 0) {
      return
    }
    const param: FanClubDetailParam = { groupId: row.fansGroupId }
    this.pageStack.pushPathByName('FanClubDetailPage', param)
  }

  private openBubble(row: RelationRow): void {
    if (row.bubbleType === 2) {
      this.openNote(row.bubbleId)
      return
    }
    if (row.bubbleType === 5) {
      const param: MvPlayerPageParam = { id: row.bubbleId, name: row.bubbleTitle, cover: row.bubbleCover }
      this.pageStack.pushPathByName('MvPlayerPage', param)
      return
    }
    BubbleTip.show(this.getUIContext(), '这条动态暂时打不开')
  }

  /** 笔记：先按 id 拉详情，再进详情页。 */
  private async openNote(eventId: string): Promise<void> {
    if (eventId.length === 0) {
      return
    }
    try {
      const response = await ApiClient.get<EventByIdResponse>('/event', [
        { key: 'id', value: eventId }
      ])
      // 只接受 id 对得上的那条：万一服务端忽略了 id 返回动态流，
      // 也不能拿别人的笔记冒充这一条。
      const wanted = Number(eventId)
      let target: UserEventItem | null = null
      const single = response.event
      if (single && single.id === wanted) {
        target = single
      } else {
        const list = response.events || []
        list.forEach((item: UserEventItem) => {
          if (item.id === wanted) {
            target = item
          }
        })
      }
      if (response.code !== 200 || target === null) {
        BubbleTip.show(this.getUIContext(), '这条笔记暂时打不开')
        return
      }
      const param: EventDetailPageParam = { event: target }
      this.pageStack.pushPathByName('EventDetailPage', param)
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '笔记加载失败')
    }
  }

  /* ---------------- 视图 ---------------- */

  @Builder
  private SceneChips() {
    Row({ space: 4 }) {
      ForEach(SCENES, (item: SceneOption) => {
        Text(item.label)
          .fontSize(11)
          .fontColor(this.scene === item.value ? TC.textOnAccent() : TC.textSecondary())
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .backgroundColor(this.scene === item.value ? TC.accent() : TC.surfaceRaised())
          .borderRadius(11)
          .onClick(() => this.changeScene(item.value))
      }, (item: SceneOption) => `scene-${item.value}`)
    }
  }

  @Builder
  private RowAvatar(row: RelationRow) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Image(resizeImageUrl(row.avatarUrl, 120, 120))
        .width(50)
        .height(50)
        .borderRadius(25)
        .objectFit(ImageFit.Cover)
        .backgroundColor(TC.surfaceRaised())
      if (row.identityIconUrl.length > 0) {
        Image(row.identityIconUrl)
          .width(17)
          .height(17)
          .borderRadius(9)
          .objectFit(ImageFit.Cover)
          .border({ width: 1.5, color: '#FFFFFF' })
      } else if (row.isArtist) {
        Image($r('app.media.ic_singer'))
          .width(17)
          .height(17)
          .borderRadius(9)
          .border({ width: 1.5, color: '#FFFFFF' })
      }
    }
    .width(50)
    .height(50)
    .onClick(() => this.openRow(row))
  }

  @Builder
  private FanClubChip(row: RelationRow) {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.person_2_fill')).fontSize(10).fontColor([TC.accent()])
      Text(row.fansGroupLevel.length > 0 ? `乐迷团 Lv.${row.fansGroupLevel}` : '乐迷团')
        .fontSize(9)
        .fontColor(TC.accent())
    }
    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    .backgroundColor(TC.accentContainer())
    .borderRadius(8)
    .onClick(() => this.openFanClub(row))
  }

  @Builder
  private ContentBubble(row: RelationRow) {
    Row({ space: 3 }) {
      Text(row.bubbleMessage)
        .fontSize(10)
        .fontColor(TC.accent())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      // 只有能跳转的资源才给箭头，避免点了没反应还带指示
      if (row.bubbleType === 2 || row.bubbleType === 5) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([TC.accent()])
      }
    }
    .constraintSize({ maxWidth: 210 })
    .padding({ left: 8, right: 6, top: 4, bottom: 4 })
    .backgroundColor(TC.accentContainer())
    .borderRadius(9)
    .onClick(() => this.openBubble(row))
  }

  @Builder
  private RelationButton(row: RelationRow) {
    Text(this.relationText(row))
      .width(76)
      .height(32)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isFollowing(row) ? TC.accent() : TC.textOnAccent())
      .textAlign(TextAlign.Center)
      .backgroundColor(this.isFollowing(row) ? '#00ffffff' : TC.accent())
      .borderRadius(16)
      .border({ width: this.isFollowing(row) ? 1 : 0, color: TC.accent() })
      .onClick(() => this.relationClick(row))
  }

  @Builder
  private CancelSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.58)')
        .onClick(() => this.confirmVisible = false)
      Column({ space: 18 }) {
        Column({ space: 8 }) {
          Text(this.selectedRow?.isArtist === true ? '取消收藏歌手' : '取消关注')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary())
          Text(`确定不再关注「${this.selectedRow?.nickname || ''}」吗？`)
            .fontSize(13)
            .fontColor(TC.textSecondary())
            .textAlign(TextAlign.Center)
        }
        Row({ space: 12 }) {
          Button('暂不取消')
            .layoutWeight(1)
            .height(46)
            .fontColor(TC.textBody())
            .backgroundColor(TC.surfaceRaised())
            .borderRadius(23)
            .onClick(() => this.confirmVisible = false)
          Button('取消关注')
            .layoutWeight(1)
            .height(46)
            .backgroundColor(TC.accent())
            .borderRadius(23)
            .onClick(() => this.cancelFollow())
        }
      }
      .width('100%')
      .height('34%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 24, right: 24, bottom: 18 })
      .backgroundColor(TC.surfaceCard())
      .borderRadius({ topLeft: 28, topRight: 28 })
      .transition(TransitionEffect.translate({ y: 500 }).animation({ duration: 260, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private BlockedState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([TC.textQuaternary()])
      Text('无法查看该列表')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(TC.textSecondary())
      Text(this.blockedText)
        .fontSize(11)
        .fontColor(TC.textTertiary())
        .textAlign(TextAlign.Center)
        .padding({ left: 40, right: 40 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private RowsList() {
    List() {
      ForEach(this.rows, (row: RelationRow) => {
        ListItem() {
          Row({ space: 12 }) {
            this.RowAvatar(row)
            Column({ space: 4 }) {
              Row({ space: 5 }) {
                Text(row.nickname)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TC.textBody())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '60%' })
                if (row.isArtist) {
                  Text('歌手')
                    .fontSize(8)
                    .fontColor(TC.accentSoft())
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                    .border({ width: 1, color: TC.accentSoft() })
                    .borderRadius(4)
                }
                if (row.fansGroupId.length > 0) {
                  this.FanClubChip(row)
                }
              }
              .width('100%')

              if (row.bubbleMessage.length > 0) {
                this.ContentBubble(row)
              } else if (row.showMessage.length > 0) {
                Text(row.showMessage)
                  .fontSize(10)
                  .fontColor(TC.textTertiary())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              } else if (row.subtitle.length > 0) {
                Text(row.subtitle)
                  .fontSize(10)
                  .fontColor(TC.textTertiary())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .onClick(() => this.openRow(row))

            this.RelationButton(row)
          }
          .width('100%')
          .constraintSize({ minHeight: 72 })
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        }
      }, (row: RelationRow) => this.rowKey(row))

      ListItem() {
        Row() {
          if (this.loading) {
            LoadingProgress().width(24).height(24).color(TC.accent())
          } else {
            Text(this.more ? '继续上滑加载' : '已经到底了')
              .fontSize(11)
              .fontColor(TC.textQuaternary())
          }
        }
        .width('100%')
        .height(54)
        .justifyContent(FlexAlign.Center)
      }
    }
    .layoutWeight(1)
    .onReachEnd(() => this.loadMore())
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Stack() {
        Column() {
          Column().width('100%').height(this.topAvoidHeight)
          // 场景筛选叠在右侧，标题仍在整行居中
          Stack({ alignContent: Alignment.End }) {
            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(24)
                .fontColor([TC.textPrimary()])
                .onClick(() => this.pageStack.pop())
              Text(this.pageParam.title)
                .layoutWeight(1)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(TC.textPrimary())
                .textAlign(TextAlign.Center)
              Column().width(24)
            }
            .height(56)
            .width('100%')
            .padding({ left: 16, right: 16 })

            if (this.isMixedMode()) {
              this.SceneChips()
            }
          }
          .height(56)
          .width('100%')
          .padding({ right: this.isMixedMode() ? 16 : 0 })

          if (!this.authStore.loggedIn && !this.isArtistFans()) {
            Column({ space: 14 }) {
              Text('登录后才能查看关系列表').fontSize(13).fontColor(TC.textTertiary())
              Button('去登录')
                .fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
                .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.blocked) {
            this.BlockedState()
          } else if (this.rows.length === 0 && this.loading) {
            LoadingProgress().layoutWeight(1).width(46).color(TC.accent())
          } else if (this.rows.length === 0) {
            Column({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.person_2_fill'))
                .fontSize(44).fontColor([TC.textQuaternary()])
              Text(this.message || '这里还没有用户').fontSize(13).fontColor(TC.textTertiary())
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            this.RowsList()
          }

          if (this.message && this.rows.length > 0) {
            Text(this.message)
              .width('100%').fontSize(11).fontColor(TC.accentSoft()).textAlign(TextAlign.Center)
              .padding({ bottom: 8 })
          }
        }
        .width('100%').height('100%').backgroundColor(TC.pageBackground())

        if (this.confirmVisible) {
          this.CancelSheet()
        }
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
  }
}
