import { common } from '@kit.AbilityKit'
import { systemShare } from '@kit.ShareKit'
import {
  MsgRecentContactResponse,
  MsgRecentContactUser,
  PrivateChatPageParam,
  SharePageParam,
  ShareResourceResponse
} from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'

@Component
export struct ShareSheet {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('authStore') authStore: AuthStore
  @Prop shareParam: SharePageParam = { type: 'song', id: '', name: '', img: '' }
  @Prop visible: boolean = false
  @State shareMessage: string = ''
  @State sendingToDynamic: boolean = false
  @State contactsVisible: boolean = false
  @State contacts: MsgRecentContactUser[] = []
  @State contactsLoading: boolean = false
  onClose: () => void = () => {}

  private async shareSystem(): Promise<void> {
    try {
      const typeLabel = this.shareParam.type === 'song' ? '歌曲' : this.shareParam.type === 'playlist' ? '歌单' : '专辑'
      const typePath = this.shareParam.type === 'playlist' ? 'playlist' : this.shareParam.type === 'album' ? 'album' : 'song'
      const record: systemShare.SharedRecord = {
        utd: 'general.plain-text',
        title: this.shareParam.name,
        content: `分享${typeLabel}「${this.shareParam.name}」\nhttps://music.163.com/${typePath}?id=${this.shareParam.id}`
      }
      const data = new systemShare.SharedData(record)
      const controller = new systemShare.ShareController(data)
      const options: systemShare.ShareControllerOptions = {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      }
      await controller.show(this.getUIContext().getHostContext() as common.UIAbilityContext, options)
    } catch (error) {
      this.shareMessage = error instanceof Error ? error.message : '无法打开系统分享面板'
    }
  }

  private async shareToDynamic(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.sendingToDynamic = true
    this.shareMessage = ''
    try {
      const response = await ApiClient.get<ShareResourceResponse>('/share/resource', [
        { key: 'type', value: this.shareParam.type },
        { key: 'id', value: this.shareParam.id },
        { key: 'msg', value: '' }
      ])
      if (response.code === 200) {
        this.shareMessage = '已分享到动态'
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
    const typeLabel = this.shareParam.type === 'song' ? '单曲' : this.shareParam.type === 'playlist' ? '歌单' : '专辑'
    const typePath = this.shareParam.type === 'playlist' ? 'playlist' : this.shareParam.type === 'album' ? 'album' : 'song'
    const shareMsg = `分享${typeLabel}「${this.shareParam.name}」\nhttps://music.163.com/${typePath}?id=${this.shareParam.id}`
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
        SymbolGlyph(icon).fontSize(22).fontColor(['#ffffff'])
      }
      .width(52).height(52).borderRadius(14).backgroundColor('#2a2a30')
      .alignContent(Alignment.Center)
      Text(title).fontSize(11).fontColor('#b5b5bc')
    }
    .onClick(onClick)
  }

  @Builder
  private ContactItem(user: MsgRecentContactUser) {
    Row({ space: 10 }) {
      Image(user.avatarUrl || '').width(40).height(40).borderRadius(20).objectFit(ImageFit.Cover)
      Column({ space: 3 }) {
        Text(user.nickname || '').fontSize(13).fontColor('#ededf0').maxLines(1)
        if (user.mutual) {
          Text('互相关注').fontSize(10).fontColor('#77777f')
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor(['#55555d'])
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
            Text(`分享「${this.shareParam.name}」`).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            Text('选择分享方式').fontSize(11).fontColor('#77777f')
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor(['#686870'])
            .onClick(() => this.onClose())
        }
        .width('100%').padding({ left: 20, right: 20, top: 18, bottom: 4 })

        if (this.contactsVisible) {
          Column({ space: 10 }) {
            if (this.contactsLoading) {
              Row() {
                LoadingProgress().width(24).height(24).color('#ef233c')
                Text('加载联系人…').fontSize(12).fontColor('#77777f').margin({ left: 8 })
              }
              .width('100%').justifyContent(FlexAlign.Center).padding({ top: 16, bottom: 16 })
            } else if (this.contacts.length > 0) {
              Text('选择联系人发起私信').fontSize(12).fontColor('#9999a0').width('100%').padding({ left: 20 })
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
              Text('暂无联系人').fontSize(12).fontColor('#77777f').width('100%')
                .textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
            }
            Button('返回').width('100%').backgroundColor('#2a2a30').fontColor('#b5b5bc')
              .onClick(() => { this.contactsVisible = false })
          }
          .width('100%').padding({ left: 20, right: 20 })
        } else {
          Row({ space: 16 }) {
            this.ShareOption($r('sys.symbol.share'), '系统分享', () => this.shareSystem())
            this.ShareOption($r('sys.symbol.ellipsis_bubble'), '私信分享', () => this.openContacts())
            this.ShareOption($r('sys.symbol.textformat'), '动态分享', () => this.shareToDynamic())
          }
          .width('100%').justifyContent(FlexAlign.Center).padding({ left: 20, right: 20 })
        }

        if (this.shareMessage) {
          Text(this.shareMessage).width('100%').fontSize(12)
            .fontColor(this.shareMessage.includes('已') ? '#4caf50' : '#ff6577')
            .textAlign(TextAlign.Center).padding({ bottom: 8 })
        }
      }
      .width('100%')
      .backgroundColor('#19191f')
      .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 0, bottomRight: 0 })
      .padding({ bottom: 28 })
      .transition(TransitionEffect.translate({ y: 400 }).animation({ duration: 260, curve: Curve.EaseOut }))
    }
    .width('100%').height('100%')
  }
}
