import {
  AlbumPageParam,
  ApiAlbum,
  ApiArtist,
  ApiParam,
  ArtistPageParam,
  mapApiSong,
  playlistType,
  songItemType,
  StyleAlbumResponse,
  StyleArtistResponse,
  StyleDetailData,
  StyleDetailPageParam,
  StyleDetailResponse,
  StylePlaylistItem,
  StylePlaylistResponse,
  StyleSongResponse
} from '../models'
import { ApiClient } from '../services/ApiClient'
import { resizeImageUrl } from '../services/ImageUrl'
import { playerController } from '../services/PlayerController'

@Component
export struct StyleDetailPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: StyleDetailPageParam = { tagId: 0, name: '' }

  @State detail?: StyleDetailData = undefined
  @State currentTab: string = 'songs'
  @State songs: songItemType[] = []
  @State albums: ApiAlbum[] = []
  @State playlists: StylePlaylistItem[] = []
  @State artists: ApiArtist[] = []
  @State loading: boolean = true
  @State resourceLoading: boolean = false
  @State resourceMore: boolean = true
  @State message: string = ''
  private songCursor: number = 0
  private albumCursor: number = 0
  private playlistCursor: number = 0
  private artistCursor: number = 0

  aboutToAppear(): void {
    this.loadPage()
  }

  private async loadPage(): Promise<void> {
    if (this.pageParam.tagId <= 0) {
      this.loading = false
      this.message = '曲风参数无效'
      return
    }
    await Promise.all([this.loadDetail(), this.loadCurrentResources(true)])
    this.loading = false
  }

  private async loadDetail(): Promise<void> {
    try {
      const response = await ApiClient.get<StyleDetailResponse>('/style/detail', [
        { key: 'tagId', value: this.pageParam.tagId.toString() }
      ])
      if (response.code === 200) {
        this.detail = response.data
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '曲风详情加载失败'
    }
  }

  private cursorOf(tab: string): number {
    if (tab === 'albums') {
      return this.albumCursor
    }
    if (tab === 'playlists') {
      return this.playlistCursor
    }
    if (tab === 'artists') {
      return this.artistCursor
    }
    return this.songCursor
  }

  private resetTab(tab: string): void {
    if (tab === 'albums') {
      this.albums = []
      this.albumCursor = 0
    } else if (tab === 'playlists') {
      this.playlists = []
      this.playlistCursor = 0
    } else if (tab === 'artists') {
      this.artists = []
      this.artistCursor = 0
    } else {
      this.songs = []
      this.songCursor = 0
    }
  }

  private tabHasData(tab: string): boolean {
    if (tab === 'albums') {
      return this.albums.length > 0
    }
    if (tab === 'playlists') {
      return this.playlists.length > 0
    }
    if (tab === 'artists') {
      return this.artists.length > 0
    }
    return this.songs.length > 0
  }

  private async loadCurrentResources(reset: boolean = false): Promise<void> {
    if (this.resourceLoading || (!this.resourceMore && !reset)) {
      return
    }
    const tab = this.currentTab
    if (reset) {
      this.resetTab(tab)
      this.resourceMore = true
    }
    this.resourceLoading = true
    this.message = ''
    const cursor = this.cursorOf(tab)
    try {
      if (tab === 'albums') {
        const response = await ApiClient.get<StyleAlbumResponse>('/style/album', this.resourceParams(cursor, true))
        const incoming = response.data?.albums || []
        this.albums = this.albums.concat(incoming)
        this.albumCursor += incoming.length
        this.resourceMore = response.data?.page?.more || false
      } else if (tab === 'playlists') {
        const response = await ApiClient.get<StylePlaylistResponse>('/style/playlist', this.resourceParams(cursor, false))
        const incoming = response.data?.playlist || []
        this.playlists = this.playlists.concat(incoming)
        this.playlistCursor += incoming.length
        this.resourceMore = response.data?.page?.more || false
      } else if (tab === 'artists') {
        const response = await ApiClient.get<StyleArtistResponse>('/style/artist', this.resourceParams(cursor, false))
        const incoming = response.data?.artists || []
        this.artists = this.artists.concat(incoming)
        this.artistCursor += incoming.length
        this.resourceMore = response.data?.page?.more || false
      } else {
        const response = await ApiClient.get<StyleSongResponse>('/style/song', this.resourceParams(cursor, true))
        const incoming = (response.data?.songs || []).map((song) => mapApiSong(song))
        this.songs = this.songs.concat(incoming)
        this.songCursor += incoming.length
        this.resourceMore = response.data?.page?.more || false
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '曲风内容加载失败'
    } finally {
      this.resourceLoading = false
    }
  }

  private resourceParams(cursor: number, sortable: boolean): ApiParam[] {
    const params: ApiParam[] = [
      { key: 'tagId', value: this.pageParam.tagId.toString() },
      { key: 'size', value: '20' },
      { key: 'cursor', value: cursor.toString() }
    ]
    if (sortable) {
      params.push({ key: 'sort', value: '0' })
    }
    return params
  }

  private switchTab(tab: string): void {
    if (this.currentTab === tab) {
      return
    }
    this.currentTab = tab
    this.resourceMore = true
    if (!this.tabHasData(tab)) {
      this.loadCurrentResources(true)
    }
  }

  private cover(): string {
    return this.detail?.cover?.[0] || this.pageParam.cover || ''
  }

  private name(): string {
    return this.detail?.name || this.pageParam.name || '曲风'
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

  private async playSong(index: number): Promise<void> {
    await playerController.setQueue(this.songs, index, true)
  }

  private openAlbum(album: ApiAlbum): void {
    if (!album.id) {
      return
    }
    const param: AlbumPageParam = {
      id: album.id.toString(), name: album.name, picUrl: album.picUrl,
      artist: album.artist?.name || album.artists?.map((item: ApiArtist) => item.name).join(' / ') || ''
    }
    this.pageStack.pushPathByName('AlbumDetailPage', param)
  }

  private openPlaylist(item: StylePlaylistItem): void {
    const playlist: playlistType = {
      id: item.id.toString(), name: item.name, cover: item.cover,
      count: item.songCount, creator: item.userName
    }
    this.pageStack.pushPathByName('PlaylistDetailPage', playlist)
  }

  private openArtist(item: ApiArtist): void {
    if (!item.id) {
      return
    }
    const param: ArtistPageParam = {
      id: item.id.toString(), name: item.name, picUrl: item.picUrl || item.img1v1Url || ''
    }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  @Builder
  private Header() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image(this.cover()).width('100%').height('100%')
        .objectFit(ImageFit.Cover).blur(28).opacity(0.62)
      Column().width('100%').height('100%')
        .linearGradient({ angle: 180, colors: [['rgba(10,10,14,0.12)', 0], ['#121215', 1]] })
      Column({ space: 8 }) {
        Image(this.cover()).width(116).height(116)
          .borderRadius(22).objectFit(ImageFit.Cover)
          .backgroundColor('#202026')
        Text(this.name()).fontSize(25).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        if (this.detail?.enName) {
          Text(this.detail.enName).fontSize(11).fontColor('#b0b0b7')
        }
        Row({ space: 15 }) {
          Text(`${this.detail?.songNum || '-'} 首歌曲`).fontSize(10).fontColor('#bdbdc4')
          Text(`${this.detail?.artistNum || '-'} 位歌手`).fontSize(10).fontColor('#bdbdc4')
        }
      }.width('100%').padding({ bottom: 20 })
    }.width('100%').height(310)
  }

  @Builder
  private Description() {
    if (this.detail?.desc) {
      Text(this.detail.desc).width('100%').fontSize(13).lineHeight(21).fontColor('#a7a7af')
        .padding({ left: 17, right: 17, top: 15, bottom: 15 })
    }
    if (this.detail?.favouriteSong?.favouriteSong) {
      Row({ space: 11 }) {
        Image(resizeImageUrl(this.detail.favouriteSong.favouriteSong.al?.picUrl || '', 140, 140))
          .width(58).height(58).borderRadius(11)
          .objectFit(ImageFit.Cover).backgroundColor('#202026')
        Column({ space: 4 }) {
          Text('你最喜欢的该曲风歌曲').fontSize(9).fontColor('#ff6577')
          Text(this.detail.favouriteSong.favouriteSong.name).fontSize(13).fontColor('#ffffff').maxLines(1)
          Text((this.detail.favouriteSong.favouriteSong.ar || []).map((item: ApiArtist) => item.name).join(' / '))
            .fontSize(10).fontColor('#77777f').maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(11).backgroundColor('#1d1d22').borderRadius(14)
        .margin({ left: 16, right: 16, bottom: 13 })
    }
  }

  @Builder
  private ResourceTabs() {
    Row() {
      ForEach(['songs', 'albums', 'playlists', 'artists'], (tab: string) => {
        Column({ space: 7 }) {
          Text(tab === 'songs' ? '歌曲' : tab === 'albums' ? '专辑' : tab === 'playlists' ? '歌单' : '歌手')
            .fontSize(13).fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.currentTab === tab ? '#ffffff' : '#717179')
          Column().width(this.currentTab === tab ? 24 : 0).height(3).borderRadius(2).backgroundColor('#ef233c')
        }.layoutWeight(1).height(48).justifyContent(FlexAlign.Center).onClick(() => this.switchTab(tab))
      })
    }.width('100%').backgroundColor('#17171c')
  }

  @Builder
  private SongsContent() {
    ForEach(this.songs, (song: songItemType, index: number) => {
      Row({ space: 11 }) {
        Text(`${index + 1}`).width(25).fontSize(12).fontColor(index < 3 ? '#ef4058' : '#6f6f77')
          .textAlign(TextAlign.Center)
        Image(resizeImageUrl(song.img, 120, 120)).width(52).height(52)
          .borderRadius(10).objectFit(ImageFit.Cover).backgroundColor('#202026')
        Column({ space: 4 }) {
          Text(song.name).width('100%').fontSize(14).fontColor('#ededf0').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${song.author}${song.album ? ` · ${song.album}` : ''}`).width('100%').fontSize(10)
            .fontColor('#77777f').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.play_circle')).fontSize(22).fontColor(['#85858e'])
      }.height(66).padding({ left: 12, right: 16 }).onClick(() => this.playSong(index))
    })
  }

  @Builder
  private AlbumsContent() {
    ForEach(this.albums, (album: ApiAlbum) => {
      Row({ space: 12 }) {
        Image(resizeImageUrl(album.picUrl, 150, 150)).width(64).height(64)
          .borderRadius(12).objectFit(ImageFit.Cover).backgroundColor('#202026')
        Column({ space: 5 }) {
          Text(album.name).width('100%').fontSize(14).fontColor('#ededf0').maxLines(1)
          Text(`${album.artist?.name || ''}${album.publishTime ? ` · ${new Date(album.publishTime).getFullYear()}` : ''}`)
            .fontSize(10).fontColor('#77777f')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.height(78).padding({ left: 16, right: 16 }).onClick(() => this.openAlbum(album))
    })
  }

  @Builder
  private PlaylistsContent() {
    ForEach(this.playlists, (item: StylePlaylistItem) => {
      Row({ space: 12 }) {
        Image(resizeImageUrl(item.cover, 150, 150)).width(64).height(64)
          .borderRadius(12).objectFit(ImageFit.Cover).backgroundColor('#202026')
        Column({ space: 5 }) {
          Text(item.name).width('100%').fontSize(14).fontColor('#ededf0').maxLines(1)
          Text(`${item.songCount} 首 · ${item.userName} · ${this.formatCount(item.playCount)} 次播放`)
            .width('100%').fontSize(10).fontColor('#77777f').maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.height(78).padding({ left: 16, right: 16 }).onClick(() => this.openPlaylist(item))
    })
  }

  @Builder
  private ArtistsContent() {
    ForEach(this.artists, (item: ApiArtist) => {
      Row({ space: 12 }) {
        Image(resizeImageUrl(item.picUrl || item.img1v1Url || '', 150, 150)).width(64).height(64)
          .borderRadius(32).objectFit(ImageFit.Cover)
        Column({ space: 5 }) {
          Text(item.name).fontSize(14).fontColor('#ededf0')
          Text(`${item.musicSize || 0} 首歌曲 · ${this.formatCount(item.fansCount || 0)} 粉丝`)
            .fontSize(10).fontColor('#77777f')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor(['#686870'])
      }.height(78).padding({ left: 16, right: 16 }).onClick(() => this.openArtist(item))
    })
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text(this.name()).layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            .textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(20).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pushPathByName('SearchPage', null))
        }.height(54).width('100%').padding({ left: 16, right: 16 })

        if (this.loading) {
          LoadingProgress().layoutWeight(1).width(44).color('#ef233c')
        } else {
          Scroll() {
            Column() {
              this.Header()
              this.Description()
              this.ResourceTabs()
              if (this.currentTab === 'songs') {
                this.SongsContent()
              } else if (this.currentTab === 'albums') {
                this.AlbumsContent()
              } else if (this.currentTab === 'playlists') {
                this.PlaylistsContent()
              } else {
                this.ArtistsContent()
              }
              if (this.resourceLoading) {
                LoadingProgress().width(25).height(25).color('#ef233c').margin(18)
              } else if (!this.tabHasData(this.currentTab)) {
                Text(this.message || '暂无内容').width('100%').height(160).fontSize(12).fontColor('#77777f')
                  .textAlign(TextAlign.Center)
              } else {
                Text(this.resourceMore ? '继续上滑加载更多' : '已经到底了').width('100%').height(52)
                  .fontSize(10).fontColor('#66666e').textAlign(TextAlign.Center)
              }
            }.width('100%')
          }.layoutWeight(1).scrollBar(BarState.Off).onReachEnd(() => this.loadCurrentResources())
        }
      }.width('100%').height('100%').backgroundColor('#121215')
    }.hideTitleBar(true)
  }
}
