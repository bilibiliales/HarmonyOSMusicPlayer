import {
  ArtistPageParam,
  ArtistToplistArtist,
  ArtistToplistResponse,
  DailyPlaylistResponse,
  DailySongsResponse,
  IntelligencePlayItem,
  IntelligencePlayResponse,
  LikeListResponse,
  mapApiSong,
  mapPlaylist,
  NewSongCategory,
  NewSongPageParam,
  PersonalizedNewSongResponse,
  PersonalizedPlaylistResponse,
  PersonalizedProgramResponse,
  PersonalFmResponse,
  PlaylistDetailResponse,
  playlistType,
  PrivateContentItem,
  PrivateContentResponse,
  ProgramCard,
  ProgramRecommendResponse,
  songItemType,
  SongColumn,
  ToplistItem,
  ToplistResponse,
  ToplistTrackPreview,
  TopSongResponse,
  UserPlaylistResponse
} from '../models'
import { recommendList, songs } from '../constants'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'
import { resizeImageUrl } from '../services/ImageUrl'

@Component
struct Recommend {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('authStore') authStore: AuthStore
  onMenuClick: () => void = () => {}
  @State personalizedPlaylists: playlistType[] = recommendList.map((item, index: number) => {
    return {
      id: index.toString(),
      name: item.title,
      cover: item.img,
      count: 0,
      creator: '网易云音乐'
    } as playlistType
  })
  @State dailyPlaylists: playlistType[] = []
  @State dailyRecommendSongs: songItemType[] = []
  @State personalizedNewSongColumns: SongColumn[] = []
  @State fmColumns: SongColumn[] = []
  @State radioCards: ProgramCard[] = []
  @State programCards: ProgramCard[] = []
  @State privateContents: PrivateContentItem[] = []
  @State toplists: ToplistItem[] = []
  @State featuredRankings: RankingPreview[] = []
  @State artistRanking: ArtistToplistArtist[] = []
  @State artistRankingUpdateTime: number = 0
  @State newSongCategories: NewSongCategory[] = [
    { type: 0, title: '全部', subtitle: '全球新歌一网打尽', cover: songs[0]?.img || '' },
    { type: 7, title: '华语', subtitle: '华语乐坛最新声音', cover: songs[1]?.img || '' },
    { type: 96, title: '欧美', subtitle: '欧美流行新鲜速递', cover: songs[2]?.img || '' },
    { type: 8, title: '日本', subtitle: '日本音乐本周上新', cover: songs[3]?.img || '' },
    { type: 16, title: '韩国', subtitle: 'K-Pop 新歌推荐', cover: songs[4]?.img || '' }
  ]
  @State loading: boolean = false
  @State refreshText: string = ''
  @State isRefreshing: boolean = false
  @State heartModeLoading: boolean = false
  @State heartModeCover: string = ''
  private todayDate: string = new Date().getDate().toString()

  aboutToAppear(): void {
    this.loadHomeData()
  }

  private toColumns(list: songItemType[]): SongColumn[] {
    const result: SongColumn[] = []
    for (let index = 0; index < list.length; index += 3) {
      result.push({ key: `${index}-${list[index].id}`, songs: list.slice(index, index + 3) })
    }
    return result
  }

