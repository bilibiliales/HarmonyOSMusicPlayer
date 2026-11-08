import {
  ArtistFanItem,
  ArtistFanProfile,
  ArtistFansResponse,
  OperationResponse,
  SocialUser,
  UserFollowedsResponse,
  UserFollowsResponse,
  UserProfilePageParam
} from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'
import { TC } from '../services/ThemeColors'

export interface RelationshipPageParam {
  type: string
  title: string
  uid?: string
}

@Component
export struct RelationshipListPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: RelationshipPageParam = { type: 'following', title: '关注' }

  @State users: SocialUser[] = []
  @State loading: boolean = false
  @State more: boolean = true
  @State pageOffset: number = 0
  @State message: string = ''
  @State confirmVisible: boolean = false
  @State selectedUser: SocialUser | null = null
  private readonly pageSize: number = 20

  private isArtistFans(): boolean {
    return this.pageParam.type === 'artistFans'
  }

  private targetUid(): string {
    return this.pageParam.uid || this.authStore.userId
  }

  /** /artist/fans 的 userProfile → 列表通用的 SocialUser。 */
  private mapArtistFan(item: ArtistFanItem): SocialUser | null {
    const profile: ArtistFanProfile | undefined = item.userProfile
    if (!profile || !profile.userId) {
      return null
    }
    return {
      userId: profile.userId,
      nickname: profile.nickname || '',
      avatarUrl: profile.avatarUrl || '',
      signature: profile.signature || '',
      followed: profile.followed === true,
      mutual: profile.mutual === true,
      follows: profile.follows,
      followeds: profile.followeds,
      userType: profile.userType,
      authStatus: profile.authStatus
    }
  }

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
        const response = await ApiClient.get<ArtistFansResponse>('/artist/fans', [
          { key: 'id', value: this.targetUid() },
          { key: 'limit', value: this.pageSize.toString() },
          { key: 'offset', value: this.pageOffset.toString() }
        ])
        if (response.code === 200) {
          const raw: ArtistFanItem[] = response.data || []
          const incoming: SocialUser[] = []
          raw.forEach((item: ArtistFanItem) => {
            const user = this.mapArtistFan(item)
            if (user) {
              incoming.push(user)
            }
          })
          this.users = [...this.users, ...incoming]
          this.pageOffset += raw.length
          // 该接口不返回 more，按整页推断
          this.more = raw.length >= this.pageSize
        }
      } else if (this.pageParam.type === 'following') {
        const response = await ApiClient.get<UserFollowsResponse>('/user/follows', [
          { key: 'uid', value: this.targetUid() },
          { key: 'limit', value: this.pageSize.toString() },
          { key: 'offset', value: this.pageOffset.toString() }
        ])
        if (response.code === 200) {
          const incoming = response.follow || []
          if (this.isOwnRelationshipList()) {
            incoming.forEach((user: SocialUser) => user.followed = true)
          }
          this.users = [...this.users, ...incoming]
          this.pageOffset += incoming.length
          this.more = response.more
        }
      } else {
        const response = await ApiClient.get<UserFollowedsResponse>('/user/followeds', [
          { key: 'uid', value: this.targetUid() },
          { key: 'limit', value: this.pageSize.toString() },
          { key: 'offset', value: this.pageOffset.toString() }
        ])
        if (response.code === 200) {
          const incoming = response.followeds || []
          this.users = [...this.users, ...incoming]
          this.pageOffset += incoming.length
          this.more = response.more
        }
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '列表加载失败'
    } finally {
      this.loading = false
    }
  }

  private isOwnRelationshipList(): boolean {
    return !this.isArtistFans() && this.targetUid() === this.authStore.userId
  }

  private isFollowing(user: SocialUser): boolean {
    return user.followed || user.mutual
  }

  private relationClick(user: SocialUser): void {
    if (this.isFollowing(user)) {
      this.selectedUser = user
      this.confirmVisible = true
    } else {
      this.follow(user)
    }
  }

  private openUserProfile(user: SocialUser): void {
    const param: UserProfilePageParam = { uid: user.userId.toString() }
    if (this.isOwnRelationshipList()) {
      if (this.pageParam.type === 'following') {
        param.followsTarget = true
        param.followedByTarget = user.mutual
      } else {
        param.followsTarget = this.isFollowing(user)
        param.followedByTarget = true
      }
    }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private async follow(user: SocialUser): Promise<void> {
    try {
      const response = await ApiClient.get<OperationResponse>('/follow', [
        { key: 'id', value: user.userId.toString() },
        { key: 't', value: '1' }
      ])
      if (response.code === 200) {
        user.followed = true
        if (this.isOwnRelationshipList() && this.pageParam.type === 'followers') {
          user.mutual = true
        }
        this.users = this.users.map((item: SocialUser) => item)
      } else {
        this.message = response.message || '关注失败'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '关注失败'
    }
  }

  private relationText(user: SocialUser): string {
    if (user.mutual) {
      return '互相关注'
    }
    if (this.isFollowing(user)) {
      return '已关注'
    }
    return '关注'
  }

  private async cancelFollow(): Promise<void> {
    if (!this.selectedUser) {
      return
    }
    const userId = this.selectedUser.userId
    try {
      const response = await ApiClient.get<OperationResponse>('/follow', [
        { key: 'id', value: userId.toString() },
        { key: 't', value: '0' }
      ])
      if (response.code === 200) {
        if (this.pageParam.type === 'following') {
          this.users = this.users.filter((item: SocialUser) => item.userId !== userId)
        } else {
          this.users = this.users.map((item: SocialUser) => {
            if (item.userId === userId) {
              item.followed = false
              item.mutual = false
            }
            return item
          })
        }
        this.confirmVisible = false
        this.selectedUser = null
      } else {
        this.message = response.message || '取消关注失败'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '取消关注失败'
    }
  }

  @Builder
  private RelationButton(user: SocialUser) {
    Text(this.relationText(user))
      .width(76)
      .height(32)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isFollowing(user) ? TC.accent() : TC.textOnAccent())
      .textAlign(TextAlign.Center)
      .backgroundColor(this.isFollowing(user) ? '#00ffffff' : TC.accent())
      .borderRadius(16)
      .border({ width: this.isFollowing(user) ? 1 : 0, color: TC.accent() })
      .onClick(() => this.relationClick(user))
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
          Text('取消关注')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary())
          Text(`确定不再关注「${this.selectedUser?.nickname || ''}」吗？`)
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

  build() {
    NavDestination() {
      Stack() {
        Column() {
          Column().width('100%').height(this.topAvoidHeight)
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

          if (!this.authStore.loggedIn && !this.isArtistFans()) {
            Column({ space: 14 }) {
              Text('登录后才能查看关系列表').fontSize(13).fontColor(TC.textTertiary())
              Button('去登录')
                .fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
                .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.users.length === 0 && this.loading) {
            LoadingProgress().layoutWeight(1).width(46).color(TC.accent())
          } else if (this.users.length === 0) {
            Column({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.person_2_fill'))
                .fontSize(44).fontColor([TC.textQuaternary()])
              Text(this.message || '这里还没有用户').fontSize(13).fontColor(TC.textTertiary())
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List() {
              ForEach(this.users, (user: SocialUser) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Stack({ alignContent: Alignment.BottomEnd }) {
                      Image(user.avatarUrl)
                        .width(50).height(50).borderRadius(18).objectFit(ImageFit.Cover)
                      if (user.userType === 4) {
                        Image($r('app.media.ic_singer'))
                          .width(18).height(18).borderRadius(9)
                      }
                    }
                    .width(50).height(50)
                    .onClick(() => this.openUserProfile(user))
                    Column({ space: 5 }) {
                      Text(user.nickname)
                        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(TC.textBody()).maxLines(1)
                      Text(user.signature || `${user.follows || 0} 关注 · ${user.followeds || 0} 粉丝`)
                        .fontSize(10).fontColor(TC.textTertiary()).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .onClick(() => this.openUserProfile(user))
                    this.RelationButton(user)
                  }
                  .height(72)
                  .padding({ left: 16, right: 16 })
                }
              })
              ListItem() {
                Row() {
                  if (this.loading) {
                    LoadingProgress().width(24).height(24).color(TC.accent())
                  } else {
                    Text(this.more ? '继续上滑加载' : '已经到底了')
                      .fontSize(11).fontColor(TC.textQuaternary())
                  }
                }
                .width('100%').height(54).justifyContent(FlexAlign.Center)
              }
            }
            .layoutWeight(1)
            .onReachEnd(() => this.loadMore())
          }

          if (this.message && this.users.length > 0) {
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
