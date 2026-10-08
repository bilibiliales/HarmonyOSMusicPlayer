import { CommentResource, ResourceComment } from '../models/CommentResource'
import { UserProfilePageParam } from '../models/api'
import { AuthStore } from '../stores/AuthStore'
import { BubbleTip } from '../services/BubbleTip'
import { CommentService } from '../services/CommentService'

interface CommentLocation {
  page: number
  sort: number
  cursor: string
  parentId?: number
}

interface CommentCountGuard {
  value: number
  direction: number
}

@Component
export struct ResourceComments {
  @Consume('authStore') authStore: AuthStore
  @Consume('pageStack') pageStack: NavPathStack
  @Prop @Watch('resourceChanged') resource: CommentResource = { id: '', type: 0 }
  onClose: () => void = () => {}
  onCountChange: (total: number) => void = () => {}
  @State comments: ResourceComment[] = []
  @State total: number = 0
  @State sortType: number = 1
  @State loading: boolean = false
  @State more: boolean = true
  @State error: string = ''
  @State floorRoot: ResourceComment | undefined = undefined
  @State floorComments: ResourceComment[] = []
  @State floorTotal: number = 0
  @State floorLoading: boolean = false
  @State floorMore: boolean = true
  @State floorError: string = ''
  @State replyTo: ResourceComment | undefined = undefined
  @State input: string = ''
  @State submitting: boolean = false
  @State deleting: number = 0
  @State liking: number[] = []
  @State sentEcho: string = ''
  private pageNo: number = 0
  private cursor: string = ''
  private loadMoreArmed: boolean = false
  private locations: Map<number, CommentLocation> = new Map()
  private floorCursor: string = ''
  private generation: number = 0
  private listRequest: number = 0
  private floorRequest: number = 0
  private overrides: Map<number, ResourceComment> = new Map()
  private removed: Set<number> = new Set()
  private pinned: ResourceComment[] = []
  private floorPinned: ResourceComment[] = []
  private resourceKey: string = ''
  private totalGuard: CommentCountGuard | undefined = undefined
  private replyGuards: Map<number, CommentCountGuard> = new Map()

  aboutToAppear(): void { this.resourceKey = ''; this.resourceChanged() }

  aboutToDisappear(): void {
    this.generation++
    this.listRequest++
    this.floorRequest++
  }

  private resourceChanged(): void {
    const key = `${this.resource.type}:${this.resource.threadId || this.resource.id}`
    if (key === this.resourceKey) { return }
    this.resourceKey = key
    this.generation++
    this.listRequest++
    this.floorRequest++
    this.comments = []
    this.total = 0
    this.pageNo = 0
    this.cursor = ''
    this.more = true
    this.loading = false
    this.floorRoot = undefined
    this.floorComments = []
    this.replyTo = undefined
    this.input = ''
    this.sentEcho = ''
    this.submitting = false
    this.deleting = 0
    this.liking = []
    this.loadMoreArmed = false
    this.locations.clear()
    this.overrides.clear()
    this.removed.clear()
    this.pinned = []
    this.floorPinned = []
    this.totalGuard = undefined
    this.replyGuards.clear()
    this.load(true)
  }

  private notify(message: string): void { BubbleTip.show(this.getUIContext(), message) }

  private requireLogin(): boolean {
    if (this.authStore.loggedIn && this.authStore.userId) { return true }
    this.notify('请先登录')
    this.onClose()
    this.pageStack.pushPathByName('LoginPage', null)
    return false
  }

  private stillCurrent(generation: number, userId?: string): boolean {
    return this.generation === generation && (!userId ||
      (this.authStore.loggedIn && this.authStore.userId === userId))
  }

  private accountKey(): string {
    return `${this.authStore.loggedIn}:${this.authStore.userId}:${this.authStore.cookie}`
  }

  private acceptRead(generation: number, account: string): boolean {
    if (!this.stillCurrent(generation)) { return false }
    if (account === this.accountKey()) { return true }
    // Clear account-specific liked/deleted state before reading under another login.
    this.resourceKey = ''
    this.resourceChanged()
    return false
  }

