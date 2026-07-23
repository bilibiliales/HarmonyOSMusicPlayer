import { common, OpenLinkOptions } from '@kit.AbilityKit'
import { VipGrowthClaimResponse, VipGrowthResponse, VipInfoResponse } from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { parseVipInfo, VipDisplayInfo } from '../services/VipService'
import { AuthStore } from '../stores/AuthStore'

interface SidebarMenuItem {
  icon: Resource
  title: string
  subtitle: string
  available: boolean
  route?: string
}

@Component
export struct Sidebar {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('authStore') authStore: AuthStore
  @Prop visible: boolean = false
  @Prop topAvoidHeight: number = 0
  onClose: () => void = () => {}
  onOpenMine: () => void = () => {}
  @State hint: string = ''
  @State vipActive: boolean = false
  @State vipSvip: boolean = false
  @State vipLevel: number = 0
  @State vipExpireTime: number = 0
  @State vipLevelName: string = ''
  @State growthLoading: boolean = false
  @State vipLoading: boolean = false
  @State vipCardBg: string = ''
  private loadedVip: boolean = false

  private menuItems: SidebarMenuItem[] = [
    { icon: $r('sys.symbol.envelope_fill'), title: '消息中心', subtitle: '私信、评论与系统通知', available: true, route: 'MessageCenterPage' },
    { icon: $r('sys.symbol.clock'), title: '最近播放', subtitle: '持久化历史记录尚未接入', available: false },
    { icon: $r('sys.symbol.arrow_down_circle'), title: '本地与下载', subtitle: '媒体库扫描尚未接入', available: false },
    { icon: $r('sys.symbol.wand_and_stars'), title: 'AI 写歌', subtitle: '风格改编、AI 作词与灵感创作', available: true, route: 'AiSongStudioPage' },
    { icon: $r('sys.symbol.cart'), title: '云贝中心', subtitle: '依赖官方活动服务', available: false },
    { icon: $r('sys.symbol.gearshape'), title: '设置', subtitle: '播放与网络设置', available: true, route: 'SettingsPage' }
  ]

  private openLogin(): void {
    this.onClose()
    this.pageStack.pushPathByName('LoginPage', null)
  }

  private getVipText(level: number): string {
    if (level === 1) {
      return '壹'
    }
    if (level === 2) {
      return '贰'
    }
    if (level === 3) {
      return '叁'
    }
    if (level === 4) {
      return '肆'
    }
    if (level === 5) {
      return '伍'
    }
    if (level === 6) {
      return '陆'
    }
    if (level === 7) {
      return '柒'
    }
    return '未知'
  }

  private vipLabel(): string {
    if (!this.vipActive) {
      return 'VIP已过期'
    }
    if (this.vipLevelName.length > 0) {
      return this.vipLevelName
    }
    const prefix = this.vipSvip ? '黑胶VIP·' : '黑胶VIP·'
    return `${prefix}${this.getVipText(this.vipLevel)}`
  }

  private vipLabelColor(): string {
    if (!this.vipActive) {
      return '#888890'
    }
    if (this.vipSvip) {
      return '#fff8e1b9'
    }
    return '#ffe8d1cc'
  }

  private vipBgColor(): string {
    if (!this.vipActive) {
      return 'rgba(40,36,38,0.7)'
    }
    if (this.vipSvip) {
      return 'rgba(52,42,42,0.72)'
    }
    return 'rgba(55,44,44,0.72)'
  }

  private vipSubtext(): string {
    if (!this.vipActive) {
      return '开通会员畅享无损与 Hi-Res 音质'
    }
    if (this.vipExpireTime > 0) {
      const date = new Date(this.vipExpireTime)
      const dateStr = `${date.getFullYear()}.${(date.getMonth() + 1).toString().padStart(2, '0')}.${date.getDate().toString().padStart(2, '0')}`
      return `有效期至 ${dateStr}`
    }
    return '音质选项根据歌曲资源和账号权限自动回落'
  }

  aboutToAppear(): void {
    if (this.authStore.loggedIn && !this.loadedVip) {
      this.loadVipInfo()
    }
  }

