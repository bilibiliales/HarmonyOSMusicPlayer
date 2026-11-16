import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { http } from '@kit.NetworkKit'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'

export interface ImagePreviewPageParam {
  url: string
  name?: string
}

@Component
export struct ImagePreviewPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State pageParam: ImagePreviewPageParam = {} as ImagePreviewPageParam
  @State saving: boolean = false
  @State zoom: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  private baseZoom: number = 1

  aboutToAppear(): void {
    if (!this.pageParam) {
      this.pageParam = {} as ImagePreviewPageParam
    }
  }

  private safeFileName(value: string): string {
    const cleaned = (value || 'image').replace(/[\\/:*?"<>|]+/g, '_').replace(/\s+/g, '_')
    return cleaned.slice(0, 40) || 'image'
  }

  private async cacheImage(): Promise<string> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cacheDir = `${context.cacheDir}/image_preview`
    try {
      fileIo.mkdirSync(cacheDir, true)
    } catch (_error) {
    }
    const filePath = `${cacheDir}/${this.safeFileName(this.pageParam.name || 'avatar')}.jpg`
    const client = http.createHttp()
    try {
      const response = await client.request(this.pageParam.url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: true
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`图片下载失败 (${response.responseCode})`)
      }
      const file = fileIo.openSync(filePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(file.fd, response.result as ArrayBuffer)
      } finally {
        fileIo.closeSync(file)
      }
      return fileUri.getUriFromPath(filePath)
    } finally {
      client.destroy()
    }
  }

  private async saveToGallery(): Promise<void> {
    if (this.saving || !this.pageParam.url) {
      return
    }
    this.saving = true
    try {
      const sourceUri = await this.cacheImage()
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      try {
        const configs: photoAccessHelper.PhotoCreationConfig[] = [{
          title: this.safeFileName(this.pageParam.name || 'avatar'),
          fileNameExtension: 'jpg',
          photoType: photoAccessHelper.PhotoType.IMAGE
        }]
        const savedUris = await helper.showAssetsCreationDialog([sourceUri], configs)
        BubbleTip.show(this.getUIContext(), savedUris.length > 0 ? '图片已保存到图库' : '已取消保存')
      } finally {
        await helper.release()
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '图片保存失败')
    } finally {
      this.saving = false
    }
  }

  build() {
    NavDestination() {
      Stack() {
        Image(this.pageParam.url).width('100%').height('100%').objectFit(ImageFit.Cover).blur(48).opacity(0.5)
        Column().width('100%').height('100%')
          .linearGradient({ angle: 180, colors: [[TC.headerScrimTop(), 0], [TC.pageBackground(), 1]] })

        Column() {
          Column().width('100%').height(this.topAvoidHeight)
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([TC.textOnMedia()])
            }
            .width(36).height(36).borderRadius(18).backgroundColor('rgba(0,0,0,0.35)')
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.pageStack.pop())
            Text(this.pageParam.name || '图片查看').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
              .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
            SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(22).fontColor([TC.textPrimary()])
              .visibility(Visibility.Hidden)
          }
          .width('100%').height(56).padding({ left: 12, right: 12 })

          Stack({ alignContent: Alignment.Center }) {
            if (this.pageParam.url) {
              Image(this.pageParam.url)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .scale({ x: this.zoom, y: this.zoom })
                .offset({ x: this.offsetX, y: this.offsetY })
                .animation({ duration: this.zoom === 1 ? 200 : 0 })
                .gesture(
                  PinchGesture({ fingers: 2 })
                    .onActionStart(() => { this.baseZoom = this.zoom })
                    .onActionUpdate((event: GestureEvent) => {
                      this.zoom = Math.min(4, Math.max(1, this.baseZoom * event.scale))
                    })
                    .onActionEnd(() => {
                      if (this.zoom <= 1.01) {
                        this.zoom = 1
                        this.offsetX = 0
                        this.offsetY = 0
                      }
                    })
                )
                .gesture(
                  PanGesture()
                    .onActionUpdate((event: GestureEvent) => {
                      if (this.zoom > 1) {
                        this.offsetX = event.offsetX
                        this.offsetY = event.offsetY
                      }
                    })
                )
                .onClick(() => {
                  if (this.zoom > 1) {
                    this.zoom = 1
                    this.offsetX = 0
                    this.offsetY = 0
                  }
                })
            } else {
              Column({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(40).fontColor([TC.textTertiary()])
                Text('图片地址无效').fontSize(13).fontColor(TC.textTertiary())
              }
            }
          }
          .width('100%').layoutWeight(1)

          Row() {
            Button() {
              Row({ space: 8 }) {
                if (this.saving) {
                  LoadingProgress().width(18).height(18).color(TC.textOnAccent())
                } else {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(18).fontColor([TC.textOnAccent()])
                }
                Text(this.saving ? '正在保存…' : '保存图片')
                  .fontColor(TC.textOnAccent()).fontSize(16).fontWeight(FontWeight.Medium)
              }
            }
            .width(200).height(44).backgroundColor(TC.accent()).borderRadius(22)
            .enabled(!this.saving && (this.pageParam.url || '').length > 0)
            .onClick(() => this.saveToGallery())
          }
          .width('100%').justifyContent(FlexAlign.Center)
          .padding({ top: 12, bottom: 16 })
        }
        .width('100%').height('100%').padding({ left: 18, right: 18 })
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
