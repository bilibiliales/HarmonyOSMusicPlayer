import { favoriteList } from '../constants'
import { songItemType } from '../models'
@Component
struct SongList {
  build() {
    Column() {
      // 播放页
      Column() {
        // 歌单明细
        Column() {
          // 简介
          Row({ space: 8 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.heart_fill'))
                .fontSize(48)
                .fontColor(['#ff5186'])
                .opacity(0.8)
            }
            .width(100)
            .aspectRatio(1)
            .borderRadius(8)
            .backgroundColor(Color.White)
            .justifyContent(FlexAlign.Center)

            Column({ space: 12 }) {
              Text(favoriteList.name)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text(favoriteList.nickName)
                .fontSize(12)
                .fontColor('#ffa49a9a')
              Blank()
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          // 按钮
          Row() {
            Button() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.arrow_up'))
                  .fontSize(18)
                  .fontColor(['#ec5c87'])
                Text('分享')
                  .fontColor(Color.White)
                  .fontSize(12)
              }
              .width(100)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#ff353333')
            }
            .clip(true)

            Button() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.ellipsis_bubble'))
                  .fontSize(18)
                  .fontColor(['#ec5c87'])
                Text('评论')
                  .fontColor(Color.White)
                  .fontSize(12)
              }
              .width(100)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#ff353333')
            }
            .clip(true)

            Button() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.bookmark_fill'))
                  .fontSize(18)
                  .fontColor(['#ec5c87'])
                Text('收藏')
                  .fontColor(Color.White)
                  .fontSize(12)
              }
              .width(100)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#ff353333')
            }
            .clip(true)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .height('30%')
        .justifyContent(FlexAlign.SpaceAround)
        .radialGradient({
          center: ['80%', '-10%'],
          radius: '100%',
          colors: [['#ff865d13', 0.0], [Color.Transparent, 1.0]]
        })
        .padding(16)
        // 播放列表
        Column() {
          Row({ space: 8 }) {
           Row({space:8}){
             SymbolGlyph($r('sys.symbol.play_fill'))
               .fontSize(16)
               .fontColor(['#ff5186'])
             Text(`播放全部 (${favoriteList.songs.length})`)
               .fontColor(Color.White)
               .fontSize(14)
           }
          }
          .width('100%')
          .padding(16)
          .border({
            width: { bottom: 1 },
            color: '#12ec5c87'
          })

          Column() {
            List() {
              ForEach(favoriteList.songs, (item: songItemType, index: number) => {
                ListItem() {
                  Row() {
                    // 前三首
                    Row() {
                      if (index === 0) {
                        Text((index + 1).toString())
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#ffffe426')
                      } else if (index === 1) {
                        Text((index + 1).toString())
                          .fontColor($r('app.color.primary_light'))
                          .fontWeight(FontWeight.Bold)
                      } else if (index === 2) {
                        Text((index + 1).toString())
                          .fontWeight(FontWeight.Bold)
                          .fontColor($r('app.color.primary_dark'))
                      } else {
                        Text((index + 1).toString())
                          .fontColor('#ffa49a9a')
                      }
                    }
                    .width(50)
                    .aspectRatio(1)
                    .justifyContent(FlexAlign.Center)
                    // 列表
                    Row({ space: 10 }) {
                      if (index < 3) {
                        Image(item.img)
                          .width(32)
                          .aspectRatio(1)
                          .borderRadius(4)
                      }
                      Column() {
                        Text(item.name)
                          .fontSize(14)
                          .fontColor('#ffa49a9a')
                        Text(item.author)
                          .fontSize(12)
                          .fontColor(Color.Gray)
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      .justifyContent(FlexAlign.Center)
                    }
                    .layoutWeight(1)

                    SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                      .fontSize(22)
                      .margin({ right: 16 })
                      .fontColor([Color.Gray])
                  }
                  .alignItems(VerticalAlign.Center)
                }
                .border({
                  width: { bottom: 1 },
                  color: '#12ec5c87'
                })
              })

              ListItem() {
                Row() {
                  Text('我是有底线的~')
                    .fontColor(Color.Gray)
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding(16)
              }
            }
            .layoutWeight(1)
          }
          .layoutWeight(1)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#ff353333')
        .borderRadius({ topLeft: 12, topRight: 12 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121215')
  }
}

export default SongList