  private async loadVipInfo(): Promise<void> {
    if (!this.authStore.loggedIn || this.vipLoading) {
      return
    }
    this.vipLoading = true
    try {
      const response = await ApiClient.get<VipInfoResponse>('/vip/info', [
        { key: 'uid', value: this.authStore.userId }
      ])
      const display: VipDisplayInfo = parseVipInfo(response.data)
      this.vipActive = display.active
      this.vipSvip = display.isSvip
      this.vipLevel = display.level
      if (response.data?.redplus && response.data.redplus.expireTime > 0) {
        this.vipExpireTime = response.data.redplus.expireTime
      } else if (response.data?.associator && response.data.associator.expireTime > 0) {
        this.vipExpireTime = response.data.associator.expireTime
      }
      try {
        const growthResp = await ApiClient.get<VipGrowthResponse>('/vip/growthpoint', [])
        if (growthResp.code === 200 && growthResp.data) {
          const userLevel = growthResp.data.userLevel
          const levelCard = growthResp.data.levelCard
          if (userLevel?.levelName && userLevel.levelName.length > 0) {
            this.vipLevelName = userLevel.levelName
          }
          if (levelCard?.levelBackgroundCardImageUrl && levelCard.levelBackgroundCardImageUrl.length > 0) {
            this.vipCardBg = levelCard.levelBackgroundCardImageUrl
          }
          if (userLevel?.expireTime && userLevel.expireTime > 0) {
            this.vipExpireTime = userLevel.expireTime
          }
        }
      } catch (_e) {
      }
      this.loadedVip = true
    } catch (_error) {
      this.vipActive = false
    } finally {
      this.vipLoading = false
    }
  }

  private openVipPurchase(): void {
    try {
      const hostContext = this.getUIContext().getHostContext()
      if (hostContext) {
        const context = hostContext as common.UIAbilityContext
        const link = 'https://music.163.com/#/member'
        const options: OpenLinkOptions = { appLinkingOnly: false }
        context.openLink(link, options).catch(() => {
          this.hint = '请在浏览器中访问 music.163.com/#/member 开通会员'
        })
      } else {
        this.hint = '请在浏览器中访问 music.163.com/#/member 开通会员'
      }
    } catch (_error) {
      this.hint = '请在浏览器中访问 music.163.com/#/member 开通会员'
    }
  }

  @Builder
  private VipCard() {
    Column({ space: 0 }) {
      if (this.vipCardBg.length > 0 && this.vipActive) {
        Stack({ alignContent: Alignment.TopStart }) {
          Image(this.vipCardBg)
            .width('100%')
            .height(140)
            .objectFit(ImageFit.Cover)
            .borderRadius(18)

          Column({ space: 10 }) {
            Row() {
              Column({ space: 3 }) {
                Row({ space: 4 }) {
                  if (this.vipSvip) {
                    Image($r('app.media.ic_svip')).width(40).height(18).objectFit(ImageFit.Contain)
                  } else {
                    Image($r('app.media.ic_vip')).width(34).height(18).objectFit(ImageFit.Contain)
                  }
                  Text(this.vipLevel > 0 ? this.getVipText(this.vipLevel) : '')
                    .fontSize(11)
                    .fontWeight(FontWeight.Regular)
                    .fontColor(this.vipLabelColor())
                }
                Text(this.vipSubtext())
                  .fontSize(11)
                  .fontColor(this.vipSvip ? '#d4c4a8' : '#b7a99b')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.vipActive) {
                Button('续费会员')
                  .height(30)
                  .fontSize(11)
                  .fontColor('#2b2020')
                  .backgroundColor('#f0d3ac')
                  .borderRadius(15)
                  .type(ButtonType.Normal)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => this.openVipPurchase())
              } else {
                Button('开通会员')
                  .height(30)
                  .fontSize(11)
                  .fontColor('#2b2020')
                  .backgroundColor('#f0d3ac')
                  .borderRadius(15)
                  .type(ButtonType.Normal)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => this.openVipPurchase())
              }
            }
            .width('100%')
            Divider().color('rgba(255,255,255,0.08)')
            Text('音质选项会根据歌曲实际资源和账号权限自动回落')
              .fontSize(11)
              .fontColor('#92877d')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('100%')
        .height(140)
        .borderRadius(18)
        .clip(true)
      } else {
        Column({ space: 10 }) {
          Row() {
            Column({ space: 3 }) {
              Row({ space: 4 }) {
                if (this.vipActive) {
                  if (this.vipSvip) {
                    Image($r('app.media.ic_svip')).width(40).height(18).objectFit(ImageFit.Contain)
                  } else {
                    Image($r('app.media.ic_vip')).width(34).height(18).objectFit(ImageFit.Contain)
                  }
                  Text(this.vipLevel > 0 ? this.getVipText(this.vipLevel) : '')
                    .fontSize(11)
                    .fontWeight(FontWeight.Regular)
                    .fontColor(this.vipLabelColor())
                } else {
                  Text('VIP已过期')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#888890')
                }
              }
              Text(this.vipSubtext())
                .fontSize(11)
                .fontColor(this.vipActive ? (this.vipSvip ? '#d4c4a8' : '#b7a99b') : '#77777f')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            if (this.vipActive) {
              Button('续费会员')
                .height(30)
                .fontSize(11)
                .fontColor('#2b2020')
                .backgroundColor('#f0d3ac')
                .borderRadius(15)
                .type(ButtonType.Normal)
                .padding({ left: 12, right: 12 })
                .onClick(() => this.openVipPurchase())
            } else {
              Button('开通会员')
                .height(30)
                .fontSize(11)
                .fontColor('#2b2020')
                .backgroundColor('#f0d3ac')
                .borderRadius(15)
                .type(ButtonType.Normal)
                .padding({ left: 12, right: 12 })
                .onClick(() => this.openVipPurchase())
            }
          }
          .width('100%')
          Divider().color('rgba(255,255,255,0.08)')
          Text('音质选项会根据歌曲实际资源和账号权限自动回落')
            .fontSize(11)
            .fontColor('#92877d')
        }
        .width('100%')
        .padding(16)
        .borderRadius(18)
        .backgroundColor(this.vipBgColor())
        .border({ width: 1, color: 'rgba(255,255,255,0.06)' })
      }
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.62)')
        .backdropBlur(10)
        .onClick(() => this.onClose())
        .opacity(this.visible ? 1 : 0)

      Column() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 145,
              colors: [['#48222a', 0], ['#231a21', 0.48], ['#17171c', 1]]
            })

