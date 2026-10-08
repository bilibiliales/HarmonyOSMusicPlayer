import { EventPicture } from '../models/api'
import { EventPresentation } from '../services/EventPresentation'

let nextEventImageId: number = 0

@Component
export struct EventImages {
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Prop pictures: EventPicture[] = []
  @State loadedRatio: number = 1
  @State previewMounted: boolean = false
  @State previewVisible: boolean = false
  @State previewIndex: number = 0
  private previewClosing: boolean = false
  private transitionPrefix: string = `event-images-${++nextEventImageId}`

  aboutToDisappear(): void {
    this.previewMounted = false
    this.previewVisible = false
    this.previewClosing = false
  }

  private ratio(): number {
    const picture = this.pictures[0]
    return picture?.width && picture.height && picture.width > 0 && picture.height > 0 ?
      picture.width / picture.height : this.loadedRatio
  }

  private transitionId(index: number): string {
    return `${this.transitionPrefix}-${index}`
  }

  private preview(index: number): void {
    if (this.previewMounted || this.previewClosing) {
      return
    }
    this.previewIndex = index
    this.previewMounted = true
  }

  private revealPreview(): void {
    this.getUIContext().animateTo({ duration: 360, curve: Curve.EaseInOut }, () => {
      this.previewVisible = true
    })
  }

  private closePreview(): void {
    if (!this.previewMounted || this.previewClosing) {
      return
    }
    this.previewClosing = true
    this.getUIContext().animateTo({
      duration: 360,
      curve: Curve.EaseInOut,
      onFinish: () => {
        this.previewMounted = false
        this.previewClosing = false
      }
    }, () => {
      this.previewVisible = false
    })
  }

  @Builder
  private Preview() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column().width('100%').height('100%').backgroundColor('#000000')
        .opacity(this.previewVisible ? 1 : 0)
      Swiper() {
        ForEach(this.pictures, (picture: EventPicture, index: number) => {
          Stack() {
            if (this.previewVisible) {
              Image(EventPresentation.picture(picture)).width('100%').height('100%')
                .objectFit(ImageFit.Contain)
                .geometryTransition(this.previewIndex === index ? this.transitionId(index) :
                  this.transitionId(index) + '-preview', { follow: true })
            }
          }.width('100%').height('100%').onClick(() => this.closePreview())
        }, (_picture: EventPicture, index: number) => this.transitionId(index))
      }.width('100%').height('100%').index(this.previewIndex).indicator(false).loop(false)
        .onChange((index: number) => this.previewIndex = index)
      Row({ space: 16 }) {
        Text((this.previewIndex + 1) + ' / ' + this.pictures.length).fontSize(14).fontColor('#ffffff')
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(28).fontColor(['#ffffff'])
          .onClick(() => this.closePreview())
      }.padding({ top: this.topAvoidHeight + 12, right: 18 })
        .opacity(this.previewVisible ? 1 : 0)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
      .onAppear(() => this.revealPreview())
  }

  build() {
    Column() {
      if (this.pictures.length === 1) {
        if (this.previewVisible) {
          Column().width('100%').aspectRatio(this.ratio())
        } else {
          Image(EventPresentation.picture(this.pictures[0])).width('100%').aspectRatio(this.ratio())
            .objectFit(ImageFit.Contain).borderRadius(12)
            .geometryTransition(this.transitionId(0), { follow: true })
            .onComplete((event) => {
              if (event && event.width > 0 && event.height > 0) { this.loadedRatio = event.width / event.height }
            })
            .onClick(() => this.preview(0))
        }
      } else if (this.pictures.length > 1) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.pictures, (picture: EventPicture, index: number) => {
              if (this.previewVisible && this.previewIndex === index) {
                Column().width(116).height(116)
              } else {
                Image(EventPresentation.picture(picture)).width(116).height(116).borderRadius(12)
                  .objectFit(ImageFit.Cover)
                  .geometryTransition(this.transitionId(index), { follow: true })
                  .onClick(() => this.preview(index))
              }
            }, (_picture: EventPicture, index: number) => this.transitionId(index))
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }.width('100%')
      .bindContentCover(this.previewMounted, this.Preview(), {
        modalTransition: ModalTransition.NONE,
        backgroundColor: Color.Transparent,
        onWillDismiss: () => this.closePreview(),
        onDisappear: () => {
          this.previewMounted = false
          this.previewVisible = false
          this.previewClosing = false
        }
      })
  }
}