  private guardedCount(value: number, guard: CommentCountGuard | undefined): number {
    const count = Math.max(0, value)
    if (!guard) { return count }
    return guard.direction > 0 ? Math.max(count, guard.value) : Math.min(count, guard.value)
  }

  private changeTotal(delta: number): void {
    this.total = Math.max(0, this.total + delta)
    this.totalGuard = { value: this.total, direction: delta }
    this.onCountChange(this.total)
  }

  private changeReplies(root: ResourceComment, delta: number): void {
    const current = this.overrides.get(root.commentId) || root
    const count = Math.max(0, this.replies(current) + delta)
    this.replyGuards.set(root.commentId, { value: count, direction: delta })
    this.patchReplies(current, count)
    if (this.floorRoot?.commentId === root.commentId) { this.floorTotal = count }
  }

  private unique(items: ResourceComment[]): ResourceComment[] {
    const seen: Set<number> = new Set()
    const result: ResourceComment[] = []
    items.forEach((item: ResourceComment) => {
      if (!item.commentId || seen.has(item.commentId) || this.removed.has(item.commentId)) { return }
      seen.add(item.commentId)
      result.push(this.overrides.get(item.commentId) || item)
    })
    return result
  }

  private async load(reset: boolean = false): Promise<void> {
    if (!reset && (this.loading || !this.more)) { return }
    this.loadMoreArmed = false
    const generation = this.generation
    const account = this.accountKey()
    const request = ++this.listRequest
    const page = reset ? 1 : this.pageNo + 1
    const sort = this.sortType
    const previousCursor = reset ? '' : this.cursor
    if (reset) { this.pageNo = 0; this.cursor = ''; this.more = true }
    this.loading = true
    this.error = ''
    try {
      const result = await CommentService.list(this.resource, page, sort, previousCursor)
      if (!this.acceptRead(generation, account) || request !== this.listRequest) { return }
      const previousIds = new Set((reset ? [] : this.comments).map((item: ResourceComment) => item.commentId))
      const newCount = result.comments.filter((item: ResourceComment) =>
        !previousIds.has(item.commentId) && !this.removed.has(item.commentId)).length
      result.comments.forEach((item: ResourceComment) => {
        this.locations.set(item.commentId, { page: page, sort: sort, cursor: previousCursor })
      })
      this.pinned = this.pinned.filter((item: ResourceComment) =>
        !result.comments.some((value: ResourceComment) => value.commentId === item.commentId))
      this.comments = this.unique(this.pinned.concat(reset ? [] : this.comments).concat(result.comments))
      this.total = this.guardedCount(result.totalKnown === false ?
        Math.max(this.total, this.comments.length) : result.total, this.totalGuard)
      if (result.totalKnown !== false) {
        if (this.total === result.total) { this.totalGuard = undefined }
        this.onCountChange(this.total)
      }
      this.pageNo = page
      this.cursor = result.cursor
      this.more = result.hasMore && newCount > 0 &&
        (result.totalKnown === false || this.comments.length < result.total) &&
        (sort !== 3 || (!!result.cursor && result.cursor !== previousCursor))
      if (this.sentEcho && result.comments.some((item: ResourceComment) => item.content === this.sentEcho &&
        item.user.userId?.toString() === this.authStore.userId)) { this.sentEcho = '' }
    } catch (error) {
      if (!this.acceptRead(generation, account) || request !== this.listRequest) { return }
      this.error = error instanceof Error ? error.message : '评论加载失败'
      this.notify(this.error)
    } finally {
      if (this.acceptRead(generation, account) && request === this.listRequest) { this.loading = false }
    }
  }

  private selectSort(sort: number): void {
    if (sort === this.sortType || this.submitting || this.deleting) { return }
    this.loadMoreArmed = false
    this.sortType = sort
    this.comments = []
    this.load(true)
  }

  private replies(item: ResourceComment): number {
    return item.showFloorComment?.replyCount ?? item.replyCount ?? 0
  }

