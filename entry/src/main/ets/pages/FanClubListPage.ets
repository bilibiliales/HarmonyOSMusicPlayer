import { FanClubGroup, FanClubDetailParam, FanClubService } from '../services/FanClubService'
import { ArtistPageParam } from '../models/api'
import { BubbleTip } from '../services/BubbleTip'
import { AuthStore } from '../stores/AuthStore'

@Component
export struct FanClubListPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore

  @State groups: FanClubGroup[] = []
  @State loading: boolean = false

  aboutToAppear(): void {
    this.loadGroups()
  }

  private async loadGroups(): Promise<void> {
    this.loading = true
    try {
      this.groups = await FanClubService.getMyGroups()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '乐迷团加载失败')
    } finally {
      this.loading = false
    }
  }

  private openDetail(group: FanClubGroup): void {
    const param: FanClubDetailParam = { groupId: group.fansGroupId }
    this.pageStack.pushPathByName('FanClubDetailPage', param)
  }

  private openArtist(group: FanClubGroup): void {
    if (!group.headId) { return }
    const param: ArtistPageParam = { id: String(group.headId), name: group.artistName, picUrl: group.headAvatarUrl }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('乐迷团').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(22).fontColor(['#77777f'])
            .onClick(() => this.loadGroups())
        }.height(56).constraintSize({ minHeight: 56 }).width('100%').padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 14 }) {
            if (!this.authStore.loggedIn) {
              Text('登录后查看我加入的乐迷团').width('100%').fontSize(13).fontColor('#92929a')
                .textAlign(TextAlign.Center).padding({ top: 40 })
            } else if (this.loading) {
              LoadingProgress().width(32).height(32).color('#ef233c')
                .alignSelf(ItemAlign.Center).padding({ top: 40 })
            } else if (this.groups.length === 0) {
              Text('还没有加入任何乐迷团').width('100%').fontSize(13).fontColor('#92929a')
                .textAlign(TextAlign.Center).padding({ top: 40 })
            } else {
              ForEach(this.groups, (group: FanClubGroup) => {
                Row({ space: 14 }) {
                  Image(group.headAvatarUrl)
                    .width(72).height(72).borderRadius(16).objectFit(ImageFit.Cover)
                    .backgroundColor('#29292f')
                    .onClick(() => this.openArtist(group))
                  Column({ space: 5 }) {
                    Text(group.fansGroupName).fontSize(16).fontWeight(FontWeight.Medium)
                      .fontColor('#ffffff').maxLines(1)
                    Text(group.artistName).fontSize(12).fontColor('#ff8291').maxLines(1)
                    Text(`${group.totalMembersCount} 位成员 · ${group.activeMembersCount} 人在线`)
                      .fontSize(11).fontColor('#92929a').maxLines(1)
                    if (group.showMsg) {
                      Text(group.showMsg).fontSize(11).fontColor('#77777f').maxLines(1)
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor(['#66666e'])
                }.width('100%').padding(16).backgroundColor('#1b1b20').borderRadius(18)
                .onClick(() => this.openDetail(group))
              }, (group: FanClubGroup) => group.fansGroupId)
            }
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.width('100%').layoutWeight(1)
      }.width('100%').height('100%').backgroundColor('#121215')
    }.hideTitleBar(true)
  }
}
