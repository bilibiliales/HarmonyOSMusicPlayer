import { FanClubGroup, FanClubDetailParam, FanClubService } from '../services/FanClubService'
import { ArtistPageParam } from '../models/api'
import { BubbleTip } from '../services/BubbleTip'
import { AuthStore } from '../stores/AuthStore'
import { TC } from '../services/ThemeColors'

@Component
export struct FanClubListPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
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
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('乐迷团').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(22).fontColor([TC.textTertiary()])
            .onClick(() => this.loadGroups())
        }.height(56).constraintSize({ minHeight: 56 }).width('100%').padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 14 }) {
            if (!this.authStore.loggedIn) {
              Text('登录后查看我加入的乐迷团').width('100%').fontSize(13).fontColor(TC.textSecondary())
                .textAlign(TextAlign.Center).padding({ top: 40 })
            } else if (this.loading) {
              LoadingProgress().width(32).height(32).color(TC.accent())
                .alignSelf(ItemAlign.Center).padding({ top: 40 })
            } else if (this.groups.length === 0) {
              Text('还没有加入任何乐迷团').width('100%').fontSize(13).fontColor(TC.textSecondary())
                .textAlign(TextAlign.Center).padding({ top: 40 })
            } else {
              ForEach(this.groups, (group: FanClubGroup) => {
                Row({ space: 14 }) {
                  Image(group.headAvatarUrl)
                    .width(72).height(72).borderRadius(16).objectFit(ImageFit.Cover)
                    .backgroundColor(TC.chipBackground())
                    .onClick(() => this.openArtist(group))
                  Column({ space: 5 }) {
                    Text(group.fansGroupName).fontSize(16).fontWeight(FontWeight.Medium)
                      .fontColor(TC.textPrimary()).maxLines(1)
                    Text(group.artistName).fontSize(12).fontColor(TC.accentSoft()).maxLines(1)
                    Text(`${group.totalMembersCount} 位成员 · ${group.activeMembersCount} 人在线`)
                      .fontSize(11).fontColor(TC.textSecondary()).maxLines(1)
                    if (group.showMsg) {
                      Text(group.showMsg).fontSize(11).fontColor(TC.textTertiary()).maxLines(1)
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([TC.textQuaternary()])
                }.width('100%').padding(16).backgroundColor(TC.surfaceCard()).borderRadius(18)
                .onClick(() => this.openDetail(group))
              }, (group: FanClubGroup) => group.fansGroupId)
            }
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.width('100%').layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true)
  }
}
