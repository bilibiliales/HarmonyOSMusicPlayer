import {
  AlbumPageParam,
  ApiAlbum,
  ApiArtist,
  ApiParam,
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
import { RadioPageParam } from '../models/radio'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { SearchHistory } from '../services/SearchHistory'
import { common } from '@kit.AbilityKit'
import { TC } from '../services/ThemeColors'

@Component
export struct SearchPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
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
  @State historyWords: string[] = []
  @State historyExpanded: boolean = false
  @State longPressedWord: string = ''
  private suggestTimer: number = -1
  private suggestRequestToken: number = 0
  private searchRequestToken: number = 0

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
    try {
      this.historyWords = SearchHistory.load(this.getUIContext().getHostContext() as common.UIAbilityContext)
    } catch (_error) {
      this.historyWords = []
    }
    this.loadSearchDiscovery()
  }

  private historyContext(): common.Context {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  /** 收起时只露两行左右，展开显示全部。 */
  private visibleHistory(): string[] {
    return this.historyExpanded ? this.historyWords : this.historyWords.slice(0, 8)
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      title: '清空历史记录',
      message: '确定清空历史记录？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清空', fontColor: TC.accent(), action: () => {
          this.historyWords = []
          this.historyExpanded = false
          this.longPressedWord = ''
          SearchHistory.save(this.historyContext(), [])
        }
      }
    })
  }

  /** 长按气泡里的删除：立即删除，不弹窗。 */
  private deleteHistoryWord(word: string): void {
    this.historyWords = this.historyWords.filter((item: string) => item !== word)
    this.longPressedWord = ''
    SearchHistory.save(this.historyContext(), this.historyWords)
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
    ++this.searchRequestToken
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
      this.suggestionLoading = false
      await this.enrichSuggestionCovers(requestToken)
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

  // 搜索结果与搜索建议返回的歌曲只带专辑 picId（数字），没有可用的封面 URL，
  // 真实封面在 /song/detail 的 al.picUrl 中。此处批量补齐，使列表显示封面，
  // 并让播放队列自带封面，进入播放页无需再加载。
  private async fetchCoverMap(queue: songItemType[]): Promise<Map<string, string>> {
    const covers = new Map<string, string>()
    const ids: string[] = []
    queue.forEach((song: songItemType) => {
      if (song.id && !song.img) { ids.push(song.id) }
    })
    if (ids.length === 0) { return covers }
    for (let start = 0; start < ids.length; start += 50) {
      const batch = ids.slice(start, start + 50)
      try {
        const params: ApiParam[] = [{ key: 'ids', value: batch.join(',') }]
        const response = await ApiClient.get<SongDetailResponse>('/song/detail', params)
        const songs: ApiSong[] = response.songs || []
        songs.forEach((song: ApiSong) => {
          const mapped = mapApiSong(song)
          if (mapped.img) { covers.set(mapped.id, mapped.img) }
        })
      } catch (_error) {
      }
    }
    return covers
  }

  private async enrichSearchCovers(requestToken: number): Promise<void> {
    const covers = await this.fetchCoverMap(this.songQueue)
    if (requestToken !== this.searchRequestToken || covers.size === 0) { return }
    this.songQueue.forEach((song: songItemType) => {
      const cover = covers.get(song.id)
      if (cover && !song.img) { song.img = cover }
    })
    this.songQueue = this.songQueue.slice()
    const sections: SearchSection[] = this.sections.map((section: SearchSection) => {
      const items: SearchDisplayItem[] = section.items.map((item: SearchDisplayItem) => {
        const cover = covers.get(item.id)
        if (!cover || item.image) { return item }
        const updated: SearchDisplayItem = {
          id: item.id, title: item.title, subtitle: item.subtitle, image: cover,
          kind: item.kind, extra: item.extra, songIndex: item.songIndex,
          uid: item.uid, playlist: item.playlist
        }
        return updated
      })
      const next: SearchSection = { title: section.title, items: items }
      return next
    })
    this.sections = sections
  }

  private async enrichSuggestionCovers(requestToken: number): Promise<void> {
    const covers = await this.fetchCoverMap(this.suggestionSongQueue)
    if (requestToken !== this.suggestRequestToken || covers.size === 0) { return }
    this.suggestionSongQueue.forEach((song: songItemType) => {
      const cover = covers.get(song.id)
      if (cover && !song.img) { song.img = cover }
    })
    this.suggestionSongQueue = this.suggestionSongQueue.slice()
    const items: SearchDisplayItem[] = this.suggestionItems.map((item: SearchDisplayItem) => {
      const cover = covers.get(item.id)
      if (!cover || item.image) { return item }
      const updated: SearchDisplayItem = {
        id: item.id, title: item.title, subtitle: item.subtitle, image: cover,
        kind: item.kind, extra: item.extra, songIndex: item.songIndex,
        uid: item.uid, playlist: item.playlist
      }
      return updated
    })
    this.suggestionItems = items
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
    // 所有搜索入口（回车、搜索按钮、热搜、历史气泡）统一在这里落历史
    this.historyWords = SearchHistory.add(this.historyWords, keyword)
    SearchHistory.save(this.historyContext(), this.historyWords)
    const requestToken = ++this.searchRequestToken
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
        this.loading = false
        await this.enrichSearchCovers(requestToken)
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
    // 兜底：若补封面请求尚未返回，先补齐再进播放页，避免默认无封面
    await this.enrichSearchCovers(this.searchRequestToken)
    await playerController.setQueue(this.songQueue, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private openItem(item: SearchDisplayItem): void {
    if (item.songIndex >= 0) {
      this.playSong(item.songIndex)
    } else if (item.playlist) {
      this.pageStack.pushPathByName('PlaylistDetailPage', item.playlist)
    } else if (item.kind === '电台' && item.id) {
      const param: RadioPageParam = { id: item.id, name: item.title, cover: item.image }
      this.pageStack.pushPathByName('RadioDetailPage', param)
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
            .fontSize(23).fontColor([TC.textSecondary()])
        }
        .width(54).height(54).borderRadius(11).backgroundColor(TC.chipBackground())
      }
      Column({ space: 5 }) {
        Row({ space: 7 }) {
          Text(item.kind).fontSize(9).fontColor(TC.accentSoft())
          if (item.extra) {
            Text(item.extra).fontSize(9).fontColor(TC.textQuaternary())
          }
        }
        Text(item.title).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(TC.textBody()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.subtitle) {
          Text(item.subtitle).width('100%').fontSize(11).fontColor(TC.textTertiary())
            .maxLines(item.kind === '歌词' ? 2 : 1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (item.songIndex >= 0) {
        SymbolGlyph($r('sys.symbol.play_circle')).fontSize(23).fontColor([TC.textSecondary()])
      } else if (item.playlist || item.uid) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([TC.textQuaternary()])
      }
    }
    .width('100%').padding({ left: 14, right: 16, top: 8, bottom: 8 })
    .onClick(() => this.openItem(item))
  }

  /** 长按历史气泡时在上方浮出的删除按钮，点击立即删除、不弹窗。 */
  @Builder
  private DeleteBubble(word: string) {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor([TC.accent()])
      Text('删除').fontSize(12).fontColor(TC.accent())
    }
    .padding({ left: 14, right: 14, top: 9, bottom: 9 })
    .onClick(() => this.deleteHistoryWord(word))
  }

  /** 搜索历史：本地保存、气泡展示、可展开/收起、可清空。 */
  @Builder
  private HistorySection() {
    Column({ space: 10 }) {
      Row() {
        Text('搜索历史').fontSize(17).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        Blank()
        if (this.historyWords.length > 0) {
          SymbolGlyph(this.historyExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(16).fontColor([TC.textTertiary()])
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => this.historyExpanded = !this.historyExpanded)
          SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor([TC.textTertiary()])
            .padding({ left: 10, right: 4, top: 6, bottom: 6 })
            .onClick(() => this.confirmClearHistory())
        }
      }
      .width('100%')

      if (this.historyWords.length === 0) {
        Text('还没有搜索记录').width('100%').height(72).fontSize(12)
          .fontColor(TC.textQuaternary()).textAlign(TextAlign.Center)
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.visibleHistory(), (word: string) => {
            Text(word)
              .fontSize(12)
              .fontColor(TC.textBody())
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor(TC.chipBackground())
              .borderRadius(18)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => this.runKeyword(word))
              .gesture(
                LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
                  .onAction(() => { this.longPressedWord = word })
              )
              .bindPopup(this.longPressedWord === word, {
                builder: () => { this.DeleteBubble(word) },
                placement: Placement.Top,
                popupColor: TC.surfaceCard(),
                onStateChange: (event) => {
                  if (!event.isVisible && this.longPressedWord === word) {
                    this.longPressedWord = ''
                  }
                }
              })
          }, (word: string) => word)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SearchDiscovery() {
    Column() {
      this.HistorySection()

      Row() {
        Text('当前热搜').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        Text(`${this.hotSearches.length} 条`).fontSize(10).fontColor(TC.textQuaternary())
      }
      .width('100%').height(44).padding({ left: 16, right: 16 })

      if (this.discoveryLoading) {
        Column({ space: 10 }) {
          LoadingProgress().width(28).height(28).color(TC.accent())
          Text('正在获取热搜').fontSize(11).fontColor(TC.textTertiary())
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.hotSearches.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(34).fontColor([TC.textQuaternary()])
          Text('暂无热搜内容').fontSize(12).fontColor(TC.textTertiary())
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.hotSearches, (item: HotSearchItem, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Text((index + 1).toString()).width(27).fontSize(index < 3 ? 18 : 13)
                  .fontWeight(index < 3 ? FontWeight.Bold : FontWeight.Regular)
                  .fontColor(index < 3 ? TC.accent() : TC.textTertiary()).textAlign(TextAlign.Center)
                Column({ space: 5 }) {
                  Row({ space: 7 }) {
                    Text(item.searchWord).fontSize(14).fontWeight(index < 3 ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor(TC.textBody()).maxLines(1)
                    if (item.iconUrl && item.iconUrl.length > 0) {
                      Image(item.iconUrl).height(13).width(28).objectFit(ImageFit.Contain)
                    } else if (item.iconType === 1) {
                      Text('HOT').fontSize(8).fontColor(TC.accentSoft())
                    }
                  }
                  if (item.content && item.content.length > 0) {
                    Text(item.content).fontSize(10).fontColor(TC.textTertiary()).maxLines(1)
                  }
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (item.score && item.score > 0) {
                  Text(item.score.toString()).fontSize(9).fontColor(TC.textQuaternary())
                }
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([TC.textQuaternary()])
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
        Text('搜索建议').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        Text(this.keyword.trim()).fontSize(11).fontColor(TC.accentSoft()).maxLines(1)
      }
      .width('100%').height(48).padding({ left: 16, right: 16 })
      if (this.suggestionLoading) {
        LoadingProgress().layoutWeight(1).width(38).color(TC.accent())
      } else if (this.suggestionItems.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(36).fontColor([TC.textQuaternary()])
          Text('暂无搜索建议，按回车直接搜索').fontSize(12).fontColor(TC.textTertiary())
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
                      .fontSize(21).fontColor([TC.textSecondary()])
                  }
                  .width(50).height(50).borderRadius(10).backgroundColor(TC.chipBackground())
                }
                Column({ space: 5 }) {
                  Row({ space: 6 }) {
                    Text(item.kind).fontSize(9).fontColor(TC.accentSoft())
                    Text(item.title).layoutWeight(1).fontSize(14).fontColor(TC.textBody()).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  Text(item.subtitle).width('100%').fontSize(10).fontColor(TC.textTertiary()).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph(item.songIndex >= 0 ? $r('sys.symbol.play_circle') : $r('sys.symbol.chevron_right'))
                  .fontSize(20).fontColor([TC.textTertiary()])
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
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([TC.textOnMedia()])
          }
          .width(36).height(36).borderRadius(18).backgroundColor('rgba(0,0,0,0.35)')
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.pageStack.pop())
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor([TC.textTertiary()])
            TextInput({ text: this.keyword,
              placeholder: this.defaultKeyword || '歌曲、专辑、歌手、歌单、用户' })
              .layoutWeight(1).fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary())
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => this.onKeywordChange(value))
              .onSubmit(() => this.search())
            if (this.keyword) {
              SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(18).fontColor([TC.textQuaternary()])
                .onClick(() => {
                  this.onKeywordChange('')
                })
            }
          }
          .layoutWeight(1).height(42).padding({ left: 12, right: 12 })
          .backgroundColor(TC.surfaceCardAlt()).borderRadius(21)
          Button('搜索').fontSize(13).fontColor(TC.accentSoft()).backgroundColor(Color.Transparent)
            .onClick(() => this.search())
        }
        .width('100%').height(62).padding({ left: 14, right: 12 })

        if (this.searchedKeyword.length > 0) {
          Scroll() {
            Row({ space: 7 }) {
              ForEach(this.searchTabs, (tab: SearchTabItem) => {
                Text(tab.title)
                  .fontSize(11)
                  .fontColor(this.activeType === tab.type ? TC.textOnAccent() : TC.textTertiary())
                  .fontWeight(this.activeType === tab.type ? FontWeight.Bold : FontWeight.Regular)
                  .padding({ left: 13, right: 13, top: 8, bottom: 8 })
                  .backgroundColor(this.activeType === tab.type ? TC.accent() : TC.surfaceInset())
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
          LoadingProgress().layoutWeight(1).width(46).color(TC.accent())
        } else if (this.sections.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(44).fontColor([TC.textQuaternary()])
            Text(this.message).fontSize(13).fontColor(TC.textTertiary())
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.sections, (section: SearchSection) => {
              ListItem() {
                Column() {
                  Row() {
                    Text(section.title).layoutWeight(1).fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                    Text(`${section.items.length} 项`).fontSize(10).fontColor(TC.textQuaternary())
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
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
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
