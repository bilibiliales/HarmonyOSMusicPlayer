import { ProfileFeaturesService, SocialStatus, StatusUser } from '../services/ProfileFeaturesService'
import { AuthStore } from '../stores/AuthStore'
import { SheetSkinFrame } from './SheetSkin'
import { TC } from '../services/ThemeColors'
import { UserProfilePageParam } from '../models/api'

@Component
export struct UserStatusBadge {
  @Prop @Watch('loadStatus') uid: string = ''
  @Prop @Watch('loadStatus') refreshRevision: number = 0
  @Consume('authStore') @Watch('loadStatus') authStore: AuthStore
  @Consume('pageStack') pageStack: NavPathStack
  @StorageProp('socialStatusRevision') @Watch('loadStatus') revision: number = 0
  @StorageProp('showProfileStatus') @Watch('loadStatus') showProfileStatus: boolean = true
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @State status?: SocialStatus = undefined
  @State sheetVisible: boolean = false
  @State users: StatusUser[] = []
  @State loading: boolean = false
  @State message: string = ''
  private requestSeq: number = 0
  private statusKey: string = ''

  aboutToAppear(): void { this.loadStatus() }
  aboutToDisappear(): void { this.requestSeq++ }

  private async loadStatus(): Promise<void> {
    const key = `${this.uid}:${this.authStore.loggedIn}:${this.authStore.userId}:${this.showProfileStatus}:${this.revision}:${this.refreshRevision}`
    if (key === this.statusKey) { return }
    this.statusKey = key
    const request = ++this.requestSeq
    this.status = undefined
    if (!this.showProfileStatus) { this.sheetVisible = false; return }
    if (!this.uid || !this.authStore.loggedIn) { return }
    try {
      const statuses = await ProfileFeaturesService.currentStatus(this.uid)
      if (request === this.requestSeq) { this.status = statuses.find((status: SocialStatus) => !!status.content.trim()) }
    } catch (_error) {}
  }

  private async open(): Promise<void> {
    if (!this.status) { return }
    this.sheetVisible = true
    this.loading = true
    this.message = ''
    this.users = []
    const request = ++this.requestSeq
    const status = this.status
    try {
      if (this.uid !== this.authStore.userId) {
        const own = await ProfileFeaturesService.currentStatus(this.authStore.userId)
        if (request !== this.requestSeq) { return }
        if (!own.some((item: SocialStatus) => item.type === status.type && item.content === status.content)) {
          this.message = '暂不支持查看这个状态的同状态用户'
          return
        }
      }
      const users = await ProfileFeaturesService.sameStatusUsers()
      if (request !== this.requestSeq) { return }
      this.users = users
    } catch (error) {
      if (request === this.requestSeq) { this.message = error instanceof Error ? error.message : '同状态用户加载失败' }
    }
    finally { if (request === this.requestSeq) { this.loading = false } }
  }

  @Builder
  private StatusSheet() {
    SheetSkinFrame() {
      Column() {
        Row({ space: 12 }) {
          if (this.status?.iconUrl) { Image(this.status.iconUrl).width(28).height(28).objectFit(ImageFit.Contain) }
          Text(this.status?.content || '').layoutWeight(1).fontSize(17).fontColor(TC.textPrimary())
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([TC.textSecondary()])
            .enabled(!this.loading).onClick(() => this.open())
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([TC.textSecondary()]).onClick(() => this.sheetVisible = false)
        }.width('100%').height(56).padding({ left: 18, right: 18 })
        Text('同状态的人').width('100%').fontSize(12).fontColor(TC.textSecondary()).padding({ left: 18, bottom: 8 })
        List({ space: 4 }) {
          ForEach(this.users, (user: StatusUser) => {
            ListItem() {
              Row({ space: 12 }) {
                Image(user.avatarUrl.replace(/^http:/, 'https:')).width(42).height(42).borderRadius(21)
                Text(user.nickname).layoutWeight(1).fontSize(14).fontColor(TC.textPrimary()).maxLines(1)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([TC.textSecondary()])
              }.width('100%').padding(12).onClick(() => {
                this.sheetVisible = false
                const param: UserProfilePageParam = { uid: user.uid }
                this.pageStack.pushPathByName('UserProfilePage', param)
              })
            }
          }, (user: StatusUser) => user.uid)
          ListItem() {
            Column({ space: 12 }) {
              if (this.loading) { LoadingProgress().width(32).height(32).color(TC.accent()) }
              Text(this.message || (this.loading ? '加载中…' : this.users.length ? '已经到底了' : '暂无同状态用户'))
                .fontSize(12).fontColor(TC.textSecondary()).textAlign(TextAlign.Center)
              if (this.message && this.message !== '暂不支持查看这个状态的同状态用户') {
                Button('重新加载').onClick(() => this.open())
              }
            }.width('100%').padding(20)
          }
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%')
    }
  }

  build() {
    Row({ space: 4 }) {
      if (this.status?.iconUrl) { Image(this.status.iconUrl.replace(/^http:/, 'https:')).width(16).height(16).objectFit(ImageFit.Contain) }
      Text(this.status?.content || '').fontSize(11).fontColor(TC.textPrimary()).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(14).backgroundColor(TC.surfaceCard())
      .constraintSize({ maxWidth: '100%' }).justifyContent(FlexAlign.Center)
      .visibility(this.showProfileStatus && this.status ? Visibility.Visible : Visibility.None).onClick(() => this.open())
      .bindSheet(this.sheetVisible, this.StatusSheet(), { height: '68%', backgroundColor: TC.sheetBackground(),
        showClose: false, dragBar: true, onDisappear: () => { this.sheetVisible = false; this.requestSeq++ } })
  }
}
