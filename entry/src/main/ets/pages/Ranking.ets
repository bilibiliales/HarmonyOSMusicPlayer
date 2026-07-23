import {
  ArtistPageParam,
  ArtistToplistArtist,
  ArtistToplistResponse,
  mapApiSong,
  PlaylistDetailResponse,
  playlistType,
  songItemType,
  ToplistItem,
  ToplistResponse,
  ToplistTrackPreview
} from '../models'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'

interface RankingPreview {
  id: string
  name: string
  cover: string
  updateFrequency: string
  songs: songItemType[]
  fallbackTracks: ToplistTrackPreview[]
}

@Component
export struct RankingPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  embedded: boolean = false
  @State toplists: ToplistItem[] = []
  @State featuredRankings: RankingPreview[] = []
  @State artistRanking: ArtistToplistArtist[] = []
  @State artistRankingUpdateTime: number = 0
  @State loading: boolean = true
  @State refreshing: boolean = false
  @State message: string = ''
  @State artistVisibleCount: number = 8
  @State toplistVisibleCount: number = 6
  @State secondaryReady: boolean = false
  private readonly artistPageSize: number = 8
  private readonly toplistPageSize: number = 6

  aboutToAppear(): void {
    this.loadData()
  }

  private async loadRankingPreview(item: ToplistItem): Promise<RankingPreview> {
    let rankingSongs: songItemType[] = []
    try {
      const response = await ApiClient.get<PlaylistDetailResponse>('/playlist/detail', [
        { key: 'id', value: item.id.toString() }
      ])
      if (response.code === 200 && response.playlist?.tracks?.length) {
        rankingSongs = response.playlist.tracks.slice(0, 3).map((song) => mapApiSong(song))
      }
    } catch (_error) {
    }
    return {
      id: item.id.toString(),
      name: item.name,
      cover: item.coverImgUrl || item.picUrl || '',
      updateFrequency: item.updateFrequency || '',
      songs: rankingSongs,
      fallbackTracks: item.tracks || []
    }
  }

  private async loadRankings(): Promise<boolean> {
    try {
      const response = await ApiClient.get<ToplistResponse>('/toplist')
      if (response.code === 200 && response.list?.length) {
        this.toplists = response.list
        this.featuredRankings = await Promise.all(response.list.slice(0, 4)
          .map((item: ToplistItem) => this.loadRankingPreview(item)))
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadArtistRanking(): Promise<boolean> {
    try {
      const response = await ApiClient.get<ArtistToplistResponse>('/toplist/artist')
      if (response.code === 200 && response.list?.artists?.length) {
        this.artistRanking = response.list.artists
        this.artistRankingUpdateTime = response.list.updateTime || 0
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadData(): Promise<void> {
    this.message = ''
    this.secondaryReady = false
    this.artistVisibleCount = this.artistPageSize
    this.toplistVisibleCount = this.toplistPageSize
    const results = await Promise.all([this.loadRankings(), this.loadArtistRanking()])
    if (!results[0] && !results[1]) {
      this.message = '排行榜加载失败，请下拉重试'
    }
    this.loading = false
    setTimeout(() => {
      this.secondaryReady = true
    }, 180)
  }

  private revealMoreArtists(): void {
    if (this.artistVisibleCount < this.artistRanking.length) {
      this.artistVisibleCount = Math.min(this.artistVisibleCount + this.artistPageSize, this.artistRanking.length)
    }
  }

  private revealMoreToplists(): void {
    if (this.toplistVisibleCount < this.toplists.length) {
      this.toplistVisibleCount = Math.min(this.toplistVisibleCount + this.toplistPageSize, this.toplists.length)
    }
  }

  private openRanking(id: string, name: string, cover: string, count: number = 0): void {
    const playlist: playlistType = {
      id: id,
      name: name,
      cover: cover,
      count: count,
      creator: '网易云音乐排行榜'
    }
    this.pageStack.pushPathByName('PlaylistDetailPage', playlist)
  }

  private async playRanking(item: RankingPreview, index: number): Promise<void> {
    if (item.songs.length > 0) {
      await playerController.setQueue(item.songs, index, true)
    }
  }

  private openRankArtist(item: ArtistToplistArtist): void {
    const param: ArtistPageParam = {
      id: item.id.toString(),
      name: item.name,
      picUrl: item.picUrl || item.img1v1Url || ''
    }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  private artistRankChange(item: ArtistToplistArtist, index: number): string {
    if (!item.lastRank || item.lastRank <= 0) {
      return 'NEW'
    }
    const change = item.lastRank - (index + 1)
    if (change > 0) {
      return `↑${change}`
    }
    if (change < 0) {
      return `↓${Math.abs(change)}`
    }
    return '—'
  }

  private artistRankingDate(): string {
    if (!this.artistRankingUpdateTime) {
      return '每日更新'
    }
    const date = new Date(this.artistRankingUpdateTime)
    return `${date.getMonth() + 1}月${date.getDate()}日更新`
  }

  @Builder
  private PageHeader() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
        .onClick(() => this.pageStack.pop())
      Column({ space: 3 }) {
        Text('排行榜').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text('官方榜单与歌手热度').fontSize(11).fontColor('#6f6f77')
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
      Text('排行榜').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#ef233c').borderRadius(18)
      Text('曲风').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('StylePage', null))
      Text('电台').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('RadioPage', null))
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
  private SectionTitle(title: string, subtitle: string) {
    Row() {
      Column({ space: 3 }) {
        Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#f4f4f6')
        if (subtitle.length > 0) {
          Text(subtitle).fontSize(10).fontColor('#66666e')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ left: 16, right: 16, top: 22, bottom: 10 })
  }

  @Builder
  private FeaturedRankingSection() {
    if (this.featuredRankings.length > 0) {
      this.SectionTitle('官方榜', '点击榜单查看完整歌曲')
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.featuredRankings, (ranking: RankingPreview) => {
            Row({ space: 12 }) {
              Stack({ alignContent: Alignment.BottomStart }) {
                Image(resizeImageUrl(ranking.cover, 240, 300)).width(104).height(132)
                  .sourceSize({ width: 240, height: 300 }).borderRadius(15).objectFit(ImageFit.Cover)
                Column().width(104).height(70).borderRadius({ bottomLeft: 15, bottomRight: 15 })
                  .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.82)', 1]] })
                Column({ space: 2 }) {
                  Text(ranking.name).width(92).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(ranking.updateFrequency).width(92).fontSize(9).fontColor('#d0d0d5').maxLines(1)
                }.margin({ left: 7, bottom: 8 }).alignItems(HorizontalAlign.Start)
              }.onClick(() => this.openRanking(ranking.id, ranking.name, ranking.cover))
              Column({ space: 3 }) {
                if (ranking.songs.length > 0) {
                  ForEach(ranking.songs, (song: songItemType, index: number) => {
                    Row({ space: 7 }) {
                      Text(`${index + 1}`).width(17).fontSize(14).fontWeight(FontWeight.Bold)
                        .fontColor(index === 0 ? '#ef4058' : '#8d8d95')
                      Column({ space: 3 }) {
                        Text(song.name).width('100%').fontSize(12).fontColor('#ededf0').maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(song.author).width('100%').fontSize(9).fontColor('#707078').maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(18).fontColor(['#8a8a92'])
                    }.width(184).height(41).onClick(() => this.playRanking(ranking, index))
                  })
                } else {
                  ForEach(ranking.fallbackTracks.slice(0, 3), (track: ToplistTrackPreview, index: number) => {
                    Row({ space: 7 }) {
                      Text(`${index + 1}`).width(17).fontSize(14).fontWeight(FontWeight.Bold)
                        .fontColor(index === 0 ? '#ef4058' : '#8d8d95')
                      Column({ space: 3 }) {
                        Text(track.first).width('100%').fontSize(12).fontColor('#ededf0').maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(track.second).width('100%').fontSize(9).fontColor('#707078').maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    }.width(184).height(41)
                  })
                }
              }.layoutWeight(1).justifyContent(FlexAlign.Center)
            }.width(316).height(150).padding(9).backgroundColor('#1a1a20').borderRadius(18)
          }, (ranking: RankingPreview) => ranking.id)
        }.padding({ left: 16, right: 16 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
  }

  @Builder
  private ArtistRankingSection() {
    if (this.artistRanking.length > 0) {
      this.SectionTitle('歌手榜', `${this.artistRankingDate()} · 已展示 ` +
        `${Math.min(this.artistVisibleCount, this.artistRanking.length)}/${this.artistRanking.length}`)
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.artistRanking.slice(0, this.artistVisibleCount),
            (artist: ArtistToplistArtist, index: number) => {
            Column({ space: 7 }) {
              Stack({ alignContent: Alignment.TopStart }) {
                Image(resizeImageUrl(artist.picUrl || artist.img1v1Url || '', 180, 180))
                  .width(88).height(88).sourceSize({ width: 180, height: 180 }).borderRadius(44)
                  .objectFit(ImageFit.Cover)
                Text(`${index + 1}`).fontSize(11).fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .width(27).height(27).textAlign(TextAlign.Center)
                  .backgroundColor(index < 3 ? '#ef233c' : '#34343c')
                  .borderRadius(14).margin({ left: -3, top: -3 })
              }
              Text(artist.name).width(102).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#e8e8eb')
                .textAlign(TextAlign.Center).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.artistRankChange(artist, index)).fontSize(9)
                .fontColor(this.artistRankChange(artist, index).startsWith('↑') ?
                  '#ef6577' : '#696971')
            }.width(102).onClick(() => this.openRankArtist(artist))
          }, (artist: ArtistToplistArtist) => artist.id.toString())
        }.padding({ left: 17, right: 17, top: 4 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .onScrollEdge((side: Edge) => {
          if (side === Edge.End) {
            this.revealMoreArtists()
          }
        })
    }
  }

  @Builder
  private AllRankingsSection() {
    if (this.toplists.length > 0) {
      this.SectionTitle('全部榜单', `已展示 ${Math.min(this.toplistVisibleCount, this.toplists.length)}/` +
        `${this.toplists.length} 个榜单`)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.toplists.slice(0, this.toplistVisibleCount),
          (item: ToplistItem) => {
          Column({ space: 7 }) {
            Stack({ alignContent: Alignment.BottomStart }) {
              Image(resizeImageUrl(item.coverImgUrl || item.picUrl || '', 320, 320))
                .width('100%').aspectRatio(1).sourceSize({ width: 320, height: 320 }).borderRadius(14)
                .objectFit(ImageFit.Cover)
              Column().width('100%').height(50).borderRadius({ bottomLeft: 14, bottomRight: 14 })
                .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.78)', 1]] })
              Text(item.updateFrequency || '').width('90%').fontSize(8).fontColor('#ededf0')
                .margin({ left: 7, bottom: 7 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            Text(item.name).width('100%').fontSize(11).fontColor('#dcdce1').maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('31%').margin({ bottom: 15 }).alignItems(HorizontalAlign.Start)
            .onClick(() => this.openRanking(item.id.toString(), item.name, item.coverImgUrl || item.picUrl || '',
              item.trackCount || 0))
        }, (item: ToplistItem) => item.id.toString())
      }.width('100%').padding({ left: 16, right: 16 })
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
              LoadingProgress().width(34).height(34).color('#ef233c')
              Text('正在加载排行榜').fontSize(12).fontColor('#77777f')
            }.width('100%').height(360).justifyContent(FlexAlign.Center)
          } else if (this.toplists.length === 0 && this.artistRanking.length === 0) {
            Column({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(36).fontColor(['#77777f'])
              Text(this.message || '暂无排行榜数据').fontSize(12).fontColor('#77777f')
            }.width('100%').height(360).justifyContent(FlexAlign.Center)
          } else {
            this.FeaturedRankingSection()
            if (this.secondaryReady) {
              this.ArtistRankingSection()
              this.AllRankingsSection()
            } else {
              LoadingProgress().width(28).height(28).color('#ef233c').margin({ top: 28, bottom: 28 })
            }
            Blank().height(this.embedded ? 145 : 50)
          }
        }.width('100%')
      }.width('100%').height('100%').scrollBar(BarState.Off).onReachEnd(() => this.revealMoreToplists())
    }.width('100%').height('100%').backgroundColor('#121215').onRefreshing(async () => {
      this.refreshing = true
      await this.loadData()
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
