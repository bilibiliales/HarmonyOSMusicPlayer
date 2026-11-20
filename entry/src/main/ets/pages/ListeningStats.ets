import { SkinBackdrop } from '../components/SkinBackdrop'
import {
  ApiParam,
  ListenDataResponse,
  ListenDataValue,
  ListenReportData,
  ListenReportAgeSection,
  ListenReportLanguageSection,
  ListenReportResponse,
  ListenReportStyleSection,
  ListenReportTopArtistSection,
  ListenReportTopSongSection,
  ListenTimePeriodDuration
} from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'
import {
  buildListeningPeriod, ListeningDay, ListeningPeriod, listeningDayBackground, listeningDayColor,
  listeningPeriodEnd, listeningPeriodOffsetLabel, listeningPeriodStart, listeningPeriodTitle, listeningTimeValue
} from '../services/ListeningFootprint'
import { TC } from '../services/ThemeColors'

@Component
export struct ListeningStatsPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @State total: ListenDataValue | null = null
  @State weekReport: ListenReportData | null = null
  @State monthReport: ListenReportData | null = null
  @State loading: boolean = true
  @State message: string = ''
  @State currentPeriod: string = 'week'
  @State weekChart: ListeningPeriod | null = null
  @State monthChart: ListeningPeriod | null = null
  @State selectedDay: string = ''
  @State weekMessage: string = ''
  @State monthMessage: string = ''
  /** 0 = 本周/本月（不传 endTime）；负数 = 往前翻了几个周期。周、月各自独立。 */
  @State weekOffset: number = 0
  @State monthOffset: number = 0
  @State switching: boolean = false
  /** 不带 endTime 请求返回的 endTime，作为所有翻页的唯一基准（毫秒）。 */
  @State weekBaseEnd: number = 0
  @State monthBaseEnd: number = 0
  /** 每次数据落到界面上自增：用来重建下面的整块内容，避免参数化 @Builder 复用到旧值。 */
  @State dataRevision: number = 0

  /** 已翻过的周期缓存，来回切换不再重复请求。 */
  private reportCache: Map<string, ListenReportData> = new Map<string, ListenReportData>()
  private emptyCache: Map<string, string> = new Map<string, string>()

  private cacheKey(period: string, offset: number): string { return `${period}:${offset}` }
  private offsetFor(period: string): number { return period === 'week' ? this.weekOffset : this.monthOffset }
  private activeOffset(): number { return this.offsetFor(this.currentPeriod) }
  private baseEndFor(period: string): number { return period === 'week' ? this.weekBaseEnd : this.monthBaseEnd }

  /**
   * 只用接口基准递减：offset=0 不传 endTime，offset<0 从「接口返回的本周/本月 endTime」往前推。
   * 不按本地今天推算——接口的周/月切分和本地未必一致，自己算会和数据错位。
   */
  private endTimeFor(period: string, offset: number): number {
    return listeningPeriodEnd(period, this.baseEndFor(period), offset)
  }

  /** 当前选中的周期第一天（画日期网格用），与 endTime 同源。 */
  private periodStartFor(period: string, offset: number): Date | null {
    const base = this.baseEndFor(period)
    if (base <= 0) { return null }
    return listeningPeriodStart(period, base, offset)
  }

  /** 首次（不传 endTime）成功后记录基准；缺 endTime 时用 startTime 补算。 */
  private calibrateBase(period: string, data: ListenReportData): void {
    let end = listeningTimeValue(data.endTime)
    const start = listeningTimeValue(data.startTime)
    if (end <= 0 && start > 0) {
      if (period === 'week') {
        end = start + 6 * 24 * 60 * 60 * 1000
      } else {
        const d = new Date(start)
        const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
        end = start + (days - 1) * 24 * 60 * 60 * 1000
      }
    }
    if (end <= 0) { return }
    if (period === 'week') { this.weekBaseEnd = end } else { this.monthBaseEnd = end }
  }

  /**
   * 返回的数据是否就是请求的那个周期。
   * 服务端万一忽略 endTime 又回了默认的本周/本月，界面会出现「标题是上周、数据是本周」，
   * 所以这里按 startTime 做一次校验（拿不到 startTime 时只能信任服务端）。
   */
  private matchesPeriod(period: string, offset: number, data: ListenReportData): boolean {
    const start = listeningTimeValue(data.startTime)
    if (start <= 0) { return true }
    const expected = this.periodStartFor(period, offset)
    if (!expected) { return true }
    const actual = new Date(start)
    if (period === 'month') {
      return actual.getFullYear() === expected.getFullYear() && actual.getMonth() === expected.getMonth()
    }
    // 周边界可能因时区/零点差一天，给 1.5 天容差
    return Math.abs(actual.getTime() - expected.getTime()) <= 36 * 60 * 60 * 1000
  }

  private activeReport(): ListenReportData | null { return this.currentPeriod === 'week' ? this.weekReport : this.monthReport }
  private activeChart(): ListeningPeriod | null { return this.currentPeriod === 'week' ? this.weekChart : this.monthChart }
  private activeMessage(): string { return this.currentPeriod === 'week' ? this.weekMessage : this.monthMessage }

  private activeChartTitle(): string {
    const chart = this.activeChart()
    return chart ? chart.title :
      listeningPeriodTitle(this.currentPeriod, this.baseEndFor(this.currentPeriod), this.activeOffset())
  }

  /** 下一周期：最多回到最新的本周/本月，不能翻到未来。 */
  private canGoNewer(): boolean { return this.activeOffset() < 0 }

  /** 上一周期：限制最大回溯范围，并保证时间戳仍有效。 */
  private canGoOlder(): boolean {
    const next = this.activeOffset() - 1
    if (this.currentPeriod === 'week' ? next < -104 : next < -60) { return false }
    return this.endTimeFor(this.currentPeriod, next) > 0
  }

  private switchPeriod(period: string): void {
    this.currentPeriod = period
    this.selectedDay = ''
  }

  /** delta = -1 上一周期，+1 下一周期。 */
  private async stepPeriod(delta: number): Promise<void> {
    if (this.switching || this.loading) { return }
    if (delta < 0 && !this.canGoOlder()) { return }
    if (delta > 0 && !this.canGoNewer()) { return }
    const period = this.currentPeriod
    const next = this.offsetFor(period) + delta
    if (period === 'week') { this.weekOffset = next } else { this.monthOffset = next }
    this.selectedDay = ''
    this.switching = true
    await this.loadReport(period, next)
    this.switching = false
  }

  private async fetchReport(period: string, endTime: number, seconds: boolean): Promise<ListenReportResponse> {
    const params: ApiParam[] = [{ key: 'type', value: period }]
    if (endTime > 0) {
      // 先按毫秒传（与接口返回的 endTime 同单位），空数据时再退回秒
      params.push({ key: 'endTime', value: (seconds ? Math.floor(endTime / 1000) : endTime).toString() })
    }
    return await ApiClient.get<ListenReportResponse>('/listen/data/report', params)
  }

  private applyReport(period: string, offset: number, data: ListenReportData | null, errorMessage: string): void {
    // 异步返回时用户可能已翻到别的周期，此时结果只留在缓存里，不覆盖当前展示
    if (this.offsetFor(period) !== offset) { return }
    const monthly = period === 'month'
    // 网格优先用接口返回的 startTime（那是这份数据的权威周期）；
    // 只有接口没给 startTime 时，才用与 endTime 同源的周期起点兜底，保证不会画错月份。
    const hasApiStart = data !== null && listeningTimeValue(data.startTime) > 0
    const start = !hasApiStart && offset !== 0 ? this.periodStartFor(period, offset) : null
    let chart: ListeningPeriod | null = null
    if (data) { chart = buildListeningPeriod(data, monthly, new Date(), start ?? undefined) }
    if (period === 'week') {
      this.weekReport = data
      this.weekChart = chart
      this.weekMessage = errorMessage
    } else {
      this.monthReport = data
      this.monthChart = chart
      this.monthMessage = errorMessage
    }
    this.dataRevision++
  }

  private async loadReport(period: string, offset: number): Promise<void> {
    const key = this.cacheKey(period, offset)
    if (this.reportCache.has(key)) {
      this.applyReport(period, offset, this.reportCache.get(key) ?? null, '')
      return
    }
    if (this.emptyCache.has(key)) {
      this.applyReport(period, offset, null, this.emptyCache.get(key) || '暂无该周期的听歌足迹')
      return
    }
    const endTime = this.endTimeFor(period, offset)
    // 翻到历史周期却还没有基准（本周/本月还没回来）：不要发不带 endTime 的请求，
    // 否则会把「本周」的数据当成历史周期显示。
    if (offset !== 0 && endTime <= 0) {
      // 不写缓存：等基准到了再次点击就能正常请求
      this.applyReport(period, offset, null, '本周数据还没加载完成，稍后再试')
      return
    }
    try {
      let response = await this.fetchReport(period, endTime, false)
      let data = response.data
      // 毫秒没拿到「该周期的」数据时退回秒级再试一次
      if (endTime > 0 && (response.code !== 200 || !data || !this.matchesPeriod(period, offset, data))) {
        const retry = await this.fetchReport(period, endTime, true)
        if (retry.code === 200 && retry.data && this.matchesPeriod(period, offset, retry.data)) {
          response = retry
          data = retry.data
        }
      }
      if (response.code !== 200 || !data) {
        throw new Error(response.message || '暂无该周期的听歌足迹')
      }
      // 服务端忽略了 endTime、回的还是当前周期：宁可显示暂无，也不要张冠李戴
      if (!this.matchesPeriod(period, offset, data)) {
        throw new Error('该周期暂无听歌足迹')
      }
      if (offset === 0) { this.calibrateBase(period, data) }
      this.reportCache.set(key, data)
      this.applyReport(period, offset, data, '')
    } catch (error) {
      const text = error instanceof Error ? error.message : '听歌报告加载失败'
      this.emptyCache.set(key, text)
      this.applyReport(period, offset, null, text)
    }
  }

  private async retryCurrent(): Promise<void> {
    if (this.switching) { return }
    const period = this.currentPeriod
    const offset = this.activeOffset()
    const key = this.cacheKey(period, offset)
    this.reportCache.delete(key)
    this.emptyCache.delete(key)
    this.switching = true
    await this.loadReport(period, offset)
    this.switching = false
    if (!this.total) { await this.loadTotal() }
  }

  private async loadTotal(): Promise<void> {
    try {
      const response = await ApiClient.get<ListenDataResponse>('/listen/data/total')
      if (response.code === 200) { this.total = response.data || null }
    } catch (_error) {}
  }

  aboutToAppear(): void {
    this.loadData()
  }

  private async loadData(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.loading = false
      this.message = '登录后才能获取听歌足迹'
      return
    }
    this.loading = true
    this.message = ''
    this.weekMessage = ''
    this.monthMessage = ''
    await Promise.all([
      this.loadTotal(),
      this.loadReport('week', this.weekOffset),
      this.loadReport('month', this.monthOffset)
    ])
    if (!this.total && !this.weekReport && !this.monthReport) {
      this.message = this.activeMessage() || '暂无听歌足迹'
    }
    this.loading = false
  }

  private totalDuration(): number {
    if (!this.total) {
      return 0
    }
    const raw = this.total.totalTime || this.total.totalDuration || this.total.duration || this.total.listenTime || 0
    return raw
  }

  private formatDuration(raw: number): string {
    if (raw <= 0) {
      return '0 分钟'
    }
    const milliseconds = raw > 100000000 ? raw : raw * 1000
    const hours = Math.floor(milliseconds / 3600000)
    const minutes = Math.floor(milliseconds % 3600000 / 60000)
    if (hours > 0) {
      return `${hours} 小时 ${minutes} 分钟`
    }
    return `${minutes} 分钟`
  }

  private formatTotalDuration(): string {
    return this.formatDuration(this.totalDuration())
  }

  private formatPlayDuration(value: number | undefined): string {
    if (!value || value <= 0) {
      return '0 分钟'
    }
    const minutes = Math.floor(value)
    if (minutes === 0) { return '不足 1 分钟' }
    if (minutes >= 60) {
      const h = Math.floor(minutes / 60)
      const m = minutes % 60
      return m > 0 ? `${h} 小时 ${m} 分钟` : `${h} 小时`
    }
    return `${minutes} 分钟`
  }

  private totalSongCount(): number {
    return this.total?.songCount || this.total?.count || 0
  }

  private formatPeriodName(period: string): string {
    const map: Record<string, string> = {
      'early_morning': '凌晨',
      'morning': '上午',
      'noon': '中午',
      'afternoon': '下午',
      'night': '晚上',
      'deep_night': '深夜'
    }
    return map[period] || period
  }

  private periodLabel(): string {
    return listeningPeriodOffsetLabel(this.currentPeriod, this.activeOffset())
  }

  private percent(value?: string): number { return Math.max(0, Math.min(100, parseFloat(value || '0') || 0)) }

  @Builder
  private CardHeading(title: string) {
    Text(title).width('100%').fontSize(28).fontWeight(FontWeight.Bold).fontColor(TC.textQuaternary())
  }

  @Builder
  private TopSongSection(report: ListenReportData | null, label: string) {
    if (report?.topSongBlock?.sections?.length) {
      Column({ space: 18 }) {
        Row({ space: 18 }) {
          Column({ space: 16 }) {
            this.CardHeading(`${label}\n单曲`)
            Text('TOP').fontSize(15).fontWeight(FontWeight.Bold).fontColor(TC.accentSoft())
            Text(report.topSongBlock.sections[0].text || '').fontSize(30).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
            Text(report.topSongBlock.sections[0].songName || '').fontSize(23).fontWeight(FontWeight.Bold)
              .fontColor(TC.textBody()).maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (report.topSongBlock.sections[0].picUrl) {
            Image(report.topSongBlock.sections[0].picUrl).width(108).height(108).borderRadius(12).objectFit(ImageFit.Cover)
          }
        }.width('100%').alignItems(VerticalAlign.Top)
        ForEach(report.topSongBlock.sections.slice(1, 3), (section: ListenReportTopSongSection, index: number) => {
          Row({ space: 14 }) {
            Image(section.picUrl || '').width(64).height(64).borderRadius(10).objectFit(ImageFit.Cover)
            Column({ space: 4 }) {
              Text(`收听 TOP ${index + 2}`).fontSize(11).fontColor(TC.accentSoft())
              Text(section.text || '').fontSize(22).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              Text(section.songName || '').fontSize(13).fontColor(TC.textBody()).maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor(TC.surfaceCard()).borderRadius(22)
    }
  }

  @Builder
  private TopArtistSection(report: ListenReportData | null, label: string) {
    if (report?.topArtistBlock?.sections?.length) {
      Column({ space: 18 }) {
        Row({ space: 18 }) {
          Column({ space: 14 }) {
            this.CardHeading(`${label}\n音乐人`)
            Text('TOP').fontSize(15).fontColor(TC.accentSoft()).fontWeight(FontWeight.Bold)
            Text(report.topArtistBlock.sections[0].text || '').fontSize(28).fontColor(TC.textPrimary()).fontWeight(FontWeight.Bold)
            Text(report.topArtistBlock.sections[0].artistName || '').fontSize(22).fontColor(TC.textBody()).maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Image(report.topArtistBlock.sections[0].picUrl || '').width(108).height(108).borderRadius(54).objectFit(ImageFit.Cover)
        }.width('100%').alignItems(VerticalAlign.Top)
        ForEach(report.topArtistBlock.sections.slice(1), (section: ListenReportTopArtistSection) => {
          Row({ space: 14 }) {
            Image(section.picUrl || '').width(60).height(60).borderRadius(30).objectFit(ImageFit.Cover)
            Column({ space: 5 }) {
              Text(section.field || '').fontSize(11).fontColor(TC.accentSoft())
              Text(section.text || '').fontSize(20).fontColor(TC.textPrimary()).fontWeight(FontWeight.Bold)
              Text(section.artistName || '').fontSize(13).fontColor(TC.textBody()).maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor(TC.surfaceCard()).borderRadius(22)
    }
  }

  @Builder
  private StyleSection(report: ListenReportData | null, label: string) {
    if (report?.topStyleBlock?.sections?.length) {
      Column({ space: 18 }) {
        this.CardHeading(`${label}曲风`)
        Column({ space: 6 }) {
          Text('TOP').fontSize(15).fontColor(TC.accentSoft()).fontWeight(FontWeight.Bold)
          Text(report.topStyleBlock.genreName || report.topStyleBlock.sections[0].genreName || '')
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        }.width('100%').alignItems(HorizontalAlign.Start)
        ForEach(report.topStyleBlock.sections.slice(0, 3), (section: ListenReportStyleSection) => {
          Row({ space: 8 }) {
            Stack({ alignContent: Alignment.Start }) {
              Row().width(`${this.percent(section.percent)}%`).constraintSize({ minWidth: 60 }).height(26)
                .borderRadius(13).linearGradient({ angle: 90, colors: [['#ef233c', 0], ['#ff6577', 1]] })
              Text(section.genreName || '').fontSize(12).fontColor(TC.textPrimary()).padding({ left: 10 })
            }.layoutWeight(1).height(26)
            Text(`${this.percent(section.percent)}%`).fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textBody()).width(48)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor(TC.surfaceCard()).borderRadius(22)
    }
  }

  @Builder
  private AgeSection(report: ListenReportData | null, label: string) {
    if (report?.topAgeBlock?.sections?.length) {
      Column({ space: 22 }) {
        this.CardHeading(`${label}听歌年代`)
        ForEach(report.topAgeBlock.sections, (section: ListenReportAgeSection) => {
          Row({ space: 16 }) {
            Text(section.age || '').width(72).fontSize(19).fontWeight(FontWeight.Bold).fontColor(TC.textBody())
            Column().width(2).height(58).backgroundColor(TC.divider())
            if (section.picUrl) { Image(section.picUrl).width(58).height(58).borderRadius(8).objectFit(ImageFit.Cover) }
            Column({ space: 6 }) {
              Text(`${section.playSongNum || 0} 首`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              if (section.songName) { Text(section.songName).fontSize(12).fontColor(TC.textSecondary()).maxLines(1) }
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor(TC.surfaceCard()).borderRadius(22)
    }
  }

  @Builder
  private LanguageSection(report: ListenReportData | null, label: string) {
    if (report?.topLanguageBlock?.sections?.length) {
      Column({ space: 20 }) {
        this.CardHeading(`${label}听歌语言`)
        Row({ space: 12 }) {
          ForEach(report.topLanguageBlock.sections.slice(0, 3), (section: ListenReportLanguageSection, index: number) => {
            Column({ space: 7 }) {
              if (index === 0) { Text('TOP').fontSize(12).fontColor(TC.accentSoft()).fontWeight(FontWeight.Bold) }
              Text(`${this.percent(section.percent)}%`).fontSize(index === 0 ? 30 : 24).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              Text(section.language || '').fontSize(18).fontColor(TC.textBody())
              if (section.picUrl) {
                Image(section.picUrl).width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(8)
              } else {
                Column().width('100%').height(Math.max(18, this.percent(section.percent) * 1.6))
                  .borderRadius({ topLeft: 8, topRight: 8 }).backgroundColor(TC.accent())
              }
              Text(section.songName || '').fontSize(10).fontColor(TC.textSecondary()).maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          })
        }.width('100%').alignItems(VerticalAlign.Bottom)
      }.width('100%').padding(20).backgroundColor(TC.surfaceCard()).borderRadius(22)
    }
  }

  private maxDuration(durations: ListenTimePeriodDuration[]): number {
    let maxVal: number = 1
    for (let i = 0; i < durations.length; i++) {
      if (durations[i].duration > maxVal) {
        maxVal = durations[i].duration
      }
    }
    return maxVal
  }

  @Builder
  private TimeDistributionSection(report: ListenReportData | null, label: string) {
    if (report?.listenTimeBlock?.circleTimePeriodDurations?.length) {
      Column({ space: 20 }) {
        this.CardHeading('听歌时段分布')
        ForEach(report.listenTimeBlock.circleTimePeriodDurations, (item: ListenTimePeriodDuration) => {
          Column({ space: 9 }) {
            Row() {
              Text(this.formatPeriodName(item.period)).fontSize(16).fontColor(TC.textBody())
              Blank()
              Text(this.formatPlayDuration(item.duration)).fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
            }.width('100%')
            Stack({ alignContent: Alignment.Start }) {
              Column().width('100%').height(12).borderRadius(6).backgroundColor(TC.surfaceRaised())
              Column().width(`${Math.max(0, item.duration) / this.maxDuration(report.listenTimeBlock!.circleTimePeriodDurations!) * 100}%`)
                .height(12).borderRadius(6)
                .linearGradient({ angle: 90, colors: [['#ef233c', 0], ['#ff6577', 1]] })
            }.width('100%').height(12)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor(TC.surfaceCard()).borderRadius(22)
    }
  }

  @Builder
  private DayBubble(day: ListeningDay) {
    Column({ space: 5 }) {
      Text(day.key.replace(/-/g, '.')).fontSize(12).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
      Text(day.future ? '尚未到来' : !day.reported ? '暂无数据' : `听歌 ${this.formatPlayDuration(day.minutes)}`)
        .fontSize(14).fontColor(TC.textBody())
    }.padding(12)
  }

  private peakDay(chart: ListeningPeriod): ListeningDay | undefined {
    return chart.days.filter((day: ListeningDay) => day.minutes > 0)
      .sort((a: ListeningDay, b: ListeningDay) => b.minutes - a.minutes)[0]
  }

  @Builder
  private PeriodTabs() {
    Row() {
      ForEach(['week', 'month'], (period: string) => {
        Column({ space: 7 }) {
          Text(period === 'week' ? '周报' : '月报').fontSize(15)
            .fontWeight(this.currentPeriod === period ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.currentPeriod === period ? TC.textPrimary() : TC.textTertiary())
          Column().width(24).height(3).borderRadius(2)
            .backgroundColor(this.currentPeriod === period ? TC.accent() : 'transparent')
        }.layoutWeight(1).height(48).justifyContent(FlexAlign.Center)
          .onClick(() => this.switchPeriod(period))
      })
    }.width('100%')
  }

  private navigatorHint(): string {
    if (this.switching) { return '正在加载该周期…' }
    return `${listeningPeriodOffsetLabel(this.currentPeriod, this.activeOffset())} · 左右箭头切换周期`
  }

  /** 左箭头 = 上一周期，右箭头 = 下一周期；周 / 月各自独立，年度暂不开放。 */
  @Builder
  private PeriodNavigator() {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([TC.textPrimary()])
      }
      .width(38).height(38).borderRadius(19)
      .backgroundColor(TC.surfaceRaised())
      .justifyContent(FlexAlign.Center)
      .opacity(this.canGoOlder() && !this.switching ? 1 : 0.35)
      .onClick(() => this.stepPeriod(-1))

      Column({ space: 3 }) {
        Text(this.activeChartTitle()).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(TC.textPrimary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.navigatorHint())
          .fontSize(10).fontColor(TC.textTertiary()).maxLines(1)
      }.layoutWeight(1).alignItems(HorizontalAlign.Center)

      Row() {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([TC.textPrimary()])
      }
      .width(38).height(38).borderRadius(19)
      .backgroundColor(TC.surfaceRaised())
      .justifyContent(FlexAlign.Center)
      .opacity(this.canGoNewer() && !this.switching ? 1 : 0.35)
      .onClick(() => this.stepPeriod(1))
    }
    .width('100%').height(58).padding({ left: 16, right: 16 })
  }

  @Builder
  private WeekBars(chart: ListeningPeriod) {
    Row({ space: 8 }) {
      Column() {
        Text(this.formatPlayDuration(chart.axisMinutes)).fontSize(9).fontColor(TC.textTertiary())
        Blank()
        Text(this.formatPlayDuration(chart.axisMinutes / 2)).fontSize(9).fontColor(TC.textTertiary())
        Blank()
        Text('0分钟').fontSize(9).fontColor(TC.textTertiary())
      }.width(38).height(190).margin({ bottom: 30 })
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Divider().color(TC.surfaceRaised())
          Blank()
          Divider().color(TC.surfaceRaised())
          Blank()
          Divider().color(TC.surfaceRaised())
        }.width('100%').height(190).margin({ bottom: 30 })
        Row({ space: 6 }) {
          ForEach(chart.days, (day: ListeningDay) => {
            Column({ space: 10 }) {
              Column() {
                Blank()
                Column().width('100%').height(day.minutes > 0 ? Math.max(8, day.minutes / chart.axisMinutes * 190) : 2)
                  .backgroundColor(listeningDayBackground(day)).borderRadius(24)
                  .linearGradient({ angle: 180, colors: [
                    [day.minutes >= 60 ? '#ef233c' : listeningDayBackground(day), 0],
                    [day.minutes >= 60 ? '#ff6577' : listeningDayBackground(day), 1]
                  ] })
                  .bindPopup(this.selectedDay === day.key, {
                    builder: () => { this.DayBubble(day) }, placement: Placement.Top, popupColor: TC.sheetBackground(),
                    onStateChange: (event) => { if (!event.isVisible && this.selectedDay === day.key) { this.selectedDay = '' } }
                  })
              }.width('100%').height(190)
              Text(day.weekday).fontSize(12).fontColor(TC.textSecondary()).height(20)
            }.layoutWeight(1).onClick(() => this.selectedDay = this.selectedDay === day.key ? '' : day.key)
          }, (day: ListeningDay) => day.key)
        }.width('100%').alignItems(VerticalAlign.Bottom)
      }.layoutWeight(1).height(220)
    }.width('100%').alignItems(VerticalAlign.Bottom).margin({ top: 28 })
  }

  @Builder
  private MonthCalendar(chart: ListeningPeriod) {
    Column({ space: 12 }) {
      Row() {
        ForEach(['日', '一', '二', '三', '四', '五', '六'], (label: string) => {
          Text(label).layoutWeight(1).fontSize(12).fontColor(TC.textTertiary()).textAlign(TextAlign.Center)
        })
      }.width('100%')
      ForEach(chart.rows, (week: ListeningDay[]) => {
        Row() {
          ForEach(week, (day: ListeningDay) => {
            Stack() {
              if (day.day > 0) {
                Circle().width(32).height(32).fill(listeningDayBackground(day))
                  .stroke(day.minutes > 0 ? 'transparent' : TC.textTertiary()).strokeWidth(1).strokeDashArray([2, 2])
                Text(day.day.toString()).fontSize(14).fontWeight(FontWeight.Bold).fontColor(listeningDayColor(day))
              }
            }.layoutWeight(1).height(38)
              .onClick(() => { if (day.day > 0) { this.selectedDay = this.selectedDay === day.key ? '' : day.key } })
              .bindPopup(day.day > 0 && this.selectedDay === day.key, {
                builder: () => { this.DayBubble(day) }, placement: Placement.Top, popupColor: TC.sheetBackground(),
                onStateChange: (event) => { if (!event.isVisible && this.selectedDay === day.key) { this.selectedDay = '' } }
              })
          }, (day: ListeningDay) => day.key)
        }.width('100%').height(38)
      }, (week: ListeningDay[]) => week.map((day: ListeningDay) => day.key).join(','))
    }.width('100%').margin({ top: 14 })
  }

  @Builder
  private DurationCard(chart: ListeningPeriod, label: string) {
    Column({ space: 12 }) {
      this.CardHeading(`${label}收听时长`)
      Text() {
        if (chart.totalMinutes >= 60) {
          Span(Math.floor(chart.totalMinutes / 60).toString()).fontSize(44).fontWeight(FontWeight.Bold)
          Span('小时').fontSize(21).fontWeight(FontWeight.Medium)
        }
        Span(Math.floor(chart.totalMinutes % 60).toString()).fontSize(44).fontWeight(FontWeight.Bold)
        Span('分').fontSize(21).fontWeight(FontWeight.Medium)
      }.width('100%').fontColor(TC.textPrimary()).textAlign(TextAlign.End).margin({ top: 12 })
      Text(`已听 ${chart.listenedDays}/${chart.days.length} 天`).width('100%')
        .fontSize(13).fontColor(TC.textSecondary()).textAlign(TextAlign.End)
      if (this.currentPeriod === 'week') { this.WeekBars(chart) } else { this.MonthCalendar(chart) }
      Row({ space: 16 }) {
        Column({ space: 7 }) {
          Text('收听日均').fontSize(12).fontColor(TC.textSecondary())
          Text(this.formatPlayDuration(chart.listenedDays > 0 ? chart.totalMinutes / chart.listenedDays : 0))
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          Text('按有收听记录的天数计算').fontSize(10).fontColor(TC.textTertiary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 7 }) {
          Text('单日最长').fontSize(12).fontColor(TC.textSecondary())
          Text(this.formatPlayDuration(this.peakDay(chart)?.minutes))
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          Text(this.peakDay(chart)?.key.replace(/-/g, '.') || '暂无收听记录').fontSize(10).fontColor(TC.textTertiary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ top: 14, bottom: 4 })
    }.width('100%').padding(20).backgroundColor(TC.surfaceCard()).borderRadius(22)
  }

  @Builder
  private ReportDetail(report: ListenReportData | null, label: string) {
    Column({ space: 12 }) {
      this.TopSongSection(report, label)
      this.TopArtistSection(report, label)
      this.StyleSection(report, label)
      this.AgeSection(report, label)
      this.LanguageSection(report, label)
      this.TimeDistributionSection(report, label)
    }
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24).fontColor([TC.textPrimary()]).onClick(() => this.pageStack.pop())
          Column({ space: 3 }) {
            Text('听歌足迹').fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
            Text(`总时长 ${this.formatTotalDuration()}`).fontSize(11).fontColor(TC.textSecondary())
          }.layoutWeight(1)
          Column().width(24)
        }
        .height(56).width('100%').padding({ left: 16, right: 16 })

        this.PeriodTabs()
        this.PeriodNavigator()

        if (this.loading) {
          LoadingProgress().layoutWeight(1).width(46).color(TC.accent())
        } else if (!this.total && !this.weekReport && !this.monthReport) {
          Column({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.clock')).fontSize(44).fontColor([TC.textQuaternary()])
            Text(this.message).fontSize(13).fontColor(TC.textTertiary()).textAlign(TextAlign.Center)
            if (!this.authStore.loggedIn) {
              Button('去登录').fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
                .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
            }
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center).padding(24)
        } else {
          Scroll() {
            // 用周期 + 数据版本做 key：换周期或新数据到达时整块重建，
            // 避免有参 @Builder 复用旧值导致「标题变了、下面还是上一份数据」。
            ForEach([`${this.currentPeriod}:${this.activeOffset()}:${this.dataRevision}`], (token: string) => {
              Column({ space: 16 }) {

                if (this.activeChart()) {
                  if (this.currentPeriod === 'week' && this.weekChart) {
                    this.DurationCard(this.weekChart, this.periodLabel())
                    this.ReportDetail(this.weekReport, this.periodLabel())
                  } else if (this.currentPeriod === 'month' && this.monthChart) {
                    this.DurationCard(this.monthChart, this.periodLabel())
                    this.ReportDetail(this.monthReport, this.periodLabel())
                  }
                } else {
                  Text(this.activeMessage() || '暂无该周期的听歌数据').width('100%').fontSize(13)
                    .fontColor(TC.textSecondary()).textAlign(TextAlign.Center).padding(24)
                  Button('重新加载').fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
                    .onClick(() => this.retryCurrent())
                }

                Text('听歌足迹数据由网易云接口提供，部分账号或数据维度可能需要会员权益。')
                  .width('100%').fontSize(11).lineHeight(18).fontColor(TC.textQuaternary())
                  .padding(16).backgroundColor(TC.surfaceCardAlt()).borderRadius(16)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 32 })
            }, (token: string) => token)
          }
          .layoutWeight(1)
        }
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
