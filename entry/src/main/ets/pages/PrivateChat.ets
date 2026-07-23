import {
  ApiAlbum,
  ApiArtist,
  ApiParam,
  ApiSong,
  MsgPrivateHistoryResponse,
  PrivateChatPageParam,
  PrivateMsgContent,
  SendMsgResponse,
  UserProfilePageParam
} from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'
import { playerController } from '../services/PlayerController'
import { common, OpenLinkOptions } from '@kit.AbilityKit'

class ChatMessage {
  msg: string = ''
  type: string = 'text'
  isSelf: boolean = false
  time: number = 0
  fromAvatar: string = ''
  toAvatar: string = ''
  songItem: songItemType | undefined = undefined
  playlistName: string = ''
  playlistId: string = ''
  albumName: string = ''
  albumImg: string = ''
  albumId: string = ''
  generalTitle: string = ''
  generalNotice: string = ''
  generalCover: string = ''
  generalWebUrl: string = ''
  generalNativeUrl: string = ''
  imageUrl: string = ''
  imageWidth: number = 0
  imageHeight: number = 0
}

interface ParsedMsgArtist {
  name: string
}

interface ParsedMsgAlbum {
  name: string
  picUrl: string
}

interface ParsedMsgSong {
  id: number
  name: string
  dt?: number
  duration?: number
  fee?: number
  ar?: ParsedMsgArtist[]
  artists?: ParsedMsgArtist[]
  al?: ParsedMsgAlbum
  album?: ParsedMsgAlbum
}

interface ParsedMsgPlaylist {
  id: number
  name: string
}

interface ParsedMsgAlbumShare {
  id: number
  name: string
  picUrl: string
}

interface ParsedGeneralMsg {
  noticeMsg?: string
  title?: string
  cover?: string
  webUrl?: string
  nativeUrl?: string
  subTitle?: string
  inboxBriefContent?: string
}

interface ParsedPictureInfo {
  picUrl: string
  width?: number
  height?: number
  format?: string
}

interface ParsedMsgBody {
  msg: string
  pushMsg?: string
  resType?: number
  type: number
  title: string
  song: ParsedMsgSong
  playlist: ParsedMsgPlaylist
  album: ParsedMsgAlbumShare
  generalMsg?: ParsedGeneralMsg
  picInfo?: ParsedPictureInfo
}

