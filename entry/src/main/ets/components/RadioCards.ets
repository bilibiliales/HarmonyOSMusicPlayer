import { DjRadioItem } from '../models/api'
import { ProgramItem } from '../models/home'
import { RadioService } from '../services/RadioService'
import { resizeImageUrl } from '../services/ImageUrl'
import { TC } from '../services/ThemeColors'

@Component
export struct RadioStationCard {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop station: DjRadioItem
  onOpen: () => void = () => {}

  build() {
    Row({ space: 13 }) {
      Image(resizeImageUrl(this.station.picUrl, 180, 180)).width(72).height(72)
        .borderRadius(14).objectFit(ImageFit.Cover).backgroundColor(TC.surfaceInset())
      Column({ space: 6 }) {
        Text(this.station.name).fontSize(15).fontColor(TC.textBody()).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.station.dj?.nickname || this.station.creator?.nickname || this.station.desc || '网易云电台')
          .fontSize(11).fontColor(TC.textSecondary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.station.programCount || 0} 期 · ${RadioService.count(this.station.subCount)} 人订阅`)
          .fontSize(10).fontColor(TC.textTertiary())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([TC.textTertiary()])
    }.width('100%').padding({ left: 17, right: 17, top: 9, bottom: 9 }).onClick(this.onOpen)
  }
}

@Component
export struct RadioProgramRow {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop program: ProgramItem
  @Prop rank: number = 0
  onPlay: () => void = () => {}
  onDetails: () => void = () => {}

  build() {
    Row({ space: 11 }) {
      if (this.rank > 0) {
        Text(String(this.rank)).fontSize(15).fontColor(this.rank <= 3 ? TC.accentSoft() : TC.textTertiary()).width(24)
      }
      Image(resizeImageUrl(RadioService.cover(this.program), 150, 150)).width(58).height(58)
        .objectFit(ImageFit.Cover).borderRadius(10).backgroundColor(TC.surfaceInset()).onClick(this.onPlay)
      Column({ space: 5 }) {
        Text(this.program.name).fontSize(14).fontColor(TC.textBody()).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${RadioService.author(this.program)} · ${RadioService.duration(this.program.duration)}`)
          .fontSize(10).fontColor(TC.textSecondary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${RadioService.count(this.program.listenerCount)} 次收听`).fontSize(10).fontColor(TC.textQuaternary())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(this.onPlay)
      SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(22).fontColor([TC.textSecondary()])
        .width(36).height(44).onClick(this.onDetails)
    }.width('100%').padding({ left: 17, right: 12, top: 9, bottom: 9 })
  }
}
