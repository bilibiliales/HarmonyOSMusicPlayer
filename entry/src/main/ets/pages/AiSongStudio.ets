import { http } from '@kit.NetworkKit'
import {
  ApiSong,
  LikeListResponse,
  LyricResponse,
  mapApiSong,
  SearchResponse,
  SongDetailResponse
} from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { AppSettings } from '../services/AppSettings'
import { AuthStore } from '../stores/AuthStore'

interface AiMessage {
  role: string
  content: string
}

interface AiRequestBody {
  model: string
  messages: AiMessage[]
  temperature: number
}

interface AiResponseMessage {
  role?: string
  content: string
}

interface AiChoice {
  index?: number
  message: AiResponseMessage
}

interface AiResponse {
  choices?: AiChoice[]
  error?: AiError
}

interface AiError {
  message?: string
}

@Component
export struct AiSongStudioPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore

  @State mode: string = 'adapt'
  @State style: string = ''
  @State inspiration: string = ''
  @State seedLyrics: string = ''
  @State extraPrompt: string = ''
  @State result: string = ''
  @State generating: boolean = false
  @State polishing: boolean = false
  @State message: string = ''
  @State likedSongs: songItemType[] = []
  @State likedLoading: boolean = false
  @State selectedSongId: string = ''
  @State sourceLyrics: string = ''
  @State sourceLyricsMessage: string = ''
  @State lyricLoading: boolean = false
  @State searchSheetVisible: boolean = false
  @State searchKeyword: string = ''
  @State searchResults: songItemType[] = []
  @State searchLoading: boolean = false
  @State searchMessage: string = ''
  private baseUrl: string = ''
  private apiKey: string = ''
  private model: string = 'gpt-3.5-turbo'

  aboutToAppear(): void {
    this.baseUrl = AppSettings.aiBaseUrl
    this.apiKey = AppSettings.aiApiKey
    this.model = AppSettings.aiModel
    if (this.authStore.loggedIn) {
      this.loadLikedSongs()
    }
  }

  private async loadLikedSongs(): Promise<void> {
    if (this.likedLoading || !this.authStore.userId) {
      return
    }
    this.likedLoading = true
    try {
      const likeResponse = await ApiClient.get<LikeListResponse>('/likelist', [
        { key: 'uid', value: this.authStore.userId }
      ])
      if (likeResponse.code === 200 && likeResponse.ids.length > 0) {
        const ids = likeResponse.ids.slice(0, 30)
        const detailResponse = await ApiClient.get<SongDetailResponse>('/song/detail', [
          { key: 'ids', value: ids.join(',') }
        ])
        if (detailResponse.code === 200) {
          this.likedSongs = (detailResponse.songs || []).map((song: ApiSong) => mapApiSong(song))
        }
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '喜欢歌曲加载失败'
    } finally {
      this.likedLoading = false
    }
  }

  private selectedSong(): songItemType | undefined {
    return this.likedSongs.find((song: songItemType) => song.id === this.selectedSongId)
  }

  private async selectSong(song: songItemType): Promise<void> {
    if (!this.likedSongs.some((item: songItemType) => item.id === song.id)) {
      this.likedSongs = [song].concat(this.likedSongs)
    }
    this.selectedSongId = song.id
    this.sourceLyrics = ''
    this.sourceLyricsMessage = ''
    this.lyricLoading = true
    this.searchSheetVisible = false
    try {
      const response = await ApiClient.get<LyricResponse>('/lyric', [
        { key: 'id', value: song.id }
      ])
      if (response.nolyric) {
        this.sourceLyricsMessage = '该歌曲为纯音乐，暂无可用于风格改编的原歌词'
      } else if (response.uncollected || !response.lrc?.lyric) {
        this.sourceLyricsMessage = response.uncollected ? '歌词暂未收录，请更换其他歌曲' : '该歌曲暂无歌词，请更换其他歌曲'
      } else {
        this.sourceLyrics = response.lrc.lyric.replace(/\[[^\]]+\]/g, '').replace(/\n{3,}/g, '\n\n').trim()
        if (!this.sourceLyrics) {
          this.sourceLyricsMessage = '没有解析到有效歌词，请更换其他歌曲'
        }
      }
    } catch (error) {
      this.sourceLyrics = ''
      this.sourceLyricsMessage = error instanceof Error ? error.message : '原歌词加载失败'
    } finally {
      this.lyricLoading = false
    }
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
        { key: 'limit', value: '30' }
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

  private endpoint(): string {
    return this.baseUrl.trim() || 'https://api.openai.com/v1/chat/completions'
  }

  private async requestAi(systemPrompt: string, userPrompt: string, temperature: number = 0.85): Promise<string> {
    if (!this.baseUrl.trim() || !this.apiKey.trim()) {
      throw new Error('请先前往设置页配置 AI 模型连接')
    }
    const messages: AiMessage[] = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt }
    ]
    const body: AiRequestBody = {
      model: this.model.trim() || 'gpt-5.6-sol',
      messages: messages,
      temperature: temperature
    }
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${this.apiKey.trim()}`,
      'Content-Type': 'application/json'
    }
    const response = await ApiClient.callOpenAIApi<AiResponse, AiRequestBody>(this.endpoint(), body, headers)
    const content = response.choices && response.choices.length > 0 ? response.choices[0].message.content : ''
    if (!content) {
      throw new Error('AI 没有返回文本内容')
    }
    return content.trim()
  }

  private polishTarget(): string {
    if (this.mode === 'lyrics') {
      return this.seedLyrics || this.extraPrompt
    }
    return this.inspiration || this.extraPrompt
  }

  private async polishPrompt(): Promise<void> {
    const source = this.polishTarget().trim()
    if (!source) {
      this.message = '请先输入需要润色的灵感或歌词'
      return
    }
    this.polishing = true
    this.message = ''
    try {
      const polished = await this.requestAi(
        '你是一位专业华语音乐创作策划。只润色用户给出的创作灵感，使其更具体、更有画面感和音乐可执行性。不要直接写完整歌词，不要解释。',
        `目标风格：${this.style || '未指定'}\n原始内容：${source}`,
        0.7
      )
      if (this.mode === 'lyrics') {
        this.seedLyrics = polished
      } else {
        this.inspiration = polished
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : 'AI 润色失败'
    } finally {
      this.polishing = false
    }
  }

  private generationPrompt(): string {
    if (this.mode === 'adapt') {
      const song = this.selectedSong()
      if (!song) {
        return ''
      }
      return `请以歌曲《${song.name}》的情绪主题为灵感，创作一首差异化的新作品。\n原歌手：${song.author}\n原歌词参考：\n${this.sourceLyrics.substring(0, 6000)}\n目标风格：${this.style || '由你判断'}\n改编要求：${this.inspiration || this.extraPrompt || '保留情绪内核，但重新设计标题、叙事视角、意象和歌词表达，避免逐句仿写。'}`
    }
    if (this.mode === 'lyrics') {
      return `请完善以下歌词片段，发展成一首完整歌曲。\n歌词种子：\n${this.seedLyrics}\n风格：${this.style || '由你判断'}\n额外要求：${this.extraPrompt || '注意段落推进、押韵和可演唱性。'}`
    }
    return `请根据一句话灵感创作一首完整歌曲。\n灵感：${this.inspiration}\n风格：${this.style || '由你判断'}\n额外要求：${this.extraPrompt || '作品应有鲜明主题、记忆点和完整结构。'}`
  }

  private async generateSong(): Promise<void> {
    if (this.mode === 'adapt' && this.lyricLoading) {
      this.message = '正在加载原歌词，请稍候'
      return
    }
    if (this.mode === 'adapt' && this.selectedSong() && !this.sourceLyrics) {
      this.message = this.sourceLyricsMessage || '所选歌曲暂无有效歌词，请更换一首歌曲'
      return
    }
    const prompt = this.generationPrompt()
    if (!prompt) {
      this.message = this.mode === 'adapt' ? '请先选择一首喜欢的歌曲' : '请先输入歌词或创作灵感'
      return
    }
    this.generating = true
    this.message = ''
    try {
      this.result = await this.requestAi(
        '你是一位专业歌曲创作者。输出一首原创中文歌曲，只使用纯文本。输出格式必须包含：标题、风格说明、创作概念、[主歌1]、[预副歌]、[副歌]、[主歌2]、[桥段]、[尾声]。作品要有差异化，歌词自然可唱，避免解释生成过程。',
        prompt,
        0.95
      )
    } catch (error) {
      this.message = error instanceof Error ? error.message : 'AI 生成失败'
    } finally {
      this.generating = false
    }
  }

  @Builder
  private ModeTabs() {
    Row({ space: 8 }) {
      ForEach(['adapt', 'lyrics', 'idea'], (item: string) => {
        Text(item === 'adapt' ? '风格改编' : item === 'lyrics' ? 'AI 作词' : '一句话写歌')
          .layoutWeight(1).height(38).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.mode === item ? '#ffffff' : '#85858e').textAlign(TextAlign.Center)
          .backgroundColor(this.mode === item ? '#ef233c' : '#232329').borderRadius(13)
          .onClick(() => this.mode = item)
      })
    }
    .width('100%')
  }

  @Builder
  private SongPicker() {
    Column({ space: 11 }) {
      Row() {
        Text('选择喜欢的歌曲').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Blank()
        if (this.likedLoading) {
          LoadingProgress().width(20).height(20).color('#ef233c')
        }
      }
      Scroll() {
        Row({ space: 10 }) {
          Column({ space: 6 }) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(28).fontColor(['#ffffff'])
              Text('搜索单曲').fontSize(11).fontWeight(FontWeight.Medium).fontColor('#ffffff')
            }
            .width(88).height(88).justifyContent(FlexAlign.Center)
            .backgroundColor('#ef233c').borderRadius(13)
            Text('更多歌曲').width(88).fontSize(11).fontColor('#ededf0').textAlign(TextAlign.Center)
          }
          .onClick(() => {
            this.searchSheetVisible = true
            this.searchMessage = ''
          })
          if (this.authStore.loggedIn) {
            ForEach(this.likedSongs, (song: songItemType) => {
              Column({ space: 6 }) {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  Image(song.img).width(88).height(88).borderRadius(13).objectFit(ImageFit.Cover)
                  if (this.selectedSongId === song.id) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(23).fontColor(['#ef233c'])
                      .margin({ right: 6, bottom: 6 })
                  }
                }
                Text(song.name).width(88).fontSize(11).fontColor('#ededf0').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start).onClick(() => this.selectSong(song))
            })
          }
        }
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      if (!this.authStore.loggedIn) {
        Text('未登录时仍可搜索单曲；登录后还会显示“我喜欢的音乐”').fontSize(11).fontColor('#77777f')
      }
    }
    .width('100%').padding(15).backgroundColor('#1b1b20').borderRadius(17)
  }

  @Builder
  private LyricsPreview() {
    if (this.selectedSong()) {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Image(this.selectedSong()?.img || '').width(46).height(46).borderRadius(9).objectFit(ImageFit.Cover)
          Column({ space: 3 }) {
            Text(this.selectedSong()?.name || '').width('100%').fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor('#ffffff').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.selectedSong()?.author || '').width('100%').fontSize(11).fontColor('#85858e')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.lyricLoading) {
            LoadingProgress().width(22).height(22).color('#ef233c')
          }
        }
        Text('原歌词预览').width('100%').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        if (this.lyricLoading) {
          Text('正在检查歌曲歌词…').width('100%').fontSize(11).fontColor('#85858e')
        } else if (this.sourceLyrics) {
          Scroll() {
            Text(this.sourceLyrics).width('100%').fontSize(12).lineHeight(20).fontColor('#c9c9cf')
          }.width('100%').height(180).scrollBar(BarState.Off)
        } else {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill')).fontSize(19).fontColor(['#ff9c57'])
            Text(this.sourceLyricsMessage || '该歌曲暂无有效歌词，请更换其他歌曲')
              .layoutWeight(1).fontSize(11).lineHeight(18).fontColor('#ffb47c')
          }.width('100%').padding(12).backgroundColor('#2d241f').borderRadius(12)
        }
      }
      .width('100%').padding(15).backgroundColor('#1b1b20').borderRadius(17)
    }
  }

  @Builder
  private SearchSongSheet() {
    Column({ space: 12 }) {
      Row() {
        Text('搜索参考单曲').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Blank()
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor(['#77777f'])
          .onClick(() => this.searchSheetVisible = false)
      }.width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.searchKeyword, placeholder: '输入歌曲名或歌手名' })
          .layoutWeight(1).height(44).fontColor('#ffffff').placeholderColor('#66666e')
          .backgroundColor('#25252b').borderRadius(13)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => this.searchKeyword = value)
          .onSubmit(() => this.searchSongs())
        Button('搜索').height(44).fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
          .borderRadius(13).enabled(!this.searchLoading).onClick(() => this.searchSongs())
      }.width('100%')
      if (this.searchLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(22).height(22).color('#ef233c')
          Text('正在搜索单曲…').fontSize(12).fontColor('#85858e')
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.searchMessage) {
        Text(this.searchMessage).layoutWeight(1).width('100%').fontSize(12).fontColor('#85858e')
          .textAlign(TextAlign.Center)
      } else if (this.searchResults.length > 0) {
        List({ space: 6 }) {
          ForEach(this.searchResults, (song: songItemType) => {
            ListItem() {
              Row({ space: 11 }) {
                Image(song.img).width(48).height(48).borderRadius(9).objectFit(ImageFit.Cover)
                Column({ space: 4 }) {
                  Text(song.name).width('100%').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#f1f1f3')
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${song.author}${song.album ? ` · ${song.album}` : ''}`).width('100%').fontSize(10)
                    .fontColor('#77777f').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.selectedSongId === song.id) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(22).fontColor(['#ef233c'])
                } else {
                  Text('选择').fontSize(11).fontColor('#ff6577')
                }
              }
              .width('100%').padding(9).backgroundColor('#232329').borderRadius(12)
              .onClick(() => this.selectSong(song))
            }
          })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      } else {
        Column({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(34).fontColor(['#55555d'])
          Text('搜索并选择一首有歌词的歌曲作为改编参考').fontSize(11).fontColor('#77777f')
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').height('100%').padding({ left: 16, right: 16, top: 18, bottom: 12 })
    .backgroundColor('#19191f')
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('AI 写歌').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.wand_and_stars')).fontSize(22).fontColor(['#ff6577'])
        }
        .width('100%').height(56).padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 14 }) {
            this.ModeTabs()
            if (this.mode === 'adapt') {
              this.SongPicker()
              this.LyricsPreview()
            }
            Column({ space: 11 }) {
              TextInput({ placeholder: '作品风格，例如：城市民谣、迷幻 R&B、电影感摇滚', text: this.style })
                .height(44).fontColor('#ffffff').placeholderColor('#66666e').backgroundColor('#25252b')
                .borderRadius(12).onChange((value: string) => this.style = value)
              if (this.mode === 'lyrics') {
                TextArea({ placeholder: '输入几句歌词或零散句子，让 AI 完善成完整作品', text: this.seedLyrics })
                  .height(150).fontColor('#ffffff').placeholderColor('#66666e').backgroundColor('#25252b')
                  .borderRadius(12).onChange((value: string) => this.seedLyrics = value)
              } else {
                TextArea({ placeholder: this.mode === 'adapt' ? '描述希望如何改编：叙事视角、情绪、年代或场景' : '用一句话描述歌曲灵感', text: this.inspiration })
                  .height(125).fontColor('#ffffff').placeholderColor('#66666e').backgroundColor('#25252b')
                  .borderRadius(12).onChange((value: string) => this.inspiration = value)
              }
              TextArea({ placeholder: '其他要求，例如押韵、结构、意象、禁用词', text: this.extraPrompt })
                .height(90).fontColor('#ffffff').placeholderColor('#66666e').backgroundColor('#25252b')
                .borderRadius(12).onChange((value: string) => this.extraPrompt = value)
              Row({ space: 10 }) {
                Button(this.polishing ? '润色中…' : 'AI 润色灵感').layoutWeight(1).height(44)
                  .fontColor('#f2f2f4').backgroundColor('#2b2b32').borderRadius(14)
                  .enabled(!this.polishing && !this.generating).onClick(() => this.polishPrompt())
                Button(this.generating ? '创作中…' : '生成歌曲').layoutWeight(1).height(44)
                  .fontColor('#ffffff').backgroundColor('#ef233c').borderRadius(14)
                  .enabled(!this.polishing && !this.generating).onClick(() => this.generateSong())
              }
            }
            .width('100%').padding(15).backgroundColor('#1b1b20').borderRadius(17)

            if (this.message) {
              Text(this.message).width('100%').fontSize(11).fontColor('#ff7587').textAlign(TextAlign.Center)
            }
            if (this.result) {
              Column({ space: 10 }) {
                Row() {
                  Text('生成作品').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                  Blank()
                  Text('可继续手动编辑').fontSize(9).fontColor('#77777f')
                }
                TextArea({ text: this.result }).height(520).fontSize(13).lineHeight(21)
                  .fontColor('#d8d8dd').backgroundColor('#202026').borderRadius(13)
                  .onChange((value: string) => this.result = value)
              }
              .width('100%').padding(15).backgroundColor('#1b1b20').borderRadius(17)
            }
          }
          .width('100%').padding({ left: 12, right: 12, bottom: 32 })
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor('#121215')
      .bindSheet(this.searchSheetVisible, this.SearchSongSheet(), {
        height: '58%',
        backgroundColor: '#19191f',
        showClose: false,
        dragBar: true,
        onDisappear: () => this.searchSheetVisible = false
      })
    }
    .hideTitleBar(true)
  }
}