  private openFloor(item: ResourceComment): void {
    if (this.submitting || this.deleting) { return }
    this.loadMoreArmed = false
    this.floorRequest++
    this.floorRoot = item
    this.floorComments = []
    this.floorPinned = []
    this.floorTotal = this.replies(item)
    this.floorCursor = ''
    this.floorMore = true
    this.floorLoading = false
    this.floorError = ''
    this.replyTo = item
    this.sentEcho = ''
    this.loadFloor(true)
  }

  private closeFloor(): void {
    if (this.submitting) { return }
    this.loadMoreArmed = false
    this.floorRequest++
    this.floorRoot = undefined
    this.replyTo = undefined
    this.floorComments = []
    this.floorPinned = []
    this.sentEcho = ''
  }

  private async loadFloor(reset: boolean = false): Promise<void> {
    const root = this.floorRoot
    if (!root || (!reset && (this.floorLoading || !this.floorMore))) { return }
    this.loadMoreArmed = false
    const generation = this.generation
    const account = this.accountKey()
    const request = ++this.floorRequest
    const previous = reset ? '' : this.floorCursor
    if (reset) { this.floorCursor = ''; this.floorMore = true }
    this.floorLoading = true
    this.floorError = ''
    try {
      const result = await CommentService.floor(this.resource, root.commentId, previous)
      if (!this.acceptRead(generation, account) || request !== this.floorRequest ||
        this.floorRoot?.commentId !== root.commentId) { return }
      const previousIds = new Set((reset ? [] : this.floorComments).map((item: ResourceComment) => item.commentId))
      const newCount = result.comments.filter((item: ResourceComment) => item.commentId !== root.commentId &&
        !previousIds.has(item.commentId) && !this.removed.has(item.commentId)).length
      result.comments.forEach((item: ResourceComment) => {
        if (item.commentId !== root.commentId) {
          this.locations.set(item.commentId, { page: 0, sort: 0, cursor: previous, parentId: root.commentId })
        }
      })
      this.floorPinned = this.floorPinned.filter((item: ResourceComment) =>
        !result.comments.some((value: ResourceComment) => value.commentId === item.commentId))
      this.floorComments = this.unique(this.floorPinned.concat(reset ? [] : this.floorComments)
        .concat(result.comments)).filter((item: ResourceComment) => item.commentId !== root.commentId)
      this.floorTotal = this.guardedCount(result.totalKnown === false ?
        Math.max(this.floorTotal, this.floorComments.length) : result.total, this.replyGuards.get(root.commentId))
      if (result.totalKnown !== false && this.floorTotal === result.total) { this.replyGuards.delete(root.commentId) }
      this.floorCursor = result.cursor
      this.floorMore = result.hasMore && newCount > 0 &&
        (result.totalKnown === false || this.floorComments.length < result.total) &&
        !!result.cursor && result.cursor !== previous
      this.patchReplies(root, this.floorTotal)
      if (this.sentEcho && result.comments.some((item: ResourceComment) => item.content === this.sentEcho &&
        item.user.userId?.toString() === this.authStore.userId)) { this.sentEcho = '' }
    } catch (error) {
      if (!this.acceptRead(generation, account) || request !== this.floorRequest) { return }
      this.floorError = error instanceof Error ? error.message : '回复加载失败'
      this.notify(this.floorError)
    } finally {
      if (this.acceptRead(generation, account) && request === this.floorRequest) { this.floorLoading = false }
    }
  }

  private patch(item: ResourceComment): void {
    this.overrides.set(item.commentId, item)
    this.comments = this.comments.map((value: ResourceComment) => value.commentId === item.commentId ? item : value)
    this.floorComments = this.floorComments.map((value: ResourceComment) =>
      value.commentId === item.commentId ? item : value)
    if (this.floorRoot?.commentId === item.commentId) { this.floorRoot = item }
  }

  private copyComment(item: ResourceComment): ResourceComment {
    return { commentId: item.commentId, content: item.content, likedCount: item.likedCount,
      liked: item.liked, timeStr: item.timeStr, user: item.user, time: item.time,
      parentCommentId: item.parentCommentId, replyCount: item.replyCount,
      showFloorComment: item.showFloorComment, beReplied: item.beReplied }
  }

