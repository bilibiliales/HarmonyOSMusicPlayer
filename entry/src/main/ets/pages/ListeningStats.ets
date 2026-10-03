import {
  ListenDataResponse,
  ListenDataValue,
  ListenReportData,
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

  @Builder
  private TopSongSection(report: ListenReportData | null) {
    if (report?.topSongBlock?.sections && report.topSongBlock.sections.length > 0) {
      Column({ space: 8 }) {
        Text('收听 TOP 歌曲').fontSize(14).fontColor('#ffffff').fontWeight(FontWeight.Medium)
          .width('100%')
        ForEach(report.topSongBlock.sections, (section: ListenReportTopSongSection) => {
          Row({ space: 10 }) {
            if (section.picUrl) {
              Image(section.picUrl).width(44).height(44).borderRadius(8).objectFit(ImageFit.Cover)
            } else {
              Stack() {
                SymbolGlyph($r('sys.symbol.music')).fontSize(22).fontColor(['#55555d'])
              }.width(44).height(44).borderRadius(8).backgroundColor('#25252c')
            }
            Column({ space: 4 }) {
              Text(section.songName || '').fontSize(13).fontColor('#ededf0').maxLines(1)
              Text(section.field || '').fontSize(10).fontColor('#77777f')
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text(section.text || '').fontSize(12).fontColor('#ef233c')
          }
          .width('100%').height(56)
        })
      }
      .width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(16)
    }
  }

  @Builder
  private TopArtistSection(report: ListenReportData | null) {
    if (report?.topArtistBlock?.sections && report.topArtistBlock.sections.length > 0) {
      Column({ space: 8 }) {
        Text('收听 TOP 歌手').fontSize(14).fontColor('#ffffff').fontWeight(FontWeight.Medium)
          .width('100%')
        ForEach(report.topArtistBlock.sections, (section: ListenReportTopArtistSection) => {
          Row({ space: 10 }) {
            if (section.picUrl) {
              Image(section.picUrl).width(44).height(44).borderRadius(22).objectFit(ImageFit.Cover)
            } else {
              Stack() {
                SymbolGlyph($r('sys.symbol.person')).fontSize(22).fontColor(['#55555d'])
              }.width(44).height(44).borderRadius(22).backgroundColor('#25252c')
            }
            Column({ space: 4 }) {
              Text(section.artistName || '').fontSize(13).fontColor('#ededf0').maxLines(1)
              Text(section.field || '').fontSize(10).fontColor('#77777f')
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text(section.text || '').fontSize(12).fontColor('#ef233c')
          }
          .width('100%').height(56)
        })
      }
      .width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(16)
    }
  }

  @Builder
  private StyleSection(report: ListenReportData | null) {
    if (report?.topStyleBlock?.sections && report.topStyleBlock.sections.length > 0) {
      Column({ space: 8 }) {
        Row() {
          Text('听歌风格偏好').fontSize(14).fontColor('#ffffff').fontWeight(FontWeight.Medium)
          Text(report.topStyleBlock.genreName || '').fontSize(12).fontColor('#ef233c')
            .margin({ left: 8 })
        }.width('100%')
        ForEach(report.topStyleBlock.sections.slice(0, 5), (section: ListenReportStyleSection) => {
          Row() {
            Text(section.genreName || '').fontSize(12).fontColor('#b5b5bc').width(60)
            Row() {
              Row()
                .width(`${Number(section.percent) || 0}%`)
                .height('100%')
                .backgroundColor('#ef233c')
                .borderRadius(3)
            }
            .layoutWeight(1).height(8).backgroundColor('#25252c').borderRadius(3)
            Text(`${section.percent}%`).fontSize(10).fontColor('#77777f').width(36).textAlign(TextAlign.End)
          }
          .width('100%')
        })
      }
      .width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(16)
    }
  }

  @Builder
  private LanguageSection(report: ListenReportData | null) {
    if (report?.topLanguageBlock?.sections && report.topLanguageBlock.sections.length > 0) {
      Column({ space: 8 }) {
        Text('语种偏好').fontSize(14).fontColor('#ffffff').fontWeight(FontWeight.Medium).width('100%')
        ForEach(report.topLanguageBlock.sections, (section: ListenReportLanguageSection) => {
          Row() {
            Text(section.language || '').fontSize(12).fontColor('#b5b5bc').width(44)
            Row() {
              Row()
                .width(`${Number(section.percent) || 0}%`)
                .height('100%')
                .backgroundColor('#7f76ff')
                .borderRadius(3)
            }
            .layoutWeight(1).height(8).backgroundColor('#25252c').borderRadius(3)
            Text(`${section.percent}%`).fontSize(10).fontColor('#77777f').width(36).textAlign(TextAlign.End)
            Text(section.songName || '').fontSize(10).fontColor('#55555d')
              .layoutWeight(1).textAlign(TextAlign.End).maxLines(1)
          }
          .width('100%')
        })
      }
      .width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(16)
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

  private dayValue(day: ListeningDay): string {
    if (day.future) { return '—' }
    if (!day.reported) { return '—' }
    if (day.minutes <= 0) { return '0分' }
    if (day.minutes < 1) { return '<1分' }
    return day.minutes >= 60 ? `${Number((day.minutes / 60).toFixed(1))}时` : `${Math.floor(day.minutes)}分`
  }

  private dayDescription(chart: ListeningPeriod): string {
    const day = chart.days.find((item: ListeningDay) => item.key === this.selectedDay)
    if (!day) { return this.currentPeriod === 'week' ? '点击柱形查看当天时长' : '点击日期查看当天时长' }
    return `${day.key} · ${day.future ? '尚未到来' : !day.reported ? '暂无数据' : this.formatPlayDuration(day.minutes)}`
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
    Row({ space: 6 }) {
      Column() {
        Text(this.formatPlayDuration(chart.axisMinutes)).fontSize(9).fontColor('#77777f')
        Blank()
        Text(this.formatPlayDuration(chart.axisMinutes / 2)).fontSize(9).fontColor('#77777f')
        Blank()
        Text('0分').fontSize(9).fontColor('#77777f')
      }.width(36).height(184).margin({ bottom: 38 })
      Row({ space: 5 }) {
        ForEach(chart.days, (day: ListeningDay) => {
          Column({ space: 6 }) {
            Column() {
              Blank()
              Text(this.dayValue(day)).fontSize(9).fontWeight(FontWeight.Medium)
                .fontColor(listeningDayColor(day)).textAlign(TextAlign.Center)
                .width('100%')
                .height(day.minutes > 0 ? Math.max(28, day.minutes / chart.axisMinutes * 184) : 22)
                .backgroundColor(listeningDayBackground(day)).borderRadius(22)
                .border({ width: this.selectedDay === day.key ? 1 : 0, color: '#ff8190' })
            }.width('100%').height(184)
            Text(day.weekday).fontSize(11).fontColor('#9999a1')
            Text(day.key.substring(5).replace('-', '/')).fontSize(9).fontColor('#66666e')
          }.layoutWeight(1).onClick(() => this.selectedDay = day.key)
        }, (day: ListeningDay) => day.key)
      }.layoutWeight(1).alignItems(VerticalAlign.Bottom)
    }.width('100%').alignItems(VerticalAlign.Bottom).margin({ top: 12 })
  }

  @Builder
  private MonthCalendar(chart: ListeningPeriod) {
    Column({ space: 10 }) {
      Row() {
        ForEach(['日', '一', '二', '三', '四', '五', '六'], (label: string) => {
          Text(label).layoutWeight(1).fontSize(11).fontColor('#85858e').textAlign(TextAlign.Center)
        })
      }.width('100%')
      ForEach(chart.rows, (week: ListeningDay[]) => {
        Row() {
          ForEach(week, (day: ListeningDay) => {
            Column({ space: 4 }) {
              if (day.day > 0) {
                Text(day.day.toString()).width(32).height(32).borderRadius(16)
                  .fontSize(12).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
                  .backgroundColor(listeningDayBackground(day)).fontColor(listeningDayColor(day))
                  .border({ width: this.selectedDay === day.key ? 1 : 0, color: '#ff8190' })
                Text(this.dayValue(day)).fontSize(9).fontColor(day.minutes > 0 ? '#ff6577' : '#66666e')
              }
            }.layoutWeight(1).height(52).justifyContent(FlexAlign.Center)
              .onClick(() => { if (day.day > 0) { this.selectedDay = day.key } })
          }, (day: ListeningDay) => day.key)
        }.width('100%')
      })
    }.width('100%').margin({ top: 12 })
  }

  @Builder
  private DurationCard(chart: ListeningPeriod) {
    Column({ space: 14 }) {
      Text(this.currentPeriod === 'week' ? '本周听歌时长' : '本月听歌时长')
        .width('100%').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#a3a3ad')
      Text(this.formatPlayDuration(chart.totalMinutes)).width('100%')
        .fontSize(30).fontWeight(FontWeight.Bold).fontColor('#ffffff').textAlign(TextAlign.End)
      Text(`已听 ${chart.listenedDays}/${chart.days.length} 天`).width('100%')
        .fontSize(12).fontColor('#9999a1').textAlign(TextAlign.End)
      if (this.currentPeriod === 'week') { this.WeekBars(chart) } else { this.MonthCalendar(chart) }
      Text(this.dayDescription(chart)).width('100%').fontSize(12).fontColor('#b5b5bd')
        .textAlign(TextAlign.Center).constraintSize({ minHeight: 30 })
      Row({ space: 6 }) {
        Column().width(8).height(8).borderRadius(4).backgroundColor('rgba(239,35,60,0.22)')
        Text('不足1小时').fontSize(10).fontColor('#ff6577')
        Blank().width(12)
        Column().width(8).height(8).borderRadius(4).backgroundColor('#ef233c')
        Text('1小时及以上').fontSize(10).fontColor('#9999a1')
      }.width('100%').justifyContent(FlexAlign.Center)
    }.width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(22)
  }

  @Builder
  private ReportDetail(report: ListenReportData | null) {
    Column({ space: 12 }) {
      this.TopSongSection(report)
      this.TopArtistSection(report)
      this.StyleSection(report)
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
          Text('听歌足迹')
            .layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
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
              Column({ space: 10 }) {
                Text('累计听歌').fontSize(13).fontColor('#d7b7bb')
                Text(this.formatTotalDuration())
                  .fontSize(34).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                Text(`累计收听 ${this.totalSongCount()} 首歌曲`)
                  .fontSize(11).fontColor('#d7b7bb')
              }
              .width('100%').padding(24).borderRadius(24)
              .linearGradient({ angle: 135, colors: [['#7d2735', 0], ['#28253d', 1]] })

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
