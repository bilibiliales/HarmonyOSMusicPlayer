import {
  OperationResponse,
  SocialUser,
  UserFollowedsResponse,
  UserFollowsResponse,
  UserProfilePageParam
} from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'

export interface RelationshipPageParam {
  type: string
  title: string
  uid?: string
}

@Component
export struct RelationshipListPage {
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

  private targetUid(): string {
    return this.pageParam.uid || this.authStore.userId
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
      if (this.pageParam.type === 'following') {
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
    return this.targetUid() === this.authStore.userId
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
      .fontColor(this.isFollowing(user) ? '#ef233c' : '#ffffff')
      .textAlign(TextAlign.Center)
      .backgroundColor(this.isFollowing(user) ? '#00ffffff' : '#ef233c')
      .borderRadius(16)
      .border({ width: this.isFollowing(user) ? 1 : 0, color: '#ef233c' })
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
            .fontColor('#ffffff')
          Text(`确定不再关注「${this.selectedUser?.nickname || ''}」吗？`)
            .fontSize(13)
            .fontColor('#92929a')
            .textAlign(TextAlign.Center)
        }
        Row({ space: 12 }) {
          Button('暂不取消')
            .layoutWeight(1)
            .height(46)
            .fontColor('#d6d6da')
            .backgroundColor('#2a2a30')
            .borderRadius(23)
            .onClick(() => this.confirmVisible = false)
          Button('取消关注')
            .layoutWeight(1)
            .height(46)
            .fontColor('#ffffff')
            .backgroundColor('#ef233c')
            .borderRadius(23)
            .onClick(() => this.cancelFollow())
        }
      }
      .width('100%')
      .height('34%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 24, right: 24, bottom: 18 })
      .backgroundColor('#19191f')
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
              .fontColor(['#ffffff'])
              .onClick(() => this.pageStack.pop())
            Text(this.pageParam.title)
              .layoutWeight(1)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#ffffff')
              .textAlign(TextAlign.Center)
            Column().width(24)
          }
          .height(56)
          .width('100%')
          .padding({ left: 16, right: 16 })

          if (!this.authStore.loggedIn) {
            Column({ space: 14 }) {
              Text('登录后才能查看关系列表').fontSize(13).fontColor('#77777f')
              Button('去登录')
                .fontColor('#ffffff').backgroundColor('#ef233c')
                .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.users.length === 0 && this.loading) {
            LoadingProgress().layoutWeight(1).width(46).color('#ef233c')
          } else if (this.users.length === 0) {
            Column({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.person_2_fill'))
                .fontSize(44).fontColor(['#55555d'])
              Text(this.message || '这里还没有用户').fontSize(13).fontColor('#77777f')
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
                        .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#ededf0').maxLines(1)
                      Text(user.signature || `${user.follows || 0} 关注 · ${user.followeds || 0} 粉丝`)
                        .fontSize(10).fontColor('#77777f').maxLines(1)
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
                    LoadingProgress().width(24).height(24).color('#ef233c')
                  } else {
                    Text(this.more ? '继续上滑加载' : '已经到底了')
                      .fontSize(11).fontColor('#66666e')
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
              .width('100%').fontSize(11).fontColor('#ff6577').textAlign(TextAlign.Center)
              .padding({ bottom: 8 })
          }
        }
        .width('100%').height('100%').backgroundColor('#121215')

        if (this.confirmVisible) {
          this.CancelSheet()
        }
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
  }
}
