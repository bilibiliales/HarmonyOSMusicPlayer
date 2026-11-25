let cardStorage = new LocalStorage()

@Entry(cardStorage)
@Component
struct MusicCard {
  @LocalStorageProp('songName') songName: string = '今天听点什么？'
  @LocalStorageProp('artist') artist: string = '打开应用开始播放'
  @LocalStorageProp('songId') songId: string = ''
  @LocalStorageProp('isPlaying') isPlaying: boolean = false
  @LocalStorageProp('liked') liked: boolean = false
  @LocalStorageProp('playMode') playMode: number = 0
  @LocalStorageProp('cover') cover: string = ''
  @LocalStorageProp('dimension') dimension: number = 2

  private large(): boolean { return this.dimension === 3 }
  private actionSeq: number = 0

  private control(action: string): void {
    const requestId = `${Date.now()}-${++this.actionSeq}-${action}`
    postCardAction(this, { action: 'message',
      params: { musicCardAction: action, musicCardSongId: this.songId, requestId: requestId } })
    postCardAction(this, { action: 'call', abilityName: 'EntryAbility',
      params: { method: 'musicCardControl', musicCardAction: action, musicCardSongId: this.songId, requestId: requestId } })
  }

  @Builder
  private Control(icon: Resource, action: string, size: number = 24) {
    SymbolGlyph(icon).fontSize(this.large() ? size : Math.min(size, 24)).fontColor(['#ffffff'])
      .width(this.large() ? 42 : 32).height(this.large() ? 42 : 36)
      .onClick(() => this.control(action))
  }
  build() {
    Stack() {
      if (this.cover) { Image(this.cover).width('100%').height('100%').objectFit(ImageFit.Cover) }
      else { Column().width('100%').height('100%').backgroundColor('#352333') }
      Column().width('100%').height('100%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(0,0,0,0.25)', 0], ['rgba(0,0,0,0.72)', 1]]
        })

      Column({ space: 5 }) {
          Text(this.songName).width('100%').fontSize(this.large() ? 20 : 16).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(this.large() ? TextAlign.Start : TextAlign.Center)
          Text(this.artist).width('100%').fontSize(12).fontColor('#c9c9cd').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(this.large() ? TextAlign.Start : TextAlign.Center)
        Blank()
        Row({ space: 8 }) {
          if (this.large()) {
            if (this.playMode === 1) {
              this.Control($r('sys.symbol.repeat_1'), 'mode', 22)
            } else if (this.playMode === 2) {
              this.Control($r('sys.symbol.shuffle'), 'mode', 22)
            } else {
              this.Control($r('sys.symbol.repeat'), 'mode', 22)
            }
          }
          Row({ space: 8 }) {
          this.Control($r('sys.symbol.backward_end_fill'), 'previous')
          if (this.isPlaying) {
            this.Control($r('sys.symbol.pause_fill'), 'toggle', 28)
          } else {
            this.Control($r('sys.symbol.play_fill'), 'toggle', 28)
          }
          this.Control($r('sys.symbol.forward_end_fill'), 'next')
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
          if (this.large()) {
            SymbolGlyph(this.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(24).fontColor([this.liked ? '#ff4058' : '#ffffff']).width(42).height(42)
              .onClick(() => this.control('like'))
          }
        }.width('100%').justifyContent(this.large() ? FlexAlign.Start : FlexAlign.Center)
      }
      .width('100%').height('100%').padding(16)
      .alignItems(this.large() ? HorizontalAlign.Start : HorizontalAlign.Center)
    }
    .width('100%').height('100%').clip(true).backgroundColor(Color.Transparent)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility'
      })
    })
  }
}
