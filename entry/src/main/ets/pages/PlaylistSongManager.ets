import { ApiSong, mapApiSong, OperationResponse, SearchResponse } from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { TC } from '../services/ThemeColors'

export interface PlaylistSongManagerPageParam {
  mode: 'add' | 'order'
  playlistId: string
  playlistName: string
  songs: songItemType[]
  onChanged?: () => void
}

@Component
export struct PlaylistSongManagerPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: PlaylistSongManagerPageParam = {
    mode: 'add', playlistId: '', playlistName: '', songs: []
  }

  @State songs: songItemType[] = []
  @State keyword: string = ''
  @State results: songItemType[] = []
  @State loading: boolean = false
  @State saving: boolean = false
  @State message: string = ''
  @State addedSongIds: string[] = []
  private initialized: boolean = false

  aboutToAppear(): void {
    if (!this.initialized) {
      this.songs = this.pageParam.songs.map((song: songItemType) => song)
      this.initialized = true
    }
  }

  private containsSong(id: string): boolean {
    return this.songs.some((song: songItemType) => song.id === id) || this.addedSongIds.includes(id)
  }

  private async search(): Promise<void> {
    const value = this.keyword.trim()
    if (!value || this.loading) {
      return
    }
    this.loading = true
    this.message = ''
    this.results = []
    try {
      const response = await ApiClient.get<SearchResponse>('/search', [
        { key: 'keywords', value: value },
        { key: 'type', value: '1' },
        { key: 'limit', value: '40' },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code === 200 && response.result) {
        this.results = (response.result.songs || []).map((song: ApiSong) => mapApiSong(song))
      }
      if (this.results.length === 0) {
        this.message = '没有找到相关歌曲'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '歌曲搜索失败'
    } finally {
      this.loading = false
    }
  }

  private async addSong(song: songItemType): Promise<void> {
    if (this.containsSong(song.id)) {
      return
    }
    this.message = ''
    try {
      const response = await ApiClient.get<OperationResponse>('/playlist/tracks', [
        { key: 'op', value: 'add' },
        { key: 'pid', value: this.pageParam.playlistId },
        { key: 'tracks', value: song.id },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code !== 200) {
        throw new Error(response.message || '歌曲添加失败')
      }
      this.addedSongIds = this.addedSongIds.concat([song.id])
      this.pageParam.onChanged?.()
      this.message = `已添加《${song.name}》`
    } catch (error) {
      this.message = error instanceof Error ? error.message : '歌曲添加失败'
    }
  }

  private moveSong(index: number, offset: number): void {
    const target = index + offset
    if (target < 0 || target >= this.songs.length) {
      return
    }
    const next = this.songs.map((song: songItemType) => song)
    const moving = next[index]
    next[index] = next[target]
    next[target] = moving
    this.songs = next
  }

  private async saveOrder(): Promise<void> {
    if (this.saving || this.songs.length === 0) {
      return
    }
    this.saving = true
    this.message = ''
    try {
      const ids: number[] = this.songs.map((song: songItemType) => Number(song.id))
      const response = await ApiClient.get<OperationResponse>('/song/order/update', [
        { key: 'pid', value: this.pageParam.playlistId },
        { key: 'ids', value: JSON.stringify(ids) },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code !== 200) {
        throw new Error(response.message || '歌曲顺序保存失败')
      }
      this.pageParam.onChanged?.()
      this.pageStack.pop()
    } catch (error) {
      this.message = error instanceof Error ? error.message : '歌曲顺序保存失败'
    } finally {
      this.saving = false
    }
  }

  @Builder
  private AddContent() {
    Column({ space: 12 }) {
      Row({ space: 9 }) {
        TextInput({ text: this.keyword, placeholder: '搜索歌曲或歌手' }).layoutWeight(1).height(44)
          .fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceInset()).borderRadius(13)
          .enterKeyType(EnterKeyType.Search).onChange((value: string) => this.keyword = value)
          .onSubmit(() => this.search())
        Button('搜索').height(44).fontSize(12).fontColor(TC.textPrimary()).backgroundColor(TC.accent())
          .borderRadius(13).enabled(!this.loading).onClick(() => this.search())
      }.width('100%')
      if (this.loading) {
        LoadingProgress().layoutWeight(1).width(42).color(TC.accent())
      } else if (this.results.length > 0) {
        List({ space: 5 }) {
          ForEach(this.results, (song: songItemType) => {
            ListItem() {
              Row({ space: 11 }) {
                Image(song.img).width(50).height(50).borderRadius(10).objectFit(ImageFit.Cover)
                Column({ space: 4 }) {
                  Text(song.name).width('100%').fontSize(13).fontColor(TC.textBody()).maxLines(1)
                  Text(`${song.author}${song.album ? ` · ${song.album}` : ''}`).width('100%').fontSize(10)
                    .fontColor(TC.textTertiary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.containsSong(song.id)) {
                  Text('已添加').fontSize(11).fontColor(TC.textQuaternary())
                } else {
                  SymbolGlyph($r('sys.symbol.plus_circle_fill')).fontSize(24).fontColor([TC.accent()])
                    .onClick(() => this.addSong(song))
                }
              }.width('100%').height(66).padding({ left: 8, right: 8 })
            }
          })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      } else {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(40).fontColor([TC.textQuaternary()])
          Text('搜索后点击加号添加歌曲').fontSize(12).fontColor(TC.textTertiary())
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }

  @Builder
  private OrderContent() {
    Column() {
      Text('使用右侧按钮调整顺序，完成后点击保存').width('100%').fontSize(11).fontColor(TC.textTertiary())
        .padding({ left: 16, right: 16, bottom: 8 })
      List() {
        ForEach(this.songs, (song: songItemType, index: number) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(`${index + 1}`).width(28).fontSize(12).fontColor(index < 3 ? TC.accentSoft() : TC.textTertiary())
                .textAlign(TextAlign.Center)
              Image(song.img).width(46).height(46).borderRadius(9).objectFit(ImageFit.Cover)
              Column({ space: 4 }) {
                Text(song.name).width('100%').fontSize(13).fontColor(TC.textBody()).maxLines(1)
                Text(song.author).width('100%').fontSize(10).fontColor(TC.textTertiary()).maxLines(1)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.arrow_up_circle')).fontSize(22)
                .fontColor([index > 0 ? TC.textSecondary() : TC.textQuaternary()]).onClick(() => this.moveSong(index, -1))
              SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(22)
                .fontColor([index < this.songs.length - 1 ? TC.textSecondary() : TC.textQuaternary()])
                .onClick(() => this.moveSong(index, 1))
            }.width('100%').height(64).padding({ left: 12, right: 16 })
          }
        })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%')
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Column({ space: 2 }) {
            Text(this.pageParam.mode === 'add' ? '添加歌曲' : '调整歌曲顺序').fontSize(18)
              .fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
            Text(this.pageParam.playlistName).fontSize(9).fontColor(TC.textTertiary()).maxLines(1)
          }.layoutWeight(1).alignItems(HorizontalAlign.Center)
          if (this.pageParam.mode === 'order') {
            Button(this.saving ? '保存中' : '保存').height(36).fontSize(12).fontColor(TC.textPrimary())
              .backgroundColor(TC.accent()).borderRadius(18).enabled(!this.saving)
              .onClick(() => this.saveOrder())
          } else {
            Text('完成').fontSize(13).fontColor(TC.accentSoft()).onClick(() => this.pageStack.pop())
          }
        }.width('100%').height(60).padding({ left: 16, right: 16 })

        if (this.pageParam.mode === 'add') {
          this.AddContent()
        } else {
          this.OrderContent()
        }
        if (this.message) {
          Text(this.message).width('100%').fontSize(11)
            .fontColor(this.message.startsWith('已添加') ? '#65c98c' : '#ff8b78')
            .textAlign(TextAlign.Center).padding({ top: 8, bottom: 10 })
        }
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true)
  }
}