  private async loadHomeData(): Promise<void> {
    if (this.loading) {
      return
    }
    this.loading = true
    this.refreshText = ''
    let loadedSectionCount = 0
    const results: boolean[] = await Promise.all([
      this.loadPersonalizedPlaylists(),
      this.loadDailyPlaylists(),
      this.loadDailySongs(),
      this.loadPersonalizedNewSongs(),
      this.loadPersonalFm(),
      this.loadNewSongCovers(),
      this.loadRadioCards(),
      this.loadProgramCards(),
      this.loadPrivateContents()
    ])
    results.forEach((loaded: boolean) => {
      if (loaded) {
        loadedSectionCount += 1
      }
    })
    if (loadedSectionCount === 0) {
      this.refreshText = '当前展示离线内容，启动后端或登录后下拉刷新'
    }
    this.loading = false
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
        const featured = response.list.slice(0, 4)
        const tasks = featured.map((item: ToplistItem) => this.loadRankingPreview(item))
        this.featuredRankings = await Promise.all(tasks)
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

  private async loadPersonalizedPlaylists(): Promise<boolean> {
    try {
      const response = await ApiClient.get<PersonalizedPlaylistResponse>('/personalized', [
        { key: 'limit', value: '12' }
      ])
      if (response.code === 200 && response.result?.length) {
        this.personalizedPlaylists = response.result.map((item) => mapPlaylist(item))
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadDailyPlaylists(): Promise<boolean> {
    try {
      const response = await ApiClient.get<DailyPlaylistResponse>('/recommend/resource')
      if (response.code === 200 && response.recommend?.length) {
        this.dailyPlaylists = response.recommend.map((item) => {
          return {
            id: item.id.toString(),
            name: item.name,
            cover: item.picUrl,
            count: item.trackCount || 0,
            creator: item.creator?.nickname || '每日推荐'
          } as playlistType
        })
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadDailySongs(): Promise<boolean> {
    try {
      const response = await ApiClient.get<DailySongsResponse>('/recommend/songs')
      if (response.code === 200 && response.data?.dailySongs?.length) {
        const list = response.data.dailySongs.map((item) => {
          const song = mapApiSong(item)
          song.recommendTag = item.recommendReason || item.reason || ''
          return song
        })
        this.dailyRecommendSongs = list
        return true
      }
    } catch (_error) {
    }
    this.dailyRecommendSongs = []
    return false
  }

  private async loadPersonalizedNewSongs(): Promise<boolean> {
    try {
      const response = await ApiClient.get<PersonalizedNewSongResponse>('/personalized/newsong', [
        { key: 'limit', value: '24' }
      ])
      if (response.code === 200 && response.result?.length) {
        const list = response.result.map((item) => {
          const song = mapApiSong(item.song)
          song.id = item.id.toString()
          song.name = item.name
          song.img = item.picUrl || song.img
          return song
        })
        this.personalizedNewSongColumns = this.toColumns(list)
        return true
      }
    } catch (_error) {
    }
    this.personalizedNewSongColumns = []
    return false
  }

  private openDailyRecommend(): void {
    this.pageStack.pushPathByName('DailyRecommendPage', null)
  }

  private heartModeImage(): string {
    if (this.heartModeCover) {
      return this.heartModeCover
    }
    if (this.dailyRecommendSongs.length > 1) {
      return this.dailyRecommendSongs[1].img
    }
    if (this.dailyRecommendSongs.length > 0) {
      return this.dailyRecommendSongs[0].img
    }
    return ''
  }

  private async openHeartMode(): Promise<void> {
    if (!this.authStore.loggedIn || !this.authStore.userId) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    if (this.heartModeLoading) {
      return
    }
    this.heartModeLoading = true
    this.refreshText = ''
    try {
      const baseData = await Promise.all([
        ApiClient.get<LikeListResponse>('/likelist', [
          { key: 'uid', value: this.authStore.userId }
        ]),
        ApiClient.get<UserPlaylistResponse>('/user/playlist/create', [
          { key: 'uid', value: this.authStore.userId }
        ])
      ])
      const likedIds = baseData[0].ids || []
      const createdPlaylists = baseData[1].data?.playlist || baseData[1].playlist || []
      if (likedIds.length === 0) {
        this.refreshText = '喜欢的音乐中还没有歌曲，暂时无法生成心动模式'
        return
      }
      if (createdPlaylists.length === 0) {
        this.refreshText = '未找到当前账号的喜欢音乐歌单'
        return
      }
      const seedId = likedIds[Math.floor(Math.random() * likedIds.length)]
      const likedPlaylist = createdPlaylists.find((item) => item.specialType === 5) || createdPlaylists[0]
      const likedPlaylistId = likedPlaylist.id
      const response = await ApiClient.get<IntelligencePlayResponse>('/playmode/intelligence/list', [
        { key: 'id', value: seedId.toString() },
        { key: 'pid', value: likedPlaylistId.toString() }
      ])
      if (response.code !== 200 || !response.data?.length) {
        this.refreshText = response.message || '心动模式歌单生成失败'
        return
      }
      const queue: songItemType[] = response.data
        .filter((item: IntelligencePlayItem) => !!item.songInfo)
        .map((item: IntelligencePlayItem) => {
          const song = mapApiSong(item.songInfo!)
          song.recommendTag = item.recommended ? '心动推荐' : '红心歌曲'
          return song
        })
      if (queue.length === 0) {
        this.refreshText = '心动模式暂时没有可播放歌曲'
        return
      }
      this.heartModeCover = queue[0].img
      await playerController.setQueue(queue, 0, true)
      this.pageStack.pushPathByName('PlayPage', null)
    } catch (error) {
      this.refreshText = error instanceof Error ? error.message : '心动模式加载失败'
    } finally {
      this.heartModeLoading = false
    }
  }

  private async loadPersonalFm(): Promise<boolean> {
    try {
      const response = await ApiClient.get<PersonalFmResponse>('/personal_fm')
      if (response.code === 200 && response.data?.length) {
        const list = response.data.map((item) => {
          const song = mapApiSong(item)
          song.recommendTag = item.recommendReason || item.reason || ''
          return song
        })
        this.fmColumns = this.toColumns(list)
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadNewSongCovers(): Promise<boolean> {
    try {
      const response = await ApiClient.get<TopSongResponse>('/top/song', [{ key: 'type', value: '0' }])
      if (response.code === 200 && response.data?.length) {
        this.newSongCategories = this.newSongCategories.map((item: NewSongCategory, index: number) => {
          const song = response.data![Math.min(index * 3, response.data!.length - 1)]
          return {
            type: item.type,
            title: item.title,
            subtitle: item.subtitle,
            cover: mapApiSong(song).img
          } as NewSongCategory
        })
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadRadioCards(): Promise<boolean> {
    try {
      const response = await ApiClient.get<PersonalizedProgramResponse>('/personalized/djprogram')
      if (response.code === 200 && response.result?.length) {
        this.radioCards = response.result.map((item) => {
          const mainSong = item.program?.mainSong
          return {
            id: item.id.toString(),
            title: item.name,
            subtitle: item.copywriter || item.program?.radio?.name || '编辑推荐',
            image: item.picUrl || item.program?.coverUrl || '',
            song: mainSong ? mapApiSong(mainSong) : undefined
          } as ProgramCard
        })
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadProgramCards(): Promise<boolean> {
    try {
      const response = await ApiClient.get<ProgramRecommendResponse>('/program/recommend', [
        { key: 'limit', value: '10' }
      ])
      if (response.code === 200 && response.programs?.length) {
        this.programCards = response.programs.map((item) => {
          return {
            id: item.id.toString(),
            title: item.name,
            subtitle: item.radio?.name || item.dj?.nickname || '推荐节目',
            image: item.coverUrl || item.radio?.picUrl || '',
            song: item.mainSong ? mapApiSong(item.mainSong) : undefined
          } as ProgramCard
        })
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async loadPrivateContents(): Promise<boolean> {
    try {
      const response = await ApiClient.get<PrivateContentResponse>('/personalized/privatecontent')
      if (response.code === 200 && response.result?.length) {
        this.privateContents = response.result
        return true
      }
    } catch (_error) {
    }
    return false
  }

  private async playSong(list: songItemType[], index: number): Promise<void> {
    await playerController.setQueue(list, index, true)
  }

  private async playProgram(item: ProgramCard): Promise<void> {
    if (item.song) {
      await playerController.setQueue([item.song], 0, true)
    }
  }

  private openNewSongCategory(item: NewSongCategory): void {
    const param: NewSongPageParam = {
      type: item.type,
      title: item.title,
      cover: item.cover
    }
    this.pageStack.pushPathByName('NewSongListPage', param)
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
  private SectionTitle(title: string, subtitle: string) {
    Row() {
      Column({ space: 3 }) {
        Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#f4f4f6')
        if (subtitle.length > 0) {
          Text(subtitle).fontSize(10).fontColor('#66666e')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor(['#66666e'])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 22, bottom: 10 })
  }

  @Builder
  private ThreeRowSongs(columns: SongColumn[]) {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(columns, (column: SongColumn) => {
          Column() {
            ForEach(column.songs, (item: songItemType, rowIndex: number) => {
              Row({ space: 10 }) {
                Image(item.img).width(54).height(54).borderRadius(12).objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Text(item.name)
                    .width('100%')
                    .fontSize(13)
                    .fontColor('#eeeeF1')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 6 }) {
                    if (item.recommendTag && item.recommendTag.length > 0) {
                      Text(item.recommendTag)
                        .fontSize(9)
                        .fontColor('#ef4058')
                        .maxLines(1)
                        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                        .border({ width: 1, color: '#ef4058' })
                        .borderRadius(4)
                    }
                    Text(item.author)
                      .layoutWeight(1)
                      .fontSize(10)
                      .fontColor('#77777f')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(23).fontColor(['#a9a9b0'])
              }
              .width(310)
              .height(68)
              .padding({ left: 8, right: 8 })
              .borderRadius(14)
              .onClick(() => this.playSong(column.songs, rowIndex))
            })
          }
          .padding({ top: 4, bottom: 4 })
          .backgroundColor('#18181d')
          .borderRadius(18)
        }, (column: SongColumn) => column.key)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private FeaturedRankingSection() {
    if (this.featuredRankings.length > 0) {
      this.SectionTitle('排行榜', '使用歌单详情获取官方榜实时歌曲')
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.featuredRankings, (ranking: RankingPreview) => {
            Row({ space: 12 }) {
              Stack({ alignContent: Alignment.BottomStart }) {
                Image(ranking.cover).width(104).height(132).borderRadius(15).objectFit(ImageFit.Cover)
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
            }
            .width(316).height(150).padding(9).backgroundColor('#1a1a20').borderRadius(18)
          }, (ranking: RankingPreview) => ranking.id)
        }.padding({ left: 16, right: 16 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
  }

  @Builder
  private ArtistRankingSection() {
    if (this.artistRanking.length > 0) {
      this.SectionTitle('歌手榜', this.artistRankingDate())
      Scroll() {
        Row({ space: 13 }) {
          ForEach(this.artistRanking, (artist: ArtistToplistArtist, index: number) => {
            Column({ space: 7 }) {
              Stack({ alignContent: Alignment.TopStart }) {
                Image(artist.picUrl || artist.img1v1Url || '').width(88).height(88).borderRadius(44)
                  .objectFit(ImageFit.Cover)
                Text(`${index + 1}`).fontSize(11).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                  .width(27).height(27).textAlign(TextAlign.Center).backgroundColor(index < 3 ? '#ef233c' : '#34343c')
                  .borderRadius(14).margin({ left: -3, top: -3 })
              }
              Text(artist.name).width(102).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#e8e8eb')
                .textAlign(TextAlign.Center).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.artistRankChange(artist, index)).fontSize(9)
                .fontColor(this.artistRankChange(artist, index).startsWith('↑') ? '#ef6577' : '#696971')
            }.width(102).onClick(() => this.openRankArtist(artist))
          }, (artist: ArtistToplistArtist) => artist.id.toString())
        }.padding({ left: 17, right: 17, top: 4 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
  }

  @Builder
  private AllRankingsSection() {
    if (this.toplists.length > 0) {
      this.SectionTitle('全部榜单', `${this.toplists.length} 个榜单`)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.toplists, (item: ToplistItem) => {
          Column({ space: 7 }) {
            Stack({ alignContent: Alignment.BottomStart }) {
              Image(item.coverImgUrl || item.picUrl || '').width('100%').aspectRatio(1).borderRadius(14)
                .objectFit(ImageFit.Cover)
              Column().width('100%').height(50).borderRadius({ bottomLeft: 14, bottomRight: 14 })
                .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.78)', 1]] })
              Text(item.updateFrequency || '').width('90%').fontSize(8).fontColor('#ededf0')
                .margin({ left: 7, bottom: 7 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            Text(item.name).width('100%').fontSize(11).fontColor('#dcdce1').maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('31%').margin({ bottom: 15 }).alignItems(HorizontalAlign.Start)
          .onClick(() => this.openRanking(item.id.toString(), item.name, item.coverImgUrl || item.picUrl || '',
            item.trackCount || 0))
        }, (item: ToplistItem) => item.id.toString())
      }.width('100%').padding({ left: 16, right: 16 })
    }
  }

  @Builder
  private ProgramSection(items: ProgramCard[]) {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(items, (item: ProgramCard) => {
          Column({ space: 8 }) {
            Stack({ alignContent: Alignment.Center }) {
              Image(item.image).width(148).height(104).borderRadius(16).objectFit(ImageFit.Cover)
              SymbolGlyph($r('sys.symbol.play_circle_fill'))
                .fontSize(31)
                .fontColor(['rgba(255,255,255,0.92)'])
            }
            Text(item.title).width(148).fontSize(12).fontColor('#e3e3e6').maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.subtitle).width(148).fontSize(10).fontColor('#77777f').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .onClick(() => this.playProgram(item))
        })
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  build() {
    Refresh({ refreshing: this.isRefreshing }) {
      Scroll() {
        Column() {
          Row({ space: 12 }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(21).fontColor(['#e4e4e8'])
            }
            .width(42).height(42).borderRadius(14).backgroundColor('#1e1e24')
            .onClick(() => this.onMenuClick())

            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor(['#85858d'])
              Text('搜索歌曲、歌手、专辑').layoutWeight(1).fontSize(13).fontColor('#77777f')
            }
            .layoutWeight(1).height(42).padding({ left: 14, right: 14 })
            .backgroundColor('#1e1e24').borderRadius(14)
            .onClick(() => this.pageStack.pushPathByName('SearchPage', null))
          }
          .width('100%').padding({ left: 14, right: 14, top: 12 })

          if (this.refreshText) {
            Text(this.refreshText).width('100%').fontSize(10).fontColor('#77777f')
              .textAlign(TextAlign.Center).padding({ top: 10 })
          }

          this.SectionTitle('推荐歌单', '来自 /personalized')
          Scroll() {
            Row({ space: 12 }) {
              Column({ space: 6 }) {
                Stack({ alignContent: Alignment.Center }) {
                  if (this.dailyRecommendSongs.length > 0) {
                    Image(this.dailyRecommendSongs[0].img)
                      .width(132).height(132).borderRadius(17).objectFit(ImageFit.Cover)
                    Column().width(132).height(132).borderRadius(17)
                      .linearGradient({ angle: 0, colors: [['rgba(80,12,26,0.82)', 0], ['rgba(0,0,0,0.04)', 1]] })
                  } else {
                    Column().width(132).height(132).borderRadius(17)
                      .linearGradient({ angle: 135, colors: [['#b7253f', 0], ['#3d263e', 1]] })
                  }
                  Column({ space: 2 }) {
                    Text(this.todayDate)
                      .fontSize(38).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                    Text('今日').fontSize(10).fontColor('#f2d8dd')
                  }
                }
                .width(132).height(132).borderRadius(17).clip(true)
                Text('每日推荐').width(132).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#f0f0f3')
                Text('今日限定好歌推荐').width(132).fontSize(10).fontColor('#77777f').maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .onClick(() => this.openDailyRecommend())

              Column({ space: 6 }) {
                Stack({ alignContent: Alignment.Center }) {
                  if (this.heartModeImage()) {
                    Image(resizeImageUrl(this.heartModeImage(), 300, 300)).width(132).height(132)
                      .sourceSize({ width: 300, height: 300 }).borderRadius(17).objectFit(ImageFit.Cover)
                    Column().width(132).height(132).borderRadius(17)
                      .linearGradient({ angle: 135, colors: [['rgba(239,35,60,0.82)', 0],
                        ['rgba(32,8,22,0.35)', 0.58], ['rgba(0,0,0,0.62)', 1]] })
                  } else {
                    Column().width(132).height(132).borderRadius(17)
                      .linearGradient({ angle: 135, colors: [['#f04058', 0], ['#6f183d', 0.55], ['#24152c', 1]] })
                  }
                  if (this.heartModeLoading) {
                    Column({ space: 7 }) {
                      LoadingProgress().width(31).height(31).color('#ffffff')
                      Text('生成中').fontSize(9).fontColor('#f7e9ed')
                    }
                  } else {
                    Column({ space: 5 }) {
                      SymbolGlyph($r('sys.symbol.heart_fill')).fontSize(42).fontColor(['#ffffff'])
                    }
                  }
                }.width(132).height(132).borderRadius(17).clip(true)
                Text('心动模式').width(132).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#f0f0f3')
                Text('红心歌曲与相似推荐').width(132).fontSize(10).fontColor('#77777f').maxLines(1)
              }.alignItems(HorizontalAlign.Start).onClick(() => this.openHeartMode())

              ForEach(this.personalizedPlaylists, (item: playlistType) => {
                Column({ space: 8 }) {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    Image(item.cover).width(132).height(132).borderRadius(17).objectFit(ImageFit.Cover)
                    if (item.count > 0) {
                      Text(`${this.formatCount(item.count)}首`).fontSize(9).fontColor('#ffffff')
                        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                        .backgroundColor('rgba(0,0,0,0.42)').borderRadius(8).margin(7)
                    }
                  }
                  Text(item.name).width(132).fontSize(12).fontColor('#dedee2').maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .onClick(() => this.pageStack.pushPathByName('PlaylistDetailPage', item))
              })
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

          this.SectionTitle('根据喜爱歌曲推荐', '来自 /personalized/newsong · 横向滑动查看')
          if (this.personalizedNewSongColumns.length > 0) {
            this.ThreeRowSongs(this.personalizedNewSongColumns)
          } else if (!this.loading) {
            Text('暂无个性化新歌推荐')
              .width('100%').fontSize(11).fontColor('#66666e').textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 18 })
          }

          if (this.fmColumns.length > 0) {
            this.SectionTitle('私人 FM', '为你持续发现下一首好歌')
            this.ThreeRowSongs(this.fmColumns)
          }

          this.SectionTitle('新歌速递', '全部、华语、欧美、日本、韩国')
          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.newSongCategories, (item: NewSongCategory) => {
                Stack({ alignContent: Alignment.BottomStart }) {
                  Image(item.cover).width(200).height(120).borderRadius(18).objectFit(ImageFit.Cover)
                  Column({ space: 3 }) {
                    Text(item.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                    Text(item.subtitle).fontSize(9).fontColor('#e3e3e6').maxLines(1)
                  }
                  .width('60%').padding(12)
                  .linearGradient({ angle: 0, colors: [['rgba(0,0,0,0.72)', 0], ['rgba(0,0,0,0)', 1]] })
                }
                .borderRadius(18).clip(true)
                .onClick(() => this.openNewSongCategory(item))
              })
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

          if (this.radioCards.length > 0) {
            this.SectionTitle('推荐电台', '编辑精选的声音内容')
            this.ProgramSection(this.radioCards)
          }

          if (this.programCards.length > 0) {
            this.SectionTitle('推荐节目', '今天值得听的节目')
            this.ProgramSection(this.programCards)
          }

          if (this.privateContents.length > 0) {
            this.SectionTitle('独家放送', '网易云音乐独家内容')
            Scroll() {
              Row({ space: 12 }) {
                ForEach(this.privateContents, (item: PrivateContentItem) => {
                  Column({ space: 8 }) {
                    Stack({ alignContent: Alignment.Center }) {
                      Image(item.picUrl).width(220).height(124).borderRadius(17).objectFit(ImageFit.Cover)
                      SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(32)
                        .fontColor(['rgba(255,255,255,0.9)'])
                    }
                    Text(item.name).width(220).fontSize(12).fontColor('#e3e3e6').maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                })
              }
              .padding({ left: 16, right: 16 })
            }
            .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          }

          Blank().height(150)
        }
        .width('100%')
      }
      .width('100%').height('100%').scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor('#121215')
    .onRefreshing(async () => {
      this.isRefreshing = true
      await this.loadHomeData()
      this.isRefreshing = false
    })
  }
}

interface RankingPreview {
  id: string
  name: string
  cover: string
  updateFrequency: string
  songs: songItemType[]
  fallbackTracks: ToplistTrackPreview[]
}

export default Recommend
