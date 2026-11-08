import { common } from '@kit.AbilityKit'
import { SystemShareService, NearbyShareSession } from '../services/SystemShareService'
import {
  MsgRecentContactResponse,
  MsgRecentContactUser,
  PrivateChatPageParam,
  SharePageParam,
  ShareResourceResponse
} from '../models/api'
import { BubbleTip } from '../services/BubbleTip'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'
import { TC } from '../services/ThemeColors'

@Component
export struct ShareSheet {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('authStore') authStore: AuthStore
  @Prop shareParam: SharePageParam = { type: 'song', id: '', name: '', img: '' }
  @Prop visible: boolean = false
  @State shareMessage: string = ''
  @State sendingToDynamic: boolean = false
  @State contactsVisible: boolean = false
  @State contacts: MsgRecentContactUser[] = []
  @State contactsLoading: boolean = false
  @State preparingSystemShare: boolean = false
  private nearbyShare: NearbyShareSession = new NearbyShareSession()
  onClose: () => void = () => {}
  onShared: () => void = () => {}

  aboutToAppear(): void {
    this.nearbyShare.activate(() => SystemShareService.linkRecords(SystemShareService.musicLink(this.shareParam)))
  }

  aboutToDisappear(): void { this.nearbyShare.deactivate() }

  private async shareSystem(): Promise<void> {
    if (this.preparingSystemShare) { return }
    this.preparingSystemShare = true
    this.shareMessage = ''
    try {
      await SystemShareService.showLink(this.getUIContext().getHostContext() as common.UIAbilityContext,
        SystemShareService.musicLink(this.shareParam))
    } catch (error) {
      this.shareMessage = error instanceof Error ? error.message : '无法打开系统分享面板'
    } finally { this.preparingSystemShare = false }
  }

  private async shareToDynamic(): Promise<void> {
    if (this.sendingToDynamic) { return }
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.sendingToDynamic = true
    const userId = this.authStore.userId
    this.shareMessage = ''
    try {
      const response = this.shareParam.type === 'event' ?
        await ApiClient.get<ShareResourceResponse>('/event/forward', [
          { key: 'evId', value: this.shareParam.id },
          { key: 'uid', value: this.shareParam.eventUserId || '' },
          { key: 'forwards', value: '转发动态' }
        ]) : await ApiClient.get<ShareResourceResponse>('/share/resource', [
        { key: 'type', value: this.shareParam.type },
        { key: 'id', value: this.shareParam.id },
        { key: 'msg', value: '' }
      ])
      if (userId !== this.authStore.userId) { return }
      if (response.code === 200) {
        this.shareMessage = '已分享到动态'
        this.onShared()
        BubbleTip.show(this.getUIContext(), '已分享到动态')
        this.onClose()
      } else {
        this.shareMessage = response.message || '分享到动态失败'
      }
    } catch (error) {
      this.shareMessage = error instanceof Error ? error.message : '分享到动态失败'
    } finally {
      this.sendingToDynamic = false
    }
  }

  private async loadContacts(): Promise<void> {
    if (this.contactsLoading || this.contacts.length > 0) {
      return
    }
    this.contactsLoading = true
    try {
      const response = await ApiClient.get<MsgRecentContactResponse>('/msg/recentcontact', [])
      if (response.code === 200 && response.data?.follow) {
        this.contacts = response.data.follow
      }
    } catch (_error) {
    } finally {
      this.contactsLoading = false
    }
  }

  private openContacts(): void {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.contactsVisible = true
    this.shareMessage = ''
    this.loadContacts()
  }

  private selectContact(user: MsgRecentContactUser): void {
    const uid = (user.userId || 0).toString()
    const nickname = user.nickname || ''
    const avatarUrl = user.avatarUrl || ''
    const link = SystemShareService.musicLink(this.shareParam)
    const shareMsg = `分享${link.label}「${this.shareParam.name}」\n${link.url}`
    const chatParam: PrivateChatPageParam = {
      uid: uid,
      nickname: nickname,
      avatarUrl: avatarUrl,
      shareMsg: shareMsg,
      shareType: this.shareParam.type,
      shareId: this.shareParam.id
    }
    this.onClose()
    this.pageStack.pushPathByName('PrivateChatPage', chatParam)
  }