  private patchReplies(item: ResourceComment, count: number): void {
    const current = this.overrides.get(item.commentId) || item
    const updated = this.copyComment(current)
    updated.replyCount = Math.max(0, count)
    updated.showFloorComment = { comments: current.showFloorComment?.comments, replyCount: Math.max(0, count) }
    this.patch(updated)
  }

  private async readLikeState(resource: CommentResource, item: ResourceComment,
    location: CommentLocation | undefined, generation: number, account: string): Promise<void> {
    try {
      let fresh: ResourceComment | undefined = undefined
      try { fresh = await CommentService.readComment(resource, item.commentId) }
      catch (error) {
        if (!location) { throw new Error(error instanceof Error ? error.message : '评论状态同步失败') }
      }
      if (!this.stillCurrent(generation) || account !== this.accountKey() || this.removed.has(item.commentId)) { return }
      if ((!fresh || typeof fresh.liked !== 'boolean') && location) {
        const result = location.parentId ?
          await CommentService.floor(resource, location.parentId, location.cursor) :
          await CommentService.list(resource, location.page, location.sort, location.cursor)
        fresh = result.comments.find((value: ResourceComment) => value.commentId === item.commentId)
      }
      if (!this.stillCurrent(generation) || account !== this.accountKey() || this.removed.has(item.commentId)) { return }
      if (!fresh || typeof fresh.liked !== 'boolean') {
        this.notify('点赞操作已提交，暂未读取到最新状态')
        return
      }
      // Retain content/reply updates, but let this fresh network response own like state.
      const updated = this.copyComment(this.overrides.get(item.commentId) || item)
      updated.liked = fresh.liked
      if (typeof fresh.likedCount === 'number' && Number.isFinite(fresh.likedCount)) {
        updated.likedCount = Math.max(0, fresh.likedCount)
      }
      this.patch(updated)
    } catch (_error) {
      if (this.stillCurrent(generation) && account === this.accountKey()) {
        this.notify('点赞操作已提交，状态同步失败，请稍后重试')
      }
    }
  }

  private async toggleLike(item: ResourceComment): Promise<void> {
    if (this.liking.includes(item.commentId) || !this.requireLogin()) { return }
    const generation = this.generation
    const userId = this.authStore.userId
    const account = this.accountKey()
    const resource = this.resource
    const location = this.locations.get(item.commentId)
    const liked = !item.liked
    this.liking = this.liking.concat([item.commentId])
    try {
      await CommentService.like(resource, item.commentId, liked)
      if (!this.stillCurrent(generation, userId) || account !== this.accountKey() || this.removed.has(item.commentId)) { return }
      const current = this.overrides.get(item.commentId) || item
      const updated = this.copyComment(current)
      updated.liked = liked
      updated.likedCount = Math.max(0, (current.likedCount || 0) + (liked ? 1 : -1))
      this.patch(updated)
      this.notify(liked ? '已点赞' : '已取消点赞')
      await this.readLikeState(resource, item, location, generation, account)
    } catch (error) {
      if (this.stillCurrent(generation, userId)) {
        this.notify(error instanceof Error ? error.message : '评论点赞失败')
      }
    } finally {
      if (this.stillCurrent(generation)) {
        this.liking = this.liking.filter((id: number) => id !== item.commentId)
      }
    }
  }

  private startReply(item: ResourceComment): void {
    if (this.submitting || this.deleting || !this.requireLogin()) { return }
    if (!this.floorRoot) { this.openFloor(item); return }
    this.replyTo = item
  }

