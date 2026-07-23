import {
  ApiParam,
  ApiUser,
  MsgCommentNotification,
  MsgCommentsResponse,
  MsgNoticeItem,
  MsgNoticesResponse,
  MsgPrivateConversation,
  MsgPrivateListResponse,
  PrivateChatPageParam,
  SocialUser,
  UserProfilePageParam
} from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'

interface PrivateMessageBody {
  msg?: string
  pushMsg?: string
  title?: string
  type?: number
  generalMsg?: PrivateGeneralMessage
}

interface PrivateGeneralMessage {
  title?: string
  subTitle?: string
  inboxBriefContent?: string
  cover?: string
}

interface ResourceMessageInfo {
  name?: string
  creator?: string
}

interface NoticeGeneralInfo {
  actionDesc?: string
  content?: string
}

interface NoticePayload {
  generalNotice?: NoticeGeneralInfo
  user?: ApiUser
  track?: object
  type?: number
}

interface NoticeDisplay {
  title: string
  content: string
  user?: ApiUser
}

@Component
export struct MessageCenterPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore

  @State currentTab: string = 'private'
  @State conversations: MsgPrivateConversation[] = []
  @State commentMessages: MsgCommentNotification[] = []
  @State notices: MsgNoticeItem[] = []
  @State loading: boolean = false
  @State more: boolean = true
  @State message: string = ''
  private privateOffset: number = 0
  private commentsBefore: number = 0
  private noticeLastTime: number = -1
  private readonly pageSize: number = 30

  aboutToAppear(): void {
    if (this.authStore.loggedIn) {
      this.loadCurrentTab()
    }
  }

  private switchTab(tab: string): void {
    this.currentTab = tab
    this.more = true
    this.message = ''
    if ((tab === 'private' && this.conversations.length === 0) ||
      (tab === 'comments' && this.commentMessages.length === 0) ||
      (tab === 'notices' && this.notices.length === 0)) {
      this.loadCurrentTab()
    }
  }

  private async loadCurrentTab(reset: boolean = false): Promise<void> {
    if (this.currentTab === 'private') {
      await this.loadPrivateMessages(reset)
    } else if (this.currentTab === 'comments') {
      await this.loadComments(reset)
    } else {
      await this.loadNotices(reset)
    }
  }

  private async loadPrivateMessages(reset: boolean = false): Promise<void> {
    if (this.loading || (!this.more && !reset) || !this.authStore.loggedIn) {
      return
    }
    if (reset) {
      this.conversations = []
      this.privateOffset = 0
      this.more = true
    }
    this.loading = true
    this.message = ''
    try {
      const response = await ApiClient.get<MsgPrivateListResponse>('/msg/private', [
        { key: 'limit', value: this.pageSize.toString() },
        { key: 'offset', value: this.privateOffset.toString() },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code === 200) {
        const incoming = response.msgs || []
        this.conversations = this.conversations.concat(incoming)
        this.privateOffset += incoming.length
        this.more = response.more !== undefined ? response.more : incoming.length >= this.pageSize
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '私信加载失败'
    } finally {
      this.loading = false
    }
  }

  private async loadComments(reset: boolean = false): Promise<void> {
    if (this.loading || (!this.more && !reset) || !this.authStore.loggedIn) {
      return
    }
    if (reset) {
      this.commentMessages = []
      this.commentsBefore = 0
      this.more = true
    }
    this.loading = true
    this.message = ''
    try {
      const params: ApiParam[] = [
        { key: 'uid', value: this.authStore.userId },
        { key: 'limit', value: this.pageSize.toString() },
        { key: 'timestamp', value: Date.now().toString() }
      ]
      if (this.commentsBefore > 0) {
        params.push({ key: 'before', value: this.commentsBefore.toString() })
      }
      const response = await ApiClient.get<MsgCommentsResponse>('/msg/comments', params)
      if (response.code === 200) {
        const incoming = response.comments || []
        this.commentMessages = this.commentMessages.concat(incoming)
        if (incoming.length > 0) {
          this.commentsBefore = incoming[incoming.length - 1].time
        }
        this.more = response.more !== undefined ? response.more : incoming.length >= this.pageSize
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '评论通知加载失败'
    } finally {
      this.loading = false
    }
  }

  private async loadNotices(reset: boolean = false): Promise<void> {
    if (this.loading || (!this.more && !reset) || !this.authStore.loggedIn) {
      return
    }
    if (reset) {
      this.notices = []
      this.noticeLastTime = -1
      this.more = true
    }
    this.loading = true
    this.message = ''
    try {
      const response = await ApiClient.get<MsgNoticesResponse>('/msg/notices', [
        { key: 'limit', value: this.pageSize.toString() },
        { key: 'lasttime', value: this.noticeLastTime.toString() },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code === 200) {
        const incoming = response.notices || []
        this.notices = this.notices.concat(incoming)
        if (incoming.length > 0) {
          this.noticeLastTime = response.lasttime || incoming[incoming.length - 1].time
        }
        this.more = response.more !== undefined ? response.more : incoming.length >= this.pageSize
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '通知加载失败'
    } finally {
      this.loading = false
    }
  }

  private formatTime(value: number): string {
    if (value <= 0) {
      return ''
    }
    const elapsed = Date.now() - value
    if (elapsed < 60000) {
      return '刚刚'
    }
    if (elapsed < 3600000) {
      return `${Math.floor(elapsed / 60000)}分钟前`
    }
    if (elapsed < 86400000) {
      return `${Math.floor(elapsed / 3600000)}小时前`
    }
    const date = new Date(value)
    return `${date.getMonth() + 1}-${date.getDate()}`
  }

  private privatePreview(raw: string): string {
    try {
      const data = JSON.parse(raw) as PrivateMessageBody
      if (data.generalMsg) {
        return data.generalMsg.inboxBriefContent || data.generalMsg.title || data.pushMsg || '活动消息'
      }
      return data.msg || data.pushMsg || data.title || '分享了一条消息'
    } catch (_error) {
      return raw || '新消息'
    }
  }

  private resourceName(raw: string | undefined): string {
    if (!raw) {
      return ''
    }
    try {
      const resource = JSON.parse(raw) as ResourceMessageInfo
      return resource.name || ''
    } catch (_error) {
      return ''
    }
  }

  private noticeDisplay(item: MsgNoticeItem): NoticeDisplay {
    try {
      const data = JSON.parse(item.notice) as NoticePayload
      if (data.generalNotice) {
        return {
          title: data.generalNotice.actionDesc || '系统通知',
          content: data.generalNotice.content || item.pushMsg || '',
          user: data.user
        }
      }
      return { title: '动态通知', content: item.pushMsg || '你的动态有了新的互动', user: data.user }
    } catch (_error) {
      return { title: '系统通知', content: item.pushMsg || item.notice }
    }
  }

  private otherUser(item: MsgPrivateConversation): SocialUser {
    return item.fromUser.userId.toString() === this.authStore.userId ? item.toUser : item.fromUser
  }

  private openChat(item: MsgPrivateConversation): void {
    const user = this.otherUser(item)
    const param: PrivateChatPageParam = {
      uid: user.userId.toString(),
      nickname: user.nickname,
      avatarUrl: user.avatarUrl
    }
    this.pageStack.pushPathByName('PrivateChatPage', param)
  }

  private openUser(userId: number): void {
    if (userId <= 0) {
      return
    }
    const param: UserProfilePageParam = { uid: userId.toString() }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  @Builder
  private TabsHeader() {
    Row() {
      ForEach(['private', 'comments', 'notices'], (tab: string) => {
        Column({ space: 7 }) {
          Text(tab === 'private' ? '私信' : tab === 'comments' ? '评论' : '通知')
            .fontSize(14).fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.currentTab === tab ? '#ffffff' : '#77777f')
          Column().width(24).height(3).borderRadius(2)
            .backgroundColor(this.currentTab === tab ? '#ef233c' : 'transparent')
        }
        .layoutWeight(1).height(46).justifyContent(FlexAlign.Center).onClick(() => this.switchTab(tab))
      })
    }
    .width('100%').backgroundColor('#17171c')
  }

  @Builder
  private PrivateList() {
    List() {
      ForEach(this.conversations, (item: MsgPrivateConversation) => {
        ListItem() {
          Row({ space: 12 }) {
            Stack({ alignContent: Alignment.TopEnd }) {
              Image(this.otherUser(item).avatarUrl).width(52).height(52).borderRadius(18).objectFit(ImageFit.Cover)
              if ((item.newMsgCount || 0) > 0) {
                Text(item.newMsgCount > 99 ? '99+' : item.newMsgCount.toString())
                  .fontSize(8).fontColor('#ffffff').padding({ left: 5, right: 5, top: 2, bottom: 2 })
                  .borderRadius(9).backgroundColor('#ef233c')
              }
            }
            .width(52).height(52)
            Column({ space: 6 }) {
              Row() {
                Text(this.otherUser(item).nickname).layoutWeight(1).fontSize(14)
                  .fontWeight(FontWeight.Medium).fontColor('#ededf0').maxLines(1)
                Text(this.formatTime(item.lastMsgTime)).fontSize(9).fontColor('#66666e')
              }
              Text(this.privatePreview(item.lastMsg)).width('100%').fontSize(11).fontColor('#85858e')
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .onClick(() => this.openChat(item))
        }
      })
      this.LoadMoreItem()
    }
    .layoutWeight(1).onReachEnd(() => this.loadPrivateMessages())
  }

  @Builder
  private CommentsList() {
    List() {
      ForEach(this.commentMessages, (item: MsgCommentNotification) => {
        ListItem() {
          Row({ space: 11 }) {
            Image(item.user.avatarUrl).width(44).height(44).borderRadius(16).objectFit(ImageFit.Cover)
              .onClick(() => this.openUser(item.user.userId))
            Column({ space: 6 }) {
              Row() {
                Text(item.user.nickname).layoutWeight(1).fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor('#ededf0').maxLines(1)
                Text(this.formatTime(item.time)).fontSize(9).fontColor('#66666e')
              }
              Text(item.content || '回复了你的评论').fontSize(12).lineHeight(18).fontColor('#c5c5cb').maxLines(3)
              if (item.beRepliedContent || this.resourceName(item.resourceJson)) {
                Text(item.beRepliedContent || this.resourceName(item.resourceJson)).width('100%')
                  .fontSize(10).fontColor('#77777f').maxLines(2)
                  .padding(9).backgroundColor('#25252b').borderRadius(9)
              }
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })
        }
      })
      this.LoadMoreItem()
    }
    .layoutWeight(1).onReachEnd(() => this.loadComments())
  }

  @Builder
  private NoticesList() {
    List() {
      ForEach(this.notices, (item: MsgNoticeItem) => {
        ListItem() {
          Row({ space: 11 }) {
            if (this.noticeDisplay(item).user?.avatarUrl) {
              Image(this.noticeDisplay(item).user?.avatarUrl || '').width(44).height(44)
                .borderRadius(16).objectFit(ImageFit.Cover)
                .onClick(() => this.openUser(this.noticeDisplay(item).user?.userId || 0))
            } else {
              Stack() {
                SymbolGlyph($r('sys.symbol.bell_fill')).fontSize(21).fontColor(['#ffffff'])
              }
              .width(44).height(44).borderRadius(16).backgroundColor('#ef233c')
            }
            Column({ space: 6 }) {
              Row() {
                Text(this.noticeDisplay(item).title).layoutWeight(1).fontSize(13)
                  .fontWeight(FontWeight.Medium).fontColor('#ededf0').maxLines(1)
                Text(this.formatTime(item.time)).fontSize(9).fontColor('#66666e')
              }
              Text(this.noticeDisplay(item).content).width('100%').fontSize(11).lineHeight(18)
                .fontColor('#9d9da5').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })
        }
      })
      this.LoadMoreItem()
    }
    .layoutWeight(1).onReachEnd(() => this.loadNotices())
  }

  @Builder
  private LoadMoreItem() {
    ListItem() {
      Row() {
        if (this.loading) {
          LoadingProgress().width(24).height(24).color('#ef233c')
        } else {
          Text(this.more ? '继续上滑加载' : '已经到底了').fontSize(10).fontColor('#66666e')
        }
      }
      .width('100%').height(52).justifyContent(FlexAlign.Center)
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('消息中心').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor(['#888890'])
            .onClick(() => this.loadCurrentTab(true))
        }
        .width('100%').height(56).padding({ left: 16, right: 16 })
        this.TabsHeader()

        if (!this.authStore.loggedIn) {
          Column({ space: 13 }) {
            SymbolGlyph($r('sys.symbol.envelope_fill')).fontSize(42).fontColor(['#55555d'])
            Text('登录后查看消息中心').fontSize(13).fontColor('#77777f')
            Button('去登录').fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
              .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.loading && this.conversations.length === 0 && this.commentMessages.length === 0 &&
          this.notices.length === 0) {
          LoadingProgress().layoutWeight(1).width(44).color('#ef233c')
        } else if (this.currentTab === 'private') {
          if (this.conversations.length > 0) {
            this.PrivateList()
          } else {
            Text(this.message || '暂无私信').layoutWeight(1).fontSize(13).fontColor('#77777f')
          }
        } else if (this.currentTab === 'comments') {
          if (this.commentMessages.length > 0) {
            this.CommentsList()
          } else {
            Text(this.message || '暂无评论通知').layoutWeight(1).fontSize(13).fontColor('#77777f')
          }
        } else {
          if (this.notices.length > 0) {
            this.NoticesList()
          } else {
            Text(this.message || '暂无通知').layoutWeight(1).fontSize(13).fontColor('#77777f')
          }
        }
      }
      .width('100%').height('100%').backgroundColor('#121215')
    }
    .hideTitleBar(true)
  }
}
