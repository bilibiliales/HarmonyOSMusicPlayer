import {
  AlbumPageParam,
  ArtistPageParam,
  DigitalAlbumDescription,
  DigitalAlbumDetailPageParam,
  DigitalAlbumDetailResponse
} from '../models'
import { ApiClient } from '../services/ApiClient'
import { resizeImageUrl } from '../services/ImageUrl'
import { playerController } from '../services/PlayerController'

@Component
export struct DigitalAlbumDetailPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: DigitalAlbumDetailPageParam = { albumId: 0 }
  @State loading: boolean = true
  @State message: string = ''
  @State albumName: string = ''
  @State artistName: string = ''
  @State artistId: number = 0
  @State coverUrl: string = ''
  @State price: number = 0
  @State saleNum: number = 0
  @State pubTime: number = 0
  @State donateMsg: string = ''
  @State descriptions: string[] = []
  @State buyNotes: string[] = []
  @State tags: string[] = []
  @State canBuy: boolean = false
  @State isFree: boolean = false
  @State boughtCount: number = 0
  @State mvUrl: string = ''
  @State mvCover: string = ''
  @State mvTitle: string = ''
  @State videoPlaying: boolean = false
  private videoController: VideoController = new VideoController()

  aboutToAppear(): void {
    this.albumName = this.pageParam.albumName || ''
    this.artistName = this.pageParam.artistName || ''
    this.coverUrl = this.pageParam.coverUrl || ''
    this.loadDetail()
  }

  aboutToDisappear(): void {
    try {
      this.videoController.stop()
    } catch (_error) {
    }
  }

  private async loadDetail(): Promise<void> {
    if (!this.pageParam.albumId) {
      this.message = '数字专辑参数无效'
      this.loading = false
      return
    }
    try {
      const response = await ApiClient.get<DigitalAlbumDetailResponse>('/digitalAlbum/detail', [
        { key: 'id', value: this.pageParam.albumId.toString() }
      ])
      if (response.code === 200 && response.album) {
        this.albumName = response.album.albumName || this.albumName
        this.artistName = response.album.artistNames || response.album.artistName || this.artistName
        this.artistId = response.album.artistId || 0
        this.coverUrl = response.album.coverUrl || this.coverUrl
        if (response.product) {
          this.price = response.product.price || 0
          this.saleNum = response.product.saleNum || 0
          this.pubTime = response.product.pubTime || 0
          this.donateMsg = response.product.donateMsg || ''
          this.descriptions = (response.product.descr || [])
            .filter((item: DigitalAlbumDescription) => !!item.resource)
            .map((item: DigitalAlbumDescription) => item.resource || '')
          this.buyNotes = response.product.buynotes || []
          this.tags = response.product.tags || []
          this.isFree = response.product.isFree || response.product.albumfee === 0
          if (response.product.showMv && response.product.mvPlayUrl) {
            this.mvUrl = response.product.mvPlayUrl
            this.mvCover = response.product.mvCoverUrl || this.coverUrl
            this.mvTitle = response.product.mvTitle || '数字专辑宣传视频'
          }
        }
        this.canBuy = response.canBuy || false
        this.boughtCount = response.boughtCnt || 0
      } else {
        this.message = '数字专辑详情加载失败'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '数字专辑详情加载失败'
    } finally {
      this.loading = false
    }
  }

  private formatPrice(): string {
    if (this.isFree || this.price <= 0) {
      return '免费'
    }
    return `¥${this.price}`
  }

  private formatCount(value: number): string {
    if (value >= 100000000) {
      return `${(value / 100000000).toFixed(1)}亿`
    }
    if (value >= 10000) {
      return `${(value / 10000).toFixed(1)}万`
    }
    return value.toString()
  }

  private formatDate(value: number): string {
    if (!value) {
      return '发行时间待定'
    }
    const date = new Date(value)
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-` +
      `${date.getDate().toString().padStart(2, '0')}`
  }

  private openAlbum(): void {
    const param: AlbumPageParam = {
      id: this.pageParam.albumId.toString(),
      name: this.albumName,
      picUrl: this.coverUrl,
      artist: this.artistName
    }
    this.pageStack.pushPathByName('AlbumDetailPage', param)
  }

  private openArtist(): void {
    if (!this.artistId) {
      return
    }
    const param: ArtistPageParam = {
      id: this.artistId.toString(),
      name: this.artistName,
      picUrl: ''
    }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  @Builder
  private Header() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
        .onClick(() => this.pageStack.pop())
      Text('数字专辑详情').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        .textAlign(TextAlign.Center)
      Blank().width(24)
    }.width('100%').height(58).padding({ left: 16, right: 16 })
  }

  @Builder
  private HeroSection() {
    Column({ space: 17 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(resizeImageUrl(this.coverUrl, 560, 560)).width(224).height(224)
          .sourceSize({ width: 560, height: 560 }).borderRadius(24).objectFit(ImageFit.Cover)
        Column().width(206).height(206).border({ width: 1, color: 'rgba(255,255,255,0.14)' }).borderRadius(20)
      }
      Column({ space: 8 }) {
        Text(this.albumName || '数字专辑').width('100%').fontSize(25).fontWeight(FontWeight.Bold)
          .fontColor('#ffffff').textAlign(TextAlign.Center).maxLines(2)
        Text(this.artistName || '未知艺人').fontSize(13).fontColor('#b0b0b8').maxLines(1)
          .onClick(() => this.openArtist())
        Text(this.formatDate(this.pubTime)).fontSize(10).fontColor('#66666e')
      }.width('100%')
      if (this.tags.length > 0) {
        Row({ space: 7 }) {
          ForEach(this.tags.slice(0, 3), (tag: string) => {
            Text(tag).fontSize(9).fontColor('#d6d6dc').padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor('#28282f').borderRadius(14)
          })
        }
      }
      Row() {
        Column({ space: 4 }) {
          Text(this.formatPrice()).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#ef6577')
          Text(this.canBuy ? '当前可购买' : '当前不可购买').fontSize(9).fontColor('#696971')
        }.layoutWeight(1)
        Column({ space: 4 }) {
          Text(this.formatCount(this.saleNum)).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text('销量').fontSize(9).fontColor('#696971')
        }.layoutWeight(1)
        Column({ space: 4 }) {
          Text(this.formatCount(this.boughtCount)).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text('已购买').fontSize(9).fontColor('#696971')
        }.layoutWeight(1)
      }.width('92%').height(72).backgroundColor('#1d1d23').borderRadius(20)
      Button('查看歌曲与普通专辑详情').width('86%').height(45).fontSize(13).fontColor('#ffffff')
        .backgroundColor('#ef233c').borderRadius(23).onClick(() => this.openAlbum())
    }.width('100%').padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  @Builder
  private VideoSection() {
    if (this.mvUrl) {
      Column({ space: 10 }) {
        Row() {
          Text(this.mvTitle || '宣传视频').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
          SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right')).fontSize(19).fontColor(['#d7d7dc'])
            .onClick(() => this.videoController.requestFullscreen(true))
        }.width('100%')
        Video({ src: this.mvUrl, previewUri: resizeImageUrl(this.mvCover, 760, 430), controller: this.videoController })
          .width('100%').aspectRatio(16 / 9).objectFit(ImageFit.Contain).autoPlay(false).controls(true).loop(false)
          .onStart(async () => {
            this.videoPlaying = true
            await playerController.pause()
          })
          .onPause(() => this.videoPlaying = false)
          .onFinish(() => this.videoPlaying = false)
          .onError(() => this.message = '宣传视频播放失败，播放地址可能已过期')
      }.width('100%').padding({ left: 16, right: 16, top: 24 })
    }
  }

  @Builder
  private DescriptionSection() {
    if (this.donateMsg || this.descriptions.length > 0) {
      Column({ space: 13 }) {
        Text('专辑介绍').width('100%').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        if (this.donateMsg) {
          Text(this.donateMsg).width('100%').fontSize(14).lineHeight(23).fontWeight(FontWeight.Medium)
            .fontColor('#e1e1e6')
        }
        ForEach(this.descriptions, (text: string) => {
          Text(text).width('100%').fontSize(12).lineHeight(21).fontColor('#9999a2')
        })
      }.width('100%').padding({ left: 18, right: 18, top: 26 }).alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private BuyNotesSection() {
    if (this.buyNotes.length > 0) {
      Column({ space: 9 }) {
        Text('购买须知').width('100%').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#e6e6eb')
        ForEach(this.buyNotes, (note: string) => {
          Text(note).width('100%').fontSize(10).lineHeight(17).fontColor('#686870')
        })
      }.width('100%').padding({ left: 18, right: 18, top: 28 }).alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        this.Header()
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(40).height(40).color('#ef233c')
            Text('正在加载数字专辑详情').fontSize(11).fontColor('#77777f')
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.message && !this.albumName) {
          Text(this.message).layoutWeight(1).width('100%').fontSize(12).fontColor('#77777f')
            .textAlign(TextAlign.Center)
        } else {
          Scroll() {
            Column() {
              this.HeroSection()
              this.VideoSection()
              this.DescriptionSection()
              this.BuyNotesSection()
              if (this.message) {
                Text(this.message).width('100%').fontSize(10).fontColor('#ef6577')
                  .textAlign(TextAlign.Center).padding(16)
              }
              Blank().height(55)
            }.width('100%')
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        }
      }.width('100%').height('100%')
    }.hideTitleBar(true).backgroundColor('#121215')
  }
}
