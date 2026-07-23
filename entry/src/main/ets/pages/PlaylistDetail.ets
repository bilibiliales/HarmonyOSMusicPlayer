import { common } from '@kit.AbilityKit'
import { systemShare } from '@kit.ShareKit'
import {
  CommentResponse,
  mapApiSong,
  mapComment,
  OperationResponse,
  PlaylistDetailResponse,
  PlaylistDynamicResponse,
  SharePageParam,
  UserProfilePageParam
} from '../models/api'
import { MusicComment, playlistType, songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'
import { ShareSheet } from '../components/ShareSheet'
import { PlaylistCoverPreviewPageParam } from './PlaylistCoverPreview'
import { PlaylistEditorPageParam } from './PlaylistEditor'
import { PlaylistSongManagerPageParam } from './PlaylistSongManager'

@Component
export struct PlaylistDetail {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  initialPlaylist: playlistType = { id: '', name: '', cover: '', count: 0, creator: '' }
  @State playlist: playlistType = { id: '', name: '', cover: '', count: 0, creator: '' }
  @State playlistTags: string[] = []
  @State playlistDescription: string = ''
  @State songList: songItemType[] = []
  @State creatorId: string = ''
  @State loading: boolean = true
  @State message: string = ''
  @State searchVisible: boolean = false
  @State keyword: string = ''
  @State shareCount: number = 0
  @State commentCount: number = 0
  @State collectCount: number = 0
  @State playCount: number = 0
  @State subscribed: boolean = false
  @State commentSheetVisible: boolean = false
  @State commentsLoading: boolean = false
  @State comments: MusicComment[] = []
  @State shareSheetVisible: boolean = false
  @State ownerMenuVisible: boolean = false
  @State songMenuVisible: boolean = false
  @State deleteConfirmVisible: boolean = false
  @State selectedSongId: string = ''
  @State selectedSongName: string = ''
  @State deleting: boolean = false
  private shareParam: SharePageParam = { type: 'playlist', id: '', name: '', img: '' }

  aboutToAppear(): void {
    this.playlist = this.initialPlaylist
    this.creatorId = this.initialPlaylist.creatorId || ''
    this.loadDetail()
  }

  private async loadDetail(): Promise<void> {
    if (!this.playlist.id) {
      this.loading = false
      this.message = '歌单参数无效'
      return
    }
    try {
      const response = await ApiClient.get<PlaylistDetailResponse>('/playlist/detail', [
        { key: 'id', value: this.playlist.id },
        { key: 's', value: '8' }
      ])
      if (response.code === 200 && response.playlist) {
        this.creatorId = response.playlist.creator.userId?.toString() || ''
        this.playlist = {
          id: response.playlist.id.toString(),
          name: response.playlist.name,
          cover: response.playlist.coverImgUrl,
          count: response.playlist.trackCount,
          creator: response.playlist.creator.nickname,
          creatorId: response.playlist.creator.userId?.toString() || '',
          description: response.playlist.description || '',
          tags: response.playlist.tags || [],
          privacy: response.playlist.privacy || 0,
          onChanged: this.initialPlaylist.onChanged
        }
        this.songList = (response.playlist.tracks || []).map((item) => mapApiSong(item))
        
        // 从主API响应中获取统计数据
        this.playCount = response.playlist.playCount || 0
        this.collectCount = response.playlist.subscribedCount || 0
        
        // 获取标签和描述
        this.playlistTags = response.playlist.tags || [];
        this.playlistDescription = response.playlist.description || '';
        
        // 获取评论数（通过commentThreadId获取评论总数）
        if (response.playlist.commentThreadId) {
          try {
            const commentResponse = await ApiClient.get<CommentResponse>('/comment/playlist', [
              { key: 'id', value: this.playlist.id },
              { key: 'limit', value: '0' }  // 只需要总数，不需要具体内容
            ])
            this.commentCount = commentResponse.total || 0
          } catch (commentError) {
            // 如果无法获取评论数，则保持默认值
            console.error('获取评论数失败:', commentError)
          }
        }
      } else {
        this.message = '歌单加载失败'
      }
      
      // 获取动态数据（用于收藏状态等）
      const dynamic = await ApiClient.get<PlaylistDynamicResponse>('/playlist/detail/dynamic', [
        { key: 'id', value: this.playlist.id }
      ])
      if (dynamic.code === 200) {
        this.shareCount = dynamic.shareCount || 0
        this.commentCount = dynamic.commentCount || 0
        this.collectCount = dynamic.bookedCount || 0
        this.playCount = dynamic.playCount || 0
        this.subscribed = dynamic.subscribed || false
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '歌单加载失败'
    } finally {
      this.loading = false
    }
  }

  private filteredSongs(): songItemType[] {
    const value = this.keyword.trim().toLowerCase()
    if (!value) {
      return this.songList
    }
    return this.songList.filter((item: songItemType) =>
      item.name.toLowerCase().includes(value) || item.author.toLowerCase().includes(value) ||
        (item.album || '').toLowerCase().includes(value))
  }

  private isOwner(): boolean {
    return this.authStore.loggedIn && this.creatorId.length > 0 && this.creatorId === this.authStore.userId
  }

  private openCreatorProfile(): void {
    const uid = this.creatorId || this.playlist.creatorId || ''
    if (!uid) {
      return
    }
    const param: UserProfilePageParam = { uid: uid }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private refreshDetail(): void {
    this.loading = true
    this.message = ''
    this.loadDetail()
    this.initialPlaylist.onChanged?.()
  }

  private openEditor(): void {
    this.ownerMenuVisible = false
    const param: PlaylistEditorPageParam = {
      mode: 'edit',
      playlist: this.playlist,
      onSaved: (_playlistId: string) => this.refreshDetail()
    }
    this.pageStack.pushPathByName('PlaylistEditorPage', param)
  }

  private openSongManager(mode: 'add' | 'order'): void {
    this.ownerMenuVisible = false
    const param: PlaylistSongManagerPageParam = {
      mode: mode,
      playlistId: this.playlist.id,
      playlistName: this.playlist.name,
      songs: this.songList.map((song: songItemType) => song),
      onChanged: () => this.refreshDetail()
    }
    this.pageStack.pushPathByName('PlaylistSongManagerPage', param)
  }

  private openSongMenu(song: songItemType): void {
    if (!this.isOwner()) {
      return
    }
    this.selectedSongId = song.id
    this.selectedSongName = song.name
    this.songMenuVisible = true
  }

  private async updateSongOrder(nextSongs: songItemType[]): Promise<void> {
    const ids: number[] = nextSongs.map((song: songItemType) => Number(song.id))
    const response = await ApiClient.get<OperationResponse>('/song/order/update', [
      { key: 'pid', value: this.playlist.id },
      { key: 'ids', value: JSON.stringify(ids) },
      { key: 'timestamp', value: Date.now().toString() }
    ])
    if (response.code !== 200) {
      throw new Error(response.message || '歌曲顺序更新失败')
    }
  }

  private async pinSelectedSong(): Promise<void> {
    this.songMenuVisible = false
    const selected = this.songList.find((song: songItemType) => song.id === this.selectedSongId)
    if (!selected || this.songList[0]?.id === selected.id) {
      return
    }
    const previous = this.songList.map((song: songItemType) => song)
    const next: songItemType[] = [selected]
    previous.forEach((song: songItemType) => {
      if (song.id !== selected.id) {
        next.push(song)
      }
    })
    this.songList = next
    try {
      await this.updateSongOrder(next)
      this.message = `已将《${selected.name}》置顶`
      this.initialPlaylist.onChanged?.()
    } catch (error) {
      this.songList = previous
      this.message = error instanceof Error ? error.message : '歌曲置顶失败'
    }
  }

  private async removeSelectedSong(): Promise<void> {
    this.songMenuVisible = false
    if (!this.selectedSongId) {
      return
    }
    try {
      const response = await ApiClient.get<OperationResponse>('/playlist/tracks', [
        { key: 'op', value: 'del' },
        { key: 'pid', value: this.playlist.id },
        { key: 'tracks', value: this.selectedSongId },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code !== 200) {
        throw new Error(response.message || '歌曲移除失败')
      }
      this.songList = this.songList.filter((song: songItemType) => song.id !== this.selectedSongId)
      this.playlist.count = this.songList.length
      this.message = `已移除《${this.selectedSongName}》`
      this.initialPlaylist.onChanged?.()
    } catch (error) {
      this.message = error instanceof Error ? error.message : '歌曲移除失败'
    }
  }

  private async deletePlaylist(): Promise<void> {
    if (this.deleting) {
      return
    }
    this.deleting = true
    try {
      const response = await ApiClient.get<OperationResponse>('/playlist/delete', [
        { key: 'id', value: this.playlist.id },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code !== 200) {
        throw new Error(response.message || '歌单删除失败')
      }
      this.deleteConfirmVisible = false
      this.initialPlaylist.onChanged?.()
      this.pageStack.pop()
    } catch (error) {
      this.deleteConfirmVisible = false
      this.message = error instanceof Error ? error.message : '歌单删除失败'
    } finally {
      this.deleting = false
    }
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

  private async playAt(index: number): Promise<void> {
    const list = this.filteredSongs()
    if (list.length === 0) {
      return
    }
    await playerController.setQueue(list, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private sharePlaylist(): void {
    this.shareParam = {
      type: 'playlist',
      id: this.playlist.id,
      name: this.playlist.name,
      img: this.playlist.cover
    }
    this.shareSheetVisible = true
  }

  private async toggleSubscribe(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    if (this.creatorId === this.authStore.userId) {
      this.message = '这是你自己创建的歌单'
      return
    }
    const next = !this.subscribed
    try {
      const response = await ApiClient.get<OperationResponse>('/playlist/subscribe', [
        { key: 'id', value: this.playlist.id },
        { key: 't', value: next ? '1' : '2' }
      ])
      if (response.code === 200) {
        this.subscribed = next
        this.collectCount = Math.max(0, this.collectCount + (next ? 1 : -1))
        this.message = next ? '已收藏歌单' : '已取消收藏'
      } else {
        this.message = response.message || '操作失败'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '操作失败'
    }
  }

  private async openComments(): Promise<void> {
    this.commentSheetVisible = true
    this.commentsLoading = true
    try {
      const response = await ApiClient.get<CommentResponse>('/comment/playlist', [
        { key: 'id', value: this.playlist.id },
        { key: 'limit', value: '40' }
      ])
      const source = response.hotComments && response.hotComments.length > 0 ? response.hotComments : response.comments
      this.comments = (source || []).map((item) => mapComment(item))
      this.commentCount = response.total || this.commentCount
    } catch (_error) {
      this.comments = []
    } finally {
      this.commentsLoading = false
    }
  }

  @Builder
  private StatAction(icon: Resource, title: string, count: number, onClick: () => void, active: boolean = false) {
    Row({ space: 7 }) {
      SymbolGlyph(icon).fontSize(20).fontColor([active ? '#ff6577' : '#ededf0'])
      Text(title).fontSize(12).fontColor(active ? '#ff6577' : '#d0d0d5')
      Text(this.formatCount(count)).fontSize(11).fontColor('#77777f')
    }
    .layoutWeight(1).height(44).justifyContent(FlexAlign.Center)
    .onClick(onClick)
  }

  @Builder
  private CommentSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.58)')
        .onClick(() => this.commentSheetVisible = false)
      Column() {
        Row() {
          Column({ space: 3 }) {
            Text(`歌单评论 · ${this.commentCount}`).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            Text(this.playlist.name).fontSize(10).fontColor('#77777f').maxLines(1)
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor(['#66666e'])
            .onClick(() => this.commentSheetVisible = false)
        }
        .height(66).padding({ left: 20, right: 20 })
        if (this.commentsLoading) {
          LoadingProgress().layoutWeight(1).width(42).color('#ef233c')
        } else if (this.comments.length === 0) {
          Text('暂无评论').layoutWeight(1).fontSize(13).fontColor('#77777f')
        } else {
          List({ space: 14 }) {
            ForEach(this.comments, (item: MusicComment) => {
              ListItem() {
                Row({ space: 10 }) {
                  Image(item.user.avatarUrl).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover)
                  Column({ space: 6 }) {
                    Row() {
                      Text(item.user.nickname).layoutWeight(1).fontSize(12).fontColor('#a9a9b0')
                      Text(`♡ ${item.likedCount}`).fontSize(10).fontColor('#77777f')
                    }
                    Text(item.content).fontSize(13).lineHeight(20).fontColor('#ededf0')
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                }
                .padding({ left: 18, right: 18 })
              }
            })
          }
          .layoutWeight(1)
        }
      }
      .width('100%').height('68%').backgroundColor('#19191f')
      .borderRadius({ topLeft: 28, topRight: 28 })
      .transition(TransitionEffect.translate({ y: 600 }).animation({ duration: 260, curve: Curve.EaseOut }))
    }
    .width('100%').height('100%')
  }

  @Builder
  private MenuOption(icon: Resource, title: string, description: string, danger: boolean, action: () => void) {
    Row({ space: 13 }) {
      Stack() {
        SymbolGlyph(icon).fontSize(21).fontColor([danger ? '#ff6577' : '#ededf0'])
      }.width(42).height(42).borderRadius(13).backgroundColor(danger ? '#342126' : '#29292f')
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(danger ? '#ff6577' : '#ededf0')
        Text(description).fontSize(10).fontColor('#77777f')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor(['#55555d'])
    }.width('100%').height(64).onClick(action)
  }

  @Builder
  private OwnerMenuSheet() {
    Column({ space: 4 }) {
      Row() {
        Column({ space: 3 }) {
          Text('管理歌单').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text(this.playlist.name).fontSize(10).fontColor('#77777f').maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(25).fontColor(['#686870'])
          .onClick(() => this.ownerMenuVisible = false)
      }.width('100%').height(54)
      this.MenuOption($r('sys.symbol.square_and_pencil'), '编辑歌单', '修改名称、简介、标签、封面与可见范围', false,
        () => this.openEditor())
      this.MenuOption($r('sys.symbol.plus_circle'), '添加歌曲', '搜索歌曲并添加到当前歌单', false,
        () => this.openSongManager('add'))
      this.MenuOption($r('sys.symbol.sort'), '调整顺序', '重新排列歌单中的歌曲', false,
        () => this.openSongManager('order'))
      this.MenuOption($r('sys.symbol.trash'), '删除歌单', '删除后无法恢复', true, () => {
        this.ownerMenuVisible = false
        this.deleteConfirmVisible = true
      })
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 10, bottom: 24 })
  }

  @Builder
  private SongMenuSheet() {
    Column({ space: 5 }) {
      Row() {
        Column({ space: 3 }) {
          Text('歌曲操作').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text(this.selectedSongName).fontSize(10).fontColor('#77777f').maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(25).fontColor(['#686870'])
          .onClick(() => this.songMenuVisible = false)
      }.width('100%').height(54)
      this.MenuOption($r('sys.symbol.arrow_up_circle'), '置顶', '移动到歌单第一首', false,
        () => this.pinSelectedSong())
      this.MenuOption($r('sys.symbol.trash'), '移除歌曲', '从当前歌单中移除，不会删除歌曲', true,
        () => this.removeSelectedSong())
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 10, bottom: 24 })
  }

  @Builder
  private DeleteConfirmSheet() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill')).fontSize(38).fontColor(['#ff765f'])
      Text('删除这个歌单？').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
      Text(`“${this.playlist.name}”删除后无法恢复。`).fontSize(12).lineHeight(19).fontColor('#8b8b93')
        .textAlign(TextAlign.Center)
      Row({ space: 10 }) {
        Button('取消').layoutWeight(1).height(44).fontSize(13).fontColor('#d0d0d5')
          .backgroundColor('#29292f').borderRadius(14).onClick(() => this.deleteConfirmVisible = false)
        Button(this.deleting ? '删除中' : '确认删除').layoutWeight(1).height(44).fontSize(13).fontColor('#ffffff')
          .backgroundColor('#ef233c').borderRadius(14).enabled(!this.deleting).onClick(() => this.deletePlaylist())
      }.width('100%')
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .padding({ left: 22, right: 22, bottom: 18 })
  }

  @Builder
  private MenuSheetOverlay(kind: string) {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%').height('100%').backgroundColor('rgba(0,0,0,0.58)')
        .onClick(() => {
          this.ownerMenuVisible = false
          this.songMenuVisible = false
          this.deleteConfirmVisible = false
        })
      Column() {
        if (kind === 'owner') {
          this.OwnerMenuSheet()
        } else if (kind === 'song') {
          this.SongMenuSheet()
        } else {
          this.DeleteConfirmSheet()
        }
      }
      .width('100%')
      .height(kind === 'owner' ? 360 : kind === 'song' ? 238 : 290)
      .backgroundColor('#19191f')
      .borderRadius({ topLeft: 28, topRight: 28 })
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.42)', offsetY: -4 })
      .transition(TransitionEffect.translate({ y: 420 }).animation({ duration: 240, curve: Curve.EaseOut }))
    }
    .width('100%').height('100%')
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          Stack({ alignContent: Alignment.BottomStart }) {
            Image(this.playlist.cover).width('100%').height('100%').objectFit(ImageFit.Cover).blur(48).opacity(0.55)
            Column().width('100%').height('100%')
              .linearGradient({ angle: 180, colors: [['rgba(15,15,20,0.22)', 0], ['#121215', 1]] })

            Column() {
              Row() {
                SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
                  .onClick(() => this.pageStack.pop())
                if (this.searchVisible) {
                  TextInput({ text: this.keyword, placeholder: '搜索歌单内歌曲' })
                    .layoutWeight(1).height(38).fontColor('#ffffff').placeholderColor('#888890')
                    .backgroundColor('rgba(20,20,25,0.62)').borderRadius(14)
                    .onChange((value: string) => this.keyword = value)
                } else {
                  Text('歌单').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
                    .fontColor('#ffffff').textAlign(TextAlign.Center)
                }
                SymbolGlyph(this.searchVisible ? $r('sys.symbol.xmark_circle_fill') : $r('sys.symbol.magnifyingglass'))
                  .fontSize(21).fontColor(['#ffffff']).margin({ right: 16 })
                  .onClick(() => {
                    this.searchVisible = !this.searchVisible
                    if (!this.searchVisible) this.keyword = ''
                  })
                SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(22).fontColor(['#ffffff'])
                  .onClick(() => {
                    if (this.isOwner()) {
                      this.ownerMenuVisible = true
                    } else {
                      this.sharePlaylist()
                    }
                  })
              }
              .width('100%').height(56 + this.topAvoidHeight)
              .padding({ top: this.topAvoidHeight })

              Row({ space: 16 }) {
                Image(this.playlist.cover).width(120).height(120).borderRadius(14).objectFit(ImageFit.Cover)
                  .shadow({ radius: 18, color: 'rgba(0,0,0,0.32)', offsetY: 8 })
                  .onClick(() => {
                    const param: PlaylistCoverPreviewPageParam = {
                      playlist: this.playlist,
                      playCount: this.playCount,
                      collectCount: this.collectCount,
                      commentCount: this.commentCount,
                      tags: this.playlistTags,
                      description: this.playlistDescription
                    };
                    this.pageStack.pushPathByName('PlaylistCoverPreviewPage', param);
                  })
                Column({ space: 8 }) {
                  Text(this.playlist.name).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#ffffff').maxLines(3)
                  Row({ space: 5 }) {
                    SymbolGlyph($r('sys.symbol.person_crop_circle_fill')).fontSize(15).fontColor(['#b8b8c0'])
                    Text(this.playlist.creator).fontSize(12).fontColor('#d0d0d6').maxLines(1)
                  }
                  .onClick(() => this.openCreatorProfile())
                  Text(`${this.playlist.count} 首歌曲 · ${this.formatCount(this.playCount)} 次播放`)
                    .fontSize(11).fontColor('#77777f')
                  if (this.playlistTags.length > 0) {
                    Text(this.playlistTags.join(' · ')).fontSize(10).fontColor('#ef6577').maxLines(1)
                  }
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .width('100%').padding({ top: 12, bottom: 16 })
            }
            .width('100%').padding({ left: 18, right: 18 })
          }
          .width('100%').height(280 + this.topAvoidHeight)

          Row({ space: 10 }) {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(15).fontColor(['#ffffff'])
                Text(`播放全部 ${this.filteredSongs().length}`).fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor('#ffffff')
              }
            }
            .layoutWeight(1).height(40).backgroundColor('#ef233c').borderRadius(20)
            .type(ButtonType.Normal).onClick(() => this.playAt(0))

            Button() {
              Row({ space: 4 }) {
                SymbolGlyph(this.subscribed ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(14).fontColor([this.subscribed ? '#ef4058' : '#b0b0b8'])
                Text(this.formatCount(this.collectCount)).fontSize(10)
                  .fontColor(this.subscribed ? '#ef4058' : '#b0b0b8')
              }
            }
            .height(40).backgroundColor(this.subscribed ? 'rgba(239,35,60,0.12)' : '#27272d')
            .borderRadius(20).type(ButtonType.Normal).padding({ left: 12, right: 12 })
            .onClick(() => this.toggleSubscribe())

            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(14).fontColor(['#b0b0b8'])
                Text(this.formatCount(this.commentCount)).fontSize(10).fontColor('#b0b0b8')
              }
            }
            .height(40).backgroundColor('#27272d').borderRadius(20).type(ButtonType.Normal)
            .padding({ left: 12, right: 12 }).onClick(() => this.openComments())

            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.share')).fontSize(14).fontColor(['#b0b0b8'])
                Text(this.formatCount(this.shareCount)).fontSize(10).fontColor('#b0b0b8')
              }
            }
            .height(40).backgroundColor('#27272d').borderRadius(20).type(ButtonType.Normal)
            .padding({ left: 12, right: 12 }).onClick(() => this.sharePlaylist())
          }
          .width('100%').height(62).padding({ left: 16, right: 16, top: 10, bottom: 10 })

          if (this.loading) {
            LoadingProgress().layoutWeight(1).width(46).color('#ef233c')
          } else if (this.message && this.songList.length === 0) {
            Column({ space: 12 }) {
              Text(this.message).fontSize(12).fontColor('#77777f')
              Button('重试').fontColor('#ff6577').backgroundColor('#2b2024')
                .onClick(() => {
                  this.loading = true
                  this.message = ''
                  this.loadDetail()
                })
            }
            .layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            List() {
              ForEach(this.filteredSongs(), (item: songItemType, index: number) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Text((index + 1).toString()).width(26).fontSize(12)
                      .fontColor(index < 3 ? '#ff6577' : '#66666e').textAlign(TextAlign.Center)
                      .onClick(() => this.playAt(index))
                    Column({ space: 4 }) {
                      Text(item.name).fontSize(14).fontColor('#ededf0').maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`${item.author}${item.album ? ` · ${item.album}` : ''}`)
                        .fontSize(11).fontColor('#77777f').maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.playAt(index))
                    SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(19).fontColor(['#66666e'])
                      .onClick(() => this.openSongMenu(item))
                  }
                  .height(62).padding({ left: 14, right: 16 })
                }
              })
              if (this.filteredSongs().length === 0) {
                ListItem() {
                  Text('没有找到匹配歌曲').width('100%').height(120).fontSize(12)
                    .fontColor('#77777f').textAlign(TextAlign.Center)
                }
              }
            }
            .layoutWeight(1).backgroundColor('#121215')
          }

          if (this.message && this.songList.length > 0) {
            Text(this.message).width('100%').fontSize(10).fontColor('#ff6577')
              .textAlign(TextAlign.Center).padding({ bottom: 6 })
          }
        }
        .width('100%').height('100%').backgroundColor('#121215')

        if (this.ownerMenuVisible) {
          this.MenuSheetOverlay('owner')
        }
        if (this.songMenuVisible) {
          this.MenuSheetOverlay('song')
        }
        if (this.deleteConfirmVisible) {
          this.MenuSheetOverlay('delete')
        }

        if (this.commentSheetVisible) {
          this.CommentSheet()
        }

        if (this.shareSheetVisible) {
          ShareSheet({
            shareParam: this.shareParam,
            visible: this.shareSheetVisible,
            onClose: () => this.shareSheetVisible = false
          })
        }
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
  }
}
