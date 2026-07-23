import {
  DigitalAlbumDetailPageParam,
  DigitalAlbumNewResponse,
  DigitalAlbumProduct,
  DigitalAlbumSalesResponse,
  DigitalAlbumStyleResponse
} from '../models'
import { ApiClient } from '../services/ApiClient'
import { resizeImageUrl } from '../services/ImageUrl'

interface DigitalAlbumArea {
  code: string
  name: string
}

@Component
export struct DigitalAlbumPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  embedded: boolean = false
  @State newAlbums: DigitalAlbumProduct[] = []
  @State salesAlbums: DigitalAlbumProduct[] = []
  @State styleAlbums: DigitalAlbumProduct[] = []
  @State loading: boolean = true
  @State styleLoading: boolean = false
  @State refreshing: boolean = false
  @State message: string = ''
  @State selectedArea: string = 'Z_H'
  @State newVisibleCount: number = 6
  @State salesVisibleCount: number = 6
  @State styleVisibleCount: number = 6
  private readonly pageSize: number = 6
  private readonly areas: DigitalAlbumArea[] = [
    { code: 'Z_H', name: '华语' },
    { code: 'E_A', name: '欧美' },
    { code: 'KR', name: '韩国' },
    { code: 'JP', name: '日本' }
  ]

  aboutToAppear(): void {
    this.loadPage()
  }

  private async loadPage(): Promise<void> {
    this.loading = true
    this.message = ''
    this.newVisibleCount = this.pageSize
    this.salesVisibleCount = this.pageSize
    this.styleVisibleCount = this.pageSize
    const results = await Promise.all([this.loadNewAlbums(), this.loadSalesAlbums()])
    await this.loadStyleAlbums()
    if (!results[0] && !results[1] && this.styleAlbums.length === 0) {
      this.message = '数字专辑加载失败，请下拉重试'
    }
    this.loading = false
  }

  private async loadNewAlbums(): Promise<boolean> {
    try {
      const response = await ApiClient.get<DigitalAlbumNewResponse>('/album/list', [
        { key: 'limit', value: '20' },
        { key: 'offset', value: '0' },
        { key: 'area', value: 'ALL' },
        { key: 'type', value: 'new' }
      ])
      if (response.code === 200) {
        this.newAlbums = response.products || []
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadSalesAlbums(): Promise<boolean> {
    try {
      const response = await ApiClient.get<DigitalAlbumSalesResponse>('/digitalAlbum/sales', [
        { key: 'limit', value: '20' },
        { key: 'offset', value: '0' },
        { key: 'albumType', value: '0' },
        { key: 'type', value: 'total' }
      ])
      if (response.code === 200) {
        this.salesAlbums = response.products || []
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadStyleAlbums(): Promise<void> {
    this.styleLoading = true
    try {
      const response = await ApiClient.get<DigitalAlbumStyleResponse>('/album/list/style', [
        { key: 'limit', value: '20' },
        { key: 'offset', value: '0' },
        { key: 'area', value: this.selectedArea }
      ])
      if (response.code === 200) {
        this.styleAlbums = response.albumProducts || []
        this.styleVisibleCount = this.pageSize
      }
    } catch (_error) {
      this.styleAlbums = []
    } finally {
      this.styleLoading = false
    }
  }

  private selectArea(area: string): void {
    if (this.selectedArea === area || this.styleLoading) {
      return
    }
    this.selectedArea = area
    this.loadStyleAlbums()
  }

  private openDetail(item: DigitalAlbumProduct): void {
    const param: DigitalAlbumDetailPageParam = {
      albumId: item.albumId,
      albumName: item.albumName,
      artistName: item.artistName,
      coverUrl: item.coverUrl
    }
    this.pageStack.pushPathByName('DigitalAlbumDetailPage', param)
  }

  private formatPrice(price: number): string {
    if (price <= 0) {
      return '免费'
    }
    return `¥${price}`
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

  private revealMore(section: string): void {
    if (section === 'new' && this.newVisibleCount < this.newAlbums.length) {
      this.newVisibleCount = Math.min(this.newVisibleCount + this.pageSize, this.newAlbums.length)
    } else if (section === 'sales' && this.salesVisibleCount < this.salesAlbums.length) {
      this.salesVisibleCount = Math.min(this.salesVisibleCount + this.pageSize, this.salesAlbums.length)
    } else if (section === 'style' && this.styleVisibleCount < this.styleAlbums.length) {
      this.styleVisibleCount = Math.min(this.styleVisibleCount + this.pageSize, this.styleAlbums.length)
    }
  }

  @Builder
  private PageHeader() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
        .onClick(() => this.pageStack.pop())
      Column({ space: 3 }) {
        Text('数字专辑').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text('发现新发行与畅销数字音乐').fontSize(11).fontColor('#6f6f77')
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
        Text('排行榜').fontSize(13).fontColor('#85858e')
          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#1d1d22').borderRadius(18)
          .onClick(() => this.pageStack.replacePathByName('RankingPage', null))
        Text('曲风').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .backgroundColor('#1d1d22').borderRadius(18)
          .onClick(() => this.pageStack.replacePathByName('StylePage', null))
        Text('电台').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .backgroundColor('#1d1d22').borderRadius(18)
          .onClick(() => this.pageStack.replacePathByName('RadioPage', null))
        Text('数字专辑').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#ef233c').borderRadius(18)
        Text('助眠解压').fontSize(13).fontColor('#85858e')
          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#1d1d22').borderRadius(18)
          .onClick(() => this.pageStack.replacePathByName('SatiPage', null))
      }.padding({ left: 16, right: 16 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .margin({ top: 10, bottom: 4 })
  }

  @Builder
  private SectionTitle(title: string, subtitle: string) {
    Row() {
      Column({ space: 3 }) {
        Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#f4f4f6')
        Text(subtitle).fontSize(10).fontColor('#66666e')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ left: 16, right: 16, top: 22, bottom: 11 })
  }

  @Builder
  private AlbumCard(item: DigitalAlbumProduct, badge: string = '') {
    Column({ space: 7 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(resizeImageUrl(item.coverUrl, 280, 280)).width(126).height(126)
          .sourceSize({ width: 280, height: 280 }).borderRadius(15).objectFit(ImageFit.Cover)
        if (badge.length > 0) {
          Text(badge).fontSize(10).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            .padding({ left: 8, right: 8, top: 5, bottom: 5 }).backgroundColor('#ef233c')
            .borderRadius({ topLeft: 15, bottomRight: 12 })
        }
      }
      Text(item.albumName).width(126).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#e8e8eb')
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(item.artistName).width(126).fontSize(10).fontColor('#77777f').maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Text(this.formatPrice(item.price)).fontSize(11).fontWeight(FontWeight.Bold).fontColor('#ef6577')
        Blank()
        Text(`${this.formatCount(item.saleNum || item.sales)}人购买`).fontSize(8).fontColor('#62626a')
      }.width(126)
    }.width(126).alignItems(HorizontalAlign.Start).onClick(() => this.openDetail(item))
  }

  @Builder
  private NewAlbumsSection() {
    if (this.newAlbums.length > 0) {
      this.SectionTitle('新碟上架', '近期发行的数字专辑与单曲')
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.newAlbums.slice(0, this.newVisibleCount),
            (item: DigitalAlbumProduct) => {
            this.AlbumCard(item, item.newAlbum ? 'NEW' : '')
          }, (item: DigitalAlbumProduct) => item.albumId.toString())
        }.padding({ left: 16, right: 16 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .onScrollEdge((side: Edge) => {
          if (side === Edge.End) {
            this.revealMore('new')
          }
        })
    }
  }

  @Builder
  private SalesSection() {
    if (this.salesAlbums.length > 0) {
      this.SectionTitle('数字音乐畅销榜', '数字专辑与数字单曲累计销量')
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.salesAlbums.slice(0, this.salesVisibleCount),
            (item: DigitalAlbumProduct, index: number) => {
            this.AlbumCard(item, `TOP ${index + 1}`)
          }, (item: DigitalAlbumProduct) => item.albumId.toString())
        }.padding({ left: 16, right: 16 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .onScrollEdge((side: Edge) => {
          if (side === Edge.End) {
            this.revealMore('sales')
          }
        })
    }
  }

  @Builder
  private StyleSection() {
    this.SectionTitle('语种风格馆', '按语种发现数字音乐')
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.areas, (area: DigitalAlbumArea) => {
          Text(area.name).fontSize(11).fontWeight(this.selectedArea === area.code ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.selectedArea === area.code ? '#ffffff' : '#85858e')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(this.selectedArea === area.code ? '#ef233c' : '#202026').borderRadius(17)
            .onClick(() => this.selectArea(area.code))
        }, (area: DigitalAlbumArea) => area.code)
      }.padding({ left: 16, right: 16, bottom: 13 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    if (this.styleLoading) {
      LoadingProgress().width(28).height(28).color('#ef233c').margin({ top: 35, bottom: 35 })
    } else if (this.styleAlbums.length > 0) {
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.styleAlbums.slice(0, this.styleVisibleCount),
            (item: DigitalAlbumProduct) => {
            this.AlbumCard(item)
          }, (item: DigitalAlbumProduct) => item.albumId.toString())
        }.padding({ left: 16, right: 16 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .onScrollEdge((side: Edge) => {
          if (side === Edge.End) {
            this.revealMore('style')
          }
        })
    } else {
      Text('该语种暂无数字专辑').width('100%').height(100).fontSize(11).fontColor('#66666e')
        .textAlign(TextAlign.Center)
    }
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
          if (this.loading) {
            Column({ space: 12 }) {
              LoadingProgress().width(38).height(38).color('#ef233c')
              Text('正在加载数字专辑').fontSize(11).fontColor('#77777f')
            }.width('100%').height(360).justifyContent(FlexAlign.Center)
          } else if (this.newAlbums.length === 0 && this.salesAlbums.length === 0 &&
            this.styleAlbums.length === 0) {
            Text(this.message || '暂无数字专辑').width('100%').height(320).fontSize(12).fontColor('#77777f')
              .textAlign(TextAlign.Center)
          } else {
            this.NewAlbumsSection()
            this.SalesSection()
            this.StyleSection()
            Blank().height(this.embedded ? 145 : 55)
          }
        }.width('100%')
      }.width('100%').height('100%').scrollBar(BarState.Off)
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
