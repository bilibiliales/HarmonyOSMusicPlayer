import { common, OpenLinkOptions } from '@kit.AbilityKit'
import { AuthStore } from '../stores/AuthStore'
import { BubbleTip } from '../services/BubbleTip'
import { ApiClient } from '../services/ApiClient'
import { YunbeiService, YunbeiEntry, YunbeiOverview } from '../services/YunbeiService'

@Component
export struct YunbeiPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @State overview: YunbeiOverview = { warnings: [] }
  @State rows: YunbeiEntry[] = []
  @State tab: number = 0
  @State loading: boolean = false
  @State signing: boolean = false
  @State more: boolean = false
  @State message: string = ''
  @State pendingTaskId: number = 0
  @State taskBusy: boolean = false
  @State signMessage: string = ''
  private listOffset: number = 0
  private token: number = 0
  private overviewToken: number = 0
  private confirmedSignDay: string = ''
  private confirmedSignUser: string = ''
  private titles: string[] = ['全部任务', '待办任务', '收入', '支出', '推歌记录']
  private kinds: string[] = ['tasks', 'todo', 'income', 'expense', 'history']

  aboutToDisappear(): void { this.token++; this.overviewToken++ }

  private async refreshOverview(): Promise<void> {
    const generation = ++this.overviewToken
    const cookie = ApiClient.cookie
    this.overview = { warnings: [] }
    if (!this.authStore.loggedIn) { return }
    const result = await YunbeiService.overview()
    if (generation === this.overviewToken && cookie === ApiClient.cookie) {
      const confirmed = this.confirmedSignUser === this.authStore.userId &&
        this.confirmedSignDay === new Date().toDateString()
      if (confirmed) { result.signed = true }
      this.overview = result
    }
  }

  private async load(reset: boolean = true): Promise<void> {
    if (!reset && (this.loading || !this.more)) { return }
    const generation = ++this.token
    const cookie = ApiClient.cookie
    if (reset) { this.rows = []; this.listOffset = 0; this.more = false }
    this.message = ''
    if (!this.authStore.loggedIn) { this.loading = false; return }
    this.loading = true
    try {
      const entries = await YunbeiService.entries(this.kinds[this.tab], this.listOffset)
      if (generation !== this.token || cookie !== ApiClient.cookie) { return }
      this.rows = this.rows.concat(entries)
      this.listOffset += entries.length
      this.more = this.tab >= 2 && entries.length === 20
    } catch (error) {
      if (generation === this.token) { this.message = error instanceof Error ? error.message : '云贝加载失败' }
    } finally { if (generation === this.token) { this.loading = false } }
  }

  private async sign(): Promise<void> {
    if (this.signing || !this.authStore.loggedIn) { return }
    this.signing = true
    this.signMessage = ''
    const cookie = ApiClient.cookie
    try {
      const result = await YunbeiService.sign()
      if (cookie !== ApiClient.cookie) { return }
      this.confirmedSignDay = new Date().toDateString()
      this.confirmedSignUser = this.authStore.userId
      this.overview = { balance: this.overview.balance, signed: true, signDays: this.overview.signDays,
        todayAmount: this.overview.todayAmount, warnings: this.overview.warnings }
      BubbleTip.show(this.getUIContext(), result.signedNow ? '签到成功，云贝+' + result.amount : '今天已经签到过了')
      await this.refreshOverview()
      await this.load()
    } catch (error) {
      if (cookie === ApiClient.cookie) {
        this.signMessage = error instanceof Error ? error.message : '签到失败'
        BubbleTip.show(this.getUIContext(), this.signMessage)
      }
    } finally { this.signing = false }
  }

  private taskIcon(row: YunbeiEntry): Resource {
    if (row.title.includes('音乐') || row.title.includes('歌曲')) { return $r('sys.symbol.music') }
    if (row.title.includes('分享')) { return $r('sys.symbol.arrow_right_up_and_square') }
    if (row.title.includes('关注') || row.title.includes('资料')) { return $r('sys.symbol.person') }
    return $r('sys.symbol.checkmark_circle')
  }

  private async taskAction(row: YunbeiEntry): Promise<void> {
    if (this.taskBusy || row.completed || !row.taskId) { return }
    this.taskBusy = true
    this.signMessage = ''
    try {
      if (this.pendingTaskId === row.taskId) {
        const tasks = await YunbeiService.entries('tasks', 0)
        const current = tasks.find((item: YunbeiEntry) => item.taskId === row.taskId)
        if (!current) { throw new Error('任务已更新，请重新加载') }
        await YunbeiService.finish(current)
        this.signMessage = '已提交核验，以刷新后的任务状态与余额为准'
        this.pendingTaskId = 0
        await this.refreshOverview()
        await this.load()
      } else {
        const link = row.link || ''
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext
        if (link.startsWith('https://') || link.startsWith('http://')) {
          const options: OpenLinkOptions = { appLinkingOnly: false }
          await context.openLink(link, options)
        } else if (link.startsWith('orpheus://')) {
          await context.startAbility({ action: 'ohos.want.action.viewData', uri: link })
        } else { throw new Error('此任务暂未提供可打开的入口') }
        this.pendingTaskId = row.taskId
        this.signMessage = '完成任务后返回，点击“检查完成”进行核验'
      }
    } catch (error) { this.signMessage = error instanceof Error ? error.message : '无法处理任务；部分任务需要安装网易云音乐官方应用' }
    finally { this.taskBusy = false }
  }

  build() {
    NavDestination() {
      Column({ space: 16 }) {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('云贝中心').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#ffffff').layoutWeight(1)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor(['#ffffff'])
            .onClick(() => { this.refreshOverview(); this.load() })
        }.width('100%')
        if (!this.authStore.loggedIn) {
          Text('登录后查看云贝余额、任务和收支记录').fontColor('#a0a0aa')
          Button('登录').onClick(() => this.pageStack.pushPathByName('LoginPage', null))
        } else {
          Column({ space: 10 }) {
            Row({ space: 14 }) {
              Column({ space: 4 }) {
                Text('我的云贝').fontSize(12).fontColor('#9999a4')
                Text(this.overview.balance === undefined ? '暂不可用' : this.overview.balance.toString())
                  .fontSize(36).fontColor('#ef4058').fontWeight(FontWeight.Bold)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button(this.signing ? '签到中…' : this.overview.signed === true ? '已签到' : '签到')
                .height(36).fontSize(14).borderRadius(18).padding({ left: 22, right: 22 })
                .enabled(!this.signing && this.overview.signed !== true).backgroundColor('#ef233c').onClick(() => this.sign())
            }.width('100%')
            if (this.overview.signDays !== undefined) { Text('连续签到 ' + this.overview.signDays + ' 天').fontColor('#9999a4').fontSize(12) }
            if (this.overview.todayAmount !== undefined) { Text('今日签到获得 ' + this.overview.todayAmount + ' 云贝').fontColor('#9999a4').fontSize(12) }
            if (this.signMessage) { Text(this.signMessage).fontSize(12).fontColor('#bbbbc5') }
            ForEach(this.overview.warnings, (warning: string) => { Text(warning).fontSize(11).fontColor('#c39999') })
          }.width('100%').padding({ top: 12, bottom: 12 }).alignItems(HorizontalAlign.Start)
          Scroll() {
            Row({ space: 22 }) {
              ForEach(this.titles, (title: string, index: number) => {
                Text(title).fontSize(14).fontColor(this.tab === index ? '#ffffff' : '#85858f')
                  .fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal)
                  .onClick(() => { if (this.tab !== index) { this.tab = index; this.load() } })
              })
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(38)
          List({ space: 12 }) {
            ForEach(this.rows, (row: YunbeiEntry) => {
              ListItem() {
                Row({ space: 12 }) {
                  if (row.taskId) {
                    Stack() {
                      Circle().width(46).height(46).fill('rgba(239,35,60,0.10)')
                      SymbolGlyph(this.taskIcon(row)).fontSize(24).fontColor(['#ef4058'])
                    }.width(46).height(46)
                  }
                  Column({ space: 6 }) {
                    Row({ space: 6 }) {
                      Text(row.title).fontSize(15).fontColor('#eeeeef').maxLines(2).layoutWeight(1)
                      if (row.taskId && row.amount !== undefined) {
                        Text('+' + row.amount).fontSize(14).fontColor('#ef4058')
                      }
                    }.width('100%')
                    if (row.description) { Text(row.description).fontSize(12).fontColor('#9999a4') }
                    if (row.time) { Text(row.time).fontSize(11).fontColor('#777780') }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (row.taskId) {
                    Button(row.completed ? '已完成' : this.pendingTaskId === row.taskId ? '检查完成' : row.linkText || '去完成')
                      .height(30).fontSize(12).fontColor('#ef4058').backgroundColor(Color.Transparent)
                      .border({ width: 1, color: 'rgba(239,64,88,0.45)' }).borderRadius(16)
                      .padding({ left: 12, right: 12 }).enabled(!row.completed && !this.taskBusy)
                      .opacity(row.completed ? 0.4 : 1).onClick(() => this.taskAction(row))
                  } else if (row.amount !== undefined) { Text(row.amount.toString()).fontSize(18).fontColor('#ef4058') }
                }.width('100%').padding({ top: 10, bottom: 10 })
              }
            })
            ListItem() {
              Column({ space: 12 }) {
                if (this.loading) { LoadingProgress().width(32).height(32).color('#ffffff') }
                else if (this.message) {
                  Text(this.message).fontSize(13).fontColor('#c39999')
                  Button('重试').onClick(() => this.load(this.rows.length === 0))
                } else if (this.rows.length === 0) { Text('暂无记录').fontColor('#888892') }
                else if (this.more) { Button('加载更多').onClick(() => this.load(false)) }
              }.width('100%')
            }
          }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        }
      }.width('100%').height('100%').padding({ top: this.topAvoidHeight + 12, left: 20, right: 20, bottom: 20 })
        .backgroundColor('#121215')
    }.hideTitleBar(true).onShown(() => { this.refreshOverview(); this.load() })
      .onHidden(() => { this.token++; this.overviewToken++ })
  }
}
