import { UserLevelResponse } from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'

@Component
export struct UserLevelPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @State response: UserLevelResponse = { code: 0 }
  @State loading: boolean = true
  @State message: string = ''

  aboutToAppear(): void {
    this.loadLevel()
  }

  private async loadLevel(): Promise<void> {
    this.loading = true
    this.message = ''
    if (!this.authStore.loggedIn) {
      this.loading = false
      this.message = '登录后才能获取等级信息'
      return
    }
    try {
      this.response = await ApiClient.get<UserLevelResponse>('/user/level')
      if (this.response.code !== 200 || !this.response.data) {
        this.message = this.response.message || '等级信息加载失败'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '等级信息加载失败'
    } finally {
      this.loading = false
    }
  }

  private playProgress(): number {
    if (!this.response.data || this.response.data.nextPlayCount <= 0) {
      return 0
    }
    return Math.min(this.response.data.nowPlayCount / this.response.data.nextPlayCount, 1)
  }

  private loginProgress(): number {
    if (!this.response.data || this.response.data.nextLoginCount <= 0) {
      return 0
    }
    return Math.min(this.response.data.nowLoginCount / this.response.data.nextLoginCount, 1)
  }

  @Builder
  private ProgressRing(current: number, target: number, label: string, icon: Resource, color: string) {
    Column({ space: 10 }) {
      Stack() {
        DataPanel({
          values: [current, Math.max(target - current, 0)],
          max: target,
          type: DataPanelType.Circle
        })
          .width(110).height(110)
          .valueColors([
            new LinearGradient([{ color: color, offset: 0 }, { color: '#ff6577', offset: 1 }]),
            new LinearGradient([{ color: '#25252c', offset: 0 }, { color: '#1b1b20', offset: 1 }])
          ])
          .strokeWidth(10)
        Column({ space: 2 }) {
          Text(`${current}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text(`/${target}`).fontSize(10).fontColor('#77777f')
        }
      }
      .width(110).height(110)
      .alignContent(Alignment.Center)

      Text(label).fontSize(12).fontColor('#92929a')
    }
    .layoutWeight(1).padding(16).backgroundColor('#1b1b20').borderRadius(20)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
          Text('我的等级')
            .layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .width(24).fontSize(20).fontColor(['#aaaaB2'])
            .onClick(() => this.loadLevel())
        }
        .height(56).width('100%').padding({ left: 16, right: 16 })

        if (this.loading) {
          LoadingProgress().layoutWeight(1).width(46).color('#ef233c')
        } else if (!this.response.data) {
          Column({ space: 14 }) {
            Text(this.message).fontSize(13).fontColor('#77777f')
            if (!this.authStore.loggedIn) {
              Button('去登录').backgroundColor('#ef233c')
                .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
            }
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 18 }) {
              Column({ space: 14 }) {
                Text(`Lv.${this.response.data.level}`)
                  .fontSize(48).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                Text(this.response.full ? '已达到当前最高等级' : '持续听歌与登录可以提升等级')
                  .fontSize(12).fontColor('#d7b7bb')
                Progress({ value: Math.max(0, Math.min(this.response.data.progress * 100, 100)), total: 100,
                  type: ProgressType.Ring })
                  .width(120).height(120).color('#ef233c')
                  .backgroundColor('rgba(255,255,255,0.08)')
                  .style({ strokeWidth: 8 })
                Text(`升级进度 ${Math.round(this.response.data.progress * 100)}%`)
                  .fontSize(10).fontColor('#d7b7bb')
              }
              .width('100%').padding(24).borderRadius(24)
              .linearGradient({ angle: 135, colors: [['#8d2939', 0], ['#3b273b', 1]] })

              Row({ space: 12 }) {
                this.ProgressRing(
                  this.response.data.nowPlayCount,
                  this.response.data.nextPlayCount,
                  '累计听歌首数',
                  $r('sys.symbol.music'),
                  '#ef233c'
                )
                this.ProgressRing(
                  this.response.data.nowLoginCount,
                  this.response.data.nextLoginCount,
                  '累计登录天数',
                  $r('sys.symbol.calendar'),
                  '#7f76ff'
                )
              }

              if (this.response.data.info) {
                // 首先，创建一个包含标题“等级权益”的列
                Column() {
                  // 显示标题
                  Text('等级权益')
                    .fontSize(14)
                    .fontColor($r('sys.color.white'))
                    .margin({ bottom: 10 })
                  ForEach(this.response.data.info.split('$'), (item: string) => {
                    Column() {
                      Text(item)
                        .width('100%')
                        .fontSize(12)
                        .lineHeight(20)
                        .fontColor('#92929a')
                        .padding(18)
                        .backgroundColor('#1b1b20')
                        .borderRadius(18)
                        .margin({ bottom: 8 })
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                  })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }

              Column({ space: 10 }) {
                Row() {
                  Text('当前等级').layoutWeight(1).fontSize(12).fontColor('#77777f')
                  Text(`Lv.${this.response.data.level}`).fontSize(12).fontColor('#ededf0')
                }
                Row() {
                  Text('等级进度').layoutWeight(1).fontSize(12).fontColor('#77777f')
                  Text(`${Math.round(this.response.data.progress * 100)}%`).fontSize(12).fontColor('#ededf0')
                }
                Row() {
                  Text('听歌数量').layoutWeight(1).fontSize(12).fontColor('#77777f')
                  Text(`${this.response.data.nowPlayCount} / ${this.response.data.nextPlayCount}`)
                    .fontSize(12).fontColor('#ededf0')
                }
                Row() {
                  Text('登录天数').layoutWeight(1).fontSize(12).fontColor('#77777f')
                  Text(`${this.response.data.nowLoginCount} / ${this.response.data.nextLoginCount}`)
                    .fontSize(12).fontColor('#ededf0')
                }
              }
              .width('100%').padding(18).backgroundColor('#1b1b20').borderRadius(18)
            }
            .padding({ left: 16, right: 16, top: 12, bottom: 32 })
          }
          .layoutWeight(1)
        }
      }
      .width('100%').height('100%').backgroundColor('#121215')
    }
    .hideTitleBar(true)
  }
}
