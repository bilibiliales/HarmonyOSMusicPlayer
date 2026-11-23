import { common } from '@kit.AbilityKit'
import { songItemType, playlistType, QualityOption, SongArtist } from '../models/music'
import { LikeListResponse, OperationResponse, SongDetailResponse, UserPlaylistResponse,
  mapApiSong, mapPlaylist, ArtistPageParam, AlbumPageParam } from '../models/api'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { BubbleTip } from '../services/BubbleTip'
import { SystemShareService } from '../services/SystemShareService'
import { SongQualityService } from '../services/SongQualityService'
import { StreamingDownload } from '../services/StreamingAudio'
import { AudioFileFormat } from '../services/AudioFileFormat'
import { LocalLibrary } from '../services/LocalLibrary'
import { AppSettings } from '../services/AppSettings'
import { ResourceComments } from './ResourceComments'
import { HeartLike } from './HeartLike'
import { SheetSkinFrame } from './SheetSkin'
import { TC } from '../services/ThemeColors'
import { resizeImageUrl } from '../services/ImageUrl'
import { RingtonePageParam } from '../pages/RingtonePage'

/** 所有歌曲列表共用的更多按钮与逐行操作半模态。 */
@Component
export struct SongMoreButton {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('authStore') authStore: AuthStore
  @Consume('playerStore') playerStore: PlayerStore
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop song: songItemType = { id: '', name: '', author: '', img: '', url: '' }
  @Prop iconSize: number = 21
  @Prop canRemove: boolean = false
  onRemove: () => void = () => {}
  @State private visible: boolean = false
  @State private panel: string = 'main'
  @State private liked: boolean = false
  @State private busy: boolean = false
  @State private loading: boolean = false
  @State private message: string = ''
  @State private playlists: playlistType[] = []
  @State private qualities: QualityOption[] = []
  @State private artists: SongArtist[] = []
  @State private downloadProgress: number = 0
  private target: songItemType = { id: '', name: '', author: '', img: '', url: '' }
  private downloadTask?: StreamingDownload
  private generation: number = 0

