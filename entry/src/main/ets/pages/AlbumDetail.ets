import {
  AlbumDetailData,
  AlbumDetailResponse,
  AlbumDynamicResponse,
  AlbumPageParam,
  ApiArtist,
  ArtistPageParam,
  CommentResponse,
  mapApiSong,
  mapComment,
  OperationResponse,
  SharePageParam
} from '../models/api'
import { MusicComment, SongArtist, songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'
import { ShareSheet } from '../components/ShareSheet'

@Component
export struct AlbumDetail {
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
  @State comments: MusicComment[] = []
  @State commentsLoading: boolean = false
  @State commentPage: number = 0
  @State commentHasMore: boolean = true
  @State commentLoadingMore: boolean = false
  @State commentInput: string = ''
  @State commentSubmitting: boolean = false
  @State shareSheetVisible: boolean = false
  private shareParam: SharePageParam = { type: 'album', id: '', name: '', img: '' }

  aboutToAppear(): void {
    this.albumName = this.pageParam.name || ''
    this.albumCover = this.pageParam.picUrl || ''
    this.albumArtist = this.pageParam.artist || ''
    this.shareParam = { type: 'album', id: this.pageParam.id, name: this.albumName, img: this.albumCover }
    this.loadDetail()
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
          Text(artist.name).fontSize(12).fontColor('#d0d0d6').maxLines(1)
            .onClick(() => this.openArtist((artist.id || 0).toString(), artist.name,
              artist.picUrl || artist.img1v1Url || ''))
          if (index < this.albumArtists.length - 1) {
            Text('/').fontSize(12).fontColor('#77777f')
          }
        })
      } else {
        Text(this.albumArtist).fontSize(12).fontColor('#b0b0b8').maxLines(1)
      }
    }
    .width('100%')
  }

  @Builder
  private SongArtistLinks(item: songItemType) {
    Row({ space: 4 }) {
      if (item.artists && item.artists.length > 0) {
        ForEach(item.artists, (artist: SongArtist, index: number) => {
          Text(artist.name).fontSize(11).fontColor('#8d8d96').maxLines(1)
            .onClick(() => this.openArtist(artist.id, artist.name, artist.picUrl || ''))
          if (index < item.artists!.length - 1) {
            Text('/').fontSize(11).fontColor('#5f5f67')
          }
        })
      } else {
        Text(item.author).fontSize(11).fontColor('#77777f').maxLines(1)
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

  private async openCommentSheet(): Promise<void> {
    this.commentSheetVisible = true
    if (this.comments.length === 0) {
      await this.loadComments(true)
    }
  }

  private async loadComments(reset: boolean): Promise<void> {
    if (reset) {
      this.commentPage = 0
      this.commentHasMore = true
      this.commentsLoading = true
    } else {
      if (!this.commentHasMore || this.commentLoadingMore) {
        return
      }
      this.commentLoadingMore = true
    }
    try {
      const limit = 30
      const offset = this.commentPage * limit
      const response = await ApiClient.get<CommentResponse>('/comment/album', [
        { key: 'id', value: this.pageParam.id },
        { key: 'limit', value: limit.toString() },
        { key: 'offset', value: offset.toString() }
      ])
      const newComments = (response.comments || []).map((item) => mapComment(item))
      const hotComments = (response.hotComments || []).map((item) => mapComment(item))
      if (reset) {
        this.comments = hotComments.length > 0 ? [...hotComments, ...newComments] : newComments
      } else {
        this.comments = [...this.comments, ...newComments]
      }
      this.commentHasMore = this.comments.length < (response.total || 0)
      this.commentPage++
      this.commentCount = response.total || this.comments.length
    } catch (_error) {
      if (reset) {
        this.comments = []
      }
    } finally {
      this.commentsLoading = false
      this.commentLoadingMore = false
    }
  }

  private async toggleCommentLike(comment: MusicComment): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const nextLiked = !comment.liked
    try {
      const response = await ApiClient.get<CommentResponse>('/comment/like', [
        { key: 'id', value: this.pageParam.id },
        { key: 'cid', value: comment.commentId },
        { key: 'type', value: '3' },
        { key: 't', value: nextLiked ? '1' : '0' }
      ])
      if (response.code === 200) {
        comment.liked = nextLiked
        comment.likedCount = Math.max(0, comment.likedCount + (nextLiked ? 1 : -1))
        this.comments = this.comments.map((item: MusicComment) => item)
      }
    } catch (_error) {
    }
  }

  private async submitAlbumComment(): Promise<void> {
    const content = this.commentInput.trim()
    if (!content || this.commentSubmitting) {
      return
    }
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.commentSubmitting = true
    try {
      const response = await ApiClient.get<CommentResponse>('/comment', [
        { key: 't', value: '1' },
        { key: 'type', value: '3' },
        { key: 'id', value: this.pageParam.id },
        { key: 'content', value: content }
      ])
      if (response.code === 200) {
        this.commentInput = ''
        this.commentCount = this.commentCount + 1
        await this.loadComments(true)
      }
    } catch (_error) {
    } finally {
      this.commentSubmitting = false
    }
  }

  @Builder
  private CommentsSheetBuilder() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text(`评论 · ${this.commentCount}`).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text('热门评论与最新评论').fontSize(10).fontColor('#77777f')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor(['#686870'])
          .onClick(() => this.commentSheetVisible = false)
      }
      .width('100%').height(66).padding({ left: 20, right: 20 })

      if (this.commentsLoading) {
        LoadingProgress().layoutWeight(1).width(42).color('#ef233c')
      } else if (this.comments.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(38).fontColor(['#55555d'])
          Text('暂无评论').fontSize(12).fontColor('#77777f')
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 14 }) {
          ForEach(this.comments, (item: MusicComment) => {
            ListItem() {
              Row({ space: 10 }) {
                Image(item.user.avatarUrl).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover)
                Column({ space: 6 }) {
                  Row() {
                    Column({ space: 2 }) {
                      Text(item.user.nickname).fontSize(12).fontColor('#b9b9c0')
                      Text(item.timeStr).fontSize(9).fontColor('#5f5f67')
                    }
                    .layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Row({ space: 4 }) {
                      SymbolGlyph(item.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                        .fontSize(14).fontColor([item.liked ? '#ef233c' : '#77777f'])
                      Text(`${item.likedCount}`).fontSize(10).fontColor(item.liked ? '#ef233c' : '#77777f')
                    }
                    .padding({ left: 6, right: 4, top: 5, bottom: 5 })
                    .onClick(() => this.toggleCommentLike(item))
                  }
                  Text(item.content).fontSize(13).fontColor('#ededf0').lineHeight(20)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .padding({ left: 18, right: 18, bottom: 6 })
            }
          })
          if (this.commentHasMore) {
            ListItem() {
              Row() {
                if (this.commentLoadingMore) {
                  LoadingProgress().width(20).height(20).color('#ef233c')
                }
                Text(this.commentLoadingMore ? '加载中…' : '上滑加载更多')
                  .fontSize(12).fontColor('#77777f').margin({ left: 8 })
              }
              .width('100%').justifyContent(FlexAlign.Center).padding({ top: 12, bottom: 12 })
            }
          }
        }
        .layoutWeight(1)
        .onReachEnd(() => this.loadComments(false))
      }
      Row({ space: 10 }) {
        TextInput({ text: this.commentInput, placeholder: '写下你对这张专辑的评论…' })
          .layoutWeight(1).height(42).fontSize(13).fontColor('#ffffff')
          .placeholderColor('#66666e').backgroundColor('#25252b').borderRadius(18)
          .onChange((value: string) => this.commentInput = value)
          .onSubmit(() => this.submitAlbumComment())
        Button(this.commentSubmitting ? '发送中' : '发送')
          .height(40).fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
          .borderRadius(18).enabled(!this.commentSubmitting && this.commentInput.trim().length > 0)
          .onClick(() => this.submitAlbumComment())
      }
      .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 12 })
    }
    .width('100%').height('100%')
  }

  build() {
    NavDestination() {
      if (this.loading) {
        Column() {
          LoadingProgress().width(42).height(42).color('#ef233c')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.message.length > 0 && this.songs.length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(38).fontColor(['#55555d'])
          Text(this.message).fontSize(13).fontColor('#77777f')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Scroll() {
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
                    colors: [['rgba(18,18,21,0.0)', 0], ['rgba(18,18,21,0.95)', 1]]
                  })
                Row({ space: 16 }) {
                  Image(this.albumCover)
                    .width(120)
                    .height(120)
                    .borderRadius(12)
                    .objectFit(ImageFit.Cover)
                    .shadow({ radius: 16, color: 'rgba(0,0,0,0.35)', offsetY: 4 })
                  Column({ space: 6 }) {
                    Text(this.albumName)
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#ffffff')
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    this.AlbumArtistLinks()
                    if (this.albumPublishTime.length > 0 || this.albumCompany.length > 0) {
                      Text(`${this.albumPublishTime}${this.albumCompany.length > 0 ? ' · ' + this.albumCompany : ''}`)
                        .fontSize(10)
                        .fontColor('#77777f')
                        .maxLines(1)
                    }
                    if (this.albumType.length > 0) {
                      Text(this.albumType)
                        .fontSize(10)
                        .fontColor('#ef233c')
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

              Row({ space: 10 }) {
                Button() {
                  Row({ space: 5 }) {
                    SymbolGlyph($r('sys.symbol.play_fill')).fontSize(14).fontColor([Color.White])
                    Text('播放全部').fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium)
                  }
                }
                .layoutWeight(1)
                .height(38)
                .backgroundColor('#ef233c')
                .borderRadius(19)
                .type(ButtonType.Normal)
                .onClick(() => this.playAll())

                Button() {
                  Row({ space: 4 }) {
                    SymbolGlyph(this.isSub ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                      .fontSize(14)
                      .fontColor([this.isSub ? '#ef233c' : '#ffffff'])
                    Text(this.isSub ? '已收藏' : '收藏')
                      .fontSize(12)
                      .fontColor(this.isSub ? '#ef233c' : '#ffffff')
                  }
                }
                .height(38)
                .backgroundColor(this.isSub ? 'rgba(239,35,60,0.12)' : '#2a2a2e')
                .borderRadius(19)
                .type(ButtonType.Normal)
                .padding({ left: 14, right: 14 })
                .onClick(() => this.toggleSub())

                Button() {
                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(14).fontColor(['#b0b0b8'])
                    Text(this.formatCount(this.commentCount)).fontSize(11).fontColor('#b0b0b8')
                  }
                }
                .height(38)
                .backgroundColor('#2a2a2e')
                .borderRadius(19)
                .type(ButtonType.Normal)
                .padding({ left: 12, right: 12 })
                .onClick(() => this.openCommentSheet())

                Button() {
                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.share')).fontSize(14).fontColor(['#b0b0b8'])
                    Text(this.formatCount(this.shareCount)).fontSize(11).fontColor('#b0b0b8')
                  }
                }
                .height(38)
                .backgroundColor('#2a2a2e')
                .borderRadius(19)
                .type(ButtonType.Normal)
                .padding({ left: 12, right: 12 })
                .onClick(() => this.shareSheetVisible = true)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })

              if (this.albumDesc.length > 0) {
                Column() {
                  Text(this.albumDesc)
                    .fontSize(12)
                    .fontColor('#9999a0')
                    .lineHeight(18)
                    .maxLines(this.descExpanded ? 100 : 2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.albumDesc.length > 60) {
                    Text(this.descExpanded ? '收起' : '展开')
                      .fontSize(11)
                      .fontColor('#ef233c')
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
                  .fontColor('#ffffff')
                  .fontWeight(FontWeight.Medium)
                Text(`${this.formatCount(this.subCount)}人收藏 · ${this.formatCount(this.shareCount)}次分享`)
                  .fontSize(10)
                  .fontColor('#77777f')
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
                        .fontColor('#77777f')
                        .textAlign(TextAlign.Center)
                      Column({ space: 3 }) {
                        Text(item.name)
                          .fontSize(14)
                          .fontColor('#ededf0')
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
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)

          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(22)
                .fontColor(['#ffffff'])
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor('rgba(0,0,0,0.35)')
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.pageStack.pop())

            Column().layoutWeight(1)

            Row() {
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(18)
                .fontColor(['#ffffff'])
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor('rgba(0,0,0,0.35)')
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.shareSheetVisible = true)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topAvoidHeight + 14 })

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
          backgroundColor: '#19191f',
          showClose: false,
          dragBar: true,
          onDisappear: () => this.commentSheetVisible = false
        })
      }

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#121215')
    }
    .hideTitleBar(true)
    .backgroundColor('#121215')
  }

}