  private async submit(): Promise<void> {
    if (this.submitting || this.deleting || !this.requireLogin()) { return }
    const content = this.input.trim()
    if (!content) { this.notify('请输入评论内容'); return }
    const generation = this.generation
    const userId = this.authStore.userId
    const reply = this.replyTo || this.floorRoot
    const root = this.floorRoot
    this.submitting = true
    try {
      const result = await CommentService.send(this.resource, content, reply?.commentId || 0)
      if (!this.stillCurrent(generation, userId)) { return }
      this.input = ''
      this.changeTotal(1)
      this.notify(reply ? '回复成功' : '评论发布成功')
      const created = result.comment || result.data
      if (root && this.floorRoot?.commentId === root.commentId) {
        this.changeReplies(root, 1)
        if (created && created.commentId && created.user) {
          this.floorPinned = this.unique([created].concat(this.floorPinned))
          this.floorComments = this.unique(this.floorPinned.concat(this.floorComments))
        } else { this.sentEcho = content }
        this.replyTo = this.floorRoot
        await this.loadFloor(true)
        if (this.stillCurrent(generation, userId)) { await this.load(true) }
      } else {
        if (reply) { this.changeReplies(reply, 1) }
        if (created && created.commentId && created.user) {
          this.pinned = this.unique([created].concat(this.pinned))
          this.comments = this.unique(this.pinned.concat(this.comments))
        } else { this.sentEcho = content }
        this.replyTo = undefined
        this.sortType = 3
        // A timestamp is included in every read, including the first page after publishing.
        await this.load(true)
      }
    } catch (error) {
      if (this.stillCurrent(generation, userId)) {
        this.notify(error instanceof Error ? error.message : '评论发送失败')
      }
    } finally {
      if (this.stillCurrent(generation)) { this.submitting = false }
    }
  }

  private owned(item: ResourceComment): boolean {
    return this.authStore.loggedIn && !!item.user.userId && item.user.userId.toString() === this.authStore.userId
  }