  private open(): void {
    if (this.busy || this.loading) { this.visible = true; return }
    this.target = this.song
    this.liked = this.song.liked || false
    this.panel = 'main'
    this.message = ''
    this.visible = true
    const generation = ++this.generation
    if (this.authStore.loggedIn) {
      ApiClient.get<LikeListResponse>('/likelist', [{ key: 'uid', value: this.authStore.userId }])
        .then((response: LikeListResponse) => {
          if (generation === this.generation && response.code === 200) {
            this.liked = (response.ids || []).some((id: number) => String(id) === this.target.id)
          }
        }).catch(() => {})
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private requireLogin(): boolean {
    if (this.authStore.loggedIn) { return true }
    this.visible = false
    this.pageStack.pushPathByName('LoginPage', null)
    return false
  }

  private async details(): Promise<songItemType> {
    const response = await ApiClient.get<SongDetailResponse>('/song/detail', [{ key: 'ids', value: this.target.id }])
    const song = response.songs?.find((item) => String(item.id) === this.target.id)
    if (response.code !== 200 || !song) { throw new Error('歌曲详情加载失败') }
    return mapApiSong(song)
  }

  private async act(action: string): Promise<void> {
    if (this.busy || this.loading) { return }
    this.busy = true
    this.message = ''
    const generation = this.generation
    const userId = this.authStore.userId
    try {
      if (action === 'next') {
        await playerController.insertNext([this.target])
        BubbleTip.show(this.getUIContext(), '已添加到下一首播放')
        this.visible = false
      } else if (action === 'like') {
        if (!this.requireLogin()) { return }
        this.generation++
        const liked = !this.liked
        const response = await ApiClient.get<OperationResponse>('/like', [
          { key: 'id', value: this.target.id }, { key: 'like', value: String(liked) }
        ])
        if (response.code !== 200) { throw new Error(response.message || '喜欢操作失败') }
        if (userId !== this.authStore.userId) { return }
        this.liked = liked
        this.song.liked = liked
        playerController.updateLiked(this.target.id, liked)
        if (this.playerStore.currentSong.id === this.target.id) { this.playerStore.currentSong.liked = liked }
        BubbleTip.show(this.getUIContext(), liked ? '已加入我喜欢的音乐' : '已取消喜欢')
      } else if (action === 'collect') {
        if (!this.requireLogin()) { return }
        this.panel = 'collect'
        this.loading = true
        const response = await ApiClient.get<UserPlaylistResponse>('/user/playlist', [
          { key: 'uid', value: this.authStore.userId }, { key: 'limit', value: '100' }
        ])
        if (response.code !== 200) { throw new Error('歌单加载失败') }
        if (generation !== this.generation || userId !== this.authStore.userId) { return }
        this.playlists = (response.playlist || []).map((item) => mapPlaylist(item))
          .filter((item: playlistType) => item.creatorId === this.authStore.userId && !item.isLiked)
      } else if (action === 'download') {
        this.panel = 'download'
        this.loading = true
        const qualities = await SongQualityService.available(this.target.id)
        if (generation !== this.generation) { return }
        this.qualities = qualities
      } else if (action === 'comments') {
        this.panel = 'comments'
      } else if (action === 'share') {
        this.visible = false
        await SystemShareService.showLink(this.context(), SystemShareService.musicLink({ type: 'song',
          id: this.target.id, name: this.target.name, img: this.target.img, author: this.target.author }))
      } else if (action === 'artists') {
        this.loading = true
        const song = await this.details()
        if (generation !== this.generation) { return }
        const artist = song.artists?.[0]
        if (!artist) { throw new Error('这首歌暂无歌手信息') }
        this.visible = false
        const param: ArtistPageParam = { id: artist.id, name: artist.name, picUrl: artist.picUrl || '' }
        this.pageStack.pushPathByName('ArtistPage', param)
      } else if (action === 'album') {
        this.loading = true
        const song = await this.details()
        if (generation !== this.generation) { return }
        if (!song.albumId || song.albumId === '0') { throw new Error('这首歌暂无专辑信息') }
        this.visible = false
        const param: AlbumPageParam = { id: song.albumId, name: song.album || '', picUrl: song.img, artist: song.author }
        this.pageStack.pushPathByName('AlbumDetailPage', param)
      } else {
        this.visible = false
        if (action === 'ringtone') {
          const param: RingtonePageParam = { song: this.target }
          this.pageStack.pushPathByName('RingtonePage', param)
        } else if (action === 'remove') {
          this.onRemove()
        } else {
          this.pageStack.pushPathByName(action === 'credits' ? 'SongCreditsPage' :
            action === 'scores' ? 'SongScoresPage' : 'SongWikiPage', this.target)
        }
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '操作失败'
      if (!this.visible) { BubbleTip.show(this.getUIContext(), this.message) }
    } finally { this.busy = false; this.loading = false }
  }

  private async collect(item: playlistType): Promise<void> {
    if (this.busy) { return }
    this.busy = true
    try {
      const response = await ApiClient.get<OperationResponse>('/playlist/tracks', [
        { key: 'op', value: 'add' }, { key: 'pid', value: item.id }, { key: 'tracks', value: this.target.id }
      ])
      if (response.code !== 200) { throw new Error(response.message || '收藏失败') }
      BubbleTip.show(this.getUIContext(), `已收藏到「${item.name}」`)
      this.visible = false
    } catch (error) { this.message = error instanceof Error ? error.message : '收藏失败' }
    finally { this.busy = false }
  }

  private async download(level: string): Promise<void> {
    if (this.busy) { return }
    this.busy = true
    this.downloadProgress = 0
    const task = new StreamingDownload()
    this.downloadTask = task
    try {
      let mode = AppSettings.downloadSaveMode
      if (AppSettings.askDownloadSaveMode) {
        const result = await this.getUIContext().getPromptAction().showActionMenu({ title: '保存方式',
          buttons: [{ text: '保存到下载目录', color: TC.accentMenu() }, { text: '另存为…', color: '#777777' }] })
        mode = result.index === 1 ? 'saveAs' : 'download'
      }
      const audio = await SongQualityService.download(this.target.id, level)
      const head = await StreamingDownload.probe(audio.url, 64)
      const ext = AudioFileFormat.extension(audio.url, audio.type, audio.encodeType, head)
      const name = `${this.target.name}-${this.target.author}`.replace(/[\\/:*?"<>|]/g, '_')
      const saved = await LocalLibrary.saveDownload(this.context(), `${name}.${ext}`, this.target, mode,
        async (fd: number): Promise<number> => task.run(audio.url, fd, audio.size, (received: number, total: number) => {
          if (total > 0) { this.downloadProgress = Math.min(99, Math.floor(received * 100 / total)) }
        }))
      if (saved) { BubbleTip.show(this.getUIContext(), `下载完成 · ${SongQualityService.title(audio.actualLevel)}`) }
      this.visible = false
    } catch (error) { this.message = error instanceof Error ? error.message : '下载失败' }
    finally { this.busy = false; this.downloadTask = undefined }
  }

  aboutToDisappear(): void { this.generation++; this.downloadTask?.cancel() }

  @Builder
  private Option(icon: Resource, label: string, action: string) {
    Row({ space: 14 }) {
      if (action === 'like') {
        HeartLike({ liked: this.liked, iconSize: 21, iconColor: this.liked ? TC.accent() : TC.textPrimary() }).width(24)
      } else {
        SymbolGlyph(icon).fontSize(21).fontColor([TC.textPrimary()]).width(24)
      }
      Text(label).layoutWeight(1).fontSize(15).fontColor(TC.textPrimary())
    }.width('100%').height(50).padding({ left: 20, right: 20 })
      .enabled(!this.busy && !this.loading).onClick(() => this.act(action))
  }

  @Builder
  private SongCard() {
    Row({ space: 12 }) {
      Image(resizeImageUrl(this.target.img, 128, 128)).width(52).height(52).borderRadius(10).objectFit(ImageFit.Cover)
      Column({ space: 5 }) {
        Text(this.target.name).width('100%').fontSize(15).fontColor(TC.textPrimary()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.target.author).width('100%').fontSize(12).fontColor(TC.textSecondary()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding(14).backgroundColor(TC.surfaceCard()).borderRadius(14).margin({ bottom: 10 })
  }

  @Builder
  private Sheet() {
    SheetSkinFrame() {
      Column() {
        Row() {
          if (this.panel !== 'main') {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([TC.textPrimary()])
              .enabled(!this.busy && !this.loading).onClick(() => { this.panel = 'main'; this.message = '' })
          }
          Text(this.panel === 'collect' ? '收藏到歌单' : this.panel === 'download' ? '选择下载音质' :
            this.panel === 'artists' ? '歌手' : '歌曲选项').layoutWeight(1).fontSize(16).fontColor(TC.textPrimary())
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([TC.textSecondary()])
            .enabled(!this.busy).onClick(() => this.visible = false)
        }.width('100%').height(48).padding({ left: 20, right: 20 })
        if (this.panel === 'comments') {
          ResourceComments({ resource: { id: this.target.id, type: 0, title: this.target.name },
            onClose: () => this.panel = 'main' })
            .layoutWeight(1)
        } else {
          Scroll() {
            Column() {
              this.SongCard()
              if (this.loading) { LoadingProgress().width(32).height(32).color(TC.accent()) }
              if (this.panel === 'main') {
                this.Option($r('sys.symbol.play_fill'), '下一首播放', 'next')
                this.Option(this.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'), this.liked ? '取消喜欢' : '喜欢', 'like')
                this.Option($r('sys.symbol.plus_circle'), '收藏到歌单', 'collect')
                this.Option($r('sys.symbol.arrow_down_circle'), '下载', 'download')
                this.Option($r('sys.symbol.ellipsis_bubble'), '评论', 'comments')
                this.Option($r('sys.symbol.share'), '分享', 'share')
                this.Option($r('sys.symbol.person_crop_circle_fill'), '歌手', 'artists')
                this.Option($r('sys.symbol.opticaldisc'), '专辑', 'album')
                this.Option($r('sys.symbol.music_note_list'), '乐谱', 'scores')
                this.Option($r('sys.symbol.info_circle'), '百科', 'wiki')
                this.Option($r('sys.symbol.bell_fill'), '设为铃声', 'ringtone')
                if (this.canRemove) { this.Option($r('sys.symbol.trash'), '从歌单移除', 'remove') }
              } else if (this.panel === 'collect') {
                ForEach(this.playlists, (item: playlistType) => {
                  Row({ space: 12 }) {
                    Image(item.cover).width(40).height(40).borderRadius(8)
                    Text(item.name).layoutWeight(1).fontSize(14).fontColor(TC.textBody()).maxLines(1)
                  }.width('100%').height(56).enabled(!this.busy).onClick(() => this.collect(item))
                }, (item: playlistType) => item.id)
                if (!this.loading && !this.playlists.length) { Text('暂无可收藏的自建歌单').fontColor(TC.textSecondary()).padding(20) }
              } else if (this.panel === 'download') {
                if (this.busy) { Text(`正在下载 ${this.downloadProgress}%`).fontColor(TC.accent()).padding(12) }
                ForEach(this.qualities, (quality: QualityOption) => {
                  Row({ space: 12 }) {
                    SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(20).fontColor([TC.textPrimary()])
                    Text(`${quality.title} · ${quality.description}`).fontSize(13).fontColor(TC.textBody()).layoutWeight(1)
                  }.width('100%').height(54).enabled(!this.busy).onClick(() => this.download(quality.level))
                }, (quality: QualityOption) => quality.level)
                if (!this.loading && !this.qualities.length) { Text('暂无可下载音质').fontColor(TC.textSecondary()).padding(20) }
              } else if (this.panel === 'artists') {
                ForEach(this.artists, (artist: SongArtist) => {
                  Text(artist.name).width('100%').height(50).fontSize(14).fontColor(TC.textBody())
                    .onClick(() => {
                      this.visible = false
                      const param: ArtistPageParam = { id: artist.id, name: artist.name, picUrl: artist.picUrl || '' }
                      this.pageStack.pushPathByName('ArtistPage', param)
                    })
                }, (artist: SongArtist) => artist.id)
              }
              if (this.message) { Text(this.message).width('100%').fontSize(12).fontColor(TC.accentSoft()).padding(12) }
            }.width('100%').padding({ left: 16, right: 16, bottom: 24 })
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        }
      }.width('100%').height('100%')
    }
  }

  build() {
    SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(this.iconSize).fontColor([TC.textTertiary()])
      .padding(6).accessibilityText('更多歌曲选项').onClick(() => this.open())
      .bindSheet(this.visible, this.Sheet(), { height: '72%', backgroundColor: TC.sheetBackground(),
        showClose: false, dragBar: true, onDisappear: () => { this.visible = false; this.generation++ } })
  }
}
