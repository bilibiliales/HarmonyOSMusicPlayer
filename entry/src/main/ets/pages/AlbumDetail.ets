import { ResourceComments } from '../components/ResourceComments'
import { CommentResource } from '../models/CommentResource'
import {
  AlbumDetailData,
  AlbumDetailResponse,
  AlbumDynamicResponse,
  AlbumPageParam,
  ApiArtist,
  ArtistPageParam,
  mapApiSong,
  OperationResponse,
  SharePageParam
} from '../models/api'
import { SongArtist, songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'
import { ShareSheet } from '../components/ShareSheet'
import { DetailTopBar } from '../components/DetailTopBar'
import { NoMoreFooter } from '../components/NoMoreFooter'
import { PlaylistCoverPreviewPageParam } from './PlaylistCoverPreview'
import { TC } from '../services/ThemeColors'

@Component
export struct AlbumDetail {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: AlbumPageParam = { id: '' }
  @State albumName: string = ''
  @State albumCover: string = ''
  @State albumArtist: string = ''
  @State albumArtists: ApiArtist[] = []
  @State albumDesc: string = ''
  @State albumCompany: string = ''
  @State albumPublishTime: string = ''
  @State albumType: string = ''
  @State songCount: number = 0
  @State songs: songItemType[] = []
  @State loading: boolean = true
  @State message: string = ''
  @State commentCount: number = 0
  @State shareCount: number = 0
  @State subCount: number = 0
  @State isSub: boolean = false
  @State descExpanded: boolean = false
  @State commentSheetVisible: boolean = false
  @State shareSheetVisible: boolean = false
  @State scrollOffset: number = 0
  private scroller: Scroller = new Scroller()
  private shareParam: SharePageParam = { type: 'album', id: '', name: '', img: '' }

  aboutToAppear(): void {
    this.albumName = this.pageParam.name || ''
    this.albumCover = this.pageParam.picUrl || ''
    this.albumArtist = this.pageParam.artist || ''
    this.shareParam = { type: 'album', id: this.pageParam.id, name: this.albumName, img: this.albumCover }
    this.loadDetail()
  }

  private openCommentSheet(): void {
    this.commentSheetVisible = true
  }

  private commentResource(): CommentResource {
    return { id: this.pageParam.id, type: 3, title: this.albumName }
  }

  @Builder
  private CommentsSheetBuilder() {
    ResourceComments({
      resource: this.commentResource(),
      onClose: () => this.commentSheetVisible = false,
      onCountChange: (total: number) => this.commentCount = total
    })
  }

  private previewCover(): void {
    if (!this.albumCover) { return }
    const param: PlaylistCoverPreviewPageParam = {
      playlist: { id: this.pageParam.id, name: this.albumName, cover: this.albumCover,
        count: this.songCount, creator: this.albumArtist },
      playCount: 0, collectCount: this.subCount, commentCount: this.commentCount,
      tags: [this.albumType, this.albumPublishTime, this.albumCompany].filter((value: string) => value.length > 0),
      description: this.albumDesc, contentType: 'album'
    }
    this.pageStack.pushPathByName('PlaylistCoverPreviewPage', param)
  }

  private async loadDetail(): Promise<void> {
    if (!this.pageParam.id) {
      this.loading = false
      this.message = '专辑参数无效'
      return
    }
    try {
      const response = await ApiClient.get<AlbumDetailResponse>('/album', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200 && response.album) {
        const album: AlbumDetailData = response.album
        this.albumName = album.name || ''
        this.albumCover = album.picUrl || ''
        const artists: ApiArtist[] = album.artists || (album.artist ? [album.artist] : [])
        this.albumArtists = artists
        this.albumArtist = artists.map((ar: ApiArtist) => ar.name).join(' / ')
        this.albumDesc = album.description || ''
        this.albumCompany = album.company || ''
        this.albumType = album.type || ''
        if (album.publishTime && album.publishTime > 0) {
          const date = new Date(album.publishTime)
          this.albumPublishTime = `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`
        }
        this.songCount = album.size || 0
        this.songs = (response.songs || []).map((item) => mapApiSong(item))
        this.shareParam = { type: 'album', id: this.pageParam.id, name: this.albumName, img: this.albumCover }
      } else {
        this.message = '专辑加载失败'
      }
      const dynamicResp = await ApiClient.get<AlbumDynamicResponse>('/album/detail/dynamic', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (dynamicResp.code === 200) {
        this.commentCount = dynamicResp.commentCount || 0
        this.shareCount = dynamicResp.shareCount || 0
        this.subCount = dynamicResp.subCount || 0
        this.isSub = dynamicResp.isSub || false
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '专辑加载失败'
    } finally {
      this.loading = false
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

  private async playAt(index: number): Promise<void> {
    if (this.songs.length === 0) {
      return
    }
    await playerController.setQueue(this.songs, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private async playAll(): Promise<void> {
    if (this.songs.length === 0) {
      return
    }
    await playerController.setQueue(this.songs, 0, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private openArtist(id: string, name: string, picUrl: string = ''): void {
    if (!id || id === '0') {
      return
    }
    const param: ArtistPageParam = { id: id, name: name, picUrl: picUrl }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  @Builder
  private AlbumArtistLinks() {
    Row({ space: 4 }) {
      if (this.albumArtists.length > 0) {
        ForEach(this.albumArtists, (artist: ApiArtist, index: number) => {
          Text(artist.name).fontSize(12).fontColor(TC.textBody()).maxLines(1)
            .onClick(() => this.openArtist((artist.id || 0).toString(), artist.name,
              artist.picUrl || artist.img1v1Url || ''))
          if (index < this.albumArtists.length - 1) {
            Text('/').fontSize(12).fontColor(TC.textTertiary())
          }
        })
      } else {
        Text(this.albumArtist).fontSize(12).fontColor(TC.textBody()).maxLines(1)
      }
    }
    .width('100%')
  }

  @Builder
  private SongArtistLinks(item: songItemType) {
    Row({ space: 4 }) {
      if (item.artists && item.artists.length > 0) {
        ForEach(item.artists, (artist: SongArtist, index: number) => {
          Text(artist.name).fontSize(11).fontColor(TC.textSecondary()).maxLines(1)
            .onClick(() => this.openArtist(artist.id, artist.name, artist.picUrl || ''))
          if (index < item.artists!.length - 1) {
            Text('/').fontSize(11).fontColor(TC.textQuaternary())
          }
        })
      } else {
        Text(item.author).fontSize(11).fontColor(TC.textTertiary()).maxLines(1)
      }
    }
    .width('100%')
  }

  private async toggleSub(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    try {
      const response = await ApiClient.get<AlbumDynamicResponse>('/album/sub', [
        { key: 'id', value: this.pageParam.id },
        { key: 't', value: this.isSub ? '0' : '1' }
      ])
      if (response.code === 200) {
        this.isSub = !this.isSub
        this.subCount = Math.max(0, this.subCount + (this.isSub ? 1 : -1))
      }
    } catch (_error) {
    }
  }






  /** 操作行：播放全部 + 收藏 / 评论 / 分享，滚动内容与吸顶浮层共用。 */
  @Builder
  private ActionBar() {
    Row({ space: 10 }) {
      Button() {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(14).fontColor([TC.textOnAccent()])
          Text('播放全部').fontSize(13).fontColor(TC.textOnAccent()).fontWeight(FontWeight.Medium)
        }
      }
      .layoutWeight(1)
      .height(38)
      .backgroundColor(TC.accent())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .onClick(() => this.playAll())

      Button() {
        Row({ space: 4 }) {
          SymbolGlyph(this.isSub ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(14)
            .fontColor([this.isSub ? TC.accent() : TC.textPrimary()])
          Text(this.isSub ? '已收藏' : '收藏')
            .fontSize(12)
            .fontColor(this.isSub ? TC.accent() : TC.textPrimary())
        }
      }
      .height(38)
      .backgroundColor(this.isSub ? 'rgba(239,35,60,0.12)' : TC.surfaceInset())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .padding({ left: 14, right: 14 })
      .onClick(() => this.toggleSub())

      Button() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(14).fontColor([TC.textBody()])
          Text(this.formatCount(this.commentCount)).fontSize(11).fontColor(TC.textBody())
        }
      }
      .height(38)
      .backgroundColor(TC.surfaceRaised())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .padding({ left: 12, right: 12 })
      .onClick(() => this.openCommentSheet())

      Button() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.share')).fontSize(14).fontColor([TC.textBody()])
          Text(this.formatCount(this.shareCount)).fontSize(11).fontColor(TC.textBody())
        }
      }
      .height(38)
      .backgroundColor(TC.surfaceRaised())
      .borderRadius(19)
      .type(ButtonType.Normal)
      .padding({ left: 12, right: 12 })
      .onClick(() => this.shareSheetVisible = true)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  /** 操作行在内容流里的原始 y（头图高度）。 */
  private actionBarBaseY(): number {
    return 320 + this.topAvoidHeight
  }

  /** 超过阈值后反向补偿滚动量，把操作行锁在标题栏下沿（Excel 冻结行）。 */
  private stickyOffset(): number {
    const threshold = this.actionBarBaseY() - this.topAvoidHeight - 54
    return Math.max(0, this.scrollOffset - threshold)
  }

  /** 全局只有这一份 ActionBar：未吸顶时随内容滚，吸顶后固定不动。 */
  @Builder
  private StickyActionBar() {
    Column() {
      this.ActionBar()
    }
    .width('100%')
    .position({ x: 0, y: this.actionBarBaseY() })
    .offset({ y: -this.scrollOffset + this.stickyOffset() })
    .backgroundColor(Color.Transparent)
    .backdropBlur(this.stickyOffset() > 0 ? 30 : 0)
    .zIndex(3)
  }

  build() {
    NavDestination() {
      if (this.loading) {
        Column() {
          LoadingProgress().width(42).height(42).color(TC.accent())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.message.length > 0 && this.songs.length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(38).fontColor([TC.textQuaternary()])
          Text(this.message).fontSize(13).fontColor(TC.textTertiary())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Scroll(this.scroller) {
            Column() {
              Stack({ alignContent: Alignment.Bottom }) {
                Image(this.albumCover)
                  .width('100%')
                  .height(320 + this.topAvoidHeight)
                  .objectFit(ImageFit.Cover)
                  .blur(60)
                  .opacity(0.4)
                Column()
                  .width('100%')
                  .height(320 + this.topAvoidHeight)
                  .linearGradient({
                    angle: 180,
                    colors: [['#00000000', 0], [TC.pageBackground(), 1]]
                  })
                Row({ space: 16 }) {
                  Image(this.albumCover)
                    .width(120)
                    .height(120)
                    .borderRadius(12)
                    .objectFit(ImageFit.Cover)
                    .shadow({ radius: 16, color: 'rgba(0,0,0,0.35)', offsetY: 4 })
                    .onClick(() => this.previewCover())
                  Column({ space: 6 }) {
                    Text(this.albumName)
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(TC.textPrimary())
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    this.AlbumArtistLinks()
                    if (this.albumPublishTime.length > 0 || this.albumCompany.length > 0) {
                      Text(`${this.albumPublishTime}${this.albumCompany.length > 0 ? ' · ' + this.albumCompany : ''}`)
                        .fontSize(10)
                        .fontColor(TC.textTertiary())
                        .maxLines(1)
                    }
                    if (this.albumType.length > 0) {
                      Text(this.albumType)
                        .fontSize(10)
                        .fontColor(TC.accent())
                        .backgroundColor('rgba(239,35,60,0.12)')
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(4)
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding({ left: 18, right: 18, bottom: 20 })
                .alignItems(VerticalAlign.Bottom)
              }
              .width('100%')
              .height(320 + this.topAvoidHeight)
              .alignContent(Alignment.Bottom)

              Column().width('100%').height(58)

              if (this.albumDesc.length > 0) {
                Column() {
                  Text(this.albumDesc)
                    .fontSize(12)
                    .fontColor(TC.textSecondary())
                    .lineHeight(18)
                    .maxLines(this.descExpanded ? 100 : 3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.albumDesc.length > 30) {
                    Text(this.descExpanded ? '收起' : '展开')
                      .fontSize(11)
                      .fontColor(TC.accent())
                      .margin({ top: 4 })
                      .onClick(() => this.descExpanded = !this.descExpanded)
                  }
                }
                .width('100%')
                .padding({ left: 18, right: 18, top: 4, bottom: 8 })
                .alignItems(HorizontalAlign.Start)
              }

              Row() {
                Text(`歌曲 ${this.songs.length}`)
                  .fontSize(13)
                  .fontColor(TC.textPrimary())
                  .fontWeight(FontWeight.Medium)
                Text(`${this.formatCount(this.subCount)}人收藏 · ${this.formatCount(this.shareCount)}次分享`)
                  .fontSize(10)
                  .fontColor(TC.textTertiary())
                  .layoutWeight(1)
                  .textAlign(TextAlign.End)
              }
              .width('100%')
              .padding({ left: 18, right: 18, top: 8, bottom: 6 })

              List({ space: 0 }) {
                ForEach(this.songs, (item: songItemType, index: number) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Text((index + 1).toString())
                        .width(28)
                        .fontSize(12)
                        .fontColor(TC.textTertiary())
                        .textAlign(TextAlign.Center)
                      Column({ space: 3 }) {
                        Text(item.name)
                          .fontSize(14)
                          .fontColor(TC.textBody())
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        this.SongArtistLinks(item)
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .height(56)
                    .padding({ left: 8, right: 18 })
                    .onClick(() => this.playAt(index as number))
                  }
                })
              }
              .width('100%')
              NoMoreFooter()
            }
            .width('100%')
            .constraintSize({ minHeight: 640 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .onDidScroll(() => { this.scrollOffset = this.scroller.currentOffset().yOffset })

          DetailTopBar({
            title: this.albumName || '专辑',
            scrollOffset: this.scrollOffset,
            onShare: () => this.shareSheetVisible = true
          })
          // 唯一的 ActionBar：随内容滚到顶栏下沿后冻结
          this.StickyActionBar()
          if (this.shareSheetVisible) {
            ShareSheet({
              shareParam: this.shareParam,
              visible: this.shareSheetVisible,
              onClose: () => this.shareSheetVisible = false
            })
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet(this.commentSheetVisible, this.CommentsSheetBuilder(), {
          height: '68%',
          backgroundColor: TC.sheetBackground(),
          showClose: false,
          dragBar: true,
          onDisappear: () => this.commentSheetVisible = false
        })
      }

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
    .backgroundColor(TC.pageBackground())
  }

}
