import {
  ApiArtist,
  ListenDataResponse,
  ListenDataValue,
  ListenDurationDetail,
  ListenReportData,
  ListenReportLanguageSection,
  ListenReportResponse,
  ListenReportStyleSection,
  ListenReportTopArtistSection,
  ListenReportTopSongSection,
  ListenTimeBlock,
  ListenTimePeriodDuration
} from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'

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

  aboutToAppear(): void {
    this.loadData()
  }

  private async loadData(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.loading = false
      this.message = '登录后才能获取听歌足迹'
      return
    }
    try {
      const totalResponse = await ApiClient.get<ListenDataResponse>('/listen/data/total')
      const weekResponse = await ApiClient.get<ListenReportResponse>('/listen/data/report', [
        { key: 'type', value: 'week' }
      ])
      const monthResponse = await ApiClient.get<ListenReportResponse>('/listen/data/report', [
        { key: 'type', value: 'month' }
      ])
      this.total = totalResponse.data || null
      if (weekResponse.code === 200 && weekResponse.data) {
        this.weekReport = weekResponse.data
      }
      if (monthResponse.code === 200 && monthResponse.data) {
        this.monthReport = monthResponse.data
      }
      if (!this.total && !this.weekReport && !this.monthReport) {
        this.message = totalResponse.message || '接口暂未返回听歌足迹，部分账号需要会员权限'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '听歌足迹加载失败'
    } finally {
      this.loading = false
    }
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
    const minutes = value
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
  private StatCard(title: string, report: ListenReportData | null, color: string = '#ef233c') {
    Row() {
      Column().width(10).height(10).borderRadius(5).backgroundColor(color)
      Text(`${title}听歌报告`).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#ffffff').margin({ left: 8 })
      if (report?.listenTimeBlock?.playDurationText) {
        Text(report.listenTimeBlock.playDurationText).fontSize(12).fontColor('#77777f').margin({ left: 10 })
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#1b1b20').borderRadius(16)
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

  private maxDailyDuration(details: ListenDurationDetail[]): number {
    let maxVal: number = 1
    for (let i = 0; i < details.length; i++) {
      if (details[i].duration > maxVal) {
        maxVal = details[i].duration
      }
    }
    return maxVal
  }

  private formatDayLabel(period: string): string {
    const parts = period.split('-')
    if (parts.length >= 3) {
      const weekDays: string[] = ['日', '一', '二', '三', '四', '五', '六']
      const date = new Date(period)
      const day = date.getDay()
      return `周${weekDays[day]}`
    }
    return period
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
  private DailyDistributionSection(report: ListenReportData | null) {
    if (report?.listenTimeDistributionBlock?.durationDetails &&
      report.listenTimeDistributionBlock.durationDetails.length > 0) {
      Column({ space: 10 }) {
        Row() {
          Text('每日听歌时长').fontSize(14).fontColor('#ffffff').fontWeight(FontWeight.Medium)
          if (report.listenTimeDistributionBlock.listenDays) {
            Text(`共 ${report.listenTimeDistributionBlock.listenDays} 天`)
              .fontSize(11).fontColor('#77777f').margin({ left: 8 })
          }
        }.width('100%')
        Column({ space: 6 }) {
          ForEach(report.listenTimeDistributionBlock.durationDetails,
            (item: ListenDurationDetail) => {
              Row({ space: 8 }) {
                Text(this.formatDayLabel(item.period)).fontSize(11).fontColor('#92929a').width(36)
                Row() {
                  Row()
                    .width(`${Math.max(2, (item.duration / this.maxDailyDuration(report.listenTimeDistributionBlock!.durationDetails!)) * 100)}%`)
                    .height('100%')
                    .borderRadius(4)
                    .linearGradient({ angle: 90, colors: [['#7f76ff', 0], ['#a59bff', 1]] })
                }
                .layoutWeight(1).height(14).backgroundColor('#25252c').borderRadius(4)
                Text(this.formatPlayDuration(item.duration)).fontSize(10).fontColor('#77777f').width(60).textAlign(TextAlign.End)
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
  private ReportDetail(title: string, report: ListenReportData | null, color: string = '#ef233c') {
    Column({ space: 12 }) {
      this.StatCard(title, report, color)
      this.TopSongSection(report)
      this.TopArtistSection(report)
      this.StyleSection(report)
      this.LanguageSection(report)
      this.TimeDistributionSection(report)
      this.DailyDistributionSection(report)
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

              if (this.weekReport) {
                this.ReportDetail('本周', this.weekReport, '#ef233c')
              }

              if (this.monthReport) {
                this.ReportDetail('本月', this.monthReport, '#7f76ff')
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
