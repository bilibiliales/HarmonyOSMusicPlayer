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
  StyleSongResponse,
  StyleTag,
  StyleListResponse,
  StylePageInfo
} from '../models'
import { PlaylistCoverPreviewPageParam } from './PlaylistCoverPreview'
import { ApiClient } from '../services/ApiClient'
import { styleReviewText, styleRoots, stylePath, filterStyleTree, styleImageUrl, nextStyleCursor } from '../services/StylePresentation'
import { common } from '@kit.AbilityKit'
import { SystemShareService } from '../services/SystemShareService'
import { BubbleTip } from '../services/BubbleTip'
import { resizeImageUrl } from '../services/ImageUrl'
import { playerController } from '../services/PlayerController'

class StyleResourceState {
  cursor: string = '0'
  more: boolean = true
  loaded: boolean = false
  loading: boolean = false
  error: string = ''
  sort: number = 0
  revision: number = 0
  cursors: string[] = []
}

function createStyleResources(): Record<string, StyleResourceState> {
  const states: Record<string, StyleResourceState> = {}
  for (const tab of ['songs', 'albums', 'playlists', 'artists']) { states[tab] = new StyleResourceState() }
  return states
}

@Component
export struct StyleDetailPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: StyleDetailPageParam = { tagId: 0, name: '' }

  @State detail?: StyleDetailData = undefined
  @State selectedTag: StyleDetailPageParam = { tagId: 0, name: '' }
  @State currentTab: string = 'songs'
  @State songs: songItemType[] = []
  @State albums: ApiAlbum[] = []
  @State playlists: StylePlaylistItem[] = []
  @State artists: ApiArtist[] = []
  @State loading: boolean = true
  @State resourceLoading: boolean = false
  @State resourceMore: boolean = true
  @State resourceMessage: string = ''
  @State sortKey: number = 0
  @State message: string = ''
  @State tree: StyleTag[] = []
  @State treeLoading: boolean = false
  @State treeMessage: string = ''
  @State pickerVisible: boolean = false
  @State draftTagId: number = 0
  @State expandedTags: number[] = []
  @State pickerQuery: string = ''
  @State preparingShare: boolean = false
  @State headerCollapsed: boolean = false
  @State reviewVisible: boolean = false
  @State reviewKind: string = 'review'
  @State reviewCardWidth: number = 310
  private scroller: Scroller = new Scroller()
  private epoch: number = 0
  private alive: boolean = true
  private resources: Record<string, StyleResourceState> = createStyleResources()

  aboutToAppear(): void {
    this.alive = true
    this.selectedTag = this.pageParam
    this.loadTree()
    this.loadPage()
  }

  aboutToDisappear(): void {
    this.alive = false
    this.epoch++
  }

  private async loadTree(): Promise<void> {
    if (this.treeLoading) { return }
    this.treeLoading = true
    this.treeMessage = ''
    try {
      const response = await ApiClient.get<StyleListResponse>('/style/list')
      if (!this.alive) { return }
      if (response.code !== 200 || !response.data?.length) { throw new Error('曲风分类加载失败') }
      this.tree = styleRoots(response.data)
      if (this.pickerVisible) { this.expandSelection() }
    } catch (error) {
      if (this.alive) { this.treeMessage = error instanceof Error ? error.message : '曲风分类加载失败' }
    } finally {
      if (this.alive) { this.treeLoading = false }
    }
  }

  private async loadPage(): Promise<void> {
    const generation = ++this.epoch
    const tagId = this.selectedTag.tagId
    this.loading = true
    this.reviewVisible = false
    this.detail = undefined
    this.message = ''
    this.songs = []
    this.albums = []
    this.playlists = []
    this.artists = []
    this.resources = createStyleResources()
    this.syncResourceState()
    if (tagId <= 0) {
      this.loading = false
      this.message = '曲风参数无效'
      return
    }
    try {
      const response = await ApiClient.get<StyleDetailResponse>('/style/detail', [
        { key: 'tagId', value: String(tagId) }
      ])
      if (generation !== this.epoch) { return }
      if (response.code !== 200 || !response.data) { throw new Error('曲风详情加载失败') }
      this.detail = response.data
      this.loading = false
      await this.loadCurrentResources()
    } catch (error) {
      if (generation === this.epoch) { this.message = error instanceof Error ? error.message : '曲风详情加载失败' }
    } finally {
      if (generation === this.epoch) { this.loading = false }
    }
  }

  private availableTabs(): string[] {
    // detail.tabs describes the official landing page, not endpoint availability.
    return ['songs', 'albums', 'playlists', 'artists']
  }

  private syncResourceState(): void {
    const state = this.resources[this.currentTab]
    this.resourceLoading = state.loading
    this.resourceMore = state.more
    this.resourceMessage = state.error
    this.sortKey = state.sort
  }

  private resetTab(tab: string): void {
    if (tab === 'albums') { this.albums = [] }
    else if (tab === 'playlists') { this.playlists = [] }
    else if (tab === 'artists') { this.artists = [] }
    else { this.songs = [] }
    const state = this.resources[tab]
    state.cursor = '0'
    state.more = true
    state.loaded = false
    state.error = ''
    state.cursors = []
  }

  private tabHasData(tab: string): boolean {
    if (tab === 'albums') { return this.albums.length > 0 }
    if (tab === 'playlists') { return this.playlists.length > 0 }
    if (tab === 'artists') { return this.artists.length > 0 }
    return this.songs.length > 0
  }

  private finishPage(state: StyleResourceState, page: StylePageInfo | undefined,
    cursor: string, count: number, added: number): void {
    state.loaded = true
    state.cursors.push(cursor)
    const next = nextStyleCursor(page, cursor, count)
    state.more = next !== undefined && added > 0 && !state.cursors.includes(next)
    if (state.more && next !== undefined) { state.cursor = next }
    if (page?.more && !state.more) {
      state.error = '接口未返回有效的下一页，已停止重复加载'
    }
  }

  private async loadCurrentResources(reset: boolean = false): Promise<void> {
    if (!this.detail) { return }
    const tab = this.currentTab
    const state = this.resources[tab]
    if (!reset && (state.loading || !state.more)) { return }
    if (reset) { this.resetTab(tab) }
    const revision = ++state.revision
    const generation = this.epoch
    const cursor = state.cursor
    const params = this.resourceParams(cursor, tab, state.sort)
    state.loading = true
    state.error = ''
    this.syncResourceState()
    try {
      if (tab === 'albums') {
        const response = await ApiClient.get<StyleAlbumResponse>('/style/album', params)
        if (generation !== this.epoch || revision !== state.revision) { return }
        if (response.code !== 200 || !response.data) { throw new Error('曲风专辑加载失败') }
        const incoming = response.data.albums || []
        const seen = new Set(this.albums.map((item: ApiAlbum) => item.id))
        const added = incoming.filter((item: ApiAlbum) => {
          if (seen.has(item.id)) { return false }
          seen.add(item.id)
          return true
        })
        this.albums = this.albums.concat(added)
        this.finishPage(state, response.data.page, cursor, incoming.length, added.length)
      } else if (tab === 'playlists') {
        const response = await ApiClient.get<StylePlaylistResponse>('/style/playlist', params)
        if (generation !== this.epoch || revision !== state.revision) { return }
        if (response.code !== 200 || !response.data) { throw new Error('曲风歌单加载失败') }
        const incoming = response.data.playlist || []
        const seen = new Set(this.playlists.map((item: StylePlaylistItem) => item.id))
        const added = incoming.filter((item: StylePlaylistItem) => {
          if (seen.has(item.id)) { return false }
          seen.add(item.id)
          return true
        })
        this.playlists = this.playlists.concat(added)
        this.finishPage(state, response.data.page, cursor, incoming.length, added.length)
      } else if (tab === 'artists') {
        const response = await ApiClient.get<StyleArtistResponse>('/style/artist', params)
        if (generation !== this.epoch || revision !== state.revision) { return }
        if (response.code !== 200 || !response.data) { throw new Error('曲风歌手加载失败') }
        const incoming = response.data.artists || []
        const seen = new Set(this.artists.map((item: ApiArtist) => item.id))
        const added = incoming.filter((item: ApiArtist) => {
          if (seen.has(item.id)) { return false }
          seen.add(item.id)
          return true
        })
        this.artists = this.artists.concat(added)
        this.finishPage(state, response.data.page, cursor, incoming.length, added.length)
      } else {
        const response = await ApiClient.get<StyleSongResponse>('/style/song', params)
        if (generation !== this.epoch || revision !== state.revision) { return }
        if (response.code !== 200 || !response.data) { throw new Error('曲风歌曲加载失败') }
        const incoming = (response.data.songs || []).map((song) => mapApiSong(song))
        const seen = new Set(this.songs.map((item: songItemType) => item.id))
        const added = incoming.filter((item: songItemType) => {
          if (seen.has(item.id)) { return false }
          seen.add(item.id)
          return true
        })
        this.songs = this.songs.concat(added)
        this.finishPage(state, response.data.page, cursor, incoming.length, added.length)
      }
    } catch (error) {
      if (generation === this.epoch && revision === state.revision) {
        state.error = error instanceof Error ? error.message : '曲风内容加载失败'
      }
    } finally {
      if (generation === this.epoch && revision === state.revision) {
        state.loading = false
        if (tab === this.currentTab) { this.syncResourceState() }
      }
    }
  }

  private resourceParams(cursor: string, tab: string, sort: number): ApiParam[] {
    const params: ApiParam[] = [
      { key: 'tagId', value: String(this.selectedTag.tagId) },
      { key: 'size', value: '20' },
      { key: 'cursor', value: cursor }
    ]
    if (tab === 'songs' || tab === 'albums') { params.push({ key: 'sort', value: String(sort) }) }
    return params
  }

  private async switchTab(tab: string): Promise<void> {
    if (this.currentTab === tab) { return }
    this.currentTab = tab
    this.syncResourceState()
    if (!this.resources[tab].loaded) { await this.loadCurrentResources() }
  }

  private async changeSort(sort: number): Promise<void> {
    if (this.currentTab !== 'songs' && this.currentTab !== 'albums') { return }
    const state = this.resources[this.currentTab]
    if (state.sort === sort) { return }
    state.sort = sort
    await this.loadCurrentResources(true)
  }

  private cover(): string {
    return styleImageUrl(this.detail?.cover?.[0] || this.selectedTag.cover)
  }

  private name(): string {
    return this.detail?.name || this.selectedTag.name || '曲风'
  }

  private parentName(): string {
    const path = stylePath(this.tree, this.selectedTag.tagId)
    return path.length > 1 ? path.slice(0, -1).map((tag: StyleTag) => tag.tagName).join(' / ') : this.detail?.parentNames || ''
  }

  private expandSelection(): void {
    this.expandedTags = stylePath(this.tree, this.draftTagId).map((tag: StyleTag) => tag.tagId)
  }

  private openPicker(): void {
    this.draftTagId = this.selectedTag.tagId
    this.pickerQuery = ''
    this.expandSelection()
    this.pickerVisible = true
    if (!this.tree.length) { this.loadTree() }
  }

  private toggleExpanded(tagId: number): void {
    this.expandedTags = this.expandedTags.includes(tagId) ?
      this.expandedTags.filter((id: number) => id !== tagId) : this.expandedTags.concat([tagId])
  }

  private expanded(tag: StyleTag): boolean {
    return this.pickerQuery.trim().length > 0 || this.expandedTags.includes(tag.tagId)
  }

  private async confirmStyle(): Promise<void> {
    const path = stylePath(this.tree, this.draftTagId)
    if (!path.length) { return }
    this.pickerVisible = false
    if (this.draftTagId === this.selectedTag.tagId) { return }
    const tag = path[path.length - 1]
    this.selectedTag = {
      tagId: tag.tagId, name: tag.tagName, cover: styleImageUrl(tag.picUrl),
      colorDeep: tag.colorDeep, colorShallow: tag.colorShallow
    }
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 })
    await this.loadPage()
  }

  private async shareStyle(): Promise<void> {
    if (this.preparingShare || !this.detail) { return }
    this.preparingShare = true
    try {
      // The style API has no universal share URL. Share the actual description
      // and cover, without fabricating a web route or sharing private preferences.
      await SystemShareService.showText(this.getUIContext().getHostContext() as common.UIAbilityContext, {
        content: this.name() + (this.detail.enName ? ' · ' + this.detail.enName : '') +
          '\n\n' + (this.detail.desc || '') + '\n\n网易云音乐 · 曲风',
        title: this.name(), description: this.detail.desc || '网易云音乐曲风', label: '曲风', image: this.cover()
      })
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '无法打开系统分享面板')
    } finally { this.preparingShare = false }
  }

  private previewCover(): void {
    if (!this.detail) { return }
    const param: PlaylistCoverPreviewPageParam = {
      playlist: { id: String(this.selectedTag.tagId), name: this.name(), cover: this.cover(), count: 0, creator: '' },
      playCount: 0, collectCount: 0, commentCount: 0, contentType: 'style',
      tags: [this.parentName(), this.detail.enName || ''].filter((value: string) => value.length > 0),
      description: this.detail.desc || '暂无曲风介绍',
      songCountText: this.detail.songNum, artistCountText: this.detail.artistNum
    }
    this.pageStack.pushPathByName('PlaylistCoverPreviewPage', param)
  }

  private reviewText(kind: string): string {
    return styleReviewText(kind === 'review' ? this.detail?.professionalReviews : this.detail?.tagPortrait)
  }

  private reviewTip(kind: string): string {
    return (kind === 'review' ? this.detail?.professionalReviews?.dataTip : this.detail?.tagPortrait?.dataTip) || ''
  }

  private openReview(kind: string): void {
    this.reviewKind = kind
    this.reviewVisible = true
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
    if (!this.songs.length) { return }
    try { await playerController.setQueue(this.songs, index, true) }
    catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败') }
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
          .backgroundColor('#202026').onClick(() => this.previewCover())
        Text('点击封面查看曲风介绍').fontSize(10).fontColor('#9999a3').onClick(() => this.previewCover())
        Text(this.name()).fontSize(25).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        if (this.detail?.enName) {
          Text(this.detail.enName).fontSize(11).fontColor('#b0b0b7')
        }
        Row({ space: 15 }) {
          Text(`${this.detail?.songNum || '-'} 首歌曲`).fontSize(10).fontColor('#bdbdc4')
          Text(`${this.detail?.artistNum || '-'} 位歌手`).fontSize(10).fontColor('#bdbdc4')
        }
      }.width('100%').padding({ bottom: 20 })
    }.width('100%').height(300 + this.topAvoidHeight + 54)
      .backgroundColor('#202026')
  }

  @Builder
  private NavigationBar() {
    Column() {
      Column().width('100%').height(this.topAvoidHeight)
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
          .width(44).height(44).onClick(() => this.pageStack.pop())
        Column({ space: 2 }) {
          if (this.parentName()) {
            Text(this.parentName()).fontSize(10).fontColor('#c0c0c8').maxLines(1)
          }
          Row({ space: 7 }) {
            Text(this.name()).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '80%' })
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor(['#eeeeee'])
          }.justifyContent(FlexAlign.Center)
        }.layoutWeight(1).onClick(() => this.openPicker())
        SymbolGlyph($r('sys.symbol.share')).fontSize(23).fontColor(['#ffffff'])
          .width(44).height(44).enabled(!this.preparingShare && !!this.detail).onClick(() => this.shareStyle())
      }.height(54).width('100%').padding({ left: 6, right: 6 })
    }.width('100%').backgroundColor(this.headerCollapsed ? '#121215' : Color.Transparent)
      .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0.45)', 0], ['rgba(0,0,0,0)', 1]] })
  }

  @Builder
  private PickerRow(tag: StyleTag, depth: number) {
    Row({ space: 8 }) {
      Text(tag.tagName).fontSize(depth === 0 ? 17 : 14)
        .fontWeight(depth === 0 ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.draftTagId === tag.tagId ? '#ff6577' : '#eeeeee')
        .layoutWeight(1).padding({ top: 15, bottom: 15 })
        .onClick(() => this.draftTagId = tag.tagId)
      if (this.draftTagId === tag.tagId) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(17).fontColor(['#ef233c'])
      }
      if ((tag.childrenTags || []).length > 0) {
        SymbolGlyph(this.expanded(tag) ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(14).fontColor(['#9898a2']).width(40).height(46)
          .onClick(() => this.toggleExpanded(tag.tagId))
      }
    }.width('100%').padding({ left: depth === 0 ? 0 : 16 })
  }

  @Builder
  private StylePicker() {
    Column({ space: 10 }) {
      Row() {
        Text('取消').fontSize(15).fontColor('#9999a3').width(52).onClick(() => this.pickerVisible = false)
        Text('选择曲风').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('完成').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#ff6577').width(52).textAlign(TextAlign.End)
          .enabled(stylePath(this.tree, this.draftTagId).length > 0).onClick(() => this.confirmStyle())
      }.width('100%').height(44)
      Search({ value: this.pickerQuery, placeholder: '搜索曲风名称' })
        .fontColor('#eeeeee').placeholderColor('#888892').backgroundColor('#27272e')
        .onChange((value: string) => this.pickerQuery = value)
      if (this.treeLoading) {
        LoadingProgress().width(32).height(32).color('#ef233c').margin(20)
      } else if (this.treeMessage) {
        Text(this.treeMessage).fontSize(13).fontColor('#ff6577').padding(18)
        Button('重试').backgroundColor('#303038').onClick(() => this.loadTree())
      } else {
        List() {
          ForEach(filterStyleTree(this.tree, this.pickerQuery), (root: StyleTag) => {
            ListItem() {
              Column() {
                this.PickerRow(root, 0)
                if (this.expanded(root)) {
                  ForEach(root.childrenTags || [], (child: StyleTag) => {
                    this.PickerRow(child, 1)
                    if (this.expanded(child)) {
                      Flex({ wrap: FlexWrap.Wrap }) {
                        ForEach(child.childrenTags || [], (leaf: StyleTag) => {
                          Text(leaf.tagName).fontSize(12)
                            .fontColor(this.draftTagId === leaf.tagId ? '#ff6577' : '#b4b4be')
                            .backgroundColor(this.draftTagId === leaf.tagId ? '#3b2028' : '#26262d')
                            .padding({ left: 13, right: 13, top: 9, bottom: 9 }).borderRadius(18)
                            .margin({ right: 8, bottom: 9 }).onClick(() => this.draftTagId = leaf.tagId)
                        }, (leaf: StyleTag) => String(leaf.tagId))
                      }.width('100%').padding({ left: 16, top: 5, bottom: 4 })
                    }
                  }, (child: StyleTag) => String(child.tagId))
                }
              }.width('100%')
            }
          }, (root: StyleTag) => String(root.tagId) + ':' + this.pickerQuery.trim().toLowerCase())
          if (filterStyleTree(this.tree, this.pickerQuery).length === 0) {
            ListItem() {
              Text('未找到匹配的曲风').fontSize(13).fontColor('#8b8b95').width('100%').padding(32)
                .textAlign(TextAlign.Center)
            }
          }
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, bottom: 18 })
  }

  @Builder
  private ReviewCard(kind: string) {
    Column({ space: 13 }) {
      Row() {
        Text(kind === 'review' ? '专业点评' : '用户画像').fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor('#eeeeF2').layoutWeight(1)
        Row({ space: 4 }) {
          Text('展开').fontSize(12).fontColor('#92929c')
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11).fontColor(['#92929c'])
        }
      }.width('100%')
      Text(this.reviewText(kind)).width('100%').fontSize(14).lineHeight(23).fontColor('#bcbcc6')
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank()
      if (this.reviewTip(kind)) {
        Text(this.reviewTip(kind)).fontSize(10).fontColor('#787883').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width(this.reviewCardWidth).height(166).padding(17).alignItems(HorizontalAlign.Start)
      .backgroundColor('#202027').borderRadius(16).onClick(() => this.openReview(kind))
  }

  @Builder
  private ReviewDetails() {
    Column({ space: 16 }) {
      Row() {
        Text(this.reviewKind === 'review' ? '专业点评' : '用户画像').fontSize(20)
          .fontWeight(FontWeight.Bold).fontColor('#ffffff').layoutWeight(1)
        Text('收起').fontSize(14).fontColor('#aaaaB5').padding(8).onClick(() => this.reviewVisible = false)
      }.width('100%')
      Scroll() {
        Column({ space: 20 }) {
          Text(this.reviewText(this.reviewKind)).width('100%').fontSize(16).lineHeight(28).fontColor('#d0d0d8')
          if (this.reviewTip(this.reviewKind)) {
            Text(this.reviewTip(this.reviewKind)).width('100%').fontSize(12).lineHeight(20).fontColor('#85858f')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 24 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').padding({ left: 22, right: 22, top: 12, bottom: 20 })
  }

  @Builder
  private Description() {
    if (this.reviewText('review') || this.reviewText('portrait')) {
      Scroll() {
        Row({ space: 12 }) {
          if (this.reviewText('review')) { this.ReviewCard('review') }
          if (this.reviewText('portrait')) { this.ReviewCard('portrait') }
        }.padding({ left: 16, right: 16 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .margin({ bottom: 16 })
        .onAreaChange((_old: Area, area: Area) => {
          this.reviewCardWidth = Math.max(220, Math.min(420, Number(area.width) - 48))
        })
        .bindSheet(this.reviewVisible, this.ReviewDetails(), {
          height: '70%', backgroundColor: '#19191f', showClose: false, dragBar: true,
          onDisappear: () => this.reviewVisible = false
        })
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
      }.width('94%').padding(11).backgroundColor('#1d1d22').borderRadius(14)
        .margin({ left: 16, right: 16, bottom: 13 })
        .onClick(() => {
          const song = this.detail?.favouriteSong?.favouriteSong
          if (song) { playerController.setQueue([mapApiSong(song)], 0, true) }
        })
    }
  }

  @Builder
  private ResourceTabs() {
    Row() {
      ForEach(this.availableTabs(), (tab: string) => {
        Column({ space: 7 }) {
          Text(tab === 'songs' ? '歌曲' : tab === 'albums' ? '专辑' : tab === 'playlists' ? '歌单' : '歌手')
            .fontSize(13).fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.currentTab === tab ? '#ffffff' : '#717179')
          Column().width(this.currentTab === tab ? 24 : 0).height(3).borderRadius(2).backgroundColor('#ef233c')
        }.layoutWeight(1).height(48).justifyContent(FlexAlign.Center).onClick(() => this.switchTab(tab))
      })
    }.width('100%')
  }

  @Builder
  private ResourceActions() {
    if (this.currentTab === 'songs' || this.currentTab === 'albums') {
      Row({ space: 12 }) {
        if (this.currentTab === 'songs') {
          Row({ space: 7 }) {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor(['#ffffff'])
            Text('播放全部').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#ffffff')
            Text('(' + this.songs.length + ')').fontSize(11).fontColor('#898994')
          }.enabled(this.songs.length > 0).onClick(() => this.playSong(0))
        } else {
          Text('专辑').fontSize(14).fontColor('#ffffff')
        }
        Blank()
        ForEach([0, 1], (sort: number) => {
          Text(sort === 0 ? '最热' : '最新').fontSize(12)
            .fontColor(this.sortKey === sort ? '#ff6577' : '#85858f')
            .fontWeight(this.sortKey === sort ? FontWeight.Bold : FontWeight.Regular)
            .padding({ top: 12, bottom: 12 }).onClick(() => this.changeSort(sort))
        })
      }.width('100%').height(52).padding({ left: 17, right: 17 })
    }
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
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll(this.scroller) {
          Column() {
            this.Header()
            if (this.loading) {
              LoadingProgress().width(44).height(44).color('#ef233c').margin(40)
            } else if (!this.detail) {
              Text(this.message || '曲风详情加载失败').fontSize(13).fontColor('#9999a3').padding(25)
              Button('重试').backgroundColor('#303038').onClick(() => this.loadPage())
            } else {
              this.Description()
              this.ResourceTabs()
              this.ResourceActions()
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
              } else if (this.resourceMessage) {
                Text(this.resourceMessage).width('100%').fontSize(12).fontColor('#ff6577').textAlign(TextAlign.Center).padding(20)
                Button('重试').backgroundColor('#303038').onClick(() => this.loadCurrentResources(!this.resourceMore))
              } else if (!this.tabHasData(this.currentTab)) {
                Text('暂无内容').width('100%').height(160).fontSize(12).fontColor('#77777f').textAlign(TextAlign.Center)
              } else {
                Text(this.resourceMore ? '加载更多' : '已经到底了').width('100%').height(52)
                  .fontSize(11).fontColor('#888892').textAlign(TextAlign.Center)
                  .onClick(() => this.loadCurrentResources())
              }
            }
            Blank().height(30)
          }.width('100%')
        }.width('100%').height('100%').scrollBar(BarState.Off)
          .onReachEnd(() => this.loadCurrentResources())
          .onDidScroll(() => this.headerCollapsed = this.scroller.currentOffset().yOffset > 220)
        this.NavigationBar()
      }.width('100%').height('100%').backgroundColor('#121215')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        .bindSheet(this.pickerVisible, this.StylePicker(), {
          height: '78%', backgroundColor: '#19191f', showClose: false, dragBar: true,
          onDisappear: () => this.pickerVisible = false
        })
    }.hideTitleBar(true)
      .onBackPressed(() => {
        if (this.reviewVisible) { this.reviewVisible = false; return true }
        if (this.pickerVisible) { this.pickerVisible = false; return true }
        return false
      })
  }
}