@Component
export struct PrivateChatPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: PrivateChatPageParam = { uid: '', nickname: '', avatarUrl: '' }

  @State messages: ChatMessage[] = []
  @State inputText: string = ''
  @State loading: boolean = true
  @State sending: boolean = false
  @State chatMessage: string = ''
  @State hasMore: boolean = true
  @State beforeTime: number = 0
  @State loadMoreLoading: boolean = false
  @State previewImageMounted: boolean = false
  @State previewImageVisible: boolean = false
  @State previewImageUrl: string = ''
  @State previewImageKey: string = ''
  @State previewImageRatio: number = 1
  private previewImageClosing: boolean = false
  private scroller: ListScroller = new ListScroller()
  private myUserId: string = ''
  private hasAutoShared: boolean = false

  aboutToAppear(): void {
    this.myUserId = this.authStore.userId
    this.loadHistory(false)
  }

  aboutToDisappear(): void {
    this.previewImageMounted = false
    this.previewImageVisible = false
    this.previewImageUrl = ''
    this.previewImageKey = ''
    this.previewImageClosing = false
  }

  private toChatMessage(item: PrivateMsgContent): ChatMessage {
    const chat = new ChatMessage()
    chat.time = item.time || Date.now()
    chat.fromAvatar = item.fromUser?.avatarUrl || ''
    chat.toAvatar = item.toUser?.avatarUrl || ''
    const fromId = item.fromUser?.userId?.toString() || '0'
    chat.isSelf = fromId === this.myUserId

    const rawMsg = item.msg || ''
    let parsed: ParsedMsgBody | undefined = undefined
    try {
      parsed = JSON.parse(rawMsg) as ParsedMsgBody
    } catch (_e) {
    }

    if (!parsed) {
      chat.type = 'text'
      chat.msg = rawMsg
      return chat
    }

    const msgType = parsed.type || 0
    const text = parsed.msg || ''

    if (msgType === 16 && parsed.picInfo?.picUrl) {
      chat.type = 'image'
      chat.imageUrl = parsed.picInfo.picUrl
      chat.imageWidth = parsed.picInfo.width || 0
      chat.imageHeight = parsed.picInfo.height || 0
      chat.msg = ''
    } else if ((msgType === 23 || parsed.resType === 23) && parsed.generalMsg) {
      const general = parsed.generalMsg
      chat.type = 'general'
      chat.generalTitle = general.title || general.noticeMsg || parsed.title || '消息卡片'
      chat.generalNotice = general.noticeMsg || general.subTitle || general.inboxBriefContent || parsed.pushMsg || ''
      chat.generalCover = general.cover || ''
      chat.generalWebUrl = general.webUrl || ''
      chat.generalNativeUrl = general.nativeUrl || ''
      chat.msg = chat.generalTitle
    } else if (msgType === 6 && text) {
      chat.type = 'text'
      chat.msg = text
    } else if (parsed.song && parsed.song.id && parsed.song.name) {
      chat.type = 'song'
      const s = parsed.song
      const artistItems = s.ar || s.artists || []
      const artists = artistItems.map((a: ParsedMsgArtist) => a.name).join(' / ')
      const al = s.al || s.album
      const song: songItemType = {
        id: s.id.toString(),
        name: s.name,
        author: artists,
        img: al ? al.picUrl : '',
        url: '',
        duration: s.dt || s.duration || 0,
        album: al ? al.name : '',
        fee: s.fee || 0
      }
      chat.songItem = song
      chat.msg = `分享单曲: ${song.name}`
    } else if (msgType === 9 && parsed.playlist) {
      chat.type = 'playlist'
      chat.playlistName = parsed.playlist.name
      chat.playlistId = parsed.playlist.id.toString()
      chat.msg = `分享歌单: ${chat.playlistName}`
    } else if (msgType === 8 && parsed.album) {
      chat.type = 'album'
      chat.albumName = parsed.album.name
      chat.albumImg = parsed.album.picUrl
      chat.albumId = parsed.album.id.toString()
      chat.msg = `分享专辑: ${chat.albumName}`
    } else if (text) {
      chat.type = 'text'
      chat.msg = text
    } else {
      chat.type = 'text'
      chat.msg = rawMsg
    }
    return chat
  }

  private async loadHistory(loadMore: boolean): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.loading = false
      return
    }
    if (loadMore) {
      if (this.loadMoreLoading || !this.hasMore) {
        return
      }
      this.loadMoreLoading = true
    } else {
      this.loading = true
    }
    try {
      const params: ApiParam[] = [
        { key: 'uid', value: this.pageParam.uid },
        { key: 'limit', value: '30' }
      ]
      if (this.beforeTime > 0) {
        params.push({ key: 'before', value: this.beforeTime.toString() })
      }
      const response = await ApiClient.get<MsgPrivateHistoryResponse>('/msg/private/history', params)
      if (response.code === 200) {
        const items = response.msgs || []
        const chatItems: ChatMessage[] = items.map((item: PrivateMsgContent) => this.toChatMessage(item))
        if (!loadMore) {
          this.messages = chatItems.reverse()
        } else {
          this.messages = chatItems.reverse().concat(this.messages)
        }
        this.hasMore = response.more || false
        if (items.length > 0) {
          const oldestTime = items[0].time || 0
          if (oldestTime > 0) {
            this.beforeTime = oldestTime
          }
        }
        if (!loadMore && this.messages.length > 0) {
          setTimeout(() => {
            this.scroller.scrollToIndex(this.messages.length - 1, false, ScrollAlign.END)
          }, 100)
        }
      }
    } catch (_error) {
    } finally {
      this.loading = false
      this.loadMoreLoading = false
    }
  }

  private async sendTextMessage(): Promise<void> {
    const text = this.inputText.trim()
    if (!text) {
      return
    }
    this.sending = true
    this.chatMessage = ''
    try {
      const response = await ApiClient.get<SendMsgResponse>('/send/text', [
        { key: 'msg', value: text },
        { key: 'user_ids', value: this.pageParam.uid }
      ])
      if (response.code === 200) {
        const selfMsg = new ChatMessage()
        selfMsg.msg = text
        selfMsg.type = 'text'
        selfMsg.isSelf = true
        selfMsg.time = Date.now()
        selfMsg.fromAvatar = this.authStore.avatarUrl
        selfMsg.toAvatar = this.pageParam.avatarUrl
        this.messages = this.messages.concat([selfMsg])
        this.inputText = ''
        setTimeout(() => {
          this.scroller.scrollToIndex(this.messages.length - 1, false, ScrollAlign.END)
        }, 50)
      } else {
        this.chatMessage = response.message || response.msg || '发送失败'
      }
    } catch (error) {
      this.chatMessage = error instanceof Error ? error.message : '发送失败'
    } finally {
      this.sending = false
    }
  }

  private async sendShareMessage(): Promise<void> {
    const shareType = this.pageParam.shareType || ''
    const shareId = this.pageParam.shareId || ''
    const shareMsg = this.pageParam.shareMsg || ''
    if (!shareType || !shareId) {
      this.chatMessage = '分享参数缺失'
      return
    }
    this.sending = true
    this.chatMessage = ''
    try {
      const params: ApiParam[] = [
        { key: 'msg', value: shareMsg },
        { key: 'user_ids', value: this.pageParam.uid }
      ]
      let apiPath = ''
      if (shareType === 'song') {
        apiPath = '/send/song'
        params.push({ key: 'id', value: shareId })
      } else if (shareType === 'playlist') {
        apiPath = '/send/playlist'
        params.push({ key: 'playlist', value: shareId })
      } else if (shareType === 'album') {
        apiPath = '/send/album'
        params.push({ key: 'id', value: shareId })
      }
      const response = await ApiClient.get<SendMsgResponse>(apiPath, params)
      if (response.code === 200) {
        const selfMsg = new ChatMessage()
        selfMsg.isSelf = true
        selfMsg.time = Date.now()
        selfMsg.fromAvatar = this.authStore.avatarUrl
        selfMsg.toAvatar = this.pageParam.avatarUrl
        selfMsg.type = shareType
        const typeLabel = shareType === 'song' ? '单曲' : shareType === 'playlist' ? '歌单' : '专辑'
        selfMsg.msg = `分享${typeLabel}: ${this.pageParam.nickname}`
        this.messages = this.messages.concat([selfMsg])
        this.hasAutoShared = true
        setTimeout(() => {
          this.scroller.scrollToIndex(this.messages.length - 1, false, ScrollAlign.END)
        }, 50)
      } else {
        this.chatMessage = response.message || response.msg || '分享发送失败'
      }
    } catch (error) {
      this.chatMessage = error instanceof Error ? error.message : '分享发送失败'
    } finally {
      this.sending = false
    }
  }

  private async playSong(song: songItemType): Promise<void> {
    await playerController.setQueue([song], 0, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private openOtherUserProfile(): void {
    if (!this.pageParam.uid || this.pageParam.uid === this.authStore.userId) {
      return
    }
    const param: UserProfilePageParam = { uid: this.pageParam.uid }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private async openGeneralCard(item: ChatMessage): Promise<void> {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      this.chatMessage = '当前无法打开该卡片'
      return
    }
    const context = hostContext as common.UIAbilityContext
    if (item.generalNativeUrl) {
      try {
        await context.startAbility({
          action: 'ohos.want.action.viewData',
          uri: item.generalNativeUrl
        })
        return
      } catch (_error) {
      }
    }
    if (item.generalWebUrl) {
      try {
        const options: OpenLinkOptions = { appLinkingOnly: false }
        await context.openLink(item.generalWebUrl, options)
        return
      } catch (_error) {
      }
    }
    this.chatMessage = '该卡片暂无可用的跳转地址'
  }

  private imageRatio(item: ChatMessage): number {
    if (item.imageWidth > 0 && item.imageHeight > 0) {
      return item.imageWidth / item.imageHeight
    }
    return 1
  }

  private imageBubbleWidth(item: ChatMessage): number {
    return this.imageRatio(item) < 0.72 ? 154 : 220
  }

  private imageBubbleHeight(item: ChatMessage): number {
    const height = this.imageBubbleWidth(item) / this.imageRatio(item)
    return Math.max(110, Math.min(270, height))
  }

  private imageTransitionKey(item: ChatMessage): string {
    return `private-image-${item.time}-${item.imageUrl}`
  }

  private showChatImage(item: ChatMessage): void {
    if (!item.imageUrl || this.previewImageClosing) {
      return
    }
    this.previewImageUrl = item.imageUrl
    this.previewImageKey = this.imageTransitionKey(item)
    this.previewImageRatio = this.imageRatio(item)
    this.previewImageMounted = true
    this.getUIContext().animateTo({ duration: 360, curve: Curve.EaseInOut }, () => {
      this.previewImageVisible = true
    })
  }

  private closeChatImage(): void {
    if (!this.previewImageMounted || !this.previewImageVisible || this.previewImageClosing) {
      return
    }
    this.previewImageClosing = true
    this.getUIContext().animateTo({
      duration: 360,
      curve: Curve.EaseInOut,
      onFinish: () => {
        this.previewImageMounted = false
        this.previewImageUrl = ''
        this.previewImageKey = ''
        this.previewImageClosing = false
      }
    }, () => {
      this.previewImageVisible = false
    })
  }

  @Builder
  private MessageBubble(item: ChatMessage) {
    Row({ space: 8 }) {
      if (item.isSelf) {
        Blank()
      } else {
        Image(item.fromAvatar || this.pageParam.avatarUrl)
          .width(32).height(32).borderRadius(16).objectFit(ImageFit.Cover)
          .onClick(() => this.openOtherUserProfile())
      }
      Column({ space: 4 }) {
        if (item.type === 'image' && item.imageUrl) {
          if (this.previewImageVisible && this.previewImageKey === this.imageTransitionKey(item)) {
            Column().width(this.imageBubbleWidth(item)).height(this.imageBubbleHeight(item))
          } else {
            Image(item.imageUrl)
              .width(this.imageBubbleWidth(item)).height(this.imageBubbleHeight(item))
              .borderRadius(14).objectFit(ImageFit.Cover)
              .geometryTransition(this.imageTransitionKey(item), { follow: true })
              .onClick(() => this.showChatImage(item))
          }
        } else if (item.type === 'song' && item.songItem) {
          Row({ space: 10 }) {
            Image(item.songItem.img).width(46).height(46).borderRadius(8).objectFit(ImageFit.Cover)
            Column({ space: 4 }) {
              Text(item.songItem.name).fontSize(13).fontColor('#ededf0').maxLines(1)
              Text(item.songItem.author).fontSize(11).fontColor('#77777f').maxLines(1)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(22).fontColor(['#ef233c'])
          }
          .width(220).padding(10).backgroundColor('#2a2a30').borderRadius(14)
          .onClick(() => {
            if (item.songItem) {
              this.playSong(item.songItem)
            }
          })
        } else if (item.type === 'playlist' && item.playlistName) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(18).fontColor(['#ef233c'])
            Text(item.playlistName).fontSize(13).fontColor('#ededf0').maxLines(1)
          }
          .width(220).padding(10).backgroundColor('#2a2a30').borderRadius(14)
        } else if (item.type === 'album' && item.albumName) {
          Row({ space: 8 }) {
            if (item.albumImg) {
              Image(item.albumImg).width(36).height(36).borderRadius(6).objectFit(ImageFit.Cover)
            }
            Text(item.albumName).fontSize(13).fontColor('#ededf0').maxLines(1)
          }
          .width(220).padding(10).backgroundColor('#2a2a30').borderRadius(14)
        } else if (item.type === 'general' && item.generalTitle) {
          Column({ space: 0 }) {
            if (item.generalCover) {
              Image(item.generalCover).width('100%').height(118).objectFit(ImageFit.Cover)
            }
            Column({ space: 7 }) {
              Text(item.generalTitle).width('100%').fontSize(14).fontWeight(FontWeight.Bold)
                .fontColor('#f4f4f6').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.generalNotice && item.generalNotice !== item.generalTitle) {
                Text(item.generalNotice).width('100%').fontSize(11).lineHeight(17).fontColor('#94949c')
                  .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              Row() {
                Text('查看详情').fontSize(11).fontColor('#ff6577')
                Blank()
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor(['#77777f'])
              }.width('100%')
            }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
          }
          .width(238).clip(true).backgroundColor('#25252b').borderRadius(15)
          .border({ width: 1, color: '#303037' })
          .onClick(() => this.openGeneralCard(item))
        }
        if (item.msg && item.type === 'text') {
          Text(item.msg)
            .fontSize(14).fontColor(item.isSelf ? '#ffffff' : '#ededf0')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor(item.isSelf ? '#ef233c' : '#2a2a30')
            .borderRadius(18)
            .maxLines(10)
        }
      }
      .alignItems(item.isSelf ? HorizontalAlign.End : HorizontalAlign.Start)
      if (item.isSelf) {
        Image(item.fromAvatar || this.authStore.avatarUrl)
          .width(32).height(32).borderRadius(16).objectFit(ImageFit.Cover)
      }
    }
    .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
  }

  build() {
    NavDestination() {
      Stack() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
          Text(this.pageParam.nickname).layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          Image(this.pageParam.avatarUrl).width(28).height(28).borderRadius(14)
            .objectFit(ImageFit.Cover).margin({ right: 16 })
            .onClick(() => this.openOtherUserProfile())
        }
        .height(54).width('100%').padding({ left: 16, right: 0 })

        if (this.loading && this.messages.length === 0) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).height(36).color('#ef233c')
            Text('加载中…').fontSize(13).fontColor('#77777f')
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.messages.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(40).fontColor(['#55555d'])
            Text('暂无消息记录').fontSize(13).fontColor('#77777f')
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 4, scroller: this.scroller }) {
            if (this.hasMore) {
              ListItem() {
                Row() {
                  if (this.loadMoreLoading) {
                    LoadingProgress().width(20).height(20).color('#ef233c')
                  }
                  Text(this.loadMoreLoading ? '加载中…' : '加载更多消息')
                    .fontSize(12).fontColor('#77777f')
                }
                .width('100%').height(40).justifyContent(FlexAlign.Center)
                .onClick(() => this.loadHistory(true))
              }
            }
            ForEach(this.messages, (item: ChatMessage, index: number) => {
              ListItem() {
                this.MessageBubble(item)
              }
            }, (item: ChatMessage, index: number) => `${index}_${item.time}`)
          }
          .layoutWeight(1).scrollBar(BarState.Off)
        }

        if (this.chatMessage) {
          Text(this.chatMessage).width('100%').fontSize(11).fontColor('#ff6577')
            .textAlign(TextAlign.Center).padding({ top: 4, bottom: 4 })
        }

        if (this.pageParam.shareType && !this.hasAutoShared) {
          Row({ space: 8 }) {
            Text(`发送「${this.pageParam.shareMsg || '分享内容'}」`).fontSize(13).fontColor('#ededf0')
              .layoutWeight(1).maxLines(1)
            Button('发送').height(32).fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
              .borderRadius(16).enabled(!this.sending)
              .onClick(() => this.sendShareMessage())
          }
          .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor('#1f1f26').borderRadius(12).margin({ left: 12, right: 12, top: 4 })
        }

        Row({ space: 10 }) {
          TextInput({ text: this.inputText, placeholder: '输入消息…' })
            .layoutWeight(1).height(42).fontColor('#ffffff').placeholderColor('#696972')
            .backgroundColor('#202026').borderRadius(21).padding({ left: 18, right: 18 })
            .onChange((value: string) => this.inputText = value)
            .onSubmit(() => this.sendTextMessage())
          Button(this.sending ? '…' : '发送')
            .height(42).fontSize(13).fontColor('#ffffff').backgroundColor('#ef233c')
            .borderRadius(21).enabled(!this.sending)
            .onClick(() => this.sendTextMessage())
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 12 })
        .backgroundColor('#17171c')
      }
      .width('100%').height('100%').backgroundColor('#121215')
      if (this.previewImageMounted && this.previewImageUrl) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#000000')
            .opacity(this.previewImageVisible ? 1 : 0)
            .animation({ duration: 240, curve: Curve.EaseInOut })
          if (this.previewImageVisible) {
            Image(this.previewImageUrl).width('100%').height('100%').objectFit(ImageFit.Contain)
              .geometryTransition(this.previewImageKey, { follow: true })
          }
        }
        .width('100%').height('100%')
        .onClick(() => this.closeChatImage())
      }
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
  }
}
