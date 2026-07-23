import {
  AlbumPageParam,
  ApiArtist,
  EventCommentItem,
  EventCommentResponse,
  EventDetailPageParam,
  EventFeedResponse,
  EventForwardData,
  EventJsonData,
  EventPicture,
  HotTopicItem,
  HotTopicResponse,
  MvPlayerPageParam,
  OperationResponse,
  TopicHotEventResponse,
  UserEventItem,
  UserProfilePageParam
} from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { resizeImageUrl } from '../services/ImageUrl'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'

@Component
struct Moment {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('authStore') authStore: AuthStore
  @Consume('playerStore') playerStore: PlayerStore
  @State events: UserEventItem[] = []
  @State discoverEvents: UserEventItem[] = []
  @State currentTab: string = 'following'
  @State loading: boolean = false
  @State discoverLoading: boolean = false
  @State discoverMore: boolean = true
  @State topicOffset: number = 0
  @State more: boolean = true
  @State lasttime: number = -1
  @State message: string = ''
  @State commentSheetVisible: boolean = false
  @State commentsLoading: boolean = false
  @State comments: EventCommentItem[] = []
  @State commentTotal: number = 0
  @State selectedThreadId: string = ''
  @State commentMessage: string = ''
  @State isRefreshing: boolean = false
  // 一个话题仍按接口要求取 30 条，但避免同时创建 5 个话题、最多 150 张原图节点。
  private readonly topicPageSize: number = 1

  aboutToAppear(): void {
    if (this.authStore.loggedIn && this.events.length === 0) {
      this.loadEvents()
    }
  }

  private switchTab(tab: string): void {
    this.currentTab = tab
    if (tab === 'following' && this.authStore.loggedIn && this.events.length === 0) {
      this.loadEvents()
    } else if (tab === 'discover' && this.discoverEvents.length === 0) {
      this.loadDiscoverEvents()
    }
  }

  private async refreshCurrentTab(): Promise<void> {
    try {
      if (this.currentTab === 'discover') {
        await this.loadDiscoverEvents(true)
      } else if (this.authStore.loggedIn) {
        await this.loadEvents(true)
      }
    } finally {
      this.isRefreshing = false
    }
  }

  private hasEventPicture(item: UserEventItem): boolean {
    return this.discoveryImage(item).length > 0
  }

  private shuffled(events: UserEventItem[]): UserEventItem[] {
    const result = events.slice()
    for (let index = result.length - 1; index > 0; index--) {
      const target = Math.floor(Math.random() * (index + 1))
      const current = result[index]
      result[index] = result[target]
      result[target] = current
    }
    return result
  }

  private async loadTopicHotEvents(topic: HotTopicItem): Promise<TopicHotEventResponse> {
    try {
      return await ApiClient.get<TopicHotEventResponse>('/topic/detail/event/hot', [
        { key: 'actid', value: topic.actId.toString() },
        { key: 'limit', value: '30' },
        { key: 'timestamp', value: `${Date.now()}-${topic.actId}` }
      ])
    } catch (error) {
      console.error(`[Moment] topic ${topic.actId} load failed: ${error instanceof Error ? error.message : 'unknown error'}`)
      return { code: 0, events: [] }
    }
  }

