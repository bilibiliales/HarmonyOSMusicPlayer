import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { PlayerStore } from '../stores/PlayerStore'
import { playerController } from '../services/PlayerController'

@Component
export struct FloatingMusicCard {
  @Consume('playerStore') @Watch('onPlayingChanged') playerStore: PlayerStore
  onOpen: () => void = () => {}
  @State vinylAngle: number = 0
  private rotationTimer: number = -1

  aboutToDisappear(): void {
    if (this.rotationTimer !== -1) {
      clearInterval(this.rotationTimer)
      this.rotationTimer = -1
    }
  }

  private onPlayingChanged(): void {
    this.syncRotation()
  }

  private syncRotation(): void {
    if (this.playerStore.isPlaying && this.rotationTimer === -1) {
      this.rotationTimer = setInterval(() => {
        this.vinylAngle = (this.vinylAngle + 0.8) % 360
      }, 16)
    } else if (!this.playerStore.isPlaying && this.rotationTimer !== -1) {
      clearInterval(this.rotationTimer)
      this.rotationTimer = -1
    }
  }

  build() {
    if (this.playerStore.queue.length === 0) {
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(20)
            .fontColor(['#73737c'])
        }
        .width(48).height(48).borderRadius(24).backgroundColor('#23232a')
        Column({ space: 3 }) {
          Text('暂无播放歌曲').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#8a8a92')
          Text('播放列表为空').fontSize(11).fontColor('#62626a')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(30).fontColor(['#55555d'])
        SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(21).fontColor(['#4d4d55']).margin({ right: 4 })
      }
      .width('91.47%').height(58).padding({ left: 8, right: 10, top: 5, bottom: 5 })
      .borderRadius(40).backgroundColor('rgba(28,28,34,0.78)').opacity(0.82)
    } else {
      Row({ space: 10 }) {
        Stack() {
          Image($r('app.media.ic_cd')).width(44).height(44)
          if (this.playerStore.currentSong.img) {
            Image(this.playerStore.currentSong.img).width(28).height(28).borderRadius(14)
              .objectFit(ImageFit.Cover).rotate({ angle: this.vinylAngle })
          } else {
            SymbolGlyph($r('sys.symbol.music')).fontSize(16).fontColor(['#ffffff'])
          }
        }
        .width(48).height(48).onClick(() => this.onOpen())

        Column({ space: 3 }) {
          Text(this.playerStore.currentSong.name).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor('#ffffff').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.playerStore.currentSong.author).fontSize(11).fontColor('#92929a').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.onOpen())

        if (this.playerStore.isLoading) {
          LoadingProgress().width(26).height(26).color('#ffffff')
        } else {
          SymbolGlyph(this.playerStore.isPlaying ? $r('sys.symbol.pause_circle_fill') :
            $r('sys.symbol.play_circle_fill'))
            .fontSize(30).fontColor(['#ffffff']).onClick(() => playerController.toggle())
        }

        SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(21).fontColor(['#d3d3d8'])
          .margin({ right: 4 }).onClick(() => playerController.next())
      }
      .width('91.47%').height(58).padding({ left: 8, right: 10, top: 5, bottom: 5 })
      .borderRadius(40).backgroundColor('rgba(28,28,34,0.92)')
      .systemMaterial(deviceInfo.apiAvailable('26.0.0') ? new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true
      }) : uiMaterial.Material.empty)
      .shadow({ radius: 40, color: 'rgba(0,0,0,0.32)', offsetY: 8 })
      .onAppear(() => this.syncRotation())
    }
  }
}
