import { PodcastLibrary } from '../components/PodcastLibrary'
import { ShareSheet } from '../components/ShareSheet'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { SharePageParam } from '../models/api'
import { PodcastLibraryParam } from '../models/podcast'
import { TC } from '../services/ThemeColors'

@Component
export struct PodcastLibraryPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @StorageProp('skinVersion') skinVersionObs: number = 0
  pageParam: PodcastLibraryParam = {}
  @State refreshKey: number = 0
  @State refreshing: boolean = false
  @State shareVisible: boolean = false
  @State shareParam: SharePageParam = { type: 'djradio', id: '', name: '', img: '' }

  private openShare(param: SharePageParam): void {
    this.shareParam = param
    this.shareVisible = true
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: this.shareParam, visible: true, onClose: () => this.shareVisible = false })
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()]).onClick(() => this.pageStack.pop())
          Text('我的播客').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 17, top: this.topAvoidHeight })
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            PodcastLibrary({ initialSection: this.pageParam.section || 'all', refreshKey: this.refreshKey,
              onShareRequest: (param: SharePageParam) => this.openShare(param) })
              .width('100%').padding({ bottom: 40 })
          }.width('100%').height('100%').scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .onRefreshing(() => {
          this.refreshKey++
          setTimeout(() => { this.refreshing = false }, 800)
        })
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
      if (this.shareVisible) { this.ShareOptions() }
      }.width('100%').height('100%')
    }.hideTitleBar(true).onShown(() => this.refreshKey++)
  }
}
