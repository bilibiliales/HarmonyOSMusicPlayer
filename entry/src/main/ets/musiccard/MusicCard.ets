let cardStorage = new LocalStorage()

@Entry(cardStorage)
@Component
struct MusicCard {
  @LocalStorageProp('songName') songName: string = '今天听点什么？'
  @LocalStorageProp('artist') artist: string = '打开应用开始播放'
  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column().width('100%').height('100%')
        .linearGradient({
          angle: 145,
          colors: [['#8f2942', 0], ['#4b2030', 0.48], ['#17151d', 1]]
        })

      Column() {
        Row({ space: 8 }) {
          Image($r('app.media.logo')).width(32).height(32).borderRadius(9).objectFit(ImageFit.Cover)
          Text('网易云音乐').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        }
        .width('100%')
        Blank()
        Column({ space: 5 }) {
          Text(this.songName).width('100%').fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.artist).width('100%').fontSize(11).fontColor('#c3c3c9').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start).width('100%')
      }
      .width('100%').height('100%').padding(16)
    }
    .width('100%').height('100%').borderRadius(24).clip(true).backgroundColor('#17171c')
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility'
      })
    })
  }
}
