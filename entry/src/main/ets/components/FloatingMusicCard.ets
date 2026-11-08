import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { PlayerStore } from '../stores/PlayerStore'
import { playerController } from '../services/PlayerController'
import { VinylRecord } from './VinylRecord'
import { TC } from '../services/ThemeColors'

@Component
export struct FloatingMusicCard {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('playerStore') playerStore: PlayerStore
  onOpen: () => void = () => {}

  build() {
    if (this.playerStore.queue.length === 0) {
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(20)
            .fontColor([TC.textTertiary()])
        }
        .width(48).height(48).borderRadius(24).backgroundColor(TC.surfaceInset())
        Column({ space: 3 }) {
          Text('暂无播放歌曲').fontSize(14).fontWeight(FontWeight.Medium).fontColor(TC.textOnMediaSecondary())
          Text('播放列表为空').fontSize(11).fontColor(TC.textQuaternary())
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.backward_end_fill')).fontSize(21).fontColor([TC.textQuaternary()])
        SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(30).fontColor([TC.textQuaternary()])
        SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(21).fontColor([TC.textQuaternary()]).margin({ right: 4 })
      }
      .width('91.47%').height(58).padding({ left: 8, right: 10, top: 5, bottom: 5 })
      .borderRadius(40).backgroundColor('rgba(28,28,34,0.78)').opacity(0.82)
    } else {
      Row({ space: 10 }) {
        Stack() {
          VinylRecord({
            coverUrl: this.playerStore.currentSong.img,
            isPlaying: this.playerStore.isPlaying && !this.playerStore.isLoading,
            diameter: 44
          })
        }
        .width(48).height(48).onClick(() => this.onOpen())

        Column({ space: 3 }) {
          Text(this.playerStore.currentSong.name).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(TC.textOnMedia()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.playerStore.currentSong.author).fontSize(11).fontColor(TC.textOnMediaSecondary()).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.onOpen())

        SymbolGlyph($r('sys.symbol.backward_end_fill')).fontSize(21).fontColor([TC.textOnMedia()])
          .onClick(() => playerController.previous())
        if (this.playerStore.isLoading) {
          LoadingProgress().width(26).height(26).color(TC.textOnMedia())
        } else {
          SymbolGlyph(this.playerStore.isPlaying ? $r('sys.symbol.pause_circle_fill') :
            $r('sys.symbol.play_circle_fill'))
            .fontSize(30).fontColor([TC.textOnMedia()]).onClick(() => playerController.toggle())
        }

        SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(21).fontColor([TC.textOnMedia()])
          .margin({ right: 4 }).onClick(() => playerController.next())
      }
      .width('91.47%').height(58).padding({ left: 8, right: 10, top: 5, bottom: 5 })
      .borderRadius(40).backgroundColor('rgba(28,28,34,0.92)')
      .systemMaterial(deviceInfo.apiAvailable('26.0.0') ? new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true
      }) : uiMaterial.Material.empty)
      .shadow({ radius: 40, color: 'rgba(0,0,0,0.32)', offsetY: 8 })
    }
  }
}
