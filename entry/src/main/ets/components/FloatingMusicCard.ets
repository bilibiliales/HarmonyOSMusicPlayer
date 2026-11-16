import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { PlayerStore } from '../stores/PlayerStore'
import { playerController } from '../services/PlayerController'
import { VinylRecord } from './VinylRecord'
import { TC } from '../services/ThemeColors'
import { DecoKeys } from '../services/DecorationRuntime'
import { DecorationMedia } from '../services/DecorationMedia'

/**
 * 首页底部的迷你悬浮播放器。
 *
 * 「迷你播放器」装扮可以替换整条胶囊的贴图 / 底色，并单独指定歌名、歌手与控制图标颜色；
 * 没设置任何内容时与默认观感完全一致（含沉浸材质与半透明）。
 */
@Component
export struct FloatingMusicCard {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @StorageProp(DecoKeys.MINI_BG) miniBg: string = ''
  @StorageProp(DecoKeys.MINI_BG_COLOR) miniBgColor: string = ''
  @StorageProp(DecoKeys.MINI_BG_OPACITY) miniBgOpacity: number = 100
  @StorageProp(DecoKeys.MINI_BG_BLUR) miniBgBlur: number = 0
  @StorageProp(DecoKeys.MINI_RADIUS) miniRadius: number = 29
  @StorageProp(DecoKeys.MINI_TITLE_COLOR) miniTitleColor: string = ''
  @StorageProp(DecoKeys.MINI_SUBTITLE_COLOR) miniSubtitleColor: string = ''
  @StorageProp(DecoKeys.MINI_ICON_COLOR) miniIconColor: string = ''
  @Consume('playerStore') playerStore: PlayerStore
  onOpen: () => void = () => {}

  /** 是否设置了任意迷你播放器装扮。 */
  private skinned(): boolean {
    return this.miniBg.length > 0 || this.miniBgColor.length > 0
  }

  private titleColor(): ResourceColor {
    return this.miniTitleColor ? this.miniTitleColor : TC.textPrimary()
  }

  private subtitleColor(): ResourceColor {
    return this.miniSubtitleColor ? this.miniSubtitleColor : TC.textSecondary()
  }

  private iconColor(): ResourceColor {
    return this.miniIconColor ? this.miniIconColor : TC.textPrimary()
  }

  @Builder
  private Backdrop() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.miniBgColor ? this.miniBgColor : TC.sheetBackground())
      if (this.miniBg) {
        Image(DecorationMedia.displayUri(this.miniBg))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.miniBgBlur)
          .opacity(Math.max(0, Math.min(100, this.miniBgOpacity)) / 100)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private EmptyRow() {
    Row({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(20)
          .fontColor([TC.textTertiary()])
      }
      .width(48).height(48).borderRadius(24).backgroundColor(TC.surfaceInset())
      Column({ space: 3 }) {
        Text('暂无播放歌曲').fontSize(14).fontWeight(FontWeight.Medium).fontColor(TC.textSecondary())
        Text('播放列表为空').fontSize(11).fontColor(TC.textQuaternary())
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.backward_end_fill')).fontSize(21).fontColor([TC.textQuaternary()])
      SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(30).fontColor([TC.textQuaternary()])
      SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(21).fontColor([TC.textQuaternary()]).margin({ right: 4 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 10, top: 5, bottom: 5 })
  }

  @Builder
  private PlayingRow() {
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
          .fontColor(this.titleColor()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.playerStore.currentSong.author).fontSize(11).fontColor(this.subtitleColor()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.onOpen())

      SymbolGlyph($r('sys.symbol.backward_end_fill')).fontSize(21).fontColor([this.iconColor()])
        .onClick(() => playerController.previous())
      if (this.playerStore.isLoading) {
        LoadingProgress().width(26).height(26).color(this.iconColor())
      } else {
        SymbolGlyph(this.playerStore.isPlaying ? $r('sys.symbol.pause_circle_fill') :
          $r('sys.symbol.play_circle_fill'))
          .fontSize(30).fontColor([this.iconColor()]).onClick(() => playerController.toggle())
      }

      SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(21).fontColor([this.iconColor()])
        .margin({ right: 4 }).onClick(() => playerController.next())
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 10, top: 5, bottom: 5 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.Backdrop()
      if (this.playerStore.queue.length === 0) {
        this.EmptyRow()
      } else {
        this.PlayingRow()
      }
    }
    .width('91.47%')
    .height(58)
    .borderRadius(this.miniRadius)
    .clip(true)
    // 未装扮时保留原来的半透明观感；装扮后按用户填的颜色/贴图原样显示
    .opacity(this.skinned() ? 1 : (this.playerStore.queue.length === 0 ? 0.82 : 0.95))
    .systemMaterial(this.skinned() || !deviceInfo.apiAvailable('26.0.0') ? uiMaterial.Material.empty :
      new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true
      }))
    .shadow({ radius: 40, color: 'rgba(0,0,0,0.32)', offsetY: 8 })
  }
}
