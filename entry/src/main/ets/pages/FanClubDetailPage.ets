import { FanClubDetail, FanClubDetailParam, FanClubService } from '../services/FanClubService'
import { ArtistPageParam, UserEventItem } from '../models/api'
import { EventCard } from '../components/EventCard'
import { EventPresentation } from '../services/EventPresentation'
import { BubbleTip } from '../services/BubbleTip'
import { AuthStore } from '../stores/AuthStore'

@Component
export struct FanClubDetailPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: FanClubDetailParam = { groupId: '' }

  @State detail: FanClubDetail | null = null
  @State events: UserEventItem[] = []
  @State loading: boolean = false
  @State feedLoading: boolean = false
  @State more: boolean = false
  @State cursor: string = '0'
  @State message: string = ''

  aboutToAppear(): void {
    this.loadDetail()
    this.loadFeed(true)
  }

  private async loadDetail(): Promise<void> {
    this.loading = true
    try {
      this.detail = await FanClubService.getGroupDetail(this.pageParam.groupId)
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '乐迷团详情加载失败')
    } finally {
      this.loading = false
    }
  }

  private async loadFeed(reset: boolean): Promise<void> {
    if (this.feedLoading || (!reset && !this.more)) { return }
    if (reset) {
      this.events = []
      this.cursor = '0'
      this.more = true
    }
    this.feedLoading = true
    this.message = ''
    try {
      const result = await FanClubService.getGroupFeed(this.pageParam.groupId, this.cursor)
      this.events = this.events.concat(result.records)
      this.more = result.more
      this.cursor = result.cursor
    } catch (error) {
      if (reset) { this.message = error instanceof Error ? error.message : '动态加载失败' }
    } finally {
      this.feedLoading = false
    }
  }

  private loadMore(): void {
    this.loadFeed(false)
  }

  private openArtist(): void {
    if (!this.detail || !this.detail.headId) { return }
    const param: ArtistPageParam = { id: String(this.detail.headId), name: this.detail.artistName, picUrl: this.detail.headAvatarUrl }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  private applyEventChange(changed: UserEventItem, deleted: boolean): void {
    if (deleted) {
      this.events = this.events.filter((event: UserEventItem) => event.id !== changed.id)
    } else {
      this.events = EventPresentation.changeList(this.events, changed, false)
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text(this.detail?.fansGroupName || '乐迷团').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center).maxLines(1)
          Column().width(24)
        }.height(56).constraintSize({ minHeight: 56 }).width('100%').padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 16 }) {
            if (this.detail) {
              Column({ space: 14 }) {
                Row({ space: 16 }) {
                  Image(this.detail.headAvatarUrl)
                    .width(96).height(96).borderRadius(20).objectFit(ImageFit.Cover)
                    .backgroundColor('#29292f').onClick(() => this.openArtist())
                  Column({ space: 6 }) {
                    Text(this.detail.fansGroupName).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                    Text(this.detail.artistName).fontSize(13).fontColor('#ff8291')
                    Text(`${this.detail.totalMembersCount} 位成员 · ${this.detail.activeMembersCount} 人在线`)
                      .fontSize(12).fontColor('#92929a')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }.width('100%')
                if (this.detail.brief) {
                  Text(this.detail.brief).width('100%').fontSize(13).lineHeight(20).fontColor('#b5b5bc')
                }
                if (this.detail.headId) {
                  Row() {
                    Text('歌手主页').fontSize(13).fontColor('#ffffff').layoutWeight(1)
                    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor(['#66666e'])
                  }.width('100%').padding(14).backgroundColor('#1b1b20').borderRadius(14)
                    .onClick(() => this.openArtist())
                }
              }.width('100%').padding(18).backgroundColor('#16161b').borderRadius(20)
            } else if (this.loading) {
              LoadingProgress().width(32).height(32).color('#ef233c').alignSelf(ItemAlign.Center).padding({ top: 20 })
            }

            Column({ space: 10 }) {
              Text('动态').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              if (this.feedLoading && this.events.length === 0) {
                LoadingProgress().width(28).height(28).color('#ef233c').alignSelf(ItemAlign.Center)
              } else if (this.events.length === 0) {
                Text(this.message || '还没有动态').fontSize(12).fontColor('#92929a')
                  .alignSelf(ItemAlign.Center).padding({ top: 16, bottom: 16 })
              } else {
                ForEach(this.events.filter((event: UserEventItem) => event.id > 0), (item: UserEventItem) => {
                  EventCard({ item: item, onChanged: (event: UserEventItem, deleted: boolean) => this.applyEventChange(event, deleted) })
                    .margin({ bottom: 8 })
                }, (item: UserEventItem) => item.id.toString())
                if (this.more) {
                  Text(this.feedLoading ? '加载中…' : '加载更多').width('100%').height(44).fontSize(12)
                    .fontColor('#77777f').textAlign(TextAlign.Center).onClick(() => this.loadMore())
                }
              }
            }.width('100%').padding(18).backgroundColor('#1b1b20').borderRadius(20)
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.width('100%').layoutWeight(1).onReachEnd(() => this.loadMore())
      }.width('100%').height('100%').backgroundColor('#121215')
    }.hideTitleBar(true)
  }
}
