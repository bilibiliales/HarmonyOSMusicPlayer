import {
  AlbumPageParam,
  BannerItem,
  BannerResponse,
  HomeBlockView,
  HomeCreativeView,
  HomepageBlock,
  HomepageCreative,
  HomepageResponse,
  HomepageResource,
  HomepageUiElement,
  HomeResourceView,
  mapApiSong,
  playlistType,
  songItemType
} from '../models'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'
import { RankingPage } from './Ranking'
import { StylePage } from './Style'
import { RadioPage } from './Radio'
import { DigitalAlbumPage } from './DigitalAlbum'
import { SatiPage } from './Sati'

@Component
struct Find {
  @Consume('pageStack') pageStack: NavPathStack
  @State blocks: HomeBlockView[] = []
  @State banners: BannerItem[] = []
  @State loading: boolean = true
  @State message: string = ''
  @State isRefreshing: boolean = false
  @State failedImages: Set<string> = new Set()
  @State currentSection: number = 0
  @State transitionDirection: number = 1
  private readonly sectionTitles: string[] = ['发现', '排行榜', '曲风', '电台', '数字专辑', '助眠解压']

  aboutToAppear(): void {
    this.loadData(false)
  }

  private switchSection(index: number): void {
    if (index === this.currentSection) {
      return
    }
    this.transitionDirection = index > this.currentSection ? -1 : 1
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
      this.currentSection = index
    })
  }

  private sectionSubtitle(): string {
    if (this.currentSection === 1) {
      return '官方榜单、歌手榜与热门排行'
    }
    if (this.currentSection === 2) {
      return '从偏好出发探索音乐类型'
    }
    if (this.currentSection === 3) {
      return '发现值得收听的声音节目'
    }
    if (this.currentSection === 4) {
      return '发现新发行与畅销数字音乐'
    }
    if (this.currentSection === 5) {
      return '让自然与轻柔声音安抚此刻'
    }
    return '来自网易云音乐首页的实时推荐'
  }

  private titleOf(ui?: HomepageUiElement): string {
    return ui?.mainTitle?.title || ''
  }

  private subtitleOf(ui?: HomepageUiElement): string {
    return ui?.subTitle?.title || ''
  }

  private imageOf(ui?: HomepageUiElement): string {
    return ui?.image?.imageUrl || ''
  }

  private normalizeResource(resource: HomepageResource, creative: HomepageCreative): HomeResourceView {
    const ext = resource.resourceExtInfo
    const rawSong = ext?.songData || ext?.song
    let song: songItemType | undefined = undefined
    if (rawSong) {
      song = mapApiSong(rawSong)
    }
    const artistText = ext?.artists?.map((item) => item.name).join(' / ') || song?.author || ''
    const title = this.titleOf(resource.uiElement) || this.titleOf(creative.uiElement) || song?.name || '网易云音乐'
    const image = this.imageOf(resource.uiElement) || this.imageOf(creative.uiElement) || song?.img || ''
    if (song) {
      song.name = title
      song.img = image
    }
    return {
      id: resource.resourceId || song?.id || '',
      title: title,
      subtitle: this.subtitleOf(resource.uiElement) || artistText,
      image: image,
      resourceType: resource.resourceType || '',
      playCount: ext?.playCount || 0,
      song: song
    }
  }

  private normalizeBlock(block: HomepageBlock, blockIndex: number): HomeBlockView {
    const creativeViews: HomeCreativeView[] = []
    const creatives = block.creatives || []
    for (let creativeIndex = 0; creativeIndex < creatives.length; creativeIndex++) {
      const creative = creatives[creativeIndex]
      const items: HomeResourceView[] = []
      const resources = creative.resources || []
      for (let resourceIndex = 0; resourceIndex < resources.length; resourceIndex++) {
        items.push(this.normalizeResource(resources[resourceIndex], creative))
      }
      if (items.length > 0) {
        creativeViews.push({
          key: `${blockIndex}-${creativeIndex}`,
          title: this.titleOf(creative.uiElement),
          items: items
        })
      }
    }
    return {
      key: block.blockCode || `block-${blockIndex}`,
      title: this.subtitleOf(block.uiElement) || this.titleOf(block.uiElement) || '为你推荐',
      showType: block.showType || '',
      creativeType: creatives.length > 0 ? (creatives[0].creativeType || '') : '',
      creatives: creativeViews
    }
  }

  private async loadData(refresh: boolean): Promise<void> {
    this.loading = this.blocks.length === 0
    this.message = ''
    await this.loadBanners()
    try {
      const response = await ApiClient.get<HomepageResponse>('/homepage/block/page', [
        { key: 'refresh', value: refresh ? 'true' : 'false' }
      ])
      if (response.code === 200 && response.data?.blocks?.length) {
        const result: HomeBlockView[] = []
        response.data.blocks.forEach((block: HomepageBlock, index: number) => {
          const normalized = this.normalizeBlock(block, index)
          if (normalized.creatives.length > 0) {
            result.push(normalized)
          }
        })
        this.blocks = result
        if (result.length === 0) {
          this.message = '首页接口暂未返回可展示内容'
        }
      } else {
        this.message = response.message || '首页接口暂未返回内容'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '发现页加载失败'
    } finally {
      this.loading = false
    }
  }

  private async loadBanners(): Promise<void> {
    try {
      const response = await ApiClient.get<BannerResponse>('/banner', [{ key: 'type', value: '1' }])
      if (response.code === 200 && response.banners?.length) {
        this.banners = response.banners
      }
    } catch (_error) {
    }
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

  private openPlaylist(item: HomeResourceView): void {
    const playlist: playlistType = {
      id: item.id,
      name: item.title,
      cover: item.image,
      count: 0,
      creator: '网易云音乐'
    }
    this.pageStack.pushPathByName('PlaylistDetailPage', playlist)
  }

  private openAlbum(item: HomeResourceView): void {
    const param: AlbumPageParam = {
      id: item.id,
      name: item.title,
      picUrl: item.image,
      artist: item.subtitle
    }
    this.pageStack.pushPathByName('AlbumDetailPage', param)
  }

  private openBanner(item: BannerItem): void {
    if (item.targetType === 1000 && item.targetId > 0) {
      const playlist: playlistType = {
        id: item.targetId.toString(),
        name: item.typeTitle || '推荐歌单',
        cover: item.pic,
        count: 0,
        creator: '网易云音乐'
      }
      this.pageStack.pushPathByName('PlaylistDetailPage', playlist)
    } else if (item.targetType === 10 && item.targetId > 0) {
      const param: AlbumPageParam = {
        id: item.targetId.toString(),
        name: item.typeTitle || '推荐专辑',
        picUrl: item.pic,
        artist: ''
      }
      this.pageStack.pushPathByName('AlbumDetailPage', param)
    }
  }

  private async playResource(block: HomeBlockView, item: HomeResourceView): Promise<void> {
    const songs: songItemType[] = []
    let targetIndex = 0
    for (let creativeIndex = 0; creativeIndex < block.creatives.length; creativeIndex++) {
      const items = block.creatives[creativeIndex].items
      for (let itemIndex = 0; itemIndex < items.length; itemIndex++) {
        const current = items[itemIndex]
        if (current.song) {
          if (current.id === item.id) {
            targetIndex = songs.length
          }
          songs.push(current.song)
        }
      }
    }
    if (songs.length > 0) {
      await playerController.setQueue(songs, targetIndex, true)
    }
  }

  private openResource(block: HomeBlockView, item: HomeResourceView): void {
    if (item.resourceType === 'list') {
      this.openPlaylist(item)
    } else if (item.resourceType === 'album') {
      this.openAlbum(item)
    } else if (item.song || item.resourceType === 'song') {
      this.playResource(block, item)
    }
  }

  @Builder
  private PageHeader() {
    Row() {
      Column({ space: 3 }) {
        Text('发现').fontSize(27).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text(this.sectionSubtitle()).fontSize(11).fontColor('#6f6f77')
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      Stack() {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(19).fontColor(['#ddddE2'])
      }
      .width(42).height(42).borderRadius(14).backgroundColor('#1e1e24')
      .onClick(() => this.pageStack.pushPathByName('SearchPage', null))
    }
    .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 5 })
  }

  @Builder
  private DiscoveryTabs() {
    Scroll() {
      Row() {
        ForEach(this.sectionTitles, (title: string, index: number) => {
          Column({ space: 7 }) {
            Text(title).fontSize(13)
              .fontWeight(this.currentSection === index ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.currentSection === index ? '#ffffff' : '#74747d')
            Column().width(24).height(3).borderRadius(2)
              .backgroundColor(this.currentSection === index ? '#ef233c' : 'transparent')
          }.width(title.length > 4 ? 82 : 66).height(46).justifyContent(FlexAlign.Center)
            .onClick(() => this.switchSection(index))
        })
      }.padding({ left: 8, right: 8 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .backgroundColor('#17171c')
  }

  @Builder
  private BlockTitle(title: string) {
    Row() {
      Text(title).layoutWeight(1).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#eeeeF1')
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor(['#66666e'])
    }
    .width('100%').padding({ left: 16, right: 16, top: 24, bottom: 11 })
  }

  @Builder
  private PlaylistBlock(block: HomeBlockView) {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(block.creatives, (creative: HomeCreativeView) => {
          if (creative.items.length > 0) {
            Column({ space: 8 }) {
              Stack({ alignContent: Alignment.TopEnd }) {
                this.NetworkImage(creative.items[0].image, 138, 138, 17)
                if (creative.items[0].playCount > 0) {
                  Text(`▷ ${this.formatCount(creative.items[0].playCount)}`)
                    .fontSize(9).fontColor('#ffffff')
                    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                    .backgroundColor('rgba(0,0,0,0.48)').borderRadius(9).margin(7)
                }
              }
              Text(creative.items[0].title).width(138).fontSize(12).fontColor('#dedee2').maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .onClick(() => this.openResource(block, creative.items[0]))
          }
        }, (creative: HomeCreativeView) => creative.key)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
  }

  @Builder
  private GroupedBlock(block: HomeBlockView) {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(block.creatives, (creative: HomeCreativeView) => {
          Column() {
            if (creative.title.length > 0) {
              Text(creative.title).width('100%').fontSize(11).fontWeight(FontWeight.Medium)
                .fontColor('#ef4058').padding({ left: 10, top: 8, bottom: 2 })
            }
            ForEach(creative.items, (item: HomeResourceView) => {
              Row({ space: 10 }) {
                this.NetworkImage(item.image, 54, 54, 12)
                Column({ space: 5 }) {
                  Text(item.title).width('100%').fontSize(13).fontColor('#eeeeF1').maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (item.subtitle.length > 0) {
                    Text(item.subtitle).width('100%').fontSize(10).fontColor('#77777f').maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  } else {
                    Text(item.resourceType === 'album' ? '新碟' : '网易云音乐')
                      .fontSize(10).fontColor('#77777f')
                  }
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (item.song) {
                  SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(23).fontColor(['#9999a1'])
                } else {
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor(['#66666e'])
                }
              }
              .width(310).height(68).padding({ left: 8, right: 8 })
              .onClick(() => this.openResource(block, item))
            })
          }
          .padding({ bottom: 4 }).backgroundColor('#18181d').borderRadius(18).clip(true)
        }, (creative: HomeCreativeView) => creative.key)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
  }

  @Builder
  private NetworkImage(url: string, width: number, height: number, radius: number) {
    if (!url || this.failedImages.has(url)) {
      Stack() {
        SymbolGlyph($r('sys.symbol.music')).fontSize(22).fontColor(['#62626c'])
      }
      .width(width).height(height).borderRadius(radius)
      .linearGradient({ angle: 135, colors: [['#30303c', 0], ['#1f1f28', 1]] })
    } else {
      Image(resizeImageUrl(url, width * 2, height * 2)).width(width).height(height)
        .sourceSize({ width: width * 2, height: height * 2 }).borderRadius(radius).objectFit(ImageFit.Cover)
        .onError(() => {
          this.failedImages.add(url)
          this.failedImages = new Set(this.failedImages)
        })
    }
  }

  @Builder
  private DiscoverContent() {
    Refresh({ refreshing: this.isRefreshing }) {
      Scroll() {
        Column() {
          if (this.banners.length > 0) {
            Swiper() {
              ForEach(this.banners, (item: BannerItem) => {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  Image(resizeImageUrl(item.pic, 720, 292)).width('100%').height('100%')
                    .sourceSize({ width: 720, height: 292 }).borderRadius(18).objectFit(ImageFit.Cover)
                  if (item.typeTitle && item.typeTitle.length > 0) {
                    Text(item.typeTitle).fontSize(10).fontColor('#ffffff')
                      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                      .backgroundColor(item.titleColor === 'red' ? '#d9364f' : '#3f67a5')
                      .borderRadius({ topLeft: 10, bottomRight: 18 })
                  }
                }
                .width('100%').height('100%').borderRadius(18).clip(true)
                .onClick(() => this.openBanner(item))
              }, (item: BannerItem) => item.bannerId || item.pic)
            }
            .width('92%').height(146).margin({ top: 12, bottom: 4 })
            .autoPlay(true).interval(4000).duration(450).loop(true).indicator(true)
            .borderRadius(18).clip(true)
          }

          if (this.loading) {
            Column({ space: 12 }) {
              LoadingProgress().width(34).height(34).color('#ef233c')
              Text('正在加载发现内容').fontSize(12).fontColor('#77777f')
            }
            .width('100%').height(420).justifyContent(FlexAlign.Center)
          } else if (this.blocks.length === 0) {
            Column({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(36).fontColor(['#77777f'])
              Text(this.message || '发现页暂无内容').fontSize(12).fontColor('#77777f')
              Text('下拉可重新请求 /homepage/block/page').fontSize(10).fontColor('#55555d')
            }
            .width('100%').height(420).justifyContent(FlexAlign.Center)
          } else {
            ForEach(this.blocks, (block: HomeBlockView) => {
              this.BlockTitle(block.title)
              if (block.creativeType === 'list' || block.showType === 'HOMEPAGE_SLIDE_PLAYLIST') {
                this.PlaylistBlock(block)
              } else {
                this.GroupedBlock(block)
              }
            }, (block: HomeBlockView) => block.key)
            Blank().height(145)
          }
        }
        .width('100%')
      }
      .width('100%').height('100%').scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor('#121215')
    .onRefreshing(async () => {
      this.isRefreshing = true
      await this.loadData(true)
      this.isRefreshing = false
    })
  }

  @Builder
  private SectionContent() {
    Stack() {
      if (this.currentSection === 0) {
        Column() {
          this.DiscoverContent()
        }.width('100%').height('100%')
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: this.transitionDirection * 52 }))
            .animation({ duration: 280, curve: Curve.EaseOut }))
      } else if (this.currentSection === 1) {
        RankingPage({ embedded: true })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: this.transitionDirection * 52 }))
            .animation({ duration: 280, curve: Curve.EaseOut }))
      } else if (this.currentSection === 2) {
        StylePage({ embedded: true })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: this.transitionDirection * 52 }))
            .animation({ duration: 280, curve: Curve.EaseOut }))
      } else if (this.currentSection === 3) {
        RadioPage({ embedded: true })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: this.transitionDirection * 52 }))
            .animation({ duration: 280, curve: Curve.EaseOut }))
      } else if (this.currentSection === 4) {
        DigitalAlbumPage({ embedded: true })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: this.transitionDirection * 52 }))
            .animation({ duration: 280, curve: Curve.EaseOut }))
      } else {
        SatiPage({ embedded: true })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: this.transitionDirection * 52 }))
            .animation({ duration: 280, curve: Curve.EaseOut }))
      }
    }.width('100%').height('100%')
  }

  build() {
    Column() {
      this.PageHeader()
      this.DiscoveryTabs()
      this.SectionContent()
    }.width('100%').height('100%').backgroundColor('#121215')
  }
}

export default Find
