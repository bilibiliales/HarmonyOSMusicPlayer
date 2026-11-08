import { fileIo } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { OperationResponse, PlaylistCreateResponse } from '../models/api'
import { playlistType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'
import { TC } from '../services/ThemeColors'

export interface PlaylistEditorPageParam {
  mode: 'create' | 'edit'
  playlist?: playlistType
  onSaved?: (playlistId: string) => void
}

@Component
export struct PlaylistEditorPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: PlaylistEditorPageParam = { mode: 'create' }

  @State name: string = ''
  @State description: string = ''
  @State tagsText: string = ''
  @State privacy: number = 0
  @State coverUri: string = ''
  @State saving: boolean = false
  @State message: string = ''
  private initialized: boolean = false

  aboutToAppear(): void {
    if (!this.authStore.loggedIn) {
      this.pageStack.replacePathByName('LoginPage', null)
      return
    }
    if (!this.initialized) {
      const playlist = this.pageParam.playlist
      this.name = playlist?.name || ''
      this.description = playlist?.description || ''
      this.tagsText = (playlist?.tags || []).join(', ')
      this.privacy = playlist?.privacy === 10 ? 10 : 0
      this.initialized = true
    }
  }

  private async selectCover(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const result = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      })
      if (result.photoUris.length > 0) {
        this.coverUri = result.photoUris[0]
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '封面选择失败'
    }
  }

  private normalizedTags(): string {
    return this.tagsText.split(',').map((item: string) => item.trim()).filter((item: string) => item.length > 0)
      .slice(0, 3).join(';')
  }

  private async uploadCover(playlistId: string): Promise<void> {
    if (!this.coverUri) {
      return
    }
    const file = fileIo.openSync(this.coverUri, fileIo.OpenMode.READ_ONLY)
    try {
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      const lower = this.coverUri.toLowerCase()
      const isPng = lower.includes('.png')
      const response = await ApiClient.upload<OperationResponse>('/playlist/cover/update', [
        { key: 'id', value: playlistId },
        { key: 'imgSize', value: '500' },
        { key: 'imgX', value: '0' },
        { key: 'imgY', value: '0' }
      ], 'imgFile', isPng ? 'cover.png' : 'cover.jpg', buffer, isPng ? 'image/png' : 'image/jpeg')
      if (response.code !== 200) {
        throw new Error(response.message || '歌单封面上传失败')
      }
    } finally {
      fileIo.closeSync(file)
    }
  }

  private async save(): Promise<void> {
    const playlistName = this.name.trim()
    if (!playlistName || this.saving) {
      return
    }
    this.saving = true
    this.message = ''
    try {
      let playlistId = this.pageParam.playlist?.id || ''
      if (this.pageParam.mode === 'create') {
        const createResponse = await ApiClient.get<PlaylistCreateResponse>('/playlist/create', [
          { key: 'name', value: playlistName },
          { key: 'privacy', value: this.privacy.toString() },
          { key: 'timestamp', value: Date.now().toString() }
        ])
        playlistId = createResponse.id?.toString() || createResponse.playlist?.id?.toString() || ''
        if (createResponse.code !== 200 || !playlistId) {
          throw new Error(createResponse.message || '歌单创建失败')
        }
      }

      const updateResponse = await ApiClient.get<OperationResponse>('/playlist/update', [
        { key: 'id', value: playlistId },
        { key: 'name', value: playlistName },
        { key: 'desc', value: this.description.trim() },
        { key: 'tags', value: this.normalizedTags() },
        { key: 'privacy', value: this.privacy.toString() },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (updateResponse.code !== 200) {
        throw new Error(updateResponse.message || '歌单信息更新失败')
      }
      await this.uploadCover(playlistId)
      this.pageParam.onSaved?.(playlistId)
      this.pageStack.pop()
    } catch (error) {
      this.message = error instanceof Error ? error.message : '歌单保存失败'
    } finally {
      this.saving = false
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text(this.pageParam.mode === 'create' ? '新建歌单' : '编辑歌单').layoutWeight(1)
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          Button(this.saving ? '保存中' : '保存').height(36).fontSize(12).fontColor(TC.textPrimary())
            .backgroundColor(this.name.trim() && !this.saving ? TC.accent() : TC.surfaceRaised()).borderRadius(18)
            .enabled(this.name.trim().length > 0 && !this.saving).onClick(() => this.save())
        }.width('100%').height(58).padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 20 }) {
            Column({ space: 9 }) {
              Text('歌单封面').width('100%').fontSize(13).fontWeight(FontWeight.Medium).fontColor(TC.textBody())
              Stack({ alignContent: Alignment.BottomEnd }) {
                if (this.coverUri || this.pageParam.playlist?.cover) {
                  Image(this.coverUri || this.pageParam.playlist?.cover || '').width(148).height(148)
                    .borderRadius(18).objectFit(ImageFit.Cover)
                } else {
                  Stack() {
                    SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(44).fontColor([TC.textQuaternary()])
                  }.width(148).height(148).borderRadius(18).backgroundColor(TC.surfaceInset())
                }
                Stack() {
                  SymbolGlyph($r('sys.symbol.camera_fill')).fontSize(18).fontColor([TC.textOnAccent()])
                }.width(38).height(38).borderRadius(19).backgroundColor(TC.accent())
              }.width(148).height(148).onClick(() => this.selectCover())
            }.width('100%').alignItems(HorizontalAlign.Center)

            Column({ space: 8 }) {
              Text('名称').width('100%').fontSize(12).fontColor(TC.textTertiary())
              TextInput({ text: this.name, placeholder: '输入歌单名称' }).width('100%').height(48)
                .fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceCardAlt()).borderRadius(14)
                .onChange((value: string) => this.name = value.substring(0, 40))
            }.width('100%')

            Column({ space: 8 }) {
              Text('简介').width('100%').fontSize(12).fontColor(TC.textTertiary())
              TextArea({ text: this.description, placeholder: '介绍一下这个歌单' }).width('100%').height(130)
                .fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceCardAlt()).borderRadius(14)
                .onChange((value: string) => this.description = value.substring(0, 1000))
            }.width('100%')

            Column({ space: 8 }) {
              Text('标签').width('100%').fontSize(12).fontColor(TC.textTertiary())
              TextInput({ text: this.tagsText, placeholder: '流行, 华语, 学习（最多三个）' }).width('100%').height(48)
                .fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceCardAlt()).borderRadius(14)
                .onChange((value: string) => this.tagsText = value)
            }.width('100%')

            Column({ space: 10 }) {
              Text('可见范围').width('100%').fontSize(12).fontColor(TC.textTertiary())
              Row({ space: 10 }) {
                Text('公开').layoutWeight(1).height(44).fontSize(13).textAlign(TextAlign.Center)
                  .fontColor(this.privacy === 0 ? TC.textOnAccent() : TC.textTertiary())
                  .backgroundColor(this.privacy === 0 ? TC.accent() : TC.surfaceInset()).borderRadius(13)
                  .onClick(() => this.privacy = 0)
                Text('仅自己可见').layoutWeight(1).height(44).fontSize(13).textAlign(TextAlign.Center)
                  .fontColor(this.privacy === 10 ? TC.textOnAccent() : TC.textTertiary())
                  .backgroundColor(this.privacy === 10 ? TC.accent() : TC.surfaceInset()).borderRadius(13)
                  .onClick(() => this.privacy = 10)
              }.width('100%')
            }.width('100%')

            if (this.message) {
              Text(this.message).width('100%').padding(12).fontSize(11).lineHeight(18).fontColor(TC.accentSoft())
                .textAlign(TextAlign.Center).backgroundColor(TC.surfaceInset()).borderRadius(13)
            }
          }.width('100%').padding({ left: 18, right: 18, top: 16, bottom: 40 })
        }.layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true)
  }
}
