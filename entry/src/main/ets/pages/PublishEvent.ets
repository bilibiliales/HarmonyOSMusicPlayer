import { ApiParam, ApiSong, mapApiSong, SearchResponse, ShareResourceResponse } from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'

export interface PublishEventPageParam {
  onPublished?: () => void
}

@Component
export struct PublishEventPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: PublishEventPageParam = {}

  @State content: string = ''
  @State selectedSongId: string = ''
  @State selectedSongName: string = ''
  @State selectedSongAuthor: string = ''
  @State selectedSongCover: string = ''
  @State publishing: boolean = false
  @State message: string = ''
  @State searchSheetVisible: boolean = false
  @State searchKeyword: string = ''
  @State searchLoading: boolean = false
  @State searchMessage: string = ''
  @State searchResults: songItemType[] = []

  aboutToAppear(): void {
    if (!this.authStore.loggedIn) {
      this.pageStack.replacePathByName('LoginPage', null)
    }
  }

  private canPublish(): boolean {
    return !this.publishing && (this.content.trim().length > 0 || this.selectedSongId.length > 0)
  }

  private async searchSongs(): Promise<void> {
    const keyword = this.searchKeyword.trim()
    if (!keyword || this.searchLoading) {
      return
    }
    this.searchLoading = true
    this.searchMessage = ''
    this.searchResults = []
    try {
      const response = await ApiClient.get<SearchResponse>('/search', [
        { key: 'keywords', value: keyword },
        { key: 'type', value: '1' },
        { key: 'limit', value: '30' },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code === 200 && response.result) {
        this.searchResults = (response.result.songs || []).map((song: ApiSong) => mapApiSong(song))
      }
      if (this.searchResults.length === 0) {
        this.searchMessage = '没有找到相关单曲'
      }
    } catch (error) {
      this.searchMessage = error instanceof Error ? error.message : '单曲搜索失败'
    } finally {
      this.searchLoading = false
    }
  }

  private selectSong(song: songItemType): void {
    this.selectedSongId = song.id
    this.selectedSongName = song.name
    this.selectedSongAuthor = song.author
    this.selectedSongCover = song.img
    this.searchSheetVisible = false
  }

  private clearSong(): void {
    this.selectedSongId = ''
    this.selectedSongName = ''
    this.selectedSongAuthor = ''
    this.selectedSongCover = ''
  }

  private async publish(): Promise<void> {
    if (!this.canPublish()) {
      return
    }
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.publishing = true
    this.message = ''
    try {
      const params: ApiParam[] = [
        { key: 'msg', value: this.content.trim() },
        { key: 'timestamp', value: Date.now().toString() }
      ]
      if (this.selectedSongId) {
        params.push({ key: 'type', value: 'song' })
        params.push({ key: 'id', value: this.selectedSongId })
      }
      const response = await ApiClient.get<ShareResourceResponse>('/share/resource', params)
      if (response.code !== 200) {
        throw new Error(response.message || '笔记发布失败')
      }
      this.pageParam.onPublished?.()
      this.pageStack.pop()
    } catch (error) {
      this.message = error instanceof Error ? error.message : '笔记发布失败'
    } finally {
      this.publishing = false
    }
  }

  @Builder
  private SearchSongSheet() {
    Column({ space: 14 }) {
      Row() {
        Text('添加歌曲').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Blank()
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(25).fontColor(['#6f6f77'])
          .onClick(() => this.searchSheetVisible = false)
      }.width('100%')

      Row({ space: 9 }) {
        TextInput({ text: this.searchKeyword, placeholder: '搜索歌曲名或歌手' })
          .layoutWeight(1).height(44).fontColor('#ffffff').placeholderColor('#66666e')
          .backgroundColor('#25252b').borderRadius(13).enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => this.searchKeyword = value)
          .onSubmit(() => this.searchSongs())
        Button('搜索').height(44).fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
          .borderRadius(13).enabled(!this.searchLoading).onClick(() => this.searchSongs())
      }.width('100%')

      if (this.searchLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(24).height(24).color('#ef233c')
          Text('正在搜索单曲…').fontSize(12).fontColor('#85858e')
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.searchMessage) {
        Text(this.searchMessage).layoutWeight(1).width('100%').fontSize(12).fontColor('#85858e')
          .textAlign(TextAlign.Center)
      } else if (this.searchResults.length > 0) {
        List({ space: 7 }) {
          ForEach(this.searchResults, (song: songItemType) => {
            ListItem() {
              Row({ space: 11 }) {
                Image(song.img).width(50).height(50).borderRadius(10).objectFit(ImageFit.Cover)
                Column({ space: 4 }) {
                  Text(song.name).width('100%').fontSize(13).fontWeight(FontWeight.Medium)
                    .fontColor('#f1f1f3').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${song.author}${song.album ? ` · ${song.album}` : ''}`).width('100%').fontSize(10)
                    .fontColor('#77777f').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.selectedSongId === song.id) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(22).fontColor(['#ef233c'])
                } else {
                  Text('添加').fontSize(11).fontColor('#ff6577')
                }
              }
              .width('100%').padding(9).backgroundColor('#232329').borderRadius(13)
              .onClick(() => this.selectSong(song))
            }
          })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      } else {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(38).fontColor(['#55555d'])
          Text('搜索并添加一首歌曲到笔记').fontSize(12).fontColor('#77777f')
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').height('100%').padding({ left: 18, right: 18, top: 14, bottom: 24 })
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row({ space: 12 }) {
          Text('取消').fontSize(14).fontColor('#a0a0a8').onClick(() => this.pageStack.pop())
          Text('发布笔记').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          Button(this.publishing ? '发布中' : '发布').height(36).fontSize(12).fontColor('#ffffff')
            .backgroundColor(this.canPublish() ? '#ef233c' : '#38383f').borderRadius(18)
            .enabled(this.canPublish()).onClick(() => this.publish())
        }.width('100%').height(58).padding({ left: 17, right: 17 })

        Scroll() {
          Column({ space: 18 }) {
            TextArea({ text: this.content, placeholder: '分享此刻的音乐与心情…' })
              .width('100%').height(220).fontSize(15).lineHeight(23).fontColor('#f1f1f3')
              .placeholderColor('#66666e').backgroundColor('#1b1b20').borderRadius(18).padding(16)
              .onChange((value: string) => this.content = value.substring(0, 1000))
            Text(`${this.content.length}/1000`).width('100%').fontSize(10).fontColor('#5f5f67')
              .textAlign(TextAlign.End).margin({ top: -12 })

            if (this.selectedSongId) {
              Row({ space: 11 }) {
                Image(this.selectedSongCover).width(58).height(58).borderRadius(11).objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Text(this.selectedSongName).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
                    .fontColor('#f1f1f3').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.selectedSongAuthor).width('100%').fontSize(11).fontColor('#77777f').maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(23).fontColor(['#686870'])
                  .onClick(() => this.clearSong())
              }.width('100%').padding(12).backgroundColor('#24242a').borderRadius(16)
            } else {
              Row({ space: 12 }) {
                Stack() {
                  SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(23).fontColor(['#ffffff'])
                }.width(48).height(48).borderRadius(14).backgroundColor('#ef233c')
                Column({ space: 4 }) {
                  Text('添加歌曲').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#f1f1f3')
                  Text('搜索并选择一首歌曲随笔记发布').fontSize(10).fontColor('#77777f')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor(['#686870'])
              }
              .width('100%').padding(13).backgroundColor('#1b1b20').borderRadius(16)
              .onClick(() => this.searchSheetVisible = true)
            }

            if (this.message) {
              Text(this.message).width('100%').padding(12).fontSize(11).lineHeight(18)
                .fontColor('#ff8b78').textAlign(TextAlign.Center).backgroundColor('#2b211f').borderRadius(13)
            }

            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.info_circle')).fontSize(16).fontColor(['#77777f'])
              Text('可发布纯文字笔记，也可以附带一首歌曲。').layoutWeight(1).fontSize(11)
                .lineHeight(18).fontColor('#77777f')
            }.width('100%').padding(13).backgroundColor('#18181d').borderRadius(13)
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 36 })
        }.layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').backgroundColor('#121215')
      .bindSheet(this.searchSheetVisible, this.SearchSongSheet(), {
        height: '68%', backgroundColor: '#19191f', showClose: false, dragBar: true,
        onDisappear: () => this.searchSheetVisible = false
      })
    }.hideTitleBar(true)
  }
}