  private async loadDiscoverEvents(reset: boolean = false): Promise<void> {
    if (this.discoverLoading || (!this.discoverMore && !reset)) {
      return
    }
    if (reset) {
      this.discoverEvents = []
      this.topicOffset = 0
      this.discoverMore = true
    }
    this.discoverLoading = true
    this.message = ''
    try {
      const topicResponse = await ApiClient.get<HotTopicResponse>('/hot/topic', [
        { key: 'limit', value: this.topicPageSize.toString() },
        { key: 'offset', value: this.topicOffset.toString() },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      const topics = topicResponse.hot || []
      if (topics.length === 0) {
        this.discoverMore = false
        return
      }
      const tasks: Promise<TopicHotEventResponse>[] = []
      topics.forEach((topic: HotTopicItem) => {
        tasks.push(this.loadTopicHotEvents(topic))
      })
      const responses = await Promise.all(tasks)
      const incoming: UserEventItem[] = []
      responses.forEach((response: TopicHotEventResponse) => {
        (response.events || []).slice(0, 30).forEach((event: UserEventItem) => {
          const exists = this.discoverEvents.some((item: UserEventItem) => item.id === event.id) ||
            incoming.some((item: UserEventItem) => item.id === event.id)
          if (!exists && this.hasEventPicture(event)) {
            incoming.push(event)
          }
        })
      })
      this.discoverEvents = this.discoverEvents.concat(this.shuffled(incoming))
      this.topicOffset += topics.length
      this.discoverMore = topics.length >= this.topicPageSize
    } catch (error) {
      this.message = error instanceof Error ? error.message : '发现动态加载失败'
    } finally {
      this.discoverLoading = false
    }
  }

  private async loadEvents(reset: boolean = false): Promise<void> {
    if (!this.authStore.loggedIn || this.loading || (!this.more && !reset)) {
      return
    }
    if (reset) {
      this.events = []
      this.lasttime = -1
      this.more = true
    }
    this.loading = true
    this.message = ''
    try {
      const response = await ApiClient.get<EventFeedResponse>('/event', [
        { key: 'pagesize', value: '30' },
        { key: 'lasttime', value: this.lasttime.toString() },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code === 200) {
        this.events = this.events.concat(response.event || [])
        this.more = response.more || false
        this.lasttime = response.lasttime || -1
      } else {
        this.message = '动态加载失败'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '动态加载失败'
    } finally {
      this.loading = false
    }
  }

  private eventData(item: UserEventItem): EventJsonData {
    try {
      return JSON.parse(item.json) as EventJsonData
    } catch (_error) {
      const empty: EventJsonData = { msg: '' }
      return empty
    }
  }

  private forwardData(item: UserEventItem): EventForwardData | null {
    const data = this.eventData(item)
    return data.event || null
  }

  private isForwardEvent(item: UserEventItem): boolean {
    const forward = this.forwardData(item)
    return forward !== null && forward.id !== undefined && (forward.id ?? 0) > 0
  }

  private forwardResourceOf(forward: EventForwardData): EventResourceDisplay {
    if (!forward.json) {
      const empty: EventResourceDisplay = { kind: '', title: '', subtitle: '', image: '' }
      return empty
    }
    try {
      const data = JSON.parse(forward.json) as EventJsonData
      if (data.song) {
        const artists = data.song.ar || data.song.artists || []
        const album = data.song.al || data.song.album
        const result: EventResourceDisplay = {
          kind: '歌曲',
          title: data.song.name,
          subtitle: this.artistText(artists),
          image: album?.picUrl || data.song.picUrl || '',
          songId: data.song.id?.toString() || '',
          songName: data.song.name,
          songArtists: artists,
          songImg: album?.picUrl || data.song.picUrl || ''
        }
        return result
      }
      if (data.playlist) {
        const result: EventResourceDisplay = {
          kind: '歌单',
          title: data.playlist.name,
          subtitle: data.playlist.creator?.nickname || '',
          image: data.playlist.coverImgUrl || data.playlist.picUrl || ''
        }
        return result
      }
      if (data.album) {
        const artists = data.album.artists || (data.album.artist ? [data.album.artist] : [])
        const result: EventResourceDisplay = {
          kind: '专辑',
          title: data.album.name || '专辑',
          subtitle: this.artistText(artists),
          image: data.album.picUrl || '',
          albumId: data.album.id?.toString() || ''
        }
        return result
      }
      if (data.mv) {
        const result: EventResourceDisplay = {
          kind: 'MV',
          title: data.mv.name || 'MV',
          subtitle: data.mv.artistName || '',
          image: data.mv.imgurl16v9 || data.mv.imgurl || '',
          mvId: data.mv.id?.toString() || '',
          mvDuration: data.mv.duration,
          mvPlayCount: data.mv.playCount
        }
        return result
      }
    } catch (_error) {
    }
    const empty: EventResourceDisplay = { kind: '', title: '', subtitle: '', image: '' }
    return empty
  }

  private forwardEventItem(forward: EventForwardData): UserEventItem {
    const item: UserEventItem = {
      id: forward.id || 0,
      type: forward.type,
      eventTime: forward.eventTime,
      showTime: forward.showTime,
      json: forward.json || '',
      user: forward.user || { userId: 0, nickname: '', avatarUrl: '', followed: false, mutual: false },
      info: forward.info || { commentCount: 0, likedCount: 0, shareCount: 0 },
      pics: forward.pics,
      actName: forward.actName
    }
    return item
  }

  private openForwardEventDetail(forward: EventForwardData): void {
    const item = this.forwardEventItem(forward)
    const param: EventDetailPageParam = { event: item, canDelete: false }
    this.pageStack.pushPathByName('EventDetailPage', param)
  }

  private forwardContent(forward: EventForwardData): string {
    if (!forward.json) {
      return forward.actName || '源动态'
    }
    try {
      const data = JSON.parse(forward.json) as EventJsonData
      return data.msg || data.title || forward.actName || '源动态'
    } catch (_error) {
      return forward.actName || '源动态'
    }
  }

  private contentOf(item: UserEventItem): string {
    const data = this.eventData(item)
    return data.msg || data.title || item.actName || '分享了一条音乐动态'
  }

  private artistText(artists: ApiArtist[] | undefined): string {
    if (!artists || artists.length === 0) {
      return ''
    }
    return artists.map((artist: ApiArtist) => artist.name).join(' / ')
  }

  private resourceOf(item: UserEventItem): EventResourceDisplay {
    const data = this.eventData(item)
    if (data.song) {
      const artists = data.song.ar || data.song.artists || []
      const album = data.song.al || data.song.album
      const result: EventResourceDisplay = {
        kind: '歌曲',
        title: data.song.name,
        subtitle: this.artistText(artists),
        image: album?.picUrl || data.song.picUrl || '',
        songId: data.song.id?.toString() || '',
        songName: data.song.name,
        songArtists: artists,
        songImg: album?.picUrl || data.song.picUrl || ''
      }
      return result
    }
    if (data.playlist) {
      const result: EventResourceDisplay = {
        kind: '歌单',
        title: data.playlist.name,
        subtitle: data.playlist.creator?.nickname || '',
        image: data.playlist.coverImgUrl || data.playlist.picUrl || ''
      }
      return result
    }
    if (data.album) {
      const artists = data.album.artists || (data.album.artist ? [data.album.artist] : [])
      const result: EventResourceDisplay = {
        kind: '专辑',
        title: data.album.name || '专辑',
        subtitle: this.artistText(artists),
        image: data.album.picUrl || '',
        albumId: data.album.id?.toString() || ''
      }
      return result
    }
    if (data.mv) {
      const result: EventResourceDisplay = {
        kind: 'MV',
        title: data.mv.name || 'MV',
        subtitle: data.mv.artistName || '',
        image: data.mv.imgurl16v9 || data.mv.imgurl || '',
        mvId: data.mv.id?.toString() || '',
        mvDuration: data.mv.duration,
        mvPlayCount: data.mv.playCount
      }
      return result
    }
    if (data.video) {
      const result: EventResourceDisplay = {
        kind: '视频',
        title: data.video.title || '视频',
        subtitle: data.video.creator?.nickname || '',
        image: data.video.coverUrl || ''
      }
      return result
    }
    const resource = data.program || data.djRadio || data.resource
    if (resource) {
      const result: EventResourceDisplay = {
        kind: data.program ? '播客节目' : data.djRadio ? '播客' : '分享内容',
        title: resource.name || resource.title || '分享内容',
        subtitle: resource.description || this.artistText(resource.artists),
        image: resource.picUrl || resource.coverUrl || ''
      }
      return result
    }
    const empty: EventResourceDisplay = { kind: '', title: '', subtitle: '', image: '' }
    return empty
  }

  private pictureUrl(picture: EventPicture): string {
    const url = picture.rectangleUrl || picture.squareUrl || picture.pcSquareUrl || picture.originUrl || ''
    return resizeImageUrl(url, 720, 720)
  }

  private firstPicture(item: UserEventItem): EventPicture {
    const pictures = item.pics || []
    return pictures.length > 0 ? pictures[0] : {}
  }

  private discoveryImage(item: UserEventItem): string {
    const pictureUrl = this.pictureUrl(this.firstPicture(item))
    return pictureUrl.length > 0 ? pictureUrl : resizeImageUrl(this.resourceOf(item).image, 720, 720)
  }

  private formatEventTime(value: number): string {
    if (value <= 0) {
      return ''
    }
    const elapsed = Date.now() - value
    if (elapsed < 60000) {
      return '刚刚'
    }
    if (elapsed < 3600000) {
      return `${Math.floor(elapsed / 60000)}分钟前`
    }
    if (elapsed < 86400000) {
      return `${Math.floor(elapsed / 3600000)}小时前`
    }
    if (elapsed < 604800000) {
      return `${Math.floor(elapsed / 86400000)}天前`
    }
    const date = new Date(value)
    return `${date.getMonth() + 1}-${date.getDate()}`
  }

  private threadIdOf(item: UserEventItem): string {
    return item.info.threadId || `A_EV_2_${item.id}_${item.user.userId}`
  }

  private openUser(uid: number): void {
    const param: UserProfilePageParam = { uid: uid.toString() }
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private openEventDetail(item: UserEventItem): void {
    const param: EventDetailPageParam = { event: item, canDelete: false }
    this.pageStack.pushPathByName('EventDetailPage', param)
  }

  private discoverImageHeight(item: UserEventItem): number {
    const picture = (item.pics || [])[0]
    if (picture && picture.width && picture.height && picture.width > 0) {
      const height = 174 * picture.height / picture.width
      return Math.max(135, Math.min(260, height))
    }
    return 190
  }

  private playEventSong(resource: EventResourceDisplay): void {
    if (!resource.songId || resource.songId.length === 0) {
      return
    }
    const songItem: songItemType = {
      id: resource.songId,
      name: resource.songName || resource.title,
      author: resource.subtitle || '',
      img: resource.songImg || resource.image || '',
      url: '',
      duration: 0
    }
    playerController.setQueue([songItem], 0, true)
  }

  private async toggleEventLike(item: UserEventItem): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const nextLiked = !(item.info.liked || false)
    try {
      const response = await ApiClient.get<OperationResponse>('/resource/like', [
        { key: 'type', value: '6' },
        { key: 'threadId', value: this.threadIdOf(item) },
        { key: 't', value: nextLiked ? '1' : '0' }
      ])
      if (response.code === 200) {
        item.info.liked = nextLiked
        item.info.likedCount = Math.max(0, (item.info.likedCount || 0) + (nextLiked ? 1 : -1))
        this.events = this.events.map((event: UserEventItem) => event)
        this.discoverEvents = this.discoverEvents.map((event: UserEventItem) => event)
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '动态点赞失败'
    }
  }

  private async openComments(item: UserEventItem): Promise<void> {
    this.selectedThreadId = this.threadIdOf(item)
    this.commentSheetVisible = true
    this.commentsLoading = true
    this.comments = []
    this.commentMessage = ''
    try {
      const response = await ApiClient.get<EventCommentResponse>('/comment/event', [
        { key: 'threadId', value: this.selectedThreadId },
        { key: 'limit', value: '50' },
        { key: 'offset', value: '0' }
      ])
      if (response.code === 200) {
        const merged: EventCommentItem[] = []
        const source = (response.hotComments || []).concat(response.comments || [])
        source.forEach((comment: EventCommentItem) => {
          const exists = merged.find((item: EventCommentItem) => item.commentId === comment.commentId)
          if (!exists) {
            merged.push(comment)
          }
        })
        this.comments = merged
        this.commentTotal = response.total || merged.length
      }
    } catch (error) {
      this.commentMessage = error instanceof Error ? error.message : '评论加载失败'
    } finally {
      this.commentsLoading = false
    }
  }

  private async toggleCommentLike(comment: EventCommentItem): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const nextLiked = !(comment.liked || false)
    try {
      const response = await ApiClient.get<OperationResponse>('/comment/like', [
        { key: 'type', value: '6' },
        { key: 'cid', value: comment.commentId.toString() },
        { key: 'threadId', value: this.selectedThreadId },
        { key: 't', value: nextLiked ? '1' : '0' }
      ])
      if (response.code === 200) {
        comment.liked = nextLiked
        comment.likedCount = Math.max(0, (comment.likedCount || 0) + (nextLiked ? 1 : -1))
        this.comments = this.comments.map((item: EventCommentItem) => item)
      }
    } catch (error) {
      this.commentMessage = error instanceof Error ? error.message : '评论点赞失败'
    }
  }

  @Builder
  private ForwardEventCard(forward: EventForwardData) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image(resizeImageUrl(forward.user?.avatarUrl || '', 64, 64)).width(24).height(24)
          .sourceSize({ width: 64, height: 64 }).borderRadius(12).objectFit(ImageFit.Cover)
        Text(forward.user?.nickname || '').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#ffffff')
          .maxLines(1)
      }
      .width('100%')

      if (this.forwardContent(forward)) {
        Text(this.forwardContent(forward)).width('100%').fontSize(12).lineHeight(18).fontColor('#9a9aa2')
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if ((forward.pics || []).length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(forward.pics || [], (picture: EventPicture) => {
              Image(this.pictureUrl(picture))
                .width(80).height(80).sourceSize({ width: 160, height: 160 })
                .borderRadius(8).objectFit(ImageFit.Cover)
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }

      if (this.forwardResourceOf(forward).title) {
        Row({ space: 8 }) {
          if (this.forwardResourceOf(forward).image) {
            Image(resizeImageUrl(this.forwardResourceOf(forward).image, 80, 80))
              .width(38).height(38).sourceSize({ width: 80, height: 80 })
              .borderRadius(8).objectFit(ImageFit.Cover)
          }
          Column({ space: 3 }) {
            Text(this.forwardResourceOf(forward).kind).fontSize(9).fontColor('#ff7587')
            Text(this.forwardResourceOf(forward).title).fontSize(11).fontColor('#cccccc').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        .width('100%').padding(8).backgroundColor('#1d1d22').borderRadius(10)
      }
    }
    .width('100%').padding(10).backgroundColor('#18181c').borderRadius(10)
    .onClick(() => this.openForwardEventDetail(forward))
  }

  @Builder
  private ResourceCard(resource: EventResourceDisplay) {
    Row({ space: 11 }) {
      if (resource.image) {
        Image(resizeImageUrl(resource.image, 128, 128))
          .width(58).height(58).sourceSize({ width: 128, height: 128 })
          .borderRadius(11).objectFit(ImageFit.Cover)
      } else {
        Stack() {
          SymbolGlyph($r('sys.symbol.music')).fontSize(25).fontColor(['#a0a0a8'])
        }
        .width(58).height(58).borderRadius(11).backgroundColor('#303037')
      }
      Column({ space: 5 }) {
        Text(resource.kind).fontSize(9).fontColor('#ff7587')
        Text(resource.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#ededf0').maxLines(1)
        if (resource.subtitle) {
          Text(resource.subtitle).fontSize(10).fontColor('#77777f').maxLines(1)
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (resource.kind === '歌曲') {
        SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(25).fontColor(['#ffffff'])
      }
    }
    .width('100%').padding(11).backgroundColor('#24242a').borderRadius(13)
    .onClick(() => {
      if (resource.kind === '歌曲') {
        this.playEventSong(resource)
      } else if (resource.kind === '专辑' && resource.albumId) {
        const param: AlbumPageParam = { id: resource.albumId, name: resource.title, picUrl: resource.image, artist: resource.subtitle }
        this.pageStack.pushPathByName('AlbumDetailPage', param)
      } else if (resource.kind === 'MV' && resource.mvId) {
        const param: MvPlayerPageParam = {
          id: resource.mvId,
          name: resource.title,
          cover: resource.image,
          artistName: resource.subtitle,
          duration: resource.mvDuration,
          playCount: resource.mvPlayCount
        }
        this.pageStack.pushPathByName('MvPlayerPage', param)
      }
    })
  }

  @Builder
  private EventCard(item: UserEventItem) {
    Column({ space: 11 }) {
      Row({ space: 11 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Image(resizeImageUrl(item.user.avatarUrl, 96, 96)).width(46).height(46)
            .sourceSize({ width: 96, height: 96 }).borderRadius(18).objectFit(ImageFit.Cover)
          if (item.user.userType === 4) {
            Image($r('app.media.ic_singer')).width(18).height(18).borderRadius(9)
          }
        }
        .width(46).height(46)
        .onClick(() => this.openUser(item.user.userId))
        Column({ space: 4 }) {
          Text(item.user.nickname).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#ffffff')
          Text(this.formatEventTime(item.showTime || item.eventTime || 0)).fontSize(10).fontColor('#66666e')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.openEventDetail(item))
      }

      if (this.contentOf(item)) {
        Text(this.contentOf(item)).width('100%').fontSize(14).lineHeight(22).fontColor('#c5c5cb')
          .onClick(() => this.openEventDetail(item))
      }

      if ((item.pics || []).length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(item.pics || [], (picture: EventPicture) => {
              Image(this.pictureUrl(picture))
                .width((item.pics || []).length === 1 ? 240 : 118)
                .height((item.pics || []).length === 1 ? 190 : 118)
                .sourceSize({ width: 480, height: 380 })
                .borderRadius(12).objectFit(ImageFit.Cover)
                .onClick(() => this.openEventDetail(item))
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }

      if (this.isForwardEvent(item) && this.forwardData(item)) {
        this.ForwardEventCard(this.forwardData(item)!)
      }

      if (this.resourceOf(item).title) {
        this.ResourceCard(this.resourceOf(item))
      }

      Row({ space: 26 }) {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.arrow_right_up_and_square')).fontSize(16).fontColor(['#77777f'])
          Text(`${item.info.shareCount || 0}`).fontSize(10).fontColor('#77777f')
        }
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(16).fontColor(['#77777f'])
          Text(`${item.info.commentCount || 0}`).fontSize(10).fontColor('#77777f')
        }
        .onClick(() => this.openComments(item))
        Row({ space: 5 }) {
          SymbolGlyph(item.info.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(16).fontColor([item.info.liked ? '#ef233c' : '#77777f'])
          Text(`${item.info.likedCount || 0}`)
            .fontSize(10).fontColor(item.info.liked ? '#ef233c' : '#77777f')
        }
        .onClick(() => this.toggleEventLike(item))
      }
      .width('100%')
    }
    .width('100%').padding({ left: 16, right: 16, top: 17, bottom: 17 })
    .backgroundColor('#1b1b20').borderRadius(17)
  }

  @Builder
  private MomentTabs() {
    Row() {
      ForEach(['following', 'discover'], (tab: string) => {
        Column({ space: 7 }) {
          Text(tab === 'following' ? '关注' : '发现')
            .fontSize(14).fontWeight(this.currentTab === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.currentTab === tab ? '#ffffff' : '#74747d')
          Column().width(24).height(3).borderRadius(2)
            .backgroundColor(this.currentTab === tab ? '#ef233c' : 'transparent')
        }
        .layoutWeight(1).height(46).justifyContent(FlexAlign.Center)
        .onClick(() => this.switchTab(tab))
      })
    }
    .width('100%').backgroundColor('#17171c')
  }

  @Builder
  private DiscoverCard(item: UserEventItem) {
    Column({ space: 9 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(this.discoveryImage(item)).width('100%').height(this.discoverImageHeight(item))
          .sourceSize({ width: 360, height: 520 })
          .borderRadius({ topLeft: 15, topRight: 15 }).objectFit(ImageFit.Cover)
        if ((item.pics || []).length > 1) {
          Text(`${(item.pics || []).length} 图`).fontSize(9).fontColor('#ffffff')
            .padding({ left: 7, right: 7, top: 4, bottom: 4 })
            .margin({ top: 8, right: 8 }).borderRadius(10).backgroundColor('rgba(0,0,0,0.55)')
        }
      }
      .width('100%').onClick(() => this.openEventDetail(item))
      if (item.actName) {
        Text(`# ${item.actName}`).width('100%').fontSize(10).fontColor('#ff6577').maxLines(1)
          .padding({ left: 11, right: 11 })
      }
      Text(this.contentOf(item)).width('100%').fontSize(12).lineHeight(18).fontColor('#d1d1d6')
        .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 11, right: 11 }).onClick(() => this.openEventDetail(item))
      Row({ space: 7 }) {
        Image(resizeImageUrl(item.user.avatarUrl, 64, 64)).width(24).height(24)
          .sourceSize({ width: 64, height: 64 }).borderRadius(12).objectFit(ImageFit.Cover)
          .onClick(() => this.openUser(item.user.userId))
        Text(item.user.nickname).layoutWeight(1).fontSize(10).fontColor('#92929a').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 3 }) {
          SymbolGlyph(item.info.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(14).fontColor([item.info.liked ? '#ef233c' : '#77777f'])
          Text(`${item.info.likedCount || 0}`).fontSize(9)
            .fontColor(item.info.liked ? '#ef233c' : '#77777f')
        }
        .onClick(() => this.toggleEventLike(item))
      }
      .width('100%').padding({ left: 11, right: 11, bottom: 11 })
    }
    .width('100%').backgroundColor('#1b1b20').borderRadius(15)
  }

  @Builder
  private CommentSheet() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text(`动态评论 · ${this.commentTotal}`).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          Text('点击红心可点赞或取消点赞').fontSize(10).fontColor('#77777f')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor(['#686870'])
          .onClick(() => this.commentSheetVisible = false)
      }
      .height(66).padding({ left: 20, right: 20 })

      if (this.commentsLoading) {
        LoadingProgress().layoutWeight(1).width(42).color('#ef233c')
      } else if (this.comments.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(38).fontColor(['#55555d'])
          Text(this.commentMessage || '暂无评论').fontSize(12).fontColor('#77777f')
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 15 }) {
          ForEach(this.comments, (comment: EventCommentItem) => {
            ListItem() {
              Row({ space: 10 }) {
                Image(resizeImageUrl(comment.user.avatarUrl, 80, 80)).width(38).height(38)
                  .sourceSize({ width: 80, height: 80 }).borderRadius(19).objectFit(ImageFit.Cover)
                Column({ space: 6 }) {
                  Row() {
                    Column({ space: 2 }) {
                      Text(comment.user.nickname).fontSize(12).fontColor('#aaaab2')
                      Text(comment.timeStr || this.formatEventTime(comment.time)).fontSize(9).fontColor('#5e5e66')
                    }
                    .layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Row({ space: 4 }) {
                      SymbolGlyph(comment.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                        .fontSize(14).fontColor([comment.liked ? '#ef233c' : '#77777f'])
                      Text(`${comment.likedCount || 0}`)
                        .fontSize(9).fontColor(comment.liked ? '#ef233c' : '#77777f')
                    }
                    .onClick(() => this.toggleCommentLike(comment))
                  }
                  Text(comment.content).fontSize(13).lineHeight(20).fontColor('#ededf0')
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
              .padding({ left: 18, right: 18 })
            }
          })
        }
        .layoutWeight(1)
      }

      if (this.commentMessage && this.comments.length > 0) {
        Text(this.commentMessage).width('100%').fontSize(10).fontColor('#ff6577')
          .textAlign(TextAlign.Center).padding({ bottom: 8 })
      }
    }
    .width('100%').height('100%')
  }

  build() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text('动态').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('sys.color.white'))
          Text(this.currentTab === 'discover' ? '从热门话题中发现图片动态' :
            (this.authStore.loggedIn ? '关注的人最近分享' : '登录后查看关注动态'))
            .fontSize(10).fontColor('#66666e')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.currentTab === 'following' && !this.authStore.loggedIn) {
          Button('登录').fontSize(12).fontColor($r('sys.color.white')).backgroundColor('#ef233c')
            .onClick(() => this.pageStack.pushPathByName('LoginPage', null))
        }
      }
      .width('100%').height(64).padding({ left: 16, right: 16 })
      this.MomentTabs()

      Refresh({ refreshing: $$this.isRefreshing }) {
        Column() {
          if (this.currentTab === 'following') {
            if (!this.authStore.loggedIn) {
              Column({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.person_2_fill')).fontSize(44).fontColor(['#55555d'])
                Text('登录后获取完整动态和评论').fontSize(12).fontColor('#77777f')
              }
              .layoutWeight(1).justifyContent(FlexAlign.Center)
            } else if (this.loading && this.events.length === 0) {
              LoadingProgress().layoutWeight(1).width(42).color('#ef233c')
            } else if (this.events.length === 0) {
              Column({ space: 11 }) {
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(42).fontColor(['#55555d'])
                Text(this.message || '暂时没有动态').fontSize(12).fontColor('#77777f')
              }
              .layoutWeight(1).justifyContent(FlexAlign.Center)
            } else {
              List({ space: 12 }) {
                ForEach(this.events, (item: UserEventItem) => {
                  ListItem() {
                    this.EventCard(item)
                  }
                })
                ListItem() {
                  Row() {
                    if (this.loading) {
                      LoadingProgress().width(24).height(24).color('#ef233c')
                    } else {
                      Text(this.more ? '上滑加载更多' : '已经到底了').fontSize(11).fontColor('#66666e')
                    }
                  }
                  .width('100%').height(54).justifyContent(FlexAlign.Center)
                }
              }
              .layoutWeight(1).padding({ left: 12, right: 12 }).onReachEnd(() => this.loadEvents())
            }
          } else {
            if (this.discoverLoading && this.discoverEvents.length === 0) {
              LoadingProgress().layoutWeight(1).width(42).color('#ef233c')
            } else if (this.discoverEvents.length === 0) {
              Column({ space: 11 }) {
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(42).fontColor(['#55555d'])
                Text(this.message || '暂时没有带图片的热门动态').fontSize(12).fontColor('#77777f')
              }
              .layoutWeight(1).justifyContent(FlexAlign.Center)
            } else {
              WaterFlow() {
                ForEach(this.discoverEvents, (item: UserEventItem) => {
                  FlowItem() {
                    this.DiscoverCard(item)
                  }
                })
                FlowItem() {
                  Row() {
                    if (this.discoverLoading) {
                      LoadingProgress().width(24).height(24).color('#ef233c')
                    } else {
                      Text(this.discoverMore ? '继续上滑发现更多' : '已经到底了')
                        .fontSize(10).fontColor('#66666e')
                    }
                  }
                  .width('100%').height(52).justifyContent(FlexAlign.Center)
                }
              }
              .layoutWeight(1).columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(10)
              .padding({ left: 10, right: 10, top: 10 }).onReachEnd(() => this.loadDiscoverEvents())
            }
          }
        }.width('100%')
      }
      .layoutWeight(1)
      .onRefreshing(() => this.refreshCurrentTab())
    }
    .width('100%').height('100%')
      .bindSheet(this.commentSheetVisible, this.CommentSheet(), {
        height: '68%',
        backgroundColor: '#19191f',
        showClose: false,
        dragBar: true,
        onDisappear: () => this.commentSheetVisible = false
      })
  }
}

interface EventResourceDisplay {
  kind: string
  title: string
  subtitle: string
  image: string
  songId?: string
  songName?: string
  songArtists?: ApiArtist[]
  songImg?: string
  albumId?: string
  mvId?: string
  mvDuration?: number
  mvPlayCount?: number
}

export default Moment
