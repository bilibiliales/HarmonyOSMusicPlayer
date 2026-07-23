import {
  AlbumPageParam,
  ApiAlbum,
  ApiArtist,
  ApiPlaylist,
  ApiSong,
  ApiUser,
  ArtistPageParam,
  DjRadioItem,
  HotSearchItem,
  HotSearchResponse,
  mapApiSong,
  mapPlaylist,
  MvPlayerPageParam,
  SearchDefaultResponse,
  SearchMvItem,
  SearchResponse,
  SearchSuggestResponse,
  SearchVideoItem,
  SearchVoiceItem,
  SongDetailResponse,
  UserProfilePageParam
} from '../models/api'
import { playlistType, songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'

@Component
export struct SearchPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State keyword: string = ''
  @State activeType: number = 1018
  @State sections: SearchSection[] = []
  @State songQueue: songItemType[] = []
  @State loading: boolean = false
  @State message: string = ''
  @State defaultKeyword: string = ''
  @State hotSearches: HotSearchItem[] = []
  @State suggestionItems: SearchDisplayItem[] = []
  @State suggestionSongQueue: songItemType[] = []
  @State suggestionLoading: boolean = false
  @State searchedKeyword: string = ''
  @State discoveryLoading: boolean = true
  private suggestTimer: number = -1
  private suggestRequestToken: number = 0

  private searchTabs: SearchTabItem[] = [
    { type: 1018, title: '综合' },
    { type: 1, title: '单曲' },
    { type: 10, title: '专辑' },
    { type: 100, title: '歌手' },
    { type: 1000, title: '歌单' },
    { type: 1002, title: '用户' },
    { type: 1004, title: 'MV' },
    { type: 1006, title: '歌词' },
    { type: 1009, title: '电台' },
    { type: 1014, title: '视频' },
    { type: 2000, title: '声音' }
  ]

  aboutToAppear(): void {
    this.loadSearchDiscovery()
  }

  aboutToDisappear(): void {
    if (this.suggestTimer !== -1) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
  }

  private async loadSearchDiscovery(): Promise<void> {
    try {
      const response = await ApiClient.get<SearchDefaultResponse>('/search/default')
      if (response.code === 200 && response.data) {
        this.defaultKeyword = response.data.showKeyword || response.data.realkeyword || ''
      }
    } catch (_error) {
    }
    try {
      const response = await ApiClient.get<HotSearchResponse>('/search/hot/detail')
      if (response.code === 200 && response.data) {
        this.hotSearches = response.data
      }
    } catch (_error) {
    }
    this.discoveryLoading = false
  }

  private runKeyword(value: string): void {
    this.keyword = value
    this.suggestionItems = []
    this.suggestionSongQueue = []
    this.search()
  }

  private onKeywordChange(value: string): void {
    this.keyword = value
    this.sections = []
    this.songQueue = []
    this.message = ''
    if (this.suggestTimer !== -1) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    const normalized = value.trim()
    if (normalized.length === 0) {
      this.searchedKeyword = ''
      this.suggestionItems = []
      this.suggestionSongQueue = []
      this.suggestionLoading = false
      ++this.suggestRequestToken
      return
    }
    this.searchedKeyword = ''
    this.suggestionLoading = true
    const requestToken = ++this.suggestRequestToken
    this.suggestTimer = setTimeout(() => {
      this.loadSuggestions(normalized, requestToken)
      this.suggestTimer = -1
    }, 280)
  }

  private async loadSuggestions(keyword: string, requestToken: number): Promise<void> {
    try {
      const response = await ApiClient.get<SearchSuggestResponse>('/search/suggest', [
        { key: 'keywords', value: keyword }
      ])
      if (requestToken !== this.suggestRequestToken || this.keyword.trim() !== keyword) {
        return
      }
      const items: SearchDisplayItem[] = []
      const songs = response.result?.songs || []
      const albums = response.result?.albums || []
      this.suggestionSongQueue = []
      songs.forEach((song: ApiSong) => {
        const mapped = mapApiSong(song)
        const songIndex = this.suggestionSongQueue.length
        this.suggestionSongQueue.push(mapped)
        const item: SearchDisplayItem = {
          id: mapped.id,
          title: mapped.name,
          subtitle: `${mapped.author}${mapped.album ? ` · ${mapped.album}` : ''}`,
          image: mapped.img,
          kind: '单曲',
          extra: '搜索建议',
          songIndex: songIndex,
          uid: '',
          playlist: null
        }
        items.push(item)
      })
      albums.forEach((album: ApiAlbum) => {
        const artists = album.artists || (album.artist ? [album.artist] : [])
        const item: SearchDisplayItem = {
          id: album.id?.toString() || '',
          title: album.name,
          subtitle: this.artistsText(artists),
          image: album.picUrl || album.artist?.picUrl || '',
          kind: '专辑',
          extra: '搜索建议',
          songIndex: -1,
          uid: '',
          playlist: null
        }
        items.push(item)
      })
      this.suggestionItems = items
    } catch (_error) {
      if (requestToken === this.suggestRequestToken) {
        this.suggestionItems = []
        this.suggestionSongQueue = []
      }
    } finally {
      if (requestToken === this.suggestRequestToken) {
        this.suggestionLoading = false
      }
    }
  }

  private async search(): Promise<void> {
    let keyword = this.keyword.trim()
    if (!keyword) {
      keyword = this.defaultKeyword.trim()
      if (!keyword) {
        return
      }
      this.keyword = keyword
    }
    if (this.suggestTimer !== -1) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    ++this.suggestRequestToken
    this.suggestionItems = []
    this.suggestionSongQueue = []
    this.suggestionLoading = false
    this.searchedKeyword = keyword
    this.loading = true
    this.message = ''
    this.sections = []
    this.songQueue = []
    try {
      const response = await ApiClient.get<SearchResponse>('/search', [
        { key: 'keywords', value: keyword },
        { key: 'type', value: this.activeType.toString() },
        { key: 'limit', value: this.activeType === 1018 ? '20' : '50' }
      ])
      if (response.code === 200 && response.result) {
        this.sections = this.mapSearchResult(response)
      }
      if (this.sections.length === 0) {
        this.message = `没有找到相关${this.activeTabTitle()}`
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '搜索失败'
    } finally {
      this.loading = false
    }
  }

  private activeTabTitle(): string {
    const tab = this.searchTabs.find((item: SearchTabItem) => item.type === this.activeType)
    return tab?.title || '内容'
  }

  private selectType(type: number): void {
    if (this.activeType === type) {
      return
    }
    this.activeType = type
    if (this.keyword.trim()) {
      this.search()
    }
  }

  private makeSection(title: string, items: SearchDisplayItem[]): SearchSection {
    const section: SearchSection = { title: title, items: items }
    return section
  }

  private artistsText(artists: ApiArtist[] | undefined): string {
    return (artists || []).map((artist: ApiArtist) => artist.name).join(' / ')
  }

  private addSongs(title: string, songs: ApiSong[], sections: SearchSection[], lyricMode: boolean = false): void {
    if (songs.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    songs.forEach((song: ApiSong) => {
      const mapped = mapApiSong(song)
      const songIndex = this.songQueue.length
      this.songQueue.push(mapped)
      const lyricText = song.lyrics?.txt || ''
      const item: SearchDisplayItem = {
        id: mapped.id,
        title: mapped.name,
        subtitle: lyricMode && lyricText ? lyricText.replace(/\n/g, ' ').slice(0, 110) :
          `${mapped.author}${mapped.album ? ` · ${mapped.album}` : ''}`,
        image: mapped.img,
        kind: lyricMode ? '歌词' : '单曲',
        extra: '',
        songIndex: songIndex,
        uid: '',
        playlist: null
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private addAlbums(title: string, albums: ApiAlbum[], sections: SearchSection[]): void {
    if (albums.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    albums.forEach((album: ApiAlbum) => {
      const artists = album.artists || (album.artist ? [album.artist] : [])
      const item: SearchDisplayItem = {
        id: album.id?.toString() || '',
        title: album.name || '专辑',
        subtitle: this.artistsText(artists),
        image: album.picUrl || '',
        kind: '专辑',
        extra: album.size ? `${album.size} 首` : '',
        songIndex: -1,
        uid: '',
        playlist: null
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private addArtists(title: string, artists: ApiArtist[], sections: SearchSection[]): void {
    if (artists.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    artists.forEach((artist: ApiArtist) => {
      const item: SearchDisplayItem = {
        id: artist.id?.toString() || '',
        title: artist.name,
        subtitle: `${artist.musicSize || 0} 首单曲 · ${artist.albumSize || 0} 张专辑`,
        image: artist.picUrl || artist.img1v1Url || '',
        kind: '歌手',
        extra: artist.fansSize ? `${artist.fansSize} 粉丝` : '',
        songIndex: -1,
        uid: '',
        playlist: null
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private addPlaylists(title: string, playlists: ApiPlaylist[], sections: SearchSection[]): void {
    if (playlists.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    playlists.forEach((playlist: ApiPlaylist) => {
      const mapped = mapPlaylist(playlist)
      const item: SearchDisplayItem = {
        id: mapped.id,
        title: mapped.name,
        subtitle: `${mapped.count} 首 · ${mapped.creator}`,
        image: mapped.cover,
        kind: '歌单',
        extra: playlist.playCount ? `${playlist.playCount} 次播放` : '',
        songIndex: -1,
        uid: '',
        playlist: mapped
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private addUsers(title: string, users: ApiUser[], sections: SearchSection[]): void {
    if (users.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    users.forEach((user: ApiUser) => {
      const isArtist = (user.artistId || 0) > 0
      const item: SearchDisplayItem = {
        id: isArtist ? user.artistId?.toString() || '' : user.userId?.toString() || '',
        title: user.nickname,
        subtitle: user.signature || `${user.follows || 0} 关注 · ${user.followeds || 0} 粉丝`,
        image: user.avatarUrl,
        kind: isArtist ? '歌手' : '用户',
        extra: user.userType === 4 ? '认证歌手' : '',
        songIndex: -1,
        uid: isArtist ? '' : user.userId?.toString() || '',
        playlist: null
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private addMvs(title: string, mvs: SearchMvItem[], sections: SearchSection[]): void {
    if (mvs.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    mvs.forEach((mv: SearchMvItem) => {
      const item: SearchDisplayItem = {
        id: mv.id.toString(),
        title: mv.name,
        subtitle: mv.artistName || '',
        image: mv.cover,
        kind: 'MV',
        extra: mv.playCount ? `${mv.playCount} 次播放` : '',
        songIndex: -1,
        uid: '',
        playlist: null
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private addVideos(title: string, videos: SearchVideoItem[], sections: SearchSection[]): void {
    if (videos.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    videos.forEach((video: SearchVideoItem) => {
      const creator = video.creator && video.creator.length > 0 ? video.creator[0].userName || '' : ''
      const item: SearchDisplayItem = {
        id: video.vid || '',
        title: video.title,
        subtitle: creator,
        image: video.coverUrl,
        kind: '视频',
        extra: video.playTime ? `${video.playTime} 次播放` : '',
        songIndex: -1,
        uid: '',
        playlist: null
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private addRadios(title: string, radios: DjRadioItem[], sections: SearchSection[]): void {
    if (radios.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    radios.forEach((radio: DjRadioItem) => {
      const item: SearchDisplayItem = {
        id: radio.id.toString(),
        title: radio.name,
        subtitle: radio.dj?.nickname || radio.creator?.nickname || radio.desc || '',
        image: radio.picUrl,
        kind: '电台',
        extra: `${radio.programCount || 0} 期节目`,
        songIndex: -1,
        uid: '',
        playlist: null
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private addVoices(title: string, voices: SearchVoiceItem[], sections: SearchSection[]): void {
    if (voices.length === 0) {
      return
    }
    const items: SearchDisplayItem[] = []
    voices.forEach((voice: SearchVoiceItem) => {
      const item: SearchDisplayItem = {
        id: voice.id?.toString() || '',
        title: voice.name || voice.title || '声音',
        subtitle: voice.creator?.nickname || voice.description || '',
        image: voice.coverUrl || voice.picUrl || '',
        kind: '声音',
        extra: '',
        songIndex: -1,
        uid: '',
        playlist: null
      }
      items.push(item)
    })
    sections.push(this.makeSection(title, items))
  }

  private mapSearchResult(response: SearchResponse): SearchSection[] {
    const result = response.result
    const sections: SearchSection[] = []
    if (!result) {
      return sections
    }
    if (this.activeType === 1018) {
      this.addSongs('单曲', result.song?.songs || [], sections)
      this.addPlaylists('歌单', result.playList?.playLists || [], sections)
      this.addArtists('歌手', result.artist?.artists || [], sections)
      this.addAlbums('专辑', result.album?.albums || [], sections)
      this.addUsers('用户', result.user?.users || [], sections)
      this.addVideos('视频', result.new_mlog?.resources || [], sections)
      this.addVoices('声音', result.voice?.resources || [], sections)
    } else if (this.activeType === 1) {
      this.addSongs('单曲', result.songs || [], sections)
    } else if (this.activeType === 10) {
      this.addAlbums('专辑', result.albums || [], sections)
    } else if (this.activeType === 100) {
      this.addArtists('歌手', result.artists || [], sections)
    } else if (this.activeType === 1000) {
      this.addPlaylists('歌单', result.playlists || [], sections)
    } else if (this.activeType === 1002) {
      this.addUsers('用户', result.userprofiles || [], sections)
    } else if (this.activeType === 1004) {
      this.addMvs('MV', result.mvs || [], sections)
    } else if (this.activeType === 1006) {
      this.addSongs('歌词匹配', result.songs || [], sections, true)
    } else if (this.activeType === 1009) {
      this.addRadios('电台', result.djRadios || [], sections)
    } else if (this.activeType === 1014) {
      this.addVideos('视频', result.videos || [], sections)
    } else if (this.activeType === 2000) {
      this.addVoices('声音', result.resources || result.voices || [], sections)
    }
    return sections
  }

  private async playSong(index: number): Promise<void> {
    await playerController.setQueue(this.songQueue, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private openItem(item: SearchDisplayItem): void {
    if (item.songIndex >= 0) {
      this.playSong(item.songIndex)
    } else if (item.playlist) {
      this.pageStack.pushPathByName('PlaylistDetailPage', item.playlist)
    } else if (item.kind === '专辑' && item.id) {
      const param: AlbumPageParam = { id: item.id, name: item.title, picUrl: item.image, artist: item.subtitle }
      this.pageStack.pushPathByName('AlbumDetailPage', param)
    } else if (item.kind === '歌手' && item.id) {
      const param: ArtistPageParam = { id: item.id, name: item.title, picUrl: item.image }
      this.pageStack.pushPathByName('ArtistPage', param)
    } else if (item.kind === 'MV' && item.id) {
      const param: MvPlayerPageParam = {
        id: item.id,
        name: item.title,
        cover: item.image,
        artistName: item.subtitle
      }
      this.pageStack.pushPathByName('MvPlayerPage', param)
    } else if (item.uid) {
      const param: UserProfilePageParam = { uid: item.uid }
      this.pageStack.pushPathByName('UserProfilePage', param)
    }
  }

  private async openSuggestion(item: SearchDisplayItem): Promise<void> {
    if (item.songIndex >= 0) {
      let queue = this.suggestionSongQueue
      try {
        const ids = this.suggestionSongQueue.map((song: songItemType) => song.id).join(',')
        if (ids.length > 0) {
          const response = await ApiClient.get<SongDetailResponse>('/song/detail', [
            { key: 'ids', value: ids }
          ])
          const detailed = (response.songs || []).map((song: ApiSong) => mapApiSong(song))
          if (detailed.length > 0) {
            const detailMap = new Map<string, songItemType>()
            detailed.forEach((song: songItemType) => detailMap.set(song.id, song))
            queue = this.suggestionSongQueue.map((song: songItemType) => detailMap.get(song.id) || song)
          }
        }
      } catch (_error) {
      }
      await playerController.setQueue(queue, item.songIndex, true)
      this.pageStack.pushPathByName('PlayPage', null)
    } else if (item.kind === '专辑' && item.id) {
      const param: AlbumPageParam = { id: item.id, name: item.title, picUrl: item.image, artist: item.subtitle }
      this.pageStack.pushPathByName('AlbumDetailPage', param)
    }
  }

  @Builder
  private ResultItem(item: SearchDisplayItem) {
    Row({ space: 12 }) {
      if (item.image) {
        Image(item.image)
          .width(item.kind === '视频' || item.kind === 'MV' ? 94 : 54)
          .height(item.kind === '视频' || item.kind === 'MV' ? 58 : 54)
          .borderRadius(item.kind === '歌手' || item.kind === '用户' ? 27 : 11)
          .objectFit(ImageFit.Cover)
      } else {
        Stack() {
          SymbolGlyph(item.kind === '用户' ? $r('sys.symbol.person_fill') : $r('sys.symbol.music'))
            .fontSize(23).fontColor(['#909098'])
        }
        .width(54).height(54).borderRadius(11).backgroundColor('#292930')
      }
      Column({ space: 5 }) {
        Row({ space: 7 }) {
          Text(item.kind).fontSize(9).fontColor('#ff7587')
          if (item.extra) {
            Text(item.extra).fontSize(9).fontColor('#65656d')
          }
        }
        Text(item.title).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor('#ededf0').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.subtitle) {
          Text(item.subtitle).width('100%').fontSize(11).fontColor('#77777f')
            .maxLines(item.kind === '歌词' ? 2 : 1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (item.songIndex >= 0) {
        SymbolGlyph($r('sys.symbol.play_circle')).fontSize(23).fontColor(['#8a8a92'])
      } else if (item.playlist || item.uid) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor(['#66666e'])
      }
    }
    .width('100%').padding({ left: 14, right: 16, top: 8, bottom: 8 })
    .onClick(() => this.openItem(item))
  }

  @Builder
  private SearchDiscovery() {
    Column() {
      if (this.defaultKeyword.length > 0) {
        Column({ space: 9 }) {
          Text('搜索发现').width('100%').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(15).fontColor(['#ef4058'])
            Text(this.defaultKeyword).layoutWeight(1).fontSize(13).fontColor('#e2e2e6').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor(['#66666e'])
          }
          .width('100%').height(46).padding({ left: 13, right: 13 })
          .backgroundColor('#202026').borderRadius(14)
          .onClick(() => this.runKeyword(this.defaultKeyword))
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
      }

      Row() {
        Text('当前热搜').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text(`${this.hotSearches.length} 条`).fontSize(10).fontColor('#66666e')
      }
      .width('100%').height(44).padding({ left: 16, right: 16 })

      if (this.discoveryLoading) {
        Column({ space: 10 }) {
          LoadingProgress().width(28).height(28).color('#ef233c')
          Text('正在获取热搜').fontSize(11).fontColor('#77777f')
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.hotSearches.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(34).fontColor(['#55555d'])
          Text('暂无热搜内容').fontSize(12).fontColor('#77777f')
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.hotSearches, (item: HotSearchItem, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Text((index + 1).toString()).width(27).fontSize(index < 3 ? 18 : 13)
                  .fontWeight(index < 3 ? FontWeight.Bold : FontWeight.Regular)
                  .fontColor(index < 3 ? '#ef4058' : '#77777f').textAlign(TextAlign.Center)
                Column({ space: 5 }) {
                  Row({ space: 7 }) {
                    Text(item.searchWord).fontSize(14).fontWeight(index < 3 ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor('#ededf0').maxLines(1)
                    if (item.iconUrl && item.iconUrl.length > 0) {
                      Image(item.iconUrl).height(13).width(28).objectFit(ImageFit.Contain)
                    } else if (item.iconType === 1) {
                      Text('HOT').fontSize(8).fontColor('#ef4058')
                    }
                  }
                  if (item.content && item.content.length > 0) {
                    Text(item.content).fontSize(10).fontColor('#77777f').maxLines(1)
                  }
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (item.score && item.score > 0) {
                  Text(item.score.toString()).fontSize(9).fontColor('#55555d')
                }
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor(['#55555d'])
              }
              .height(62).padding({ left: 12, right: 16 })
              .onClick(() => this.runKeyword(item.searchWord))
            }
          })
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
    }
    .width('100%').layoutWeight(1)
  }

  @Builder
  private SuggestionPanel() {
    Column() {
      Row() {
        Text('搜索建议').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text(this.keyword.trim()).fontSize(11).fontColor('#ef6577').maxLines(1)
      }
      .width('100%').height(48).padding({ left: 16, right: 16 })
      if (this.suggestionLoading) {
        LoadingProgress().layoutWeight(1).width(38).color('#ef233c')
      } else if (this.suggestionItems.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(36).fontColor(['#55555d'])
          Text('暂无搜索建议，按回车直接搜索').fontSize(12).fontColor('#77777f')
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.suggestionItems, (item: SearchDisplayItem) => {
            ListItem() {
              Row({ space: 12 }) {
                if (item.image) {
                  Image(item.image).width(50).height(50).borderRadius(10).objectFit(ImageFit.Cover)
                } else {
                  Stack() {
                    SymbolGlyph($r('sys.symbol.music'))
                      .fontSize(21).fontColor(['#8a8a92'])
                  }
                  .width(50).height(50).borderRadius(10).backgroundColor('#292930')
                }
                Column({ space: 5 }) {
                  Row({ space: 6 }) {
                    Text(item.kind).fontSize(9).fontColor('#ef6577')
                    Text(item.title).layoutWeight(1).fontSize(14).fontColor('#ededf0').maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  Text(item.subtitle).width('100%').fontSize(10).fontColor('#77777f').maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph(item.songIndex >= 0 ? $r('sys.symbol.play_circle') : $r('sys.symbol.chevron_right'))
                  .fontSize(20).fontColor(['#77777f'])
              }
              .height(66).padding({ left: 14, right: 16 }).onClick(() => this.openSuggestion(item))
            }
          })
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
    }
    .width('100%').layoutWeight(1)
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor(['#77777f'])
            TextInput({ text: this.keyword,
              placeholder: this.defaultKeyword || '歌曲、专辑、歌手、歌单、用户' })
              .layoutWeight(1).fontColor('#ffffff').placeholderColor('#66666e')
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => this.onKeywordChange(value))
              .onSubmit(() => this.search())
            if (this.keyword) {
              SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(18).fontColor(['#66666e'])
                .onClick(() => {
                  this.onKeywordChange('')
                })
            }
          }
          .layoutWeight(1).height(42).padding({ left: 12, right: 12 })
          .backgroundColor('#202026').borderRadius(14)
          Button('搜索').fontSize(13).fontColor('#ff6577').backgroundColor(Color.Transparent)
            .onClick(() => this.search())
        }
        .width('100%').height(62).padding({ left: 14, right: 12 })

        if (this.searchedKeyword.length > 0) {
          Scroll() {
            Row({ space: 7 }) {
              ForEach(this.searchTabs, (tab: SearchTabItem) => {
                Text(tab.title)
                  .fontSize(11)
                  .fontColor(this.activeType === tab.type ? '#ffffff' : '#77777f')
                  .fontWeight(this.activeType === tab.type ? FontWeight.Bold : FontWeight.Regular)
                  .padding({ left: 13, right: 13, top: 8, bottom: 8 })
                  .backgroundColor(this.activeType === tab.type ? '#ef233c' : '#222228')
                  .borderRadius(16)
                  .onClick(() => this.selectType(tab.type))
              })
            }
            .padding({ left: 14, right: 14 })
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(44)
        }

        if (this.keyword.trim().length === 0 && this.searchedKeyword.length === 0) {
          this.SearchDiscovery()
        } else if (this.searchedKeyword.length === 0) {
          this.SuggestionPanel()
        } else if (this.loading) {
          LoadingProgress().layoutWeight(1).width(46).color('#ef233c')
        } else if (this.sections.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(44).fontColor(['#55555d'])
            Text(this.message).fontSize(13).fontColor('#77777f')
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.sections, (section: SearchSection) => {
              ListItem() {
                Column() {
                  Row() {
                    Text(section.title).layoutWeight(1).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                    Text(`${section.items.length} 项`).fontSize(10).fontColor('#66666e')
                  }
                  .height(44).padding({ left: 14, right: 16 })
                  ForEach(section.items, (item: SearchDisplayItem) => {
                    this.ResultItem(item)
                  })
                }
                .width('100%')
              }
            })
          }
          .layoutWeight(1)
        }
      }
      .width('100%').height('100%').backgroundColor('#121215')
    }
    .hideTitleBar(true)
  }
}

interface SearchTabItem {
  type: number
  title: string
}

interface SearchDisplayItem {
  id: string
  title: string
  subtitle: string
  image: string
  kind: string
  extra: string
  songIndex: number
  uid: string
  playlist: playlistType | null
}

interface SearchSection {
  title: string
  items: SearchDisplayItem[]
}
