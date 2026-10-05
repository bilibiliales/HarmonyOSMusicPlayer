import { common } from '@kit.AbilityKit'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { CloudSong } from '../models/cloud'
import { mapApiSong, mapPlaylist, OperationResponse, SearchResponse, UserPlaylistResponse } from '../models/api'
import { playlistType, songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { CloudService } from '../services/CloudService'
import { playerController } from '../services/PlayerController'
import { BubbleTip } from '../services/BubbleTip'
import { AuthStore } from '../stores/AuthStore'

@Component
export struct CloudDrivePage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  @State songs: CloudSong[] = []
  @State loading: boolean = false
  @State complete: boolean = false
  @State busy: boolean = false
  @State message: string = ''
  @State quota: string = ''
  @State query: string = ''
  @State sortKey: string = 'new'
  @State selecting: boolean = false
  @State selected: string[] = []
  @State sheet: string = ''
  @State target?: CloudSong = undefined
  @State matchQuery: string = ''
  @State matches: songItemType[] = []
  @State searching: boolean = false
  @State searchMore: boolean = false
  @State sheetMessage: string = ''
  @State playlists: playlistType[] = []
  @State sheetLoading: boolean = false
  private service?: CloudService
  private loadToken: number = 0
  private searchToken: number = 0
  private disposed: boolean = false
  private actionIds: string[] = []

  aboutToAppear(): void {
    this.disposed = false
    if (this.authStore.loggedIn) {
      this.service = new CloudService(this.authStore.userId)
      this.reload()
    }
  }

  aboutToDisappear(): void { this.disposed = true; this.loadToken++; this.searchToken++ }

  private owner(): CloudService {
    if (this.disposed || !this.authStore.loggedIn || !this.service || this.service.uid !== this.authStore.userId) {
      throw new Error('请登录后重新进入云盘')
    }
    this.service.check()
    return this.service
  }

  private bytes(size: number): string { return `${(Math.max(0, size) / 1024 / 1024).toFixed(1)} MB` }

  private async reload(): Promise<void> {
    const token = ++this.loadToken
    this.loading = true
    this.complete = false
    this.message = ''
    this.selected = []
    this.songs = []
    let offset = 0
    try {
      const service = this.owner()
      while (true) {
        const response = await service.list(offset)
        if (token !== this.loadToken) { return }
        const incoming = response.data || []
        const fresh = incoming.filter((song: CloudSong) => !this.songs.some((old: CloudSong) => old.songId === song.songId))
        this.songs = this.songs.concat(fresh)
        this.quota = response.maxSize ? `${this.bytes(Number(response.size || 0))} / ${this.bytes(Number(response.maxSize))}` : ''
        offset += incoming.length
        const more = response.hasMore === undefined ? offset < (response.count || 0) : response.hasMore
        if (!more) { break }
        if (!fresh.length) { throw new Error('云盘分页未返回新数据，请重试') }
      }
      this.complete = true
    } catch (error) {
      if (token === this.loadToken) { this.message = error instanceof Error ? error.message : '云盘加载失败' }
    } finally {
      if (token === this.loadToken) { this.loading = false }
    }
  }

  private visibleSongs(): CloudSong[] {
    const query = this.query.trim().toLowerCase()
    return this.songs.filter((song: CloudSong) =>
      `${CloudService.song(song).name} ${song.songName || ''} ${CloudService.song(song).author} ${song.album || ''} ${song.fileName || ''}`
        .toLowerCase().includes(query)).sort((a: CloudSong, b: CloudSong) => {
      if (this.sortKey === 'name') { return CloudService.song(a).name.localeCompare(CloudService.song(b).name) }
      if (this.sortKey === 'artist') { return CloudService.song(a).author.localeCompare(CloudService.song(b).author) }
      if (this.sortKey === 'size') { return (b.fileSize || 0) - (a.fileSize || 0) }
      return this.sortKey === 'old' ? (a.addTime || 0) - (b.addTime || 0) : (b.addTime || 0) - (a.addTime || 0)
    })
  }

  private toggle(id: string): void {
    this.selected = this.selected.includes(id) ? this.selected.filter((value: string) => value !== id) : this.selected.concat([id])
  }

  private selectAll(): void {
    const ids = this.visibleSongs().map((song: CloudSong) => String(song.songId))
    this.selected = ids.every((id: string) => this.selected.includes(id)) ?
      this.selected.filter((id: string) => !ids.includes(id)) :
      this.selected.concat(ids.filter((id: string) => !this.selected.includes(id)))
  }

  private async play(song?: CloudSong): Promise<void> {
    try {
      this.owner()
      const list = this.visibleSongs()
      const index = song ? list.findIndex((item: CloudSong) => item.songId === song.songId) : 0
      if (list.length) { await playerController.setQueue(list.map(CloudService.song), Math.max(0, index), true) }
    } catch (error) { this.message = error instanceof Error ? error.message : '播放失败' }
  }

  private async enqueue(): Promise<void> {
    try {
      this.owner()
      const chosen = this.visibleSongs().filter((song: CloudSong) => this.selected.includes(String(song.songId)))
      // Also retain selected rows hidden by a later search, in cloud order.
      const hidden = this.songs.filter((song: CloudSong) => this.selected.includes(String(song.songId)) &&
        !chosen.some((item: CloudSong) => item.songId === song.songId))
      await playerController.insertNext(chosen.concat(hidden).map(CloudService.song))
      BubbleTip.show(this.getUIContext(), '已加入下一首，按选择列表顺序播放')
      this.selected = []
      this.selecting = false
    } catch (error) { this.message = error instanceof Error ? error.message : '加入队列失败' }
  }

  private async more(song: CloudSong): Promise<void> {
    this.target = song
    this.sheet = 'more'
    this.sheetMessage = ''
    this.sheetLoading = true
    try {
      const detail = await this.owner().detail(String(song.songId))
      if (this.target?.songId === song.songId && this.sheet === 'more') { this.target = detail }
    } catch (error) { this.sheetMessage = error instanceof Error ? error.message : '详情加载失败' }
    finally { this.sheetLoading = false }
  }

  private openMatch(): void {
    this.sheet = 'match'
    this.matchQuery = this.target ? CloudService.song(this.target).name : ''
    this.matches = []
    this.sheetMessage = ''
    this.search(true)
  }

  private async search(reset: boolean): Promise<void> {
    if (!this.matchQuery.trim()) { return }
    const token = ++this.searchToken
    if (reset) { this.matches = [] }
    this.searching = true
    this.sheetMessage = ''
    const offset = this.matches.length
    try {
      this.owner()
      const response = await ApiClient.get<SearchResponse>('/cloudsearch', [
        { key: 'keywords', value: this.matchQuery.trim() }, { key: 'type', value: '1' },
        { key: 'limit', value: '30' }, { key: 'offset', value: offset.toString() }])
      this.owner()
      if (token !== this.searchToken || this.sheet !== 'match') { return }
      if (response.code !== 200) { throw new Error('搜索失败，请重试') }
      const incoming = (response.result?.songs || []).map(mapApiSong)
      this.matches = this.matches.concat(incoming)
      this.searchMore = incoming.length > 0 && this.matches.length < (response.result?.songCount || 0)
      if (!this.matches.length) { this.sheetMessage = '未找到歌曲，试试歌名或歌手名' }
    } catch (error) {
      if (token === this.searchToken) { this.sheetMessage = error instanceof Error ? error.message : '搜索失败' }
    } finally { if (token === this.searchToken) { this.searching = false } }
  }

  private async match(id: string): Promise<void> {
    if (!this.target || this.busy) { return }
    const targetId = String(this.target.songId)
    this.busy = true
    try {
      await this.owner().match(targetId, id)
      this.sheet = ''
      await this.reload()
      BubbleTip.show(this.getUIContext(), id === '0' ? '已解除关联' : '已更新歌曲关联')
    } catch (error) { this.sheetMessage = error instanceof Error ? error.message : '纠偏失败' }
    finally { this.busy = false }
  }

  private requestDelete(ids: string[]): void {
    this.actionIds = ids.slice()
    this.sheetMessage = ''
    this.sheet = 'delete'
  }

  private async batch(playlist?: playlistType): Promise<void> {
    if (this.busy || !this.actionIds.length) { return }
    const ids = this.actionIds.slice()
    this.busy = true
    let done = 0
    try {
      const service = this.owner()
      for (let offset = 0; offset < ids.length; offset += 100) {
        const group = ids.slice(offset, offset + 100)
        service.check()
        if (playlist) {
          const response = await ApiClient.get<OperationResponse>('/playlist/tracks', [
            { key: 'op', value: 'add' }, { key: 'pid', value: playlist.id }, { key: 'tracks', value: group.join(',') }])
          service.check()
          if (response.code !== 200) { throw new Error(response.message || '收藏失败，请检查歌单权限或重复歌曲') }
        } else { await service.remove(group) }
        done += group.length
      }
      this.sheet = ''
      BubbleTip.show(this.getUIContext(), playlist ? `已收藏到「${playlist.name}」` : `已删除 ${done} 首`)
    } catch (error) {
      this.sheetMessage = `已处理 ${done}/${ids.length} 首：${error instanceof Error ? error.message : '操作失败'}`
      this.actionIds = ids.slice(done)
    } finally {
      if (!playlist) { await this.reload() }
      this.busy = false
    }
  }

  private async choosePlaylist(): Promise<void> {
    this.actionIds = this.selected.slice()
    this.playlists = []
    this.sheetMessage = ''
    this.sheet = 'collect'
    this.sheetLoading = true
    try {
      const service = this.owner()
      let offset = 0
      const seen: number[] = []
      while (true) {
        service.check()
        const response = await ApiClient.get<UserPlaylistResponse>('/user/playlist', [
          { key: 'uid', value: service.uid }, { key: 'limit', value: '200' }, { key: 'offset', value: offset.toString() }])
        service.check()
        if (this.disposed || this.sheet !== 'collect') { return }
        if (response.code !== 200) { throw new Error('歌单加载失败') }
        const items = response.playlist || response.data?.playlist || []
        if (items.length && items.every((item) => seen.includes(item.id))) { throw new Error('歌单分页未返回新数据，请重试') }
        items.forEach((item) => seen.push(item.id))
        this.playlists = this.playlists.concat(items.map(mapPlaylist).filter((item: playlistType) => item.creatorId === service.uid))
        offset += items.length
        if (!items.length || items.length < 200) { break }
      }
      if (!this.playlists.length) { this.sheetMessage = '暂无可收藏的自建歌单' }
    } catch (error) { this.sheetMessage = error instanceof Error ? error.message : '歌单加载失败' }
    finally { this.sheetLoading = false }
  }

  private async upload(): Promise<void> {
    if (this.busy) { return }
    this.busy = true
    let succeeded = 0
    const failed: string[] = []
    try {
      const service = this.owner()
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const options = new picker.AudioSelectOptions()
      options.maxSelectNumber = 20
      const uris = await new picker.AudioViewPicker(context).select(options)
      for (const uri of uris) {
        service.check()
        const name = new fileUri.FileUri(uri).name
        try {
          if (!name.toLowerCase().endsWith('.mp3')) { throw new Error('仅支持 MP3 文件') }
          this.message = `正在上传 ${succeeded + failed.length + 1}/${uris.length}：${name}`
          const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
          try {
            const size = (await fileIo.stat(file.fd)).size
            if (size < 3) { throw new Error('文件为空或无效') }
            const buffer = new ArrayBuffer(size)
            const read = await fileIo.read(file.fd, buffer)
            if (read !== size) { throw new Error('文件读取不完整') }
            const head = new Uint8Array(buffer, 0, 3)
            if (!(head[0] === 73 && head[1] === 68 && head[2] === 51) &&
              !(head[0] === 255 && (head[1] & 224) === 224 && (head[1] & 6) !== 0)) {
              throw new Error('文件内容不是 MP3')
            }
            await service.upload(name, buffer)
            succeeded++
          } finally { await fileIo.close(file) }
        } catch (error) { failed.push(`${name}：${error instanceof Error ? error.message : '上传失败'}`) }
      }
      if (uris.length) {
        await this.reload()
        this.message = `上传完成 ${succeeded}/${uris.length}${failed.length ? `；${failed.join('；')}` : ''}`
      }
    } catch (error) { this.message = error instanceof Error ? error.message : '上传失败' }
    finally { this.busy = false }
  }

  @Builder
  private SheetContent() {
    Column({ space: 14 }) {
      Row() {
        Text(this.sheet === 'match' ? '歌曲纠偏' : this.sheet === 'collect' ? '收藏到歌单' :
          this.sheet === 'delete' ? '删除云盘歌曲' : this.sheet === 'sort' ? '排列顺序' : '歌曲选项')
          .fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ffffff').layoutWeight(1)
        Text('关闭').fontSize(14).fontColor('#9999a1').enabled(!this.busy).onClick(() => { this.sheet = ''; this.searchToken++ })
      }.width('100%')
      if (this.sheetMessage) { Text(this.sheetMessage).fontSize(12).fontColor('#ff6577') }
      if (this.busy || this.sheetLoading) { LoadingProgress().width(26).height(26).color('#ef233c') }
      if (this.sheet === 'more' && this.target) {
        Text(CloudService.song(this.target).name).fontSize(17).fontColor('#eeeeee')
        Text(`${CloudService.song(this.target).author} · ${this.bytes(this.target.fileSize || 0)}`)
          .fontSize(12).fontColor('#888890')
        Button('纠偏 / 解除关联').width('100%').backgroundColor('#303038').enabled(!this.busy && !this.sheetLoading)
          .onClick(() => this.openMatch())
        Button('删除').width('100%').backgroundColor('#ef233c').enabled(!this.busy)
          .onClick(() => { if (this.target) { this.requestDelete([String(this.target.songId)]) } })
      } else if (this.sheet === 'match') {
        Search({ value: this.matchQuery, placeholder: '搜索要关联的歌名或歌手' })
          .onChange((value: string) => { this.matchQuery = value; this.searchToken++; this.searching = false; this.matches = []; this.searchMore = false })
          .onSubmit(() => this.search(true)).searchButton('搜索').enabled(!this.busy)
        Button('解除当前关联').width('100%').backgroundColor('#303038').enabled(!this.busy).onClick(() => this.match('0'))
        List() {
          ForEach(this.matches, (song: songItemType) => {
            ListItem() {
              Column({ space: 5 }) {
                Text(song.name).fontSize(15).fontColor('#ffffff').maxLines(1)
                Text(`${song.author} · ${song.album || ''}`).fontSize(12).fontColor('#9999a1').maxLines(1)
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 12, bottom: 12 })
                .enabled(!this.busy).onClick(() => this.match(song.id))
            }
          }, (song: songItemType) => song.id)
          ListItem() {
            if (this.searching) { LoadingProgress().width(26).height(26) }
            else if (this.searchMore) { Button('更多结果').onClick(() => this.search(false)) }
          }
        }.layoutWeight(1)
      } else if (this.sheet === 'delete') {
        Text(`确认从云盘删除 ${this.actionIds.length} 首歌曲？删除后需重新上传才能恢复。`)
          .fontSize(15).fontColor('#dddddf')
        Button('确认删除').backgroundColor('#ef233c').enabled(!this.busy).onClick(() => this.batch())
      } else if (this.sheet === 'collect') {
        List() {
          ForEach(this.playlists, (playlist: playlistType) => {
            ListItem() {
              Text(playlist.name).fontSize(16).fontColor('#eeeeee').width('100%').padding(16)
                .enabled(!this.busy).onClick(() => this.batch(playlist))
            }
          }, (playlist: playlistType) => playlist.id)
        }.layoutWeight(1)
      } else if (this.sheet === 'sort') {
        ForEach(['new', 'old', 'name', 'artist', 'size'], (key: string) => {
          Text(key === 'new' ? '上传时间：新到旧' : key === 'old' ? '上传时间：旧到新' :
            key === 'name' ? '歌曲名称' : key === 'artist' ? '歌手名称' : '文件大小：大到小')
            .fontSize(16).fontColor(this.sortKey === key ? '#ff6577' : '#eeeeee').width('100%').padding(14)
            .onClick(() => { this.sortKey = key; this.sheet = '' })
        })
      }
    }.width('100%').height('100%').padding(20)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column({ space: 10 }) {
          Row({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff']).onClick(() => this.pageStack.pop())
            Text('我的云盘').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#ffffff').layoutWeight(1)
            Text('上传').fontSize(15).fontColor('#ff6577').enabled(!this.busy && !this.loading && this.authStore.loggedIn)
              .onClick(() => this.upload())
          }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 18, right: 18, top: this.topAvoidHeight })
          if (!this.authStore.loggedIn) {
            Button('登录后使用云盘').onClick(() => this.pageStack.pushPathByName('LoginPage', null))
          } else {
            Search({ value: this.query, placeholder: '查找云盘歌曲、歌手或文件名' }).margin({ left: 16, right: 16 })
              .onChange((value: string) => this.query = value)
            Row() {
              Text(`共 ${this.songs.length} 首${this.quota ? ` · ${this.quota}` : ''}`).fontSize(11).fontColor('#888890').layoutWeight(1)
              Text('刷新').fontSize(13).fontColor('#aaaaB2').enabled(!this.loading && !this.busy).onClick(() => this.reload())
            }.width('100%').padding({ left: 18, right: 18 })
            if (this.message) { Text(this.message).fontSize(12).fontColor('#ff6577').padding({ left: 18, right: 18 }).maxLines(4) }
            if (this.loading) { Text('正在加载完整云盘列表…').fontSize(12).fontColor('#9999a1') }
            Row({ space: 20 }) {
              Text('播放全部').fontSize(15).fontColor('#ffffff').onClick(() => this.play())
              Blank()
              Text('排序').fontSize(14).fontColor('#aaaaB2').onClick(() => this.sheet = 'sort')
              Text(this.selecting ? '完成' : '多选').fontSize(14).fontColor('#aaaaB2')
                .onClick(() => { this.selecting = !this.selecting; this.selected = [] })
            }.width('100%').padding({ left: 18, right: 18 }).height(40).enabled(this.complete && !this.busy)
            List() {
              ForEach(this.visibleSongs(), (song: CloudSong) => {
                ListItem() {
                  Row({ space: 12 }) {
                    if (this.selecting) {
                      SymbolGlyph(this.selected.includes(String(song.songId)) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
                        .fontSize(22).fontColor(['#ef233c']).onClick(() => this.toggle(String(song.songId)))
                    }
                    Image(CloudService.song(song).img).width(48).height(48).borderRadius(8).objectFit(ImageFit.Cover)
                      .backgroundColor('#25252c')
                    Column({ space: 5 }) {
                      Text(CloudService.song(song).name).fontSize(15).fontColor('#eeeeee').maxLines(1)
                      Text(`${CloudService.song(song).author} · ${this.bytes(song.fileSize || 0)}`).fontSize(11).fontColor('#888890').maxLines(1)
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => {
                      if (this.selecting) { this.toggle(String(song.songId)) } else { this.play(song) }
                    })
                    if (!this.selecting) {
                      SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(23).fontColor(['#aaaaB2']).onClick(() => this.more(song))
                    }
                  }.height(70).padding({ left: 18, right: 18 }).enabled(!this.busy && this.complete)
                }
              }, (song: CloudSong) => String(song.songId))
              if (!this.loading && this.visibleSongs().length === 0) {
                ListItem() { Text(this.query ? '未找到匹配的歌曲' : '云盘暂无歌曲，点击右上角上传 MP3')
                  .fontSize(14).fontColor('#888890').padding(28) }
              }
            }.layoutWeight(1).width('100%')
            if (this.selecting) {
              Row({ space: 16 }) {
                Text(`全选 (${this.selected.length})`).fontColor('#eeeeee').onClick(() => this.selectAll())
                Text('收藏').fontColor('#eeeeee').enabled(this.selected.length > 0).onClick(() => this.choosePlaylist())
                Text('加入队列').fontColor('#eeeeee').enabled(this.selected.length > 0).onClick(() => this.enqueue())
                Text('删除').fontColor('#ff6577').enabled(this.selected.length > 0).onClick(() => this.requestDelete(this.selected))
              }.height(56).width('100%').justifyContent(FlexAlign.Center).enabled(!this.busy && this.complete)
            }
          }
        }.width('100%').height('100%')
        if (this.sheet) {
          Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.55)')
            .onClick(() => { if (!this.busy) { this.sheet = ''; this.searchToken++ } })
          Column() { this.SheetContent() }.width('100%').height('62%').backgroundColor('#19191f')
            .borderRadius({ topLeft: 24, topRight: 24 })
        }
      }.width('100%').height('100%').backgroundColor('#121215')
    }.hideTitleBar(true)
  }
}
