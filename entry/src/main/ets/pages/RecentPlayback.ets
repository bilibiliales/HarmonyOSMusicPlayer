import { AuthStore } from '../stores/AuthStore'
import { ListeningPlaylistService } from '../services/ListeningPlaylistService'
import { RecentPlaybackService, RecentEntry } from '../services/RecentPlaybackService'
import { playerController } from '../services/PlayerController'
import { AlbumPageParam, MvPlayerPageParam } from '../models/api'
import { playlistType, songItemType } from '../models/music'

export interface RecentPlaybackParam { djId?: string; title?: string }

@Component
export struct RecentPlaybackPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: RecentPlaybackParam = {}
  @State tab: number = 0
  @State entries: RecentEntry[] = []
  @State songs: songItemType[] = []
  @State loading: boolean = false
  @State message: string = ''
  private requestId: number = 0
  private owner: string = ''
  private readonly titles: string[] = ['歌曲', '视频', '声音', '歌单', '专辑', '播客']
  private readonly kinds: string[] = ['song', 'video', 'voice', 'playlist', 'album', 'dj']

  aboutToAppear(): void { this.owner = this.authStore.userId; this.load() }
  aboutToDisappear(): void { this.requestId++ }

  private canPlayAll(): boolean { return !!this.pageParam.djId || this.tab === 0 || this.tab === 2 }

  private async load(): Promise<void> {
    const request = ++this.requestId
    this.loading = true
    this.message = ''
    this.songs = []
    this.entries = []
    try {
      if (!this.authStore.loggedIn || this.owner !== this.authStore.userId) { throw new Error('请登录查看自己的最近播放') }
      if (!this.pageParam.djId && this.tab === 0) {
        const songs = await ListeningPlaylistService.recent()
        if (request === this.requestId && this.owner === this.authStore.userId) { this.songs = songs }
      } else {
        const entries = this.pageParam.djId ? await RecentPlaybackService.programs(this.pageParam.djId) :
          await RecentPlaybackService.load(this.kinds[this.tab])
        if (request !== this.requestId || this.owner !== this.authStore.userId) { return }
        this.entries = entries
        this.songs = entries.filter((item: RecentEntry) => !!item.song).map((item: RecentEntry) => item.song!)
      }
    } catch (error) {
      if (request === this.requestId) { this.message = error instanceof Error ? error.message : '加载失败' }
    } finally { if (request === this.requestId) { this.loading = false } }
  }

  private async play(index: number): Promise<void> {
    if (!this.authStore.loggedIn || this.owner !== this.authStore.userId || !this.songs.length) { return }
    await playerController.setQueue(this.songs, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private open(item: RecentEntry): void {
    if (!this.authStore.loggedIn || this.owner !== this.authStore.userId) { return }
    if (item.song) { this.play(this.songs.findIndex((song: songItemType) => song.id === item.song?.id)); return }
    if (this.tab === 3) {
      const playlist: playlistType = { id: item.id, name: item.name, cover: item.cover, creator: item.creator, count: 0 }
      this.pageStack.pushPathByName('PlaylistDetailPage', playlist)
    } else if (this.tab === 4) {
      const album: AlbumPageParam = { id: item.id, name: item.name, picUrl: item.cover, artist: item.creator }
      this.pageStack.pushPathByName('AlbumDetailPage', album)
    } else if (this.tab === 5) {
      const param: RecentPlaybackParam = { djId: item.id, title: item.name }
      this.pageStack.pushPathByName('RecentPlaybackPage', param)
    } else if (this.tab === 1) {
      const video: MvPlayerPageParam = { id: item.id, name: item.name, cover: item.cover, isVideo: item.video }
      this.pageStack.pushPathByName('MvPlayerPage', video)
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
          Text(this.pageParam.title || '最近播放').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 18, top: this.topAvoidHeight })
        if (!this.pageParam.djId) {
          Scroll() {
            Row({ space: 24 }) {
              ForEach(this.titles, (title: string, index: number) => {
                Column({ space: 7 }) {
                  Text(title).fontSize(14).fontColor(this.tab === index ? '#ffffff' : '#77777f')
                    .fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Regular)
                  Column().width(24).height(3).borderRadius(2).backgroundColor(this.tab === index ? '#ef233c' : 'transparent')
                }.height(46).justifyContent(FlexAlign.Center).onClick(() => {
                  if (this.tab !== index) { this.tab = index; this.load() }
                })
              })
            }.padding({ left: 18, right: 18 })
          }.width('100%').height(46).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        }
        if (this.canPlayAll()) {
          Button(`播放全部 ${this.songs.length}`).backgroundColor('#ef233c').fontColor('#ffffff')
            .margin(12).enabled(!this.loading && this.songs.length > 0).onClick(() => this.play(0))
        }
        if (!this.authStore.loggedIn || this.owner !== this.authStore.userId) {
          Text('请登录查看自己的最近播放').fontColor('#77777f')
        } else if (this.loading) {
          LoadingProgress().width(40).color('#ef233c')
        } else if (this.message) {
          Text(this.message).fontColor('#77777f')
          Button('重试').onClick(() => this.load())
        } else {
          List() {
            if (this.canPlayAll()) {
              ForEach(this.songs, (song: songItemType, index: number) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Image(song.img).width(48).height(48).borderRadius(8)
                    Column({ space: 4 }) {
                      Text(song.name).fontColor('#eeeeee').maxLines(1)
                      Text(song.author).fontColor('#77777f').fontSize(12).maxLines(1)
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  }.height(68).padding({ left: 18, right: 18 }).onClick(() => this.play(index))
                }
              })
            } else {
              ForEach(this.entries, (item: RecentEntry) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Image(item.cover).width(48).height(48).borderRadius(8)
                    Text(item.name).layoutWeight(1).fontColor('#eeeeee').maxLines(2)
                    SymbolGlyph($r('sys.symbol.chevron_right')).fontColor(['#77777f']).fontSize(16)
                  }.height(68).padding({ left: 18, right: 18 }).onClick(() => this.open(item))
                }
              })
            }
            if (this.songs.length === 0 && this.entries.length === 0) {
              ListItem() { Text('暂无播放记录').width('100%').padding(24).fontColor('#77777f').textAlign(TextAlign.Center) }
            }
          }.layoutWeight(1)
        }
      }.width('100%').height('100%').backgroundColor('#121215')
    }.hideTitleBar(true)
  }
}
