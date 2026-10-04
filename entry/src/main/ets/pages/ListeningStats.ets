import {
  ListenDataResponse,
  ListenDataValue,
  ListenReportData,
  ListenReportSection,
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
import { buildListeningPeriod, ListeningDay, ListeningPeriod, listeningDayBackground, listeningDayColor } from '../services/ListeningFootprint'

@Component
export struct ListeningStatsPage {
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

  private activeReport(): ListenReportData | null { return this.currentPeriod === 'week' ? this.weekReport : this.monthReport }
  private activeChart(): ListeningPeriod | null { return this.currentPeriod === 'week' ? this.weekChart : this.monthChart }
  private activeMessage(): string { return this.currentPeriod === 'week' ? this.weekMessage : this.monthMessage }

  private switchPeriod(period: string): void {
    this.currentPeriod = period
    this.selectedDay = ''
  }

  private async loadReport(period: string): Promise<void> {
    try {
      const response = await ApiClient.get<ListenReportResponse>('/listen/data/report', [{ key: 'type', value: period }])
      if (response.code !== 200 || !response.data) { throw new Error(response.message || '暂无该周期的听歌报告') }
      if (period === 'week') {
        this.weekReport = response.data
        this.weekChart = buildListeningPeriod(response.data, false)
      } else {
        this.monthReport = response.data
        this.monthChart = buildListeningPeriod(response.data, true)
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : '听歌报告加载失败'
      if (period === 'week') { this.weekMessage = message } else { this.monthMessage = message }
    }
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
    await Promise.all([this.loadTotal(), this.loadReport('week'), this.loadReport('month')])
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
    const day = this.activeChart()?.days[0]
    return this.currentPeriod === 'week' ? '本周' : day ? `${Number(day.key.substring(5, 7))}月` : '本月'
  }

  private percent(value?: string): number { return Math.max(0, Math.min(100, parseFloat(value || '0') || 0)) }

  @Builder
  private CardHeading(title: string) {
    Text(title).width('100%').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#55555f')
  }

  @Builder
  private TopSongSection(report: ListenReportData | null) {
    if (report?.topSongBlock?.sections?.length) {
      Column({ space: 18 }) {
        Row({ space: 18 }) {
          Column({ space: 16 }) {
            this.CardHeading(`${this.periodLabel()}\n单曲`)
            Text('TOP').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#ff6577')
            Text(report.topSongBlock.sections[0].text || '').fontSize(30).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            Text(report.topSongBlock.sections[0].songName || '').fontSize(23).fontWeight(FontWeight.Bold)
              .fontColor('#ededf0').maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (report.topSongBlock.sections[0].picUrl) {
            Image(report.topSongBlock.sections[0].picUrl).width(108).height(108).borderRadius(12).objectFit(ImageFit.Cover)
          }
        }.width('100%').alignItems(VerticalAlign.Top)
        ForEach(report.topSongBlock.sections.slice(1, 3), (section: ListenReportTopSongSection, index: number) => {
          Row({ space: 14 }) {
            Image(section.picUrl || '').width(64).height(64).borderRadius(10).objectFit(ImageFit.Cover)
            Column({ space: 4 }) {
              Text(`收听 TOP ${index + 2}`).fontSize(11).fontColor('#ff6577')
              Text(section.text || '').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              Text(section.songName || '').fontSize(13).fontColor('#b5b5bc').maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor('#1b1b20').borderRadius(22)
    }
  }

  @Builder
  private TopArtistSection(report: ListenReportData | null) {
    if (report?.topArtistBlock?.sections?.length) {
      Column({ space: 18 }) {
        Row({ space: 18 }) {
          Column({ space: 14 }) {
            this.CardHeading(`${this.periodLabel()}\n音乐人`)
            Text('TOP').fontSize(15).fontColor('#ff6577').fontWeight(FontWeight.Bold)
            Text(report.topArtistBlock.sections[0].text || '').fontSize(28).fontColor('#ffffff').fontWeight(FontWeight.Bold)
            Text(report.topArtistBlock.sections[0].artistName || '').fontSize(22).fontColor('#ededf0').maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Image(report.topArtistBlock.sections[0].picUrl || '').width(108).height(108).borderRadius(54).objectFit(ImageFit.Cover)
        }.width('100%').alignItems(VerticalAlign.Top)
        ForEach(report.topArtistBlock.sections.slice(1), (section: ListenReportTopArtistSection) => {
          Row({ space: 14 }) {
            Image(section.picUrl || '').width(60).height(60).borderRadius(30).objectFit(ImageFit.Cover)
            Column({ space: 5 }) {
              Text(section.field || '').fontSize(11).fontColor('#ff6577')
              Text(section.text || '').fontSize(20).fontColor('#ffffff').fontWeight(FontWeight.Bold)
              Text(section.artistName || '').fontSize(13).fontColor('#b5b5bc').maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor('#1b1b20').borderRadius(22)
    }
  }

  @Builder
  private StyleSection(report: ListenReportData | null) {
    if (report?.topStyleBlock?.sections?.length) {
      Column({ space: 18 }) {
        this.CardHeading(`${this.periodLabel()}曲风`)
        Column({ space: 6 }) {
          Text('TOP').fontSize(15).fontColor('#ff6577').fontWeight(FontWeight.Bold)
          Text(report.topStyleBlock.genreName || report.topStyleBlock.sections[0].genreName || '')
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        }.width('100%').alignItems(HorizontalAlign.Start)
        ForEach(report.topStyleBlock.sections.slice(0, 3), (section: ListenReportStyleSection) => {
          Row({ space: 8 }) {
            Stack({ alignContent: Alignment.Start }) {
              Row().width(`${this.percent(section.percent)}%`).constraintSize({ minWidth: 60 }).height(26)
                .borderRadius(13).linearGradient({ angle: 90, colors: [['#ef233c', 0], ['#ff6577', 1]] })
              Text(section.genreName || '').fontSize(12).fontColor('#ffffff').padding({ left: 10 })
            }.layoutWeight(1).height(26)
            Text(`${this.percent(section.percent)}%`).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ededf0').width(48)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor('#1b1b20').borderRadius(22)
    }
  }

  @Builder
  private AgeSection(report: ListenReportData | null) {
    if (report?.topAgeBlock?.sections?.length) {
      Column({ space: 22 }) {
        this.CardHeading(`${this.periodLabel()}听歌年代`)
        ForEach(report.topAgeBlock.sections, (section: ListenReportAgeSection) => {
          Row({ space: 16 }) {
            Text(section.age || '').width(72).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ededf0')
            Column().width(2).height(58).backgroundColor('#383840')
            if (section.picUrl) { Image(section.picUrl).width(58).height(58).borderRadius(8).objectFit(ImageFit.Cover) }
            Column({ space: 6 }) {
              Text(`${section.playSongNum || 0} 首`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              if (section.songName) { Text(section.songName).fontSize(12).fontColor('#9999a1').maxLines(1) }
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
        })
      }.width('100%').padding(20).backgroundColor('#1b1b20').borderRadius(22)
    }
  }

  @Builder
  private LanguageSection(report: ListenReportData | null) {
    if (report?.topLanguageBlock?.sections?.length) {
      Column({ space: 20 }) {
        this.CardHeading(`${this.periodLabel()}听歌语言`)
        Row({ space: 12 }) {
          ForEach(report.topLanguageBlock.sections.slice(0, 3), (section: ListenReportLanguageSection, index: number) => {
            Column({ space: 7 }) {
              if (index === 0) { Text('TOP').fontSize(12).fontColor('#ff6577').fontWeight(FontWeight.Bold) }
              Text(`${this.percent(section.percent)}%`).fontSize(index === 0 ? 30 : 24).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              Text(section.language || '').fontSize(18).fontColor('#ededf0')
              if (section.picUrl) {
                Image(section.picUrl).width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(8)
              } else {
                Column().width('100%').height(Math.max(18, this.percent(section.percent) * 1.6))
                  .borderRadius({ topLeft: 8, topRight: 8 }).backgroundColor('#ef233c')
              }
              Text(section.songName || '').fontSize(10).fontColor('#9999a1').maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          })
        }.width('100%').alignItems(VerticalAlign.Bottom)
      }.width('100%').padding(20).backgroundColor('#1b1b20').borderRadius(22)
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
  private TimeDistributionSection(report: ListenReportData | null) {
    if (report?.listenTimeBlock?.circleTimePeriodDurations &&
      report.listenTimeBlock.circleTimePeriodDurations.length > 0) {
      Column({ space: 10 }) {
        Text('听歌时段分布').fontSize(14).fontColor('#ffffff').fontWeight(FontWeight.Medium).width('100%')
        Column({ space: 6 }) {
          ForEach(report.listenTimeBlock.circleTimePeriodDurations,
            (item: ListenTimePeriodDuration) => {
              Row({ space: 8 }) {
                Text(this.formatPeriodName(item.period)).fontSize(11).fontColor('#92929a').width(36)
                Row() {
                  Row()
                    .width(`${Math.max(2, (item.duration / this.maxDuration(report.listenTimeBlock!.circleTimePeriodDurations!)) * 100)}%`)
                    .height('100%')
                    .borderRadius(4)
                    .linearGradient({ angle: 90, colors: [['#ef233c', 0], ['#ff6577', 1]] })
                }
                .layoutWeight(1).height(14).backgroundColor('#25252c').borderRadius(4)
                Text(`${item.duration}分`).fontSize(10).fontColor('#77777f').width(46).textAlign(TextAlign.End)
              }
              .width('100%')
            })
        }
        .width('100%')
      }
      .width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(16)
    }
  }

  @Builder
  private DayBubble(day: ListeningDay) {
    Column({ space: 5 }) {
      Text(day.key.replace(/-/g, '.')).fontSize(12).fontWeight(FontWeight.Bold).fontColor('#ffffff')
      Text(day.future ? '尚未到来' : !day.reported ? '暂无数据' : `听歌 ${this.formatPlayDuration(day.minutes)}`)
        .fontSize(14).fontColor('#eeeeee')
    }.padding(12)
  }

  private calendarCells(chart: ListeningPeriod): ListeningDay[] {
    const cells: ListeningDay[] = []
    chart.rows.forEach((week: ListeningDay[]) => week.forEach((day: ListeningDay) => cells.push(day)))
    return cells
  }

  @Builder
  private PeriodTabs() {
    Row() {
      ForEach(['week', 'month'], (period: string) => {
        Column({ space: 7 }) {
          Text(period === 'week' ? '本周' : '本月').fontSize(15)
            .fontWeight(this.currentPeriod === period ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.currentPeriod === period ? '#ffffff' : '#77777f')
          Column().width(24).height(3).borderRadius(2)
            .backgroundColor(this.currentPeriod === period ? '#ef233c' : 'transparent')
        }.layoutWeight(1).height(48).justifyContent(FlexAlign.Center)
          .onClick(() => this.switchPeriod(period))
      })
    }.width('100%')
  }

  @Builder
  private WeekBars(chart: ListeningPeriod) {
    Row({ space: 8 }) {
      Column() {
        Text(this.formatPlayDuration(chart.axisMinutes)).fontSize(9).fontColor('#77777f')
        Blank()
        Text(this.formatPlayDuration(chart.axisMinutes / 2)).fontSize(9).fontColor('#77777f')
        Blank()
        Text('0分钟').fontSize(9).fontColor('#77777f')
      }.width(38).height(190).margin({ bottom: 30 })
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Divider().color('#303038')
          Blank()
          Divider().color('#303038')
          Blank()
          Divider().color('#303038')
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
                    builder: () => { this.DayBubble(day) }, placement: Placement.Top, popupColor: '#303038',
                    onStateChange: (event) => { if (!event.isVisible && this.selectedDay === day.key) { this.selectedDay = '' } }
                  })
              }.width('100%').height(190)
              Text(day.weekday).fontSize(12).fontColor('#9999a1').height(20)
            }.layoutWeight(1).onClick(() => this.selectedDay = this.selectedDay === day.key ? '' : day.key)
          }, (day: ListeningDay) => day.key)
        }.width('100%').alignItems(VerticalAlign.Bottom)
      }.layoutWeight(1).height(220)
    }.width('100%').alignItems(VerticalAlign.Bottom).margin({ top: 28 })
  }

  @Builder
  private MonthCalendar(chart: ListeningPeriod) {
    Column({ space: 14 }) {
      GridRow({ columns: 7, gutter: { x: 7, y: 9 } }) {
        ForEach(this.calendarCells(chart), (day: ListeningDay) => {
          GridCol() {
            Stack() {
              if (day.day > 0) {
                Circle().width('100%').height('100%').fill(listeningDayBackground(day))
                  .stroke(day.minutes > 0 ? 'transparent' : '#393941').strokeWidth(1).strokeDashArray([2, 2])
                Text(day.day.toString()).fontSize(15).fontWeight(FontWeight.Bold).fontColor(listeningDayColor(day))
              }
            }.width('100%').aspectRatio(1)
              .onClick(() => { if (day.day > 0) { this.selectedDay = this.selectedDay === day.key ? '' : day.key } })
              .bindPopup(day.day > 0 && this.selectedDay === day.key, {
                builder: () => { this.DayBubble(day) }, placement: Placement.Top, popupColor: '#303038',
                onStateChange: (event) => { if (!event.isVisible && this.selectedDay === day.key) { this.selectedDay = '' } }
              })
          }
        }, (day: ListeningDay) => day.key)
      }.width('100%')
      Row() {
        ForEach(['日', '一', '二', '三', '四', '五', '六'], (label: string) => {
          Text(label).layoutWeight(1).fontSize(12).fontColor('#85858e').textAlign(TextAlign.Center)
        })
      }.width('100%')
    }.width('100%').margin({ top: 14 })
  }

  @Builder
  private DurationCard(chart: ListeningPeriod) {
    Column({ space: 12 }) {
      this.CardHeading(`${this.periodLabel()}收听时长`)
      Text() {
        if (chart.totalMinutes >= 60) {
          Span(Math.floor(chart.totalMinutes / 60).toString()).fontSize(44).fontWeight(FontWeight.Bold)
          Span('小时').fontSize(21).fontWeight(FontWeight.Medium)
        }
        Span(Math.floor(chart.totalMinutes % 60).toString()).fontSize(44).fontWeight(FontWeight.Bold)
        Span('分').fontSize(21).fontWeight(FontWeight.Medium)
      }.width('100%').fontColor('#ffffff').textAlign(TextAlign.End).margin({ top: 12 })
      Text(`已听 ${chart.listenedDays}/${chart.days.length} 天`).width('100%')
        .fontSize(13).fontColor('#9999a1').textAlign(TextAlign.End)
      if (this.currentPeriod === 'week') { this.WeekBars(chart) } else { this.MonthCalendar(chart) }
      if (this.activeReport()?.listenTimeDistributionBlock?.sections?.length) {
        Row({ space: 12 }) {
          ForEach(this.activeReport()!.listenTimeDistributionBlock!.sections!.slice(0, 2), (section: ListenReportSection) => {
            Column({ space: 7 }) {
              Text(section.valueA || section.value || '').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              Text(section.textB || section.field || '').fontSize(12).fontColor('#ff6577')
            }.layoutWeight(1)
          })
        }.width('100%').padding({ top: 14, bottom: 4 })
      }
    }.width('100%').padding(20).backgroundColor('#1b1b20').borderRadius(22)
  }

  @Builder
  private ReportDetail(report: ListenReportData | null) {
    Column({ space: 12 }) {
      this.TopSongSection(report)
      this.TopArtistSection(report)
      this.StyleSection(report)
      this.AgeSection(report)
      this.LanguageSection(report)
      this.TimeDistributionSection(report)
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
          Column({ space: 3 }) {
            Text('听歌足迹').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            Text(`总时长 ${this.formatTotalDuration()}`).fontSize(11).fontColor('#92929a')
          }.layoutWeight(1)
          Column().width(24)
        }
        .height(56).width('100%').padding({ left: 16, right: 16 })

        this.PeriodTabs()

        if (this.loading) {
          LoadingProgress().layoutWeight(1).width(46).color('#ef233c')
        } else if (!this.total && !this.weekReport && !this.monthReport) {
          Column({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.clock')).fontSize(44).fontColor(['#55555d'])
            Text(this.message).fontSize(13).fontColor('#77777f').textAlign(TextAlign.Center)
            if (!this.authStore.loggedIn) {
              Button('去登录').backgroundColor('#ef233c')
                .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
            }
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center).padding(24)
        } else {
          Scroll() {
            Column({ space: 16 }) {

              if (this.activeChart()) {
                Text(this.activeChart()!.title).width('100%').fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor('#ededf0').textAlign(TextAlign.Center).margin({ top: 4, bottom: 4 })
                this.DurationCard(this.activeChart()!)
                this.ReportDetail(this.activeReport())
              } else {
                Text(this.activeMessage() || '暂无该周期的听歌数据').width('100%').fontSize(13)
                  .fontColor('#9999a1').textAlign(TextAlign.Center).padding(24)
                Button('重新加载').backgroundColor('#ef233c').onClick(() => this.loadData())
              }

              Text('听歌足迹数据由网易云接口提供，部分账号或数据维度可能需要会员权益。')
                .width('100%').fontSize(11).lineHeight(18).fontColor('#66666e')
                .padding(16).backgroundColor('#18181d').borderRadius(16)
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
