import { MedalData, ProfileFeaturesService, SocialStatus, UserMedal } from '../services/ProfileFeaturesService'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { AuthStore } from '../stores/AuthStore'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'
import { Responsive } from '../services/Responsive'

@Component
export struct ProfileFeaturesPage {
  mode: string = 'medals'
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @State medals: MedalData = {}
  @State category: number = 0
  @State current: SocialStatus[] = []
  @State statuses: SocialStatus[] = []
  @State loading: boolean = false
  @State saving: boolean = false
  @State message: string = ''
  @State viewWidth: number = 0
  private userId: string = ''

  aboutToAppear(): void { this.load() }

  private async load(): Promise<void> {
    if (this.loading) { return }
    this.userId = this.authStore.userId
    if (!this.authStore.loggedIn || !this.userId) { this.message = '请先登录'; return }
    this.loading = true
    this.message = ''
    const uid = this.userId
    try {
      if (this.mode === 'medals') {
        const data = await ProfileFeaturesService.medals(uid)
        if (uid === this.authStore.userId) { this.medals = data }
      } else {
        const current = await ProfileFeaturesService.currentStatus(uid)
        if (uid !== this.authStore.userId) { return }
        this.current = current
        const statuses = await ProfileFeaturesService.supportedStatuses()
        if (uid === this.authStore.userId) { this.statuses = statuses }
      }
    } catch (error) { this.message = error instanceof Error ? error.message : '加载失败' }
    finally { this.loading = false }
  }

  private async setStatus(status: SocialStatus): Promise<void> {
    if (this.saving || this.userId !== this.authStore.userId) { return }
    this.saving = true
    this.message = ''
    const uid = this.userId
    try {
      await ProfileFeaturesService.editStatus(status)
      if (uid !== this.authStore.userId) { return }
      const current = await ProfileFeaturesService.currentStatus(uid)
      if (uid !== this.authStore.userId) { return }
      this.current = current
      BubbleTip.show(this.getUIContext(), '状态已更新')
    } catch (error) { this.message = error instanceof Error ? error.message : '状态设置失败' }
    finally { this.saving = false }
  }

  private selected(status: SocialStatus): boolean {
    return this.current.some((item: SocialStatus) => item.type === status.type && item.content === status.content)
  }

  @Builder
  private MedalCard(medal: UserMedal) {
    Column({ space: 8 }) {
      Image((medal.levelMedalPicUrl || medal.medalPicUrl || '').replace(/^http:/, 'https:'))
        .width(80).height(80).objectFit(ImageFit.Contain).opacity(medal.status === 'OBTAIN' ? 1 : 0.5)
      Text(medal.medalName).fontSize(13).fontColor(TC.textPrimary()).maxLines(2).textAlign(TextAlign.Center)
      Text(medal.wear ? '正在佩戴' : medal.status === 'OBTAIN' ? '已获得' : '未获得')
        .fontSize(10).fontColor(medal.status === 'OBTAIN' ? TC.accent() : TC.textSecondary())
    }.width('100%').padding(12).backgroundColor(TC.surfaceCard()).borderRadius(14)
      .onClick(() => this.getUIContext().showAlertDialog({ title: medal.medalName,
        message: medal.descriptionText || medal.acceptCondition || '暂无徽章介绍',
        primaryButton: { value: '知道了', action: () => {} } }))
  }

  @Builder
  private StatusRow(status: SocialStatus, selectable: boolean) {
    Row({ space: 12 }) {
      if (status.iconUrl) { Image(status.iconUrl.replace(/^http:/, 'https:')).width(32).height(32).objectFit(ImageFit.Contain) }
      Text(status.content).layoutWeight(1).fontSize(15).fontColor(TC.textPrimary())
      if (selectable && this.selected(status)) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(20).fontColor([TC.accent()])
      }
    }.width('100%').padding(14).backgroundColor(TC.surfaceCard()).borderRadius(12)
      .enabled(!this.saving).onClick(() => { if (selectable) { this.setStatus(status) } })
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()]).onClick(() => this.pageStack.pop())
          Text(this.mode === 'medals' ? '徽章中心' : '我的状态').layoutWeight(1).fontSize(18)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([TC.textSecondary()])
            .enabled(!this.loading && !this.saving).onClick(() => this.load())
        }.width('100%').height(56).padding({ left: 16, right: 16 }).backdropBlur(30)
        if (this.mode === 'medals') {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(['已获得'].concat((this.medals.categoryMedalBlockVos || []).map((group) => group.categoryTitle)),
                (label: string, index: number) => {
                  Text(label).fontSize(13).fontColor(this.category === index ? TC.accent() : TC.textSecondary())
                    .padding(10).onClick(() => this.category = index)
                })
            }.padding({ left: 12, right: 12 })
          }.width('100%').height(48).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        }
        if (this.loading) { LoadingProgress().width(40).height(40).color(TC.accent()).margin(20) }
        Scroll() {
          Column({ space: 12 }) {
            if (this.mode === 'medals') {
              Text(`已获得 ${this.medals.medalNum || this.medals.obtainMedals?.length || 0} 枚徽章`)
                .width('100%').fontSize(12).fontColor(TC.textSecondary())
              GridRow({ columns: Responsive.columns(this.viewWidth, 2, 3, 4), gutter: 12 }) {
                ForEach(ProfileFeaturesService.medalItems(this.medals, this.category), (medal: UserMedal) => {
                  GridCol() { this.MedalCard(medal) }
                }, (medal: UserMedal) => medal.medalCode)
              }
              if (!this.loading && !ProfileFeaturesService.medalItems(this.medals, this.category).length) {
                Text('暂无徽章').fontColor(TC.textSecondary()).padding(24)
              }
            } else {
              Text('当前状态').width('100%').fontSize(13).fontColor(TC.textSecondary())
              ForEach(this.current, (status: SocialStatus) => { this.StatusRow(status, false) })
              if (!this.current.length && !this.loading) { Text('暂未设置状态').fontColor(TC.textSecondary()) }
              Text(this.saving ? '正在设置…' : '选择状态').width('100%').fontSize(13).fontColor(TC.textSecondary())
              ForEach(this.statuses, (status: SocialStatus) => { this.StatusRow(status, true) })
              if (!this.loading && !this.statuses.length) { Text('暂无可用状态').fontColor(TC.textSecondary()) }
            }
            if (this.message) { Text(this.message).width('100%').fontSize(12).fontColor(TC.accentSoft()) }
          }.width('100%').padding(16)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
        .onAreaChange((_old: Area, area: Area) => this.viewWidth = Number(area.width))
    }.hideTitleBar(true)
  }
}
