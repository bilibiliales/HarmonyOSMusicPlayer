import { playlistType } from '../models/music'
import { resizeImageUrl } from '../services/ImageUrl'
import { TC } from '../services/ThemeColors'

@Component
export struct ListeningPlaylistCard {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop playlist: playlistType = { id: '', name: '', cover: '', count: 0, creator: '' }
  @Prop loading: boolean = false
  @Prop message: string = ''
  onOpen: () => void = () => {}

  build() {
    Row({ space: 12 }) {
      Stack() {
        if (this.playlist.cover) {
          Image(resizeImageUrl(this.playlist.cover, 160, 160)).width('100%').height('100%').objectFit(ImageFit.Cover)
        }
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.28)')
        SymbolGlyph(this.playlist.specialType === 'recent' ? $r('sys.symbol.clock') : $r('sys.symbol.sort'))
          .fontSize(26).fontColor([TC.textPrimary()])
      }.width(56).height(56).backgroundColor(TC.surfaceRaised()).borderRadius(10).clip(true)
      Column({ space: 5 }) {
        Text(this.playlist.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(TC.textBody())
        Text(this.loading ? '加载中…' : this.message || `${this.playlist.count} 首${this.playlist.specialType === 'record' ? ' · 最近一周 / 全部时间' : ''}`)
          .fontSize(11).fontColor(TC.textTertiary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([TC.textTertiary()])
    }.width('100%').height(76).onClick(() => this.onOpen())
  }
}