  private confirmDelete(item: ResourceComment): void {
    if (!this.owned(item) || this.deleting || this.submitting) { return }
    const generation = this.generation
    this.getUIContext().showAlertDialog({
      title: '删除评论', message: '确定删除这条评论？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: '#ef233c', action: () => {
        if (this.stillCurrent(generation)) { this.remove(item) }
      } }
    })
  }

  private async remove(item: ResourceComment): Promise<void> {
    if (this.deleting || this.submitting || !this.owned(item)) { return }
    const generation = this.generation
    const userId = this.authStore.userId
    this.deleting = item.commentId
    try {
      await CommentService.remove(this.resource, item.commentId)
      if (!this.stillCurrent(generation, userId)) { return }
      this.removed.add(item.commentId)
      this.comments = this.comments.filter((value: ResourceComment) => value.commentId !== item.commentId)
      this.floorComments = this.floorComments.filter((value: ResourceComment) => value.commentId !== item.commentId)
      this.pinned = this.pinned.filter((value: ResourceComment) => value.commentId !== item.commentId)
      this.floorPinned = this.floorPinned.filter((value: ResourceComment) => value.commentId !== item.commentId)
      this.changeTotal(-1)
      this.notify('评论已删除')
      if (this.replyTo?.commentId === item.commentId) { this.replyTo = undefined }
      if (this.floorRoot?.commentId === item.commentId) { this.closeFloor() }
      else if (this.floorRoot) {
        this.changeReplies(this.floorRoot, -1)
        await this.loadFloor(true)
      }
      if (this.stillCurrent(generation, userId)) { await this.load(true) }
    } catch (error) {
      if (this.stillCurrent(generation, userId)) {
        this.notify(error instanceof Error ? error.message : '评论删除失败')
      }
    } finally {
      if (this.stillCurrent(generation)) { this.deleting = 0 }
    }
  }

  private formatTime(item: ResourceComment): string {
    if (item.timeStr) { return item.timeStr }
    if (!item.time) { return '' }
    const date = new Date(item.time)
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()} ` +
      `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
  }

  private openUser(item: ResourceComment): void {
    if (!item.user.userId) { return }
    const param: UserProfilePageParam = { uid: item.user.userId.toString() }
    this.onClose()
    this.pageStack.pushPathByName('UserProfilePage', param)
  }

  private commentRowKey(item: ResourceComment): string {
    // A lazy ListItem keeps its builder argument until its key changes.
    return `${this.resourceKey}:${item.commentId}:${item.liked ? 1 : 0}:` +
      `${item.likedCount || 0}:${this.replies(item)}`
  }

  @Builder
  private SortOption(label: string, sort: number) {
    Column({ space: 5 }) {
      Text(label).fontSize(13).fontColor(this.sortType === sort ? '#ffffff' : '#85858f')
        .fontWeight(this.sortType === sort ? FontWeight.Medium : FontWeight.Regular)
      Column().width(20).height(2).borderRadius(1).backgroundColor(this.sortType === sort ? '#ef233c' : 'transparent')
    }.padding({ left: 14, right: 14, top: 5, bottom: 5 }).onClick(() => this.selectSort(sort))
  }

  @Builder
  private CommentRow(item: ResourceComment, root: boolean = false) {
    Row({ space: 10 }) {
      Image(item.user.avatarUrl || '').width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover)
        .onClick(() => this.openUser(item))
      Column({ space: 8 }) {
        Row({ space: 10 }) {
          Text(item.user.nickname || '云音乐用户').fontSize(13).fontColor('#aaaab3').layoutWeight(1).maxLines(1)
          if (this.owned(item)) {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor(['#777781'])
              .padding(4).enabled(!this.deleting && !this.submitting).onClick(() => this.confirmDelete(item))
          }
          Row({ space: 4 }) {
            SymbolGlyph(item.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(17).fontColor([item.liked ? '#ef233c' : '#777781'])
            Text((item.likedCount || 0).toString()).fontSize(11).fontColor(item.liked ? '#ef233c' : '#777781')
          }.padding(4).enabled(!this.liking.includes(item.commentId)).onClick(() => this.toggleLike(item))
        }.width('100%')
        Text(item.content || '').width('100%').fontSize(14).fontColor('#eeeeF2').lineHeight(22)
          .onClick(() => this.startReply(item))
        if ((item.beReplied || []).length > 0 && item.beReplied![0].content) {
          Text(`回复 ${item.beReplied![0].user?.nickname || '用户'}：${item.beReplied![0].content || ''}`)
            .width('100%').fontSize(12).fontColor('#93939d').lineHeight(19).maxLines(3)
            .padding(10).backgroundColor('#24242b').borderRadius(8)
        }
        Row({ space: 14 }) {
          Text(this.formatTime(item)).fontSize(10).fontColor('#666670').layoutWeight(1)
          Text('回复').fontSize(12).fontColor('#9999a3').onClick(() => this.startReply(item))
          if (!root && !this.floorRoot) {
            Text(this.replies(item) > 0 ? `${this.replies(item)} 条回复 ›` : '查看回复')
              .fontSize(12).fontColor('#97b9e5').onClick(() => this.openFloor(item))
          }
        }.width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Top).padding({ left: 16, right: 16, top: 16, bottom: 16 })
  }

  private reachEnd(): void {
    if (!this.loadMoreArmed) { return }
    this.loadMoreArmed = false
    if (this.floorRoot) {
      if (this.floorComments.length > 0 && !this.floorError && this.floorMore && !this.floorLoading) {
        this.loadFloor()
      }
    } else if (this.comments.length > 0 && !this.error && this.more && !this.loading) { this.load() }
  }

  @Builder
  private ListStatus() {
    // Read observable fields here; primitive @Builder parameters retain their initial values.
    if (this.floorRoot ? this.floorLoading : this.loading) {
      Row({ space: 8 }) {
        LoadingProgress().width(20).height(20).color('#ef233c')
        Text('加载中…').fontSize(12).fontColor('#777781')
      }.width('100%').height(52).justifyContent(FlexAlign.Center)
    } else if (this.floorRoot ? this.floorError.length > 0 : this.error.length > 0) {
      Text((this.floorRoot ? this.floorError : this.error) + ' · 点击重试')
        .fontSize(12).fontColor('#777781').width('100%').textAlign(TextAlign.Center)
        .padding({ left: 16, right: 16, top: 18, bottom: 18 })
        .onClick(() => {
          if (this.floorRoot) { this.loadFloor(this.floorComments.length === 0) }
          else { this.load(this.comments.length === 0) }
        })
    } else if (this.floorRoot ? this.floorComments.length === 0 : this.comments.length === 0) {
      if (!this.sentEcho) {
        Text(this.floorRoot ? '还没有回复，来说两句吧' : '还没有评论，来说两句吧')
          .fontSize(13).fontColor('#777781').width('100%').textAlign(TextAlign.Center).padding(30)
      }
    } else {
      Text((this.floorRoot ? this.floorMore : this.more) ? '继续加载' : '没有更多评论了')
        .fontSize(12).fontColor('#777781').width('100%').height(52).textAlign(TextAlign.Center)
        .onClick(() => { if (this.floorRoot) { this.loadFloor() } else { this.load() } })
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        if (this.floorRoot) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor(['#ffffff']).padding(4)
            .onClick(() => this.closeFloor())
        }
        Column({ space: 4 }) {
          Text(this.floorRoot ? `回复 (${this.floorTotal})` : `评论 (${this.total})`)
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#ffffff')
          if (!this.floorRoot && this.resource.title) {
            Text(this.resource.title || '').fontSize(11).fontColor('#777781').maxLines(1)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor(['#aaaaB2']).padding(8).onClick(() => this.onClose())
      }.width('100%').padding({ left: 16, right: 12, top: 10, bottom: 8 })
      if (!this.floorRoot) {
        Row() {
          this.SortOption('推荐', 1)
          this.SortOption('最热', 2)
          this.SortOption('最新', 3)
        }
          .width('100%').padding({ left: 2, bottom: 3 })
      }
      List() {
        if (this.floorRoot) {
          ForEach([this.floorRoot], (item: ResourceComment) => {
            ListItem() { this.CommentRow(item, true) }
          }, (item: ResourceComment) => 'root:' + this.commentRowKey(item))
          ListItem() { Divider().color('#303039').margin({ left: 16, right: 16 }) }
        }
        if (this.sentEcho) {
          ListItem() {
            Column({ space: 6 }) {
              Text('刚刚发布').fontSize(11).fontColor('#9999a3')
              Text(this.sentEcho).fontSize(14).fontColor('#eeeeF2').width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
          }
        }
        ForEach(this.floorRoot ? this.floorComments : this.comments, (item: ResourceComment) => {
          ListItem() { this.CommentRow(item) }
        }, (item: ResourceComment) => this.commentRowKey(item))
        ListItem() { this.ListStatus() }
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
        .onScrollFrameBegin((offset: number, state: ScrollState) => {
          if (state !== ScrollState.Idle && offset > 0) { this.loadMoreArmed = true }
          return { offsetRemain: offset }
        })
        .onReachEnd(() => this.reachEnd())
      Column({ space: 7 }) {
        if (this.replyTo) {
          Row() {
            Text(`回复 ${this.replyTo.user.nickname || '用户'}`).fontSize(11).fontColor('#9999a3').layoutWeight(1)
            if (this.replyTo.commentId !== this.floorRoot?.commentId) {
              Text('取消').fontSize(11).fontColor('#9999a3').onClick(() => this.replyTo = this.floorRoot)
            }
          }.width('100%')
        }
        Row({ space: 10 }) {
          TextInput({ text: this.input, placeholder: this.replyTo ? '写下你的回复…' : '写下你的评论…' })
            .layoutWeight(1).height(42).fontSize(14).fontColor('#ffffff').placeholderColor('#777781')
            .backgroundColor('#292930').borderRadius(21).maxLength(1400)
            .onChange((value: string) => this.input = value).onSubmit(() => this.submit())
          Button(this.submitting ? '发送中' : '发送').height(38).fontSize(13).backgroundColor('#ef233c')
            .enabled(!this.submitting && !this.deleting && this.input.trim().length > 0).onClick(() => this.submit())
        }.width('100%')
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 })
    }.width('100%').height('100%').backgroundColor('#1b1b20')
  }
}
