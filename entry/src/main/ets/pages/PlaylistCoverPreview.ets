import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { http } from '@kit.NetworkKit'
import { playlistType } from '../models/music'
import { BubbleTip } from '../services/BubbleTip'

export interface PlaylistCoverPreviewPageParam {
  playlist: playlistType;
  playCount: number;
  collectCount: number;
  commentCount: number;
  tags?: string[];
  description?: string;
}

@Component
export struct PlaylistCoverPreview {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State playlist: playlistType = { id: '', name: '', cover: '', count: 0, creator: '' }
  @State playCount: number = 0
  @State collectCount: number = 0
  @State commentCount: number = 0
  @State tags: string[] = []
  @State description: string = ''
  @State coverSaving: boolean = false
  @State pageParam: PlaylistCoverPreviewPageParam = {} as PlaylistCoverPreviewPageParam

  aboutToAppear(): void {
    if (this.pageParam && this.pageParam.playlist) {
      this.playlist = this.pageParam.playlist;
      this.playCount = this.pageParam.playCount || 0;
      this.collectCount = this.pageParam.collectCount || 0;
      this.commentCount = this.pageParam.commentCount || 0;
      this.tags = this.pageParam.tags || [];
      this.description = this.pageParam.description || '';
    }
  }

  private formatCount(value: number): string {
    if (value >= 100000000) {
      return `${(value / 100000000).toFixed(1)}亿`;
    }
    if (value >= 10000) {
      return `${(value / 10000).toFixed(1)}万`;
    }
    return value.toString();
  }

  private safeFileName(value: string): string {
    return value.replace(/[\\/:*?"<>|]/g, '_')
  }

  private async cacheCoverImage(): Promise<string> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cacheDir = `${context.cacheDir}/playlist_cover`
    try {
      fileIo.mkdirSync(cacheDir, true)
    } catch (_error) {
    }
    const filePath = `${cacheDir}/${this.safeFileName(this.playlist.name)}-${this.playlist.id}.jpg`
    const client = http.createHttp()
    try {
      const response = await client.request(this.playlist.cover, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: true
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`封面下载失败 (${response.responseCode})`)
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

  private async saveCoverToGallery(): Promise<void> {
    if (this.coverSaving || !this.playlist.cover) {
      return
    }
    this.coverSaving = true
    try {
      const sourceUri = await this.cacheCoverImage()
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      try {
        const configs: photoAccessHelper.PhotoCreationConfig[] = [{
          title: this.safeFileName(this.playlist.name || '歌单封面'),
          fileNameExtension: 'jpg',
          photoType: photoAccessHelper.PhotoType.IMAGE
        }]
        const savedUris = await helper.showAssetsCreationDialog([sourceUri], configs)
        BubbleTip.show(this.getUIContext(), savedUris.length > 0 ? '封面已保存到图库' : '已取消保存')
      } finally {
        await helper.release()
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '封面保存失败')
    } finally {
      this.coverSaving = false
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景图像
        Image(this.playlist.cover).width('100%').height('100%').objectFit(ImageFit.Cover).blur(48).opacity(0.55)
        Column().width('100%').height('100%')
          .linearGradient({ angle: 180, colors: [['rgba(15,15,20,0.22)', 0], ['#121215', 1]] })

        Column() {
          Column().width('100%').height(this.topAvoidHeight)
          // 顶部导航栏
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
              .onClick(() => this.pageStack.pop())
            Text('封面预览').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
              .fontColor('#ffffff').textAlign(TextAlign.Center)
            // 添加更多选项按钮（留空占位）
            SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(22).fontColor(['#ffffff']).visibility(Visibility.Hidden)
          }
          .width('100%').height(56)

          // 主要内容区域
          Column() {
            // 封面图片
            Image(this.playlist.cover).width(300).height(300).borderRadius(18).objectFit(ImageFit.Cover)
              .shadow({ radius: 18, color: 'rgba(0,0,0,0.32)', offsetY: 8 })
            
            // 大标题
            Text(this.playlist.name).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#ffffff').maxLines(3)
              .margin({ top: 24 })
            
            // 统计信息
            Row({ space: 20 }) {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor(['#d0d0d5'])
                Text(`${this.formatCount(this.playCount)} 播放`).fontSize(12).fontColor('#d0d0d5')
              }
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.heart')).fontSize(16).fontColor(['#d0d0d5'])
                Text(`${this.formatCount(this.collectCount)} 收藏`).fontSize(12).fontColor('#d0d0d5')
              }
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.ellipsis_bubble')).fontSize(16).fontColor(['#d0d0d5'])
                Text(`${this.formatCount(this.commentCount)} 评论`).fontSize(12).fontColor('#d0d0d5')
              }
            }
            .margin({ top: 12 })
            
            // 标签组hi
            if (this.tags && this.tags.length > 0) {
              Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start,
                alignItems: ItemAlign.Center }) {
                ForEach(this.tags, (tag: string, index: number) => {
                  Text(tag).fontSize(12).fontColor('#ffffff')
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor('#333339').borderRadius(16)
                    .margin(4)
                })
              }
              .padding({ left: 8 })
              .margin({ top: 16 })
            }
            
            // 描述文字
            if (this.description && this.description.length > 0) {
              Text(this.description).fontSize(14).fontColor('#a9a9b0').maxLines(5)
                .margin({ top: 16, left: 24, right: 24 })
            }
            
            Button() {
              Row({ space: 8 }) {
                if (this.coverSaving) {
                  LoadingProgress().width(18).height(18).color('#ffffff')
                } else {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(18).fontColor(['#ffffff'])
                }
                Text(this.coverSaving ? '正在保存…' : '保存封面')
                  .fontColor('#ffffff').fontSize(16).fontWeight(FontWeight.Medium)
              }
            }
            .width(200).height(44).backgroundColor('#ff6577').borderRadius(22)
            .margin({ top: 32 }).enabled(!this.coverSaving)
            .onClick(() => this.saveCoverToGallery())
          }
          .width('100%').height('100%').alignSelf(ItemAlign.Center).justifyContent(FlexAlign.Center)
        }
        .width('100%').padding({ left: 18, right: 18 })
      }
      .width('100%').height('100%').backgroundColor('#121215')
    }
    .hideTitleBar(true)
  }
}
