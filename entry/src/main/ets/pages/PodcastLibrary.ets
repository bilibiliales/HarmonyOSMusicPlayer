import { PodcastLibrary } from '../components/PodcastLibrary'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { PodcastLibraryParam } from '../models/podcast'
import { TC } from '../services/ThemeColors'

@Component
export struct PodcastLibraryPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @StorageProp('skinVersion') skinVersionObs: number = 0
  pageParam: PodcastLibraryParam = {}
  @State refreshKey: number = 0

  build() {
    NavDestination() {
      SkinBackdrop()
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()]).onClick(() => this.pageStack.pop())
          Text('我的播客库').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 17, top: this.topAvoidHeight })
        Scroll() {
          PodcastLibrary({ initialSection: this.pageParam.section || 'recent', refreshKey: this.refreshKey })
            .width('100%').padding({ bottom: 40 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true).onShown(() => this.refreshKey++)
  }
}