  @Builder
  private ShareOption(icon: Resource, title: string, onClick: () => void) {
    Column({ space: 8 }) {
      Stack() {
        SymbolGlyph(icon).fontSize(22).fontColor([TC.textPrimary()])
      }
      .width(52).height(52).borderRadius(14).backgroundColor(TC.surfaceRaised())
      .alignContent(Alignment.Center)
      Text(title).fontSize(11).fontColor(TC.textBody())
    }
    .onClick(onClick)
  }

  @Builder
  private ContactItem(user: MsgRecentContactUser) {
    Row({ space: 10 }) {
      Image(user.avatarUrl || '').width(40).height(40).borderRadius(20).objectFit(ImageFit.Cover)
      Column({ space: 3 }) {
        Text(user.nickname || '').fontSize(13).fontColor(TC.textBody()).maxLines(1)
        if (user.mutual) {
          Text('互相关注').fontSize(10).fontColor(TC.textTertiary())
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([TC.textQuaternary()])
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
    .onClick(() => this.selectContact(user))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.58)')
        .onClick(() => this.onClose())
      Column({ space: 16 }) {
        Row() {
          Column({ space: 4 }) {
            Text(`分享「${this.shareParam.name}」`).fontSize(16).fontWeight(FontWeight.Bold).fontColor(
              TC.textPrimary()).maxLines(2)
            Text('选择分享方式').fontSize(11).fontColor(TC.textTertiary())
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor([TC.textQuaternary()])
            .onClick(() => this.onClose())
        }
        .width('100%').padding({ left: 20, right: 20, top: 18, bottom: 4 })

        if (this.contactsVisible) {
          Column({ space: 10 }) {
            if (this.contactsLoading) {
              Row() {
                LoadingProgress().width(24).height(24).color(TC.accent())
                Text('加载联系人…').fontSize(12).fontColor(TC.textTertiary()).margin({ left: 8 })
              }
              .width('100%').justifyContent(FlexAlign.Center).padding({ top: 16, bottom: 16 })
            } else if (this.contacts.length > 0) {
              Text('选择联系人发起私信').fontSize(12).fontColor(TC.textSecondary()).width('100%').padding({ left: 20 })
              List({ space: 0 }) {
                ForEach(this.contacts, (user: MsgRecentContactUser) => {
                  ListItem() {
                    this.ContactItem(user)
                  }
                })
              }
              .width('100%')
              .height(280)
              .scrollBar(BarState.Off)
            } else {
              Text('暂无联系人').fontSize(12).fontColor(TC.textTertiary()).width('100%')
                .textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
            }
            Button('返回').width('100%').backgroundColor(TC.surfaceRaised()).fontColor(TC.textBody())
              .onClick(() => { this.contactsVisible = false })
          }
          .width('100%').padding({ left: 20, right: 20 })
        } else {
          Row({ space: 16 }) {
            this.ShareOption($r('sys.symbol.share'), this.preparingSystemShare ? '准备分享…' : '系统分享', () => this.shareSystem())
            this.ShareOption($r('sys.symbol.ellipsis_bubble'), '私信分享', () => this.openContacts())
            if (SystemShareService.canShareToDynamic(this.shareParam)) {
              this.ShareOption($r('sys.symbol.textformat'), '动态分享', () => this.shareToDynamic())
            }
          }
          .width('100%').justifyContent(FlexAlign.Center).padding({ left: 20, right: 20 })
          Text('支持的设备可在此碰一碰分享或隔空传送')
            .fontSize(11).fontColor(TC.textSecondary()).margin({ top: 12 })
        }

        if (this.shareMessage) {
          Text(this.shareMessage).width('100%').fontSize(12)
            .fontColor(this.shareMessage.includes('已') ? '#4caf50' : '#ff6577')
            .textAlign(TextAlign.Center).padding({ bottom: 8 })
        }
      }
      .width('100%')
      .backgroundColor(TC.surfaceCard())
      .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 0, bottomRight: 0 })
      .padding({ bottom: 28 })
      .transition(TransitionEffect.translate({ y: 400 }).animation({ duration: 260, curve: Curve.EaseOut }))
    }
    .width('100%').height('100%')
  }
}
