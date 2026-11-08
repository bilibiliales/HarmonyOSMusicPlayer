import { UserLevelResponse } from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'
import { LevelTaskRing } from '../components/LevelTaskRing'
import { levelTaskProgress } from '../services/UserLevelProgress'
import { TC } from '../services/ThemeColors'

@Component
export struct UserLevelPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @State response: UserLevelResponse = { code: 0 }
  @State loading: boolean = true
  @State message: string = ''
  @State levelProgress: number = 0
  @State songProgress: number = 0
  @State loginProgress: number = 0
  private animationTimer: number = -1
  private requestId: number = 0
  private readonly levels: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

  aboutToAppear(): void { this.loadLevel() }
  aboutToDisappear(): void {
    this.requestId++
    if (this.animationTimer >= 0) { clearTimeout(this.animationTimer) }
  }

  private animateProgress(): void {
    this.levelProgress = 0
    this.songProgress = 0
    this.loginProgress = 0
    if (this.animationTimer >= 0) { clearTimeout(this.animationTimer) }
    this.animationTimer = setTimeout(() => {
      this.getUIContext().animateTo({ duration: 1100, curve: Curve.EaseOut }, () => {
        this.levelProgress = Math.max(0, Math.min(100, (this.response.data?.level || 0) * 10))
        this.songProgress = levelTaskProgress(this.response.data!.nowPlayCount, this.response.data!.nextPlayCount, this.response.full)
        this.loginProgress = levelTaskProgress(this.response.data!.nowLoginCount, this.response.data!.nextLoginCount, this.response.full)
      })
    }, 80)
  }

  private async loadLevel(): Promise<void> {
    const requestId = ++this.requestId
    this.loading = true
    this.message = ''
    this.response = { code: 0 }
    if (this.animationTimer >= 0) { clearTimeout(this.animationTimer) }
    if (!this.authStore.loggedIn) {
      this.loading = false
      this.message = '登录后才能获取等级信息'
      return
    }
    try {
      const response = await ApiClient.get<UserLevelResponse>('/user/level')
      if (requestId !== this.requestId) { return }
      if (response.code !== 200 || !response.data) { throw new Error(response.message || '等级信息加载失败') }
      this.response = response
    } catch (error) {
      if (requestId === this.requestId) { this.message = error instanceof Error ? error.message : '等级信息加载失败' }
    } finally {
      if (requestId === this.requestId) {
        this.loading = false
        if (this.response.data) { this.animateProgress() }
      }
    }
  }

  @Builder
  private LevelCard() {
    Column() {
      Column({ space: 16 }) {
        if (this.authStore.avatarUrl) {
          Image(this.authStore.avatarUrl).width(72).height(72).borderRadius(36).objectFit(ImageFit.Cover)
        } else {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill')).fontSize(72).fontColor([TC.textTertiary()])
        }
        Row({ space: 8 }) {
          Text('当前等级：').fontSize(19).fontColor(TC.textBody())
          Text(`Lv.${this.response.data!.level}`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(TC.accentSoft())
        }
        Column({ space: 8 }) {
          Row() {
            ForEach(this.levels, (level: number) => {
              Stack() {
                if (level === this.response.data!.level) {
                  Circle().width(22).height(22).fill(TC.accent())
                }
                Text(level.toString()).fontSize(11)
                  .fontColor(level === this.response.data!.level ? TC.textOnAccent() : level < this.response.data!.level ? TC.accentSoft() : TC.textTertiary())
              }.width(22).height(24)
            })
          }.width('100%').justifyContent(FlexAlign.SpaceBetween)
          Progress({ value: this.levelProgress, total: 100, type: ProgressType.Linear })
            .width('calc(100% - 22vp)').margin({ left: 11, right: 11 }).color(TC.accent()).backgroundColor(TC.surfaceRaised())
            .style({ strokeWidth: 6, enableSmoothEffect: true })
          Text('等级数据每天下午2点更新').width('100%').fontSize(12).fontColor(TC.textTertiary()).margin({ top: 5 })
        }.width('100%').margin({ top: 18 })
      }.width('100%').padding({ left: 20, right: 20, top: 24, bottom: 28 })
      Divider().color(TC.surfaceRaised())
      Column({ space: 12 }) {
        Text('当前等级特权').fontSize(17).fontColor(TC.textBody()).fontWeight(FontWeight.Medium)
        if (this.response.data!.info) {
          ForEach(this.response.data!.info!.split('$').filter((item: string) => item.trim().length > 0), (item: string) => {
            Row({ space: 9 }) {
              Circle().width(4).height(4).fill(TC.accentSoft())
              Text(item).layoutWeight(1).fontSize(14).lineHeight(22).fontColor(TC.textBody())
            }.width('100%').alignItems(VerticalAlign.Top)
          })
        } else {
          Text('暂无等级特权信息').fontSize(13).fontColor(TC.textTertiary())
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
      Divider().color(TC.surfaceRaised())
      Column({ space: 26 }) {
        Row({ space: 6 }) {
          Text(this.response.full ? '已达到最高等级' : '距离下一等级：').fontSize(14).fontColor(TC.textSecondary())
          if (!this.response.full) {
            Text(`Lv.${Math.min(10, this.response.data!.level + 1)}`).fontSize(17).fontWeight(FontWeight.Bold).fontColor(TC.accentSoft())
          }
        }.width('100%')
        Row({ space: 12 }) {
          LevelTaskRing({ value: this.songProgress,
            remaining: Math.max(0, this.response.data!.nextPlayCount - this.response.data!.nowPlayCount),
            label: '听歌量', unit: '首', color: '#ff6577' }).layoutWeight(1)
          LevelTaskRing({ value: this.loginProgress,
            remaining: Math.max(0, this.response.data!.nextLoginCount - this.response.data!.nowLoginCount),
            label: '登录天数', unit: '天', color: '#65bedc' }).layoutWeight(1)
        }.width('100%')
      }.width('100%').padding({ left: 20, right: 20, top: 24, bottom: 30 })
    }.width('100%').backgroundColor(TC.surfaceCard()).borderRadius(22)
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()]).onClick(() => this.pageStack.pop())
          Text('我的等级').layoutWeight(1).fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([TC.textBody()]).onClick(() => this.loadLevel())
        }.height(56 + this.topAvoidHeight).width('100%').padding({ left: 18, right: 18, top: this.topAvoidHeight })
        if (this.loading) {
          LoadingProgress().layoutWeight(1).width(46).color(TC.accent())
        } else if (!this.response.data) {
          Column({ space: 14 }) {
            Text(this.message).fontSize(13).fontColor(TC.textTertiary())
            Button(this.authStore.loggedIn ? '重试' : '去登录').fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
              .onClick(() => {
                if (this.authStore.loggedIn) { this.loadLevel() } else { this.pageStack.pushPathByName('LoginPage', null) }
              })
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 16 }) {
              this.LevelCard()
              Text('听歌量按累计收听的歌曲数量计算，同一首歌重复播放不重复计数，播放时间过短的歌曲不计入，每天最多计入300首。')
                .fontSize(12).lineHeight(20).fontColor(TC.textTertiary())
            }.padding({ left: 16, right: 16, top: 12, bottom: 32 })
          }.layoutWeight(1).scrollBar(BarState.Off)
        }
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true)
  }
}
