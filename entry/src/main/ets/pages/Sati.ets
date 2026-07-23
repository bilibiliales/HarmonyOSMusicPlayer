import {
  SatiMoreResponse,
  SatiOperationResponse,
  SatiResource,
  SatiResourceListResponse,
  SatiScene,
  SatiSubListResponse,
  SatiTag,
  SatiTagResponse,
  SatiTimeSceneResponse,
  songItemType
} from '../models'
import { ApiClient } from '../services/ApiClient'
import { resizeImageUrl } from '../services/ImageUrl'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'

@Component
export struct SatiPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  embedded: boolean = false
  @State scene: SatiScene = {}
  @State sceneResources: SatiResource[] = []
  @State tags: SatiTag[] = []
  @State selectedTag: string = 'RCMD'
  @State resources: SatiResource[] = []
  @State subscribedIds: number[] = []
  @State loading: boolean = true
  @State resourceLoading: boolean = false
  @State refreshing: boolean = false
  @State favoritesMode: boolean = false
  @State visibleResourceCount: number = 8
  @State similarResources: SatiResource[] = []
  @State similarTitle: string = ''
  @State similarVisible: boolean = false
  @State actionMessage: string = ''
  private readonly pageSize: number = 8

  aboutToAppear(): void {
    this.loadPage()
  }

  private async loadPage(): Promise<void> {
    this.loading = true
    this.actionMessage = ''
    await Promise.all([this.loadScene(), this.loadTags()])
    await this.loadResources('RCMD')
    if (this.authStore.loggedIn) {
      await this.loadSubscriptions()
    }
    this.loading = false
  }

  private async loadScene(): Promise<void> {
    try {
      const response = await ApiClient.get<SatiTimeSceneResponse>('/sati/timescene/resources/get')
      if (response.code === 200 && response.data) {
        this.scene = response.data.sceneVO || {}
        this.sceneResources = response.data.voiceSatiResourceVOList || []
      }
    } catch (_error) {
    }
  }

  private async loadTags(): Promise<void> {
    try {
      const response = await ApiClient.get<SatiTagResponse>('/sati/tag/list')
      if (response.code === 200) {
        this.tags = response.data || []
      }
    } catch (_error) {
    }
  }

  private async loadResources(tag: string): Promise<void> {
    this.resourceLoading = true
    this.visibleResourceCount = this.pageSize
    this.similarVisible = false
    try {
      const response = await ApiClient.get<SatiResourceListResponse>('/sati/resource/list', [
        { key: 'tag', value: tag }
      ])
      if (response.code === 200) {
        this.resources = response.data || []
      } else {
        this.resources = []
      }
    } catch (error) {
      this.resources = []
      this.actionMessage = error instanceof Error ? error.message : '助眠声音加载失败'
    } finally {
      this.resourceLoading = false
    }
  }

  private async loadSubscriptions(): Promise<void> {
    try {
      const response = await ApiClient.get<SatiSubListResponse>('/sati/resource/sub/list')
      if (response.code === 200) {
        const subscriptions = response.data || []
        this.subscribedIds = subscriptions.map((item: SatiResource) => item.id)
        if (this.favoritesMode) {
          this.resources = subscriptions
          this.visibleResourceCount = this.pageSize
        }
      }
    } catch (_error) {
    }
  }

  private selectTag(tag: SatiTag): void {
    if (this.selectedTag === tag.tag && !this.favoritesMode) {
      return
    }
    this.favoritesMode = false
    this.selectedTag = tag.tag
    this.loadResources(tag.tag)
  }

  private async showFavorites(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.favoritesMode = true
    this.selectedTag = ''
    this.resourceLoading = true
    this.similarVisible = false
    await this.loadSubscriptions()
    this.resourceLoading = false
  }

  private toSong(item: SatiResource): songItemType {
    return {
      id: item.trackId.toString(),
      name: item.name,
      author: '助眠解压',
      img: item.pic,
      url: '',
      album: this.tagName(item.category || this.selectedTag),
      fee: 0
    }
  }

  private async playResource(item: SatiResource, source: SatiResource[] = this.resources): Promise<void> {
    const queueSource = source.length > 0 ? source : [item]
    const songs = queueSource.map((resource: SatiResource) => this.toSong(resource))
    const index = Math.max(0, queueSource.findIndex((resource: SatiResource) => resource.id === item.id))
    await playerController.setQueue(songs, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private isSubscribed(item: SatiResource): boolean {
    return this.subscribedIds.includes(item.id)
  }

  private async toggleSubscription(item: SatiResource): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const subscribed = this.isSubscribed(item)
    try {
      const response = subscribed ?
        await ApiClient.get<SatiOperationResponse>('/sati/resource/sub', [
          { key: 'id', value: item.id.toString() },
          { key: 'cancel', value: 'true' }
        ]) :
        await ApiClient.get<SatiOperationResponse>('/sati/resource/sub', [
          { key: 'id', value: item.id.toString() }
        ])
      if (response.code === 200) {
        if (subscribed) {
          this.subscribedIds = this.subscribedIds.filter((id: number) => id !== item.id)
          if (this.favoritesMode) {
            this.resources = this.resources.filter((resource: SatiResource) => resource.id !== item.id)
          }
          this.actionMessage = '已取消收藏'
        } else {
          this.subscribedIds = this.subscribedIds.concat([item.id])
          this.actionMessage = '已收藏声音'
        }
      } else {
        this.actionMessage = response.message || '收藏操作失败'
      }
    } catch (error) {
      this.actionMessage = error instanceof Error ? error.message : '收藏操作失败'
    }
  }

  private async loadSimilar(item: SatiResource): Promise<void> {
    this.similarVisible = true
    this.similarResources = []
    this.similarTitle = `与「${item.name}」相似`
    try {
      const response = await ApiClient.get<SatiMoreResponse>('/sati/resource/list/more', [
        { key: 'id', value: item.id.toString() }
      ])
      if (response.code === 200 && response.data) {
        this.similarTitle = response.data.tagDesc || this.similarTitle
        this.similarResources = (response.data.resourceList || []).slice(0, 8)
      }
    } catch (error) {
      this.actionMessage = error instanceof Error ? error.message : '同类推荐加载失败'
    }
  }

  private tagName(tag: string): string {
    const match = this.tags.find((item: SatiTag) => item.tag === tag)
    return match?.tagDesc || '助眠解压'
  }

  private revealMoreResources(): void {
    if (!this.resourceLoading && this.visibleResourceCount < this.resources.length) {
      this.visibleResourceCount = Math.min(this.visibleResourceCount + this.pageSize, this.resources.length)
    }
  }

  @Builder
  private PageHeader() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
        .onClick(() => this.pageStack.pop())
      Column({ space: 3 }) {
        Text('助眠解压').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text('让自然与轻柔声音安抚此刻').fontSize(11).fontColor('#6f6f77')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Stack() {
        SymbolGlyph($r('sys.symbol.heart_fill')).fontSize(19)
          .fontColor([this.favoritesMode ? '#ef233c' : '#ddddE2'])
      }.width(42).height(42).borderRadius(14).backgroundColor('#1e1e24')
        .onClick(() => this.showFavorites())
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
        Text('数字专辑').fontSize(13).fontColor('#85858e')
          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#1d1d22').borderRadius(18)
          .onClick(() => this.pageStack.replacePathByName('DigitalAlbumPage', null))
        Text('助眠解压').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#ef233c').borderRadius(18)
      }.padding({ left: 16, right: 16 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .margin({ top: 10, bottom: 4 })
  }

  @Builder
  private SceneSection() {
    if (this.sceneResources.length > 0) {
      Column({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.scene.text || '此刻推荐').width('100%').fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
          Text('根据当前时段为你准备').width('100%').fontSize(10).fontColor('#77777f')
        }.width('100%').alignItems(HorizontalAlign.Start)
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.sceneResources, (item: SatiResource) => {
              Stack({ alignContent: Alignment.BottomStart }) {
                Image(item.pic).width(220).height(138)
                  .borderRadius(19).objectFit(ImageFit.Cover)
                Column().width(220).height(78).borderRadius({ bottomLeft: 19, bottomRight: 19 })
                  .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.84)', 1]] })
                Row({ space: 7 }) {
                  Text(item.name).layoutWeight(1).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(25).fontColor(['#ffffff'])
                }.width(202).margin({ left: 9, bottom: 10 })
              }.width(220).height(138).onClick(() => this.playResource(item, this.sceneResources))
            }, (item: SatiResource) => item.id.toString())
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }.width('100%').padding({ left: 16, right: 16, top: 20 })
    }
  }

  @Builder
  private TagSection() {
    Text(this.favoritesMode ? '我的收藏' : '声音分类').width('100%').fontSize(19).fontWeight(FontWeight.Bold)
      .fontColor('#ffffff').padding({ left: 16, right: 16, top: 24, bottom: 11 })
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.tags, (tag: SatiTag) => {
          Text(tag.tagDesc).fontSize(11).fontWeight(this.selectedTag === tag.tag ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.selectedTag === tag.tag ? '#ffffff' : '#85858e')
            .padding({ left: 15, right: 15, top: 8, bottom: 8 })
            .backgroundColor(this.selectedTag === tag.tag ? '#ef233c' : '#202026').borderRadius(17)
            .onClick(() => this.selectTag(tag))
        }, (tag: SatiTag) => tag.tag)
      }.padding({ left: 16, right: 16 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
  }

  @Builder
  private ResourceCard(item: SatiResource, source: SatiResource[]) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(resizeImageUrl(item.pic, 340, 340)).width('100%').aspectRatio(1)
          .sourceSize({ width: 340, height: 340 }).borderRadius(17).objectFit(ImageFit.Cover)
        Stack() {
          SymbolGlyph(this.isSubscribed(item) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(18).fontColor([this.isSubscribed(item) ? '#ef233c' : '#ffffff'])
        }.width(34).height(34).borderRadius(17).backgroundColor('rgba(0,0,0,0.48)').margin(7)
          .onClick(() => this.toggleSubscription(item))
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(20).fontColor(['#ffffff'])
        }.width(34).height(34).borderRadius(22).backgroundColor('rgba(239,35,60,0.9)').margin(7)
          .align(Alignment.Center).onClick(() => this.playResource(item, source))
      }.width('100%').aspectRatio(1)
      Row({ space: 6 }) {
        Column({ space: 3 }) {
          Text(item.name).width('100%').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#e8e8eb')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.tagName(item.category || this.selectedTag)).fontSize(9).fontColor('#686870')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(18).fontColor(['#77777f'])
          .onClick(() => this.loadSimilar(item))
      }.width('100%')
    }.width('48%').margin({ bottom: 17 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ResourcesSection() {
    if (this.resourceLoading) {
      LoadingProgress().width(32).height(32).color('#ef233c').margin({ top: 60, bottom: 60 })
    } else if (this.resources.length === 0) {
      Text(this.favoritesMode ? '还没有收藏助眠声音' : '该分类暂无声音').width('100%').height(180)
        .fontSize(11).fontColor('#686870').textAlign(TextAlign.Center)
    } else {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.resources.slice(0, this.visibleResourceCount),
          (item: SatiResource) => {
          this.ResourceCard(item, this.resources)
        }, (item: SatiResource) => item.id.toString())
      }.width('100%').padding({ left: 16, right: 16, top: 17 })
    }
  }

  @Builder
  private SimilarSection() {
    if (this.similarVisible) {
      Column({ space: 12 }) {
        Row() {
          Text(this.similarTitle || '同类推荐').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
          SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(22).fontColor(['#66666e'])
            .onClick(() => this.similarVisible = false)
        }.width('100%')
        if (this.similarResources.length === 0) {
          LoadingProgress().width(27).height(27).color('#ef233c').margin({ top: 25, bottom: 25 })
        } else {
          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.similarResources, (item: SatiResource) => {
                Column({ space: 7 }) {
                  Stack({ alignContent: Alignment.Center }) {
                    Image(resizeImageUrl(item.pic, 260, 260)).width(112).height(112)
                      .sourceSize({ width: 260, height: 260 }).borderRadius(16).objectFit(ImageFit.Cover)
                    SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(29).fontColor(['#ffffff'])
                  }
                  Text(item.name).width(112).fontSize(10).fontColor('#d7d7dc').maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width(112).onClick(() => this.playResource(item, this.similarResources))
              }, (item: SatiResource) => item.id.toString())
            }
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        }
      }.width('100%').padding({ left: 16, right: 16, top: 20 })
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
              Text('正在准备舒缓声音').fontSize(11).fontColor('#77777f')
            }.width('100%').height(360).justifyContent(FlexAlign.Center)
          } else {
            this.SceneSection()
            this.TagSection()
            this.ResourcesSection()
            this.SimilarSection()
            if (this.actionMessage) {
              Text(this.actionMessage).width('100%').fontSize(10).fontColor('#ef6577')
                .textAlign(TextAlign.Center).padding(14)
            }
            Blank().height(this.embedded ? 145 : 55)
          }
        }.width('100%')
      }.width('100%').height('100%').scrollBar(BarState.Off).onReachEnd(() => this.revealMoreResources())
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
