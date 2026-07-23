import { songs } from '../constants/MusicConstants'
@Component
struct PlayerNav {
  build() {
    Row() {
      Row({space:10}) {
        Image(songs[0].img)
          .width(40)
          .aspectRatio(1)
        Column() {
          Text(songs[0].name)
            .fontColor('#fff')
          Text(songs[0].author)
            .fontSize(12)
            .fontColor('#ccc')
        }.alignItems(HorizontalAlign.Start)
      }.height('100%')
      .alignItems(VerticalAlign.Center)
      Row({space:16}) {
        SymbolGlyph($r('sys.symbol.backward_fill'))
          .fontSize(20)
          .fontColor(['#4cafc6'])
        SymbolGlyph($r('sys.symbol.play_circle_fill'))
          .fontSize(24)
          .fontColor(['#4cafc6'])

        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(20)
          .fontColor(['#4cafc6'])
      }.height('100%')
    }
    .width('100%')
    .height(60)
    .backgroundColor('#ff1c1c21')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 20, right: 20 })
  }
}

export default PlayerNav