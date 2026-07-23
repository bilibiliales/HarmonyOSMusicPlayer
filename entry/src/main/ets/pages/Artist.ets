import {
  AlbumPageParam,
  ApiAlbum,
  ApiArtist,
  ArtistAlbumResponse,
  ArtistDetailArtist,
  ArtistDetailResponse,
  ArtistExpertIdentity,
  ArtistMvItem,
  ArtistMvResponse,
  ArtistPageParam,
  ArtistTopSongsResponse,
  MvPlayerPageParam,
  SimilarArtistResponse,
  mapApiSong
} from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'

@Component
export struct ArtistPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: ArtistPageParam = { id: '' }

  @State artist: ApiArtist = { name: '' }
  @State artistDetail: ArtistDetailArtist = { name: '' }
  @State expertIdentities: ArtistExpertIdentity[] = []
  @State topSongs: songItemType[] = []
  @State albums: ApiAlbum[] = []
  @State allAlbums: ApiAlbum[] = []
  @State mvs: ArtistMvItem[] = []
  @State similarArtists: ApiArtist[] = []
  @State loading: boolean = true
  @State message: string = ''
  @State bioExpanded: boolean = false
  @State currentTab: string = 'music'
  @State allAlbumsLoading: boolean = false
  @State allAlbumsMore: boolean = true
  private allAlbumsOffset: number = 0

  aboutToAppear(): void {
    this.artist = {
      id: Number(this.pageParam.id),
      name: this.pageParam.name || '',
      picUrl: this.pageParam.picUrl || ''
    }
    this.artistDetail = {
      id: Number(this.pageParam.id),
      name: this.pageParam.name || '',
      avatar: this.pageParam.picUrl || ''
    }
    this.loadArtist()
  }

  private async loadArtist(): Promise<void> {
    if (!this.pageParam.id) {
      this.loading = false
      this.message = '歌手参数无效'
      return
    }
    this.loading = true
    this.message = ''
    await Promise.all([
      this.loadSongs(),
      this.loadAlbums(),
      this.loadMvs(),
      this.loadArtistDetail(),
      this.loadSimilarArtists()
    ])
    if (!this.hasContent()) {
      this.message = '暂时没有可展示的歌手内容'
    }
    this.loading = false
  }

  private async loadSongs(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistTopSongsResponse>('/artist/top/song', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200) {
        this.topSongs = (response.songs || []).slice(0, 50).map((song) => mapApiSong(song))
      }
    } catch (error) {
      console.error(`[ArtistPage] load songs failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async loadAlbums(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistAlbumResponse>('/artist/album', [
        { key: 'id', value: this.pageParam.id },
        { key: 'limit', value: '5' },
        { key: 'offset', value: '0' }
      ])
      if (response.code === 200) {
        if (response.artist) {
          this.artist = response.artist
        }
        this.albums = (response.hotAlbums || []).slice(0, 5)
      }
    } catch (error) {
      console.error(`[ArtistPage] load albums failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async loadAllAlbums(reset: boolean = false): Promise<void> {
    if (this.allAlbumsLoading || (!this.allAlbumsMore && !reset)) {
      return
    }
    if (reset) {
      this.allAlbums = []
      this.allAlbumsOffset = 0
      this.allAlbumsMore = true
    }
    this.allAlbumsLoading = true
    try {
      const response = await ApiClient.get<ArtistAlbumResponse>('/artist/album', [
        { key: 'id', value: this.pageParam.id },
        { key: 'limit', value: '30' },
        { key: 'offset', value: this.allAlbumsOffset.toString() }
      ])
      if (response.code === 200) {
        const incoming = response.hotAlbums || []
        const merged = this.allAlbums.slice()
        incoming.forEach((album: ApiAlbum) => {
          if (!merged.some((item: ApiAlbum) => item.id === album.id)) {
            merged.push(album)
          }
        })
        this.allAlbums = merged
        this.allAlbumsOffset += incoming.length
        this.allAlbumsMore = response.more === true || (response.more === undefined && incoming.length >= 30)
      }
    } catch (error) {
      console.error(`[ArtistPage] load all albums failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    } finally {
      this.allAlbumsLoading = false
    }
  }

  private switchTab(tab: string): void {
    this.currentTab = tab
    if (tab === 'albums' && this.allAlbums.length === 0) {
      this.loadAllAlbums(true)
    }
  }

  private async loadMvs(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistMvResponse>('/artist/mv', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200) {
        this.mvs = response.mvs || []
      }
    } catch (error) {
      console.error(`[ArtistPage] load mvs failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async loadArtistDetail(): Promise<void> {
    try {
      const response = await ApiClient.get<ArtistDetailResponse>('/artist/detail', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200 && response.data) {
        if (response.data.artist) {
          this.artistDetail = response.data.artist
        }
        this.expertIdentities = response.data.secondaryExpertIdentiy || []
      }
    } catch (error) {
      console.error(`[ArtistPage] load detail failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private async loadSimilarArtists(): Promise<void> {
    try {
      const response = await ApiClient.get<SimilarArtistResponse>('/simi/artist', [
        { key: 'id', value: this.pageParam.id }
      ])
      if (response.code === 200) {
        this.similarArtists = response.artists || []
      }
    } catch (error) {
      console.error(`[ArtistPage] load similar artists failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    }
  }

  private hasContent(): boolean {
    return this.topSongs.length > 0 || this.albums.length > 0 || this.mvs.length > 0 ||
      this.hasWikiContent() || this.similarArtists.length > 0
  }

  private hasWikiContent(): boolean {
    return (this.artistDetail.briefDesc || '').length > 0 ||
      (this.artistDetail.identities || []).length > 0 || this.expertIdentities.length > 0
  }

  private async playSong(index: number): Promise<void> {
    if (this.topSongs.length === 0) {
      return
    }
    await playerController.setQueue(this.topSongs, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private albumYear(album: ApiAlbum): string {
    if (!album.publishTime) {
      return ''
    }
    return new Date(album.publishTime).getFullYear().toString()
  }

  private displayName(): string {
    return this.artistDetail.name || this.artist.name || this.pageParam.name || '歌手'
  }

  private headerImage(): string {
    return this.artistDetail.cover || this.artistDetail.avatar || this.artist.picUrl ||
      this.artist.img1v1Url || this.pageParam.picUrl || ''
  }

  private formatCount(count: number | undefined): string {
    const value = count || 0
    if (value >= 100000000) {
      return `${(value / 100000000).toFixed(1)}亿`
    }
    if (value >= 10000) {
      return `${(value / 10000).toFixed(1)}万`
    }
    return value.toString()
  }

  private formatDuration(duration: number | undefined): string {
    const totalSeconds = Math.floor((duration || 0) / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`
  }

  private openAlbum(album: ApiAlbum): void {
    if (!album.id) {
      return
    }
    const param: AlbumPageParam = {
      id: album.id.toString(),
      name: album.name,
      picUrl: album.picUrl,
      artist: this.displayName()
    }
    this.pageStack.pushPathByName('AlbumDetailPage', param)
  }

  private openArtist(artist: ApiArtist): void {
    if (!artist.id) {
      return
    }
    const param: ArtistPageParam = {
      id: artist.id.toString(),
      name: artist.name,
      picUrl: artist.picUrl || artist.img1v1Url || ''
    }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  private openMv(mv: ArtistMvItem): void {
    const param: MvPlayerPageParam = {
      id: mv.id.toString(),
      name: mv.name,
      cover: mv.imgurl16v9 || mv.imgurl || '',
      artistName: mv.artistName || this.displayName(),
      duration: mv.duration,
      playCount: mv.playCount,
      publishTime: mv.publishTime
    }
    this.pageStack.pushPathByName('MvPlayerPage', param)
  }

  @Builder
  private ArtistHeader() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image(resizeImageUrl(this.headerImage(), 720, 560))
        .width('100%').height('100%').sourceSize({ width: 720, height: 560 })
        .objectFit(ImageFit.Cover).blur(32).opacity(0.55)
      Column().width('100%').height('100%')
        .linearGradient({ angle: 180, colors: [['rgba(10,10,14,0.12)', 0], ['#121215', 1]] })
      Column({ space: 9 }) {
        Image(resizeImageUrl(
          this.artistDetail.avatar || this.artist.picUrl || this.artist.img1v1Url || this.headerImage(), 220, 220))
          .width(104).height(104).sourceSize({ width: 220, height: 220 })
          .borderRadius(52).objectFit(ImageFit.Cover)
          .border({ width: 2, color: 'rgba(255,255,255,0.78)' })
        Row({ space: 7 }) {
          Text(this.displayName())
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text('歌手').fontSize(9).fontColor('#ff6577')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .border({ width: 1, color: '#ff6577' }).borderRadius(5)
        }
        Text(`${this.artistDetail.musicSize || this.artist.musicSize || this.topSongs.length} 首单曲 · ${this.artistDetail.albumSize || this.artist.albumSize || this.albums.length} 张专辑 · ${this.artistDetail.mvSize || this.mvs.length} 个 MV`)
          .fontSize(11).fontColor('#aaaab2')
        if ((this.artistDetail.alias || []).length > 0) {
          Text((this.artistDetail.alias || []).join(' / ')).width('82%').fontSize(11).fontColor('#92929a')
            .maxLines(1).textAlign(TextAlign.Center)
        }
      }
      .width('100%').padding({ bottom: 18 })
    }
    .width('100%').height(280)
  }

  @Builder
  private SongsTab() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor(['#ffffff'])
        Text(`播放热门歌曲 (${this.topSongs.length})`).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#ffffff')
      }
      .width('100%').height(50).padding({ left: 18 })
      .onClick(() => this.playSong(0))
      ForEach(this.topSongs, (song: songItemType, index: number) => {
        Row({ space: 12 }) {
          Text((index + 1).toString()).width(28).fontSize(12)
            .fontColor(index < 3 ? '#ff6577' : '#66666e').textAlign(TextAlign.Center)
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text(song.name).fontSize(14).fontColor('#ededf0').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              if (song.fee === 1) {
                Text('VIP').fontSize(8).fontColor('#ff4058')
                  .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                  .border({ width: 1, color: '#ff4058' }).borderRadius(3)
              }
            }
            Text(song.album || song.author).fontSize(11).fontColor('#77777f').maxLines(1)
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.play_circle')).fontSize(21).fontColor(['#77777f'])
        }
        .height(62).padding({ left: 12, right: 16 }).onClick(() => this.playSong(index))
      })
    }
    .width('100%')
  }

  @Builder
  private AlbumsTab() {
    Column({ space: 12 }) {
      if (this.allAlbums.length === 0 && this.allAlbumsLoading) {
        LoadingProgress().width(38).height(38).color('#ef233c').margin({ top: 80 })
      } else if (this.allAlbums.length === 0) {
        Text('暂无专辑').width('100%').height(180).fontSize(13).fontColor('#77777f')
          .textAlign(TextAlign.Center)
      }
      ForEach(this.allAlbums, (album: ApiAlbum) => {
        Row({ space: 13 }) {
          Image(resizeImageUrl(album.picUrl, 160, 160)).width(72).height(72)
            .sourceSize({ width: 160, height: 160 }).borderRadius(13).objectFit(ImageFit.Cover)
          Column({ space: 6 }) {
            Text(album.name).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor('#ededf0').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text([this.albumYear(album), album.type || '', album.size ? `${album.size} 首` : '']
              .filter((value: string) => value.length > 0).join(' · '))
              .fontSize(11).fontColor('#77777f')
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        .width('100%').padding({ left: 16, right: 16 })
        .onClick(() => this.openAlbum(album))
      })
      if (this.allAlbums.length > 0) {
        Row() {
          if (this.allAlbumsLoading) {
            LoadingProgress().width(24).height(24).color('#ef233c')
          } else {
            Text(this.allAlbumsMore ? '继续上滑加载更多' : '已经到底了').fontSize(11).fontColor('#66666e')
          }
        }.width('100%').height(56).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').padding({ top: 14, bottom: 30 })
  }

  @Builder
  private SectionHeader(title: string, subtitle: string = '') {
    Row() {
      Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#f4f4f6')
      Blank()
      if (subtitle.length > 0) {
        Text(subtitle).fontSize(11).fontColor('#777780')
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 22, bottom: 13 })
  }

  @Builder
  private ArtistNavigation() {
    Row() {
      ForEach(['music', 'albums'], (tab: string) => {
        Column({ space: 8 }) {
          Text(tab === 'music' ? '音乐' : '全部专辑').fontSize(15)
            .fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.currentTab === tab ? '#ffffff' : '#77777f')
          Column().width(this.currentTab === tab ? 28 : 0).height(3).borderRadius(2)
            .backgroundColor('#ef233c')
        }
        .layoutWeight(1).height(52).justifyContent(FlexAlign.Center)
        .onClick(() => this.switchTab(tab))
      })
    }
    .width('100%').backgroundColor('#17171c')
  }

  @Builder
  private HotAlbumsSection() {
    Column() {
      this.SectionHeader('热门专辑', `${this.albums.length} 张`)
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.albums, (album: ApiAlbum) => {
            Column({ space: 7 }) {
              Image(resizeImageUrl(album.picUrl, 280, 280)).width(132).height(132)
                .sourceSize({ width: 280, height: 280 }).borderRadius(14).objectFit(ImageFit.Cover)
              Text(album.name).width(132).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor('#ededf0').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.albumYear(album)).width(132).fontSize(10).fontColor('#77777f')
            }
            .alignItems(HorizontalAlign.Start).onClick(() => this.openAlbum(album))
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
    .width('100%')
  }

  @Builder
  private HotMvsSection() {
    Column() {
      this.SectionHeader('热门 MV', `${this.mvs.length} 个`)
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.mvs, (mv: ArtistMvItem) => {
            Column({ space: 7 }) {
              Stack({ alignContent: Alignment.BottomEnd }) {
                Image(resizeImageUrl(mv.imgurl16v9 || mv.imgurl || '', 480, 270)).width(218).height(123)
                  .sourceSize({ width: 480, height: 270 }).borderRadius(13).objectFit(ImageFit.Cover)
                Text(this.formatDuration(mv.duration)).fontSize(9).fontColor('#ffffff')
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .margin({ right: 7, bottom: 7 }).borderRadius(5).backgroundColor('rgba(0,0,0,0.58)')
              }
              Text(mv.name).width(218).fontSize(13).fontColor('#ededf0').maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 10 }) {
                Text(`${this.formatCount(mv.playCount)} 次播放`).fontSize(10).fontColor('#77777f')
                if (mv.publishTime) {
                  Text(mv.publishTime).fontSize(10).fontColor('#77777f')
                }
              }
            }
            .alignItems(HorizontalAlign.Start).onClick(() => this.openMv(mv))
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
    .width('100%')
  }

  @Builder
  private ArtistWikiSection() {
    Column() {
      this.SectionHeader('歌手百科')
      Column({ space: 13 }) {
        if ((this.artistDetail.identities || []).length > 0) {
          Text((this.artistDetail.identities || []).join(' · ')).width('100%')
            .fontSize(12).fontColor('#ff7a8a')
        }
        if (this.expertIdentities.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.expertIdentities, (identity: ArtistExpertIdentity) => {
              Text(`${identity.expertIdentiyName}${identity.expertIdentiyCount ? ` ${identity.expertIdentiyCount}` : ''}`)
                .fontSize(10).fontColor('#b6b6be')
                .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                .margin({ right: 7, bottom: 7 }).borderRadius(12).backgroundColor('#222228')
            })
          }
          .width('100%')
        }
        Text(this.artistDetail.briefDesc || '').width('100%').fontSize(13).fontColor('#a4a4ad')
          .lineHeight(22).maxLines(this.bioExpanded ? 100 : 6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if ((this.artistDetail.briefDesc || '').length > 160) {
          Text(this.bioExpanded ? '收起' : '展开全部').fontSize(12).fontColor('#ff6577')
            .onClick(() => this.bioExpanded = !this.bioExpanded)
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 16, bottom: 17 })
      .borderRadius(17).backgroundColor('#19191e')
    }
    .width('100%').padding({ left: 12, right: 12 })
  }

  @Builder
  private SimilarArtistsSection() {
    Column() {
      this.SectionHeader('更多歌手')
      Scroll() {
        Row({ space: 17 }) {
          ForEach(this.similarArtists, (artist: ApiArtist) => {
            Column({ space: 8 }) {
              Image(resizeImageUrl(artist.picUrl || artist.img1v1Url || '', 180, 180)).width(82).height(82)
                .sourceSize({ width: 180, height: 180 }).borderRadius(41).objectFit(ImageFit.Cover)
              Text(artist.name).width(88).fontSize(12).fontColor('#ededf0').maxLines(1)
                .textAlign(TextAlign.Center).textOverflow({ overflow: TextOverflow.Ellipsis })
              if ((artist.fansCount || 0) > 0) {
                Text(`${this.formatCount(artist.fansCount)} 粉丝`).fontSize(9).fontColor('#77777f')
              }
            }
            .onClick(() => this.openArtist(artist))
          })
        }
        .padding({ left: 16, right: 16 })
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
    .width('100%').padding({ bottom: 34 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(resizeImageUrl(this.headerImage(), 720, 240))
          .width('100%').height(this.topAvoidHeight + 54).objectFit(ImageFit.Cover).blur(24).opacity(0.58)
        Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('歌手主页').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(22).fontColor(['#ffffff'])
        }
        .height(54).width('100%').padding({ left: 16, right: 16 })

        if (this.loading) {
          LoadingProgress().layoutWeight(1).width(46).color('#ef233c')
        } else {
          Scroll() {
            Column() {
              this.ArtistHeader()
              this.ArtistNavigation()
              if (this.currentTab === 'music') {
                if (this.topSongs.length > 0) {
                  this.SectionHeader('热门歌曲', `${this.topSongs.length} 首`)
                  this.SongsTab()
                }
                if (this.albums.length > 0) {
                  this.HotAlbumsSection()
                }
                if (this.mvs.length > 0) {
                  this.HotMvsSection()
                }
                if (this.hasWikiContent()) {
                  this.ArtistWikiSection()
                }
                if (this.similarArtists.length > 0) {
                  this.SimilarArtistsSection()
                }
                if (!this.hasContent()) {
                  Text(this.message).width('100%').height(180).fontSize(13).fontColor('#77777f')
                    .textAlign(TextAlign.Center)
                }
              } else {
                this.AlbumsTab()
              }
            }
          }
          .layoutWeight(1).scrollBar(BarState.Off)
          .onReachEnd(() => {
            if (this.currentTab === 'albums') {
              this.loadAllAlbums()
            }
          })
        }
      }
      .width('100%').height('100%').backgroundColor('#121215')
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
  }
}
