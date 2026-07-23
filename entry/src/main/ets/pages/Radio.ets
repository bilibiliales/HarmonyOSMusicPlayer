import {
  DjBannerItem,
  DjBannerResponse,
  DjProgramDetailResponse,
  DjProgramTopItem,
  DjProgramTopResponse,
  mapApiSong,
  ProgramItem,
  songItemType
} from '../models'
import { ApiClient } from '../services/ApiClient'
import { resizeImageUrl } from '../services/ImageUrl'
import { playerController } from '../services/PlayerController'

@Component
export struct RadioPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  embedded: boolean = false
  @State banners: DjBannerItem[] = []
  @State programs: DjProgramTopItem[] = []
  @State loading: boolean = true
  @State loadingMore: boolean = false
  @State more: boolean = true
  @State refreshing: boolean = false
  @State message: string = ''
  @State updateTime: number = 0
  private programOffset: number = 0
  private readonly pageSize: number = 20

  aboutToAppear(): void {
    this.loadPage()
  }

  private async loadPage(): Promise<void> {
    this.loading = true
    this.message = ''
    await Promise.all([this.loadBanners(), this.loadPrograms(true)])
    this.loading = false
  }

  private async loadBanners(): Promise<void> {
    try {
      const response = await ApiClient.get<DjBannerResponse>('/dj/banner')
      if (response.code === 200) {
        this.banners = response.data || []
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '电台轮播加载失败'
    }
  }

  private async loadPrograms(reset: boolean = false): Promise<void> {
    if (this.loadingMore || (!this.more && !reset)) {
      return
    }
    if (reset) {
      this.programOffset = 0
      this.programs = []
      this.more = true
    }
    this.loadingMore = true
    try {
      const response = await ApiClient.get<DjProgramTopResponse>('/dj/program/toplist', [
        { key: 'limit', value: this.pageSize.toString() },
        { key: 'offset', value: this.programOffset.toString() }
      ])
      if (response.code === 200) {
        const incoming = response.toplist || []
        this.programs = this.programs.concat(incoming)
        this.programOffset += incoming.length
        this.more = incoming.length >= this.pageSize
        this.updateTime = response.updateTime || this.updateTime
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '节目榜加载失败'
    } finally {
      this.loadingMore = false
    }
  }

  private programCover(program: ProgramItem): string {
    return program.coverUrl || program.radio?.picUrl || program.mainSong?.al?.picUrl || ''
  }

  private programAuthor(program: ProgramItem): string {
    return program.dj?.brand || program.dj?.nickname || program.radio?.name || '网易云电台'
  }

  private programCategory(program: ProgramItem): string {
    return program.categoryName || program.radio?.category || program.secondCategoryName ||
      program.radio?.secondCategory || '电台节目'
  }

  private toSong(program: ProgramItem): songItemType | null {
    if (!program.mainSong) {
      return null
    }
    const song = mapApiSong(program.mainSong)
    song.name = program.name || song.name
    song.author = this.programAuthor(program)
    song.img = this.programCover(program) || song.img
    song.duration = program.duration || song.duration
    return song
  }

  private async playProgram(program: ProgramItem): Promise<void> {
    const song = this.toSong(program)
    if (!song) {
      this.message = '该节目暂时无法播放'
      return
    }
    await playerController.setQueue([song], 0, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private async playBanner(item: DjBannerItem): Promise<void> {
    try {
      const response = await ApiClient.get<DjProgramDetailResponse>('/dj/program/detail', [
        { key: 'id', value: item.targetId.toString() }
      ])
      if (response.code === 200 && response.program) {
        await this.playProgram(response.program)
      } else {
        this.message = '推荐节目暂时无法播放'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '推荐节目加载失败'
    }
  }

  private formatCount(value: number | undefined): string {
    const count = value || 0
    if (count >= 100000000) {
      return `${(count / 100000000).toFixed(1)}亿`
    }
    if (count >= 10000) {
      return `${(count / 10000).toFixed(1)}万`
    }
    return count.toString()
  }

  private formatDuration(value: number | undefined): string {
    const seconds = Math.floor((value || 0) / 1000)
    const minute = Math.floor(seconds / 60)
    const remain = seconds % 60
    return `${minute}:${remain < 10 ? '0' : ''}${remain}`
  }

  private updateText(): string {
    if (!this.updateTime) {
      return '实时更新'
    }
    const date = new Date(this.updateTime)
    return `${date.getMonth() + 1}月${date.getDate()}日更新`
  }

  private rankChange(item: DjProgramTopItem): string {
    if (item.lastRank < 0) {
      return 'NEW'
    }
    const change = item.lastRank - item.rank
    if (change > 0) {
      return `↑${change}`
    }
    if (change < 0) {
      return `↓${Math.abs(change)}`
    }
    return '—'
  }

  @Builder
  private PageHeader() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
        .onClick(() => this.pageStack.pop())
      Column({ space: 3 }) {
        Text('电台').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text('发现值得收听的声音节目').fontSize(11).fontColor('#6f6f77')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Stack() {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(19).fontColor(['#ddddE2'])
      }.width(42).height(42).borderRadius(14).backgroundColor('#1e1e24')
        .onClick(() => this.pageStack.pushPathByName('SearchPage', null))
    }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 5 })
  }

  @Builder
  private DiscoveryTabs() {
    Scroll() {
      Row({ space: 6 }) {
      Text('发现').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor('#1d1d22').borderRadius(18).onClick(() => this.pageStack.pop())
      Text('排行榜').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('RankingPage', null))
      Text('曲风').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('StylePage', null))
      Text('电台').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#ef233c').borderRadius(18)
      Text('数字专辑').fontSize(13).fontColor('#85858e')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('DigitalAlbumPage', null))
      Text('助眠解压').fontSize(13).fontColor('#85858e')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('SatiPage', null))
      }.padding({ left: 16, right: 16 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .margin({ top: 10, bottom: 4 })
  }

  @Builder
  private BannerSection() {
    if (this.banners.length > 0) {
      Swiper() {
        ForEach(this.banners, (item: DjBannerItem) => {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Image(resizeImageUrl(item.pic, 760, 320)).width('100%').height('100%')
              .sourceSize({ width: 760, height: 320 }).borderRadius(18).objectFit(ImageFit.Cover)
            Text(item.typeTitle || '电台节目').fontSize(10).fontColor('#ffffff')
              .padding({ left: 9, right: 9, top: 5, bottom: 5 }).backgroundColor('#d9364f')
              .borderRadius({ topLeft: 10, bottomRight: 18 })
          }.width('100%').height('100%').borderRadius(18).clip(true).onClick(() => this.playBanner(item))
        }, (item: DjBannerItem) => item.targetId.toString())
      }.width('92%').height(154).margin({ top: 12, bottom: 6 }).autoPlay(true).interval(4500)
        .duration(450).loop(true).indicator(true).borderRadius(18).clip(true)
    }
  }

  @Builder
  private ProgramToplist() {
    Row() {
      Column({ space: 3 }) {
        Text('电台节目榜').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text(this.updateText()).fontSize(10).fontColor('#707078')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.podcast')).fontSize(20).fontColor(['#ef4058'])
    }.width('100%').padding({ left: 16, right: 16, top: 22, bottom: 10 })

    ForEach(this.programs, (item: DjProgramTopItem) => {
      Row({ space: 11 }) {
        Column({ space: 2 }) {
          Text(`${item.rank}`).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(item.rank <= 3 ? '#ef4058' : '#777780')
          Text(this.rankChange(item)).fontSize(8)
            .fontColor(this.rankChange(item).startsWith('↑') ? '#ef6577' : '#66666e')
        }.width(34)
        Stack({ alignContent: Alignment.BottomEnd }) {
          Image(resizeImageUrl(this.programCover(item.program), 160, 160)).width(68).height(68)
            .sourceSize({ width: 160, height: 160 }).borderRadius(13).objectFit(ImageFit.Cover)
          Text(this.formatDuration(item.program.duration)).fontSize(8).fontColor('#ffffff')
            .padding({ left: 4, right: 4, top: 2, bottom: 2 }).margin(4)
            .backgroundColor('rgba(0,0,0,0.58)').borderRadius(4)
        }.width(68).height(68)
        Column({ space: 5 }) {
          Text(item.program.name).width('100%').fontSize(14).fontColor('#ededf0').maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.programAuthor(item.program)} · ${this.programCategory(item.program)}`)
            .width('100%').fontSize(10).fontColor('#77777f').maxLines(1)
          Text(`${this.formatCount(item.program.listenerCount)} 次收听 · ${this.formatCount(item.program.likedCount)} 赞`)
            .fontSize(9).fontColor('#65656d')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(26).fontColor(['#ffffff'])
      }.width('100%').padding({ left: 13, right: 16, top: 8, bottom: 8 })
        .onClick(() => this.playProgram(item.program))
    }, (item: DjProgramTopItem) => item.program.id.toString())
  }

  @Builder
  private PageContent(showChrome: boolean) {
    Refresh({ refreshing: this.refreshing }) {
      Scroll() {
        Column() {
          if (showChrome) {
            Column().width('100%').height(this.topAvoidHeight)
            this.PageHeader()
            this.DiscoveryTabs()
          }
          this.BannerSection()
          if (this.loading) {
            LoadingProgress().width(42).height(42).color('#ef233c').margin({ top: 140 })
          } else if (this.programs.length === 0) {
            Text(this.message || '暂无电台节目').width('100%').height(280).fontSize(13).fontColor('#77777f')
              .textAlign(TextAlign.Center)
          } else {
            this.ProgramToplist()
            Row() {
              if (this.loadingMore) {
                LoadingProgress().width(24).height(24).color('#ef233c')
              } else {
                Text(this.more ? '继续上滑加载更多' : '已经到底了').fontSize(10).fontColor('#66666e')
              }
            }.width('100%').height(this.embedded ? 145 : 56).justifyContent(FlexAlign.Center)
          }
        }.width('100%')
      }.width('100%').height('100%').scrollBar(BarState.Off).onReachEnd(() => this.loadPrograms())
    }.width('100%').height('100%').backgroundColor('#121215').onRefreshing(async () => {
      this.refreshing = true
      await this.loadPage()
      this.refreshing = false
    })
  }

  build() {
    if (this.embedded) {
      this.PageContent(false)
    } else {
      NavDestination() {
        this.PageContent(true)
      }.hideTitleBar(true).backgroundColor('#121215')
    }
  }
}
