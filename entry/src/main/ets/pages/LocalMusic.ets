import { common } from '@kit.AbilityKit'
import { LocalLibrary, LocalTrack } from '../services/LocalLibrary'
import { playerController } from '../services/PlayerController'
import { ApiClient } from '../services/ApiClient'
import { mapApiSong, SearchResponse } from '../models/api'
import { songItemType } from '../models/music'
import { BubbleTip } from '../services/BubbleTip'

@Component
export struct LocalMusicPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State tracks: LocalTrack[] = []
  @State query: string = ''
  @State newest: boolean = true
  @State loading: boolean = false
  @State message: string = ''
  @State matchVisible: boolean = false
  @State matchQuery: string = ''
  @State matches: songItemType[] = []
  @State searching: boolean = false
  @State searchMore: boolean = false
  @State matchMessage: string = ''
  @State matchTarget?: LocalTrack = undefined
  @State selectedMatch?: songItemType = undefined
  @State matching: boolean = false
  private generation: number = 0
  private searchGeneration: number = 0
  private searchOffset: number = 0
  private disposed: boolean = false

  aboutToDisappear(): void { this.disposed = true; this.generation++; this.searchGeneration++ }

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext }
  private visibleTracks(): LocalTrack[] {
    const query = this.query.trim().toLowerCase()
    return this.tracks.filter((item: LocalTrack) => (item.name + item.artist).toLowerCase().includes(query))
      .sort((a: LocalTrack, b: LocalTrack) => this.newest ? b.modified - a.modified : a.name.localeCompare(b.name))
  }

  private async load(): Promise<void> {
    const token = ++this.generation
    this.loading = true
    try {
      await LocalLibrary.init(this.context())
      if (token !== this.generation) { return }
      this.tracks = LocalLibrary.cached()
      const result = await LocalLibrary.scan()
      if (token === this.generation) { this.tracks = result.tracks; this.message = result.message }
    } catch (error) { if (token === this.generation) { this.message = error instanceof Error ? error.message : '读取本地音乐失败' } }
    finally { if (token === this.generation) { this.loading = false } }
  }

  private async importMusic(): Promise<void> {
    try { await LocalLibrary.importFiles(this.context()); await this.load() }
    catch (error) { this.message = error instanceof Error ? error.message : '导入失败' }
  }

  private async match(track: LocalTrack): Promise<void> {
    if (this.matching) { return }
    this.matching = true
    this.message = '正在读取文件标签并匹配歌曲…'
    try {
      const matched = await LocalLibrary.matchMetadata(track)
      playerController.refreshLocalMetadata(LocalLibrary.song(matched))
      if (!this.disposed) {
        this.tracks = LocalLibrary.cached()
        this.message = ''
        BubbleTip.show(this.getUIContext(), '已匹配歌曲，可用的封面和歌词已缓存')
      }
    } catch (error) {
      if (!this.disposed) {
        this.message = error instanceof Error ? error.message : '自动匹配失败，可尝试手动匹配'
        BubbleTip.show(this.getUIContext(), this.message)
      }
    } finally { if (!this.disposed) { this.matching = false } }
  }

  private matchOptions(track: LocalTrack): MenuElement[] {
    return [
      { value: track.songId ? '重新选择关联歌曲' : '手动匹配歌曲', action: () => this.openMatch(track) },
      { value: '自动匹配歌曲', action: () => this.match(track) }
    ]
  }

  private openMatch(track: LocalTrack): void {
    if (this.matching) { return }
    this.searchGeneration++
    this.matchTarget = track
    this.matchQuery = track.name + (track.artist && track.artist !== '本地音乐' ? ' ' + track.artist : '')
    this.matches = []
    this.selectedMatch = undefined
    this.matchMessage = ''
    this.searchMore = false
    this.searching = false
    this.searchOffset = 0
    this.matchVisible = true
    this.searchMatches(true)
  }

  private closeMatch(): void {
    this.matchVisible = false
    this.searchGeneration++
    this.searching = false
  }

  private changeMatchQuery(value: string): void {
    this.matchQuery = value
    this.searchGeneration++
    this.matches = []
    this.searching = false
    this.searchMore = false
    this.searchOffset = 0
    this.matchMessage = ''
  }

  private async searchMatches(reset: boolean): Promise<void> {
    const query = this.matchQuery.trim()
    if (!query || this.matching || !this.matchVisible || (!reset && (this.searching || !this.searchMore))) { return }
    const generation = ++this.searchGeneration
    if (reset) { this.matches = []; this.searchOffset = 0; this.searchMore = false }
    this.searching = true
    this.matchMessage = ''
    const offset = this.searchOffset
    try {
      const response = await ApiClient.get<SearchResponse>('/cloudsearch', [
        { key: 'keywords', value: query }, { key: 'type', value: '1' },
        { key: 'limit', value: '30' }, { key: 'offset', value: offset.toString() }
      ])
      if (generation !== this.searchGeneration || !this.matchVisible || this.disposed) { return }
      if (response.code !== 200) { throw new Error('搜索失败，请重试') }
      const songs = (response.result?.songs || []).map(mapApiSong)
      const incoming = songs.filter((song: songItemType) => /^\d+$/.test(song.id) &&
        !this.matches.some((item: songItemType) => item.id === song.id))
      this.matches = this.matches.concat(incoming)
      this.searchOffset = offset + songs.length
      this.searchMore = incoming.length > 0 && this.searchOffset < (response.result?.songCount || 0)
      if (!this.matches.length) { this.matchMessage = '未找到歌曲，试试歌名或歌手名' }
    } catch (error) {
      if (generation === this.searchGeneration && !this.disposed) {
        this.matchMessage = error instanceof Error ? error.message : '搜索失败，请重试'
      }
    } finally { if (generation === this.searchGeneration && !this.disposed) { this.searching = false } }
  }

  private async confirmMatch(): Promise<void> {
    const track = this.matchTarget
    const song = this.selectedMatch
    if (!track || !song || this.matching) { return }
    this.matching = true
    this.matchMessage = ''
    try {
      const matched = await LocalLibrary.linkMetadata(track, song)
      playerController.refreshLocalMetadata(LocalLibrary.song(matched))
      if (!this.disposed) {
        this.tracks = LocalLibrary.cached()
        this.message = ''
        this.closeMatch()
        BubbleTip.show(this.getUIContext(), '已关联歌曲，可用的封面和歌词已保存到本机')
      }
    } catch (error) {
      if (!this.disposed) {
        this.matchMessage = error instanceof Error ? error.message : '保存关联失败，请重试'
        BubbleTip.show(this.getUIContext(), this.matchMessage)
      }
    } finally { if (!this.disposed) { this.matching = false } }
  }

  @Builder
  private MatchSheet() {
    Column({ space: 14 }) {
      Row() {
        Text(this.selectedMatch ? '确认关联歌曲' : '手动匹配歌曲').fontSize(19).fontWeight(FontWeight.Bold)
          .fontColor('#ffffff').layoutWeight(1)
        Text('关闭').fontSize(14).fontColor('#9999a1').enabled(!this.matching).onClick(() => this.closeMatch())
      }.width('100%')
      if (this.matchMessage) { Text(this.matchMessage).fontSize(12).fontColor('#ff6577') }
      if (this.selectedMatch) {
        Text('本地歌曲：' + (this.matchTarget?.name || '')).width('100%').fontSize(13).fontColor('#9999a1')
        Row({ space: 12 }) {
          Image(this.selectedMatch.img).width(64).height(64).objectFit(ImageFit.Cover).borderRadius(10)
          Column({ space: 6 }) {
            Text(this.selectedMatch.name).fontSize(17).fontColor('#ffffff').maxLines(2)
            Text(this.selectedMatch.author).fontSize(13).fontColor('#aaaaaf').maxLines(2)
            Text(this.selectedMatch.album || '').fontSize(12).fontColor('#888891').maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding(14).backgroundColor('#24242a').borderRadius(16)
        Text('关联信息保存到本机，继续播放原本的音频文件。').width('100%').fontSize(13).fontColor('#9999a1')
        Button(this.matching ? '正在保存…' : '确认关联').width('100%').backgroundColor('#ef233c')
          .enabled(!this.matching).onClick(() => this.confirmMatch())
        Button('重新选择').width('100%').backgroundColor('#303038').enabled(!this.matching)
          .onClick(() => { this.selectedMatch = undefined; this.matchMessage = '' })
        if (this.matching) { LoadingProgress().width(30).height(30).color('#ef233c') }
      } else {
        Text(this.matchTarget?.name || '').width('100%').fontSize(13).fontColor('#9999a1').maxLines(1)
        Search({ value: this.matchQuery, placeholder: '搜索要关联的歌名或歌手' })
          .onChange((value: string) => this.changeMatchQuery(value)).onSubmit(() => this.searchMatches(true))
          .searchButton('搜索').enabled(!this.matching)
        List({ space: 4 }) {
          ForEach(this.matches, (song: songItemType) => {
            ListItem() {
              Row({ space: 12 }) {
                Image(song.img).width(46).height(46).objectFit(ImageFit.Cover).borderRadius(8)
                Column({ space: 5 }) {
                  Text(song.name).fontSize(15).fontColor('#ffffff').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(song.author + ' · ' + (song.album || '')).fontSize(12).fontColor('#9999a1').maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor(['#777780'])
              }.width('100%').padding({ top: 10, bottom: 10 }).enabled(!this.matching)
                .onClick(() => { this.selectedMatch = song; this.matchMessage = ''; this.searchGeneration++; this.searching = false })
            }
          }, (song: songItemType) => song.id)
          ListItem() {
            Column() {
              if (this.searching) { LoadingProgress().width(28).height(28).color('#ef233c') }
              else if (this.matchMessage) {
                Text('重新搜索').fontSize(13).fontColor('#ff6577').onClick(() => this.searchMatches(true))
              } else if (this.searchMore) {
                Text('加载更多').fontSize(13).fontColor('#9999a1').onClick(() => this.searchMatches(false))
              } else if (this.matches.length > 0) { Text('已显示全部结果').fontSize(12).fontColor('#777780') }
            }.width('100%').padding(18)
          }
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).onReachEnd(() => this.searchMatches(false))
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 12, bottom: 22 }).alignItems(HorizontalAlign.Start)
  }

  private async authorize(track: LocalTrack): Promise<void> {
    try { await LocalLibrary.reauthorize(this.context(), track); await this.load() }
    catch (error) { this.message = error instanceof Error ? error.message : '授权失败' }
  }

  private async play(index: number): Promise<void> {
    const tracks = this.visibleTracks()
    if (!tracks.length) { return }
    await playerController.setQueue(tracks.map((track: LocalTrack) => LocalLibrary.song(track)), index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  build() {
    NavDestination() {
      Column({ space: 14 }) {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
          Text('本地与下载').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#ffffff').layoutWeight(1)
          Text('导入').fontSize(14).fontColor('#ef4058').onClick(() => this.importMusic())
        }.width('100%')
        TextInput({ text: this.query, placeholder: '查找本地音乐' }).onChange((value: string) => this.query = value)
          .fontColor('#ffffff').backgroundColor('#222228')
        Row({ space: 16 }) {
          Text('播放全部 · ' + this.visibleTracks().length).fontSize(14).fontColor('#ffffff')
            .layoutWeight(1).onClick(() => this.play(0))
          Text(this.newest ? '最近添加' : '名称排序').fontSize(12).fontColor('#aaaaaf').onClick(() => this.newest = !this.newest)
          Text(this.loading ? '扫描中' : '扫描').fontSize(12).fontColor('#ef4058').enabled(!this.loading).onClick(() => this.load())
        }.width('100%')
        if (this.message) { Text(this.message).fontSize(12).fontColor('#ef8795') }
        List({ space: 8 }) {
          ForEach(this.visibleTracks(), (track: LocalTrack, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                if (track.cover) { Image(track.cover).width(42).height(42).borderRadius(6).objectFit(ImageFit.Cover) }
                else { SymbolGlyph($r('sys.symbol.music')).fontSize(24).fontColor(['#b8b8c0']) }
                Column({ space: 5 }) {
                  Text(track.name).fontSize(15).fontColor('#ffffff').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(track.artist + ' · ' + track.format.toUpperCase() + ' · ' + (track.size / 1048576).toFixed(1) + ' MB')
                    .fontSize(11).fontColor('#888891').maxLines(1)
                  if (!track.persistent) { Text('再次访问可能需要授权').fontSize(10).fontColor('#d59a74') }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.play(index))
                SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(21).fontColor(['#aaaaaf']).padding(8)
                  .enabled(!this.matching).bindMenu(this.matchOptions(track))
                if (!track.managed) {
                  Text('授权').fontSize(12).fontColor('#aaaaaf').padding(10).onClick(() => this.authorize(track))
                }
              }.width('100%').padding({ top: 10, bottom: 10 })
            }
          }, (track: LocalTrack) => track.uri)
          if (!this.loading && this.tracks.length === 0) {
            ListItem() { Text('下载歌曲或导入本地文件，即可离线播放').fontSize(13).fontColor('#888891').padding({ top: 40 }) }
          }
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        Text('重新选择下载目录').fontSize(12).fontColor('#9999a4').onClick(async () => {
          try { await LocalLibrary.chooseDirectory(this.context()); await this.load() }
          catch (error) { this.message = error instanceof Error ? error.message : '目录授权失败' }
        })
      }.width('100%').height('100%').padding({ top: this.topAvoidHeight + 12, left: 20, right: 20, bottom: 24 })
        .backgroundColor('#121215')
        .bindSheet(this.matchVisible, this.MatchSheet(), {
          height: '74%', backgroundColor: '#19191f', showClose: false, dragBar: true,
          onDisappear: () => this.closeMatch()
        })
    }.hideTitleBar(true).onShown(() => this.load())
  }
}