          Column({ space: 16 }) {
            Row({ space: 12 }) {
              if (this.authStore.avatarUrl) {
                Image(this.authStore.avatarUrl)
                  .width(52)
                  .height(52)
                  .borderRadius(18)
                  .objectFit(ImageFit.Cover)
              } else {
                Stack() {
                  SymbolGlyph($r('sys.symbol.person_fill'))
                    .fontSize(25)
                    .fontColor(['#f0f0f2'])
                }
                .width(52)
                .height(52)
                .borderRadius(18)
                .backgroundColor('rgba(255,255,255,0.12)')
              }

              Column({ space: 5 }) {
                Text(this.authStore.nickname)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                Text(this.authStore.loggedIn ? '查看个人主页' : '登录后同步收藏与歌单')
                  .fontSize(11)


















                  .fontColor('#aaaab2')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(18)
                .fontColor(['#b3b3ba'])
            }
            .width('100%')
            .onClick(() => {
              if (!this.authStore.loggedIn) {
                this.openLogin()
              } else {
                this.onClose()
                this.onOpenMine()
              }
            })

            this.VipCard()
          }
          .padding({ left: 20, right: 20, top: this.topAvoidHeight + 18 })
        }
        .height(238 + this.topAvoidHeight)

        List({ space: 8 }) {
          ForEach(this.menuItems, (item: SidebarMenuItem) => {
            ListItem() {
              Row({ space: 14 }) {
                Stack() {
                  SymbolGlyph(item.icon)
                    .fontSize(20)
                    .fontColor([item.available ? '#e7e7eb' : '#66666e'])
                }
                .width(40)
                .height(40)
                .borderRadius(13)
                .backgroundColor(item.available ? '#25252c' : '#1c1c21')

                Column({ space: 3 }) {
                  Text(item.title)
                    .fontSize(14)
                    .fontColor(item.available ? '#ededf0' : '#77777f')
                  Text(item.subtitle)
                    .fontSize(10)
                    .fontColor('#66666e')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (!item.available) {
                  Text('暂不可用')
                    .fontSize(9)
                    .fontColor('#77777f')
                    .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                    .backgroundColor('#232329')
                    .borderRadius(8)
                } else {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(15)
                    .fontColor(['#5e5e66'])
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(16)
              .onClick(() => {
                if (!item.available) {
                  this.hint = `${item.title}：${item.subtitle}`
                } else if (item.route) {
                  this.onClose()
                  this.pageStack.pushPathByName(item.route, null)
                } else {
                  this.hint = `${item.title}页面将在对应数据接通后开放`
                }
              })
            }
          })
        }
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 14 })
        .scrollBar(BarState.Off)

        if (this.hint) {
          Text(this.hint)
            .fontSize(11)
            .fontColor('#a9a9b0')
            .padding({ left: 18, right: 18, bottom: 8 })
        }

        Row({ space: 10 }) {
          Button(this.authStore.loggedIn ? '退出登录' : '登录账号')
            .layoutWeight(1)
            .height(44)
            .fontColor(this.authStore.loggedIn ? '#ff7785' : '#ffffff')
            .backgroundColor(this.authStore.loggedIn ? '#2b2024' : '#ef233c')
            .borderRadius(15)
            .onClick(() => {
              if (this.authStore.loggedIn) {
                this.authStore.logout()
              } else {
                this.openLogin()
              }
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 20 })
      }
      .width('84%')
      .height('100%')
      .backgroundColor('#151519')
      .borderRadius({ topRight: 28, bottomRight: 28 })
      .clip(true)
      .translate({ x: this.visible ? 0 : -360 })
      .opacity(this.visible ? 1 : 0.92)
      .shadow({ radius: 30, color: 'rgba(0,0,0,0.4)', offsetX: 10 })
      .animation({ duration: 280, curve: this.visible ? Curve.EaseOut : Curve.EaseIn })
    }
    .width('100%')
    .height('100%')
  }
}
