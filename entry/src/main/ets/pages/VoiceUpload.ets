import { common } from '@kit.AbilityKit'
import { fileUri, picker } from '@kit.CoreFileKit'
import { VoiceList, VoicePublishOptions, VoiceUploadParam, VoiceUploadService } from '../services/VoiceUploadService'
import { PodcastService } from '../services/PodcastService'
import { DecoMediaPicker } from '../components/DecoControls'
import { DecoRatio } from '../models/decoration'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { AuthStore } from '../stores/AuthStore'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'

@Component
export struct VoiceUploadPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') @Watch('authChanged') authStore: AuthStore
  @StorageProp('skinVersion') skinVersionObs: number = 0
  pageParam: VoiceUploadParam = {}
  @State lists: VoiceList[] = []
  @State selectedId: string = ''
  @State nameText: string = ''
  @State description: string = ''
  @State fileName: string = ''
  @State fileSource: string = ''
  @State privacy: boolean = false
  @State cover: string = ''
  @State scheduled: boolean = false
  @State publishAt: string = ''
  @State autoPublish: boolean = false
  @State dynamicText: string = ''
  @State loading: boolean = false
  @State uploading: boolean = false
  @State picking: boolean = false
  @State message: string = ''
  private requestId: number = 0
  private owner: string = ''
  private alive: boolean = true

  aboutToAppear(): void { this.alive = true; this.owner = this.authStore.userId; this.load() }
  aboutToDisappear(): void { this.alive = false; this.requestId++ }

  private authChanged(): void {
    if (this.owner === this.authStore.userId && this.authStore.loggedIn) { return }
    this.requestId++
    this.lists = []
    this.selectedId = ''
    this.loading = false
    if (this.alive && !this.uploading) { this.load() }
  }

  private async load(): Promise<void> {
    if (this.loading) { return }
    if (!this.authStore.loggedIn) { this.message = '请登录后发布声音'; return }
    const request = ++this.requestId
    const owner = this.authStore.userId
    this.loading = true
    this.message = ''
    try {
      const lists = await VoiceUploadService.lists()
      if (!this.alive || request !== this.requestId || owner !== this.authStore.userId || !this.authStore.loggedIn) { return }
      this.owner = owner
      this.lists = lists
      const selected = lists.find((list: VoiceList) => String(list.voiceListId) === (this.pageParam.voiceListId || this.selectedId)) || lists[0]
      this.selectedId = selected ? String(selected.voiceListId) : ''
      if (selected?.privacy) { this.privacy = true; this.autoPublish = false }
      if (!this.lists.length) { this.message = '先在网易云创作者中心创建播客，返回后刷新即可发布声音' }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '播客列表加载失败'
    } finally { if (request === this.requestId) { this.loading = false } }
  }

  private async pickAudio(): Promise<void> {
    if (this.uploading || this.picking) { return }
    this.picking = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const options = new picker.AudioSelectOptions()
      options.maxSelectNumber = 1
      const uris = await new picker.AudioViewPicker(context).select(options)
      if (!uris.length) { return }
      this.fileSource = uris[0]
      this.fileName = new fileUri.FileUri(uris[0]).name
      if (!this.nameText) { this.nameText = this.fileName.replace(/\.[^.]+$/, '') }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '音频选择失败'
    } finally { this.picking = false }
  }

  private async submit(): Promise<void> {
    if (this.uploading || this.picking || this.loading) { return }
    if (!this.authStore.loggedIn || this.owner !== this.authStore.userId) { this.pageStack.pushPathByName('LoginPage', null); return }
    const selected = this.lists.find((list: VoiceList) => String(list.voiceListId) === this.selectedId)
    if (!selected || !this.fileSource || !this.nameText.trim() || !this.description.trim()) {
      this.message = '请选择播客和音频，并填写声音名称、介绍'
      return
    }
    this.uploading = true
    this.message = ''
    const owner = this.authStore.userId
    try {
      const options: VoicePublishOptions = { coverUri: this.cover, autoPublish: this.autoPublish, autoPublishText: this.dynamicText }
      if (this.scheduled) {
        options.publishTime = VoiceUploadService.parsePublishTime(this.publishAt)
      }
      const list = await VoiceUploadService.detail(selected)
      if (!this.alive || owner !== this.authStore.userId || !this.authStore.loggedIn) { return }
      await VoiceUploadService.upload(list, this.nameText, this.description, this.privacy, this.fileSource, this.fileName, options)
      PodcastService.changed()
      if (!this.alive || owner !== this.authStore.userId) { return }
      this.pageParam.onUploaded?.()
      BubbleTip.show(this.getUIContext(), '声音已上传，可在我的播客查看发布状态')
      this.pageStack.pop()
    } catch (error) {
      this.message = error instanceof Error ? error.message : '声音上传失败'
    } finally { this.uploading = false }
  }

  private async create(): Promise<void> {
    try { await PodcastService.openCreator(this.getUIContext().getHostContext() as common.UIAbilityContext) }
    catch (error) { this.message = error instanceof Error ? error.message : '创作者中心打开失败' }
  }

  private select(list: VoiceList): void {
    this.selectedId = String(list.voiceListId)
    if (list.privacy) { this.privacy = true; this.autoPublish = false }
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Column() {
        Column().height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .enabled(!this.uploading).onClick(() => this.pageStack.pop())
          Text('发布播客声音').layoutWeight(1).textAlign(TextAlign.Center).fontSize(18).fontColor(TC.textPrimary())
          Column().width(24)
        }.width('100%').height(56).padding({ left: 16, right: 16 })
        Scroll() {
          Column({ space: 16 }) {
            Text('选择播客').width('100%').fontSize(14).fontColor(TC.textPrimary())
            if (this.loading) { LoadingProgress().width(32).height(32).color(TC.accent()) }
            ForEach(this.lists, (list: VoiceList) => {
              Row({ space: 10 }) {
                if (list.coverUrl) { Image(list.coverUrl).width(42).height(42).borderRadius(10).objectFit(ImageFit.Cover) }
                Text(list.voiceListName).layoutWeight(1).fontSize(14).fontColor(TC.textBody()).maxLines(2)
                SymbolGlyph(String(list.voiceListId) === this.selectedId ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
                  .fontSize(20).fontColor([TC.accent()])
              }.width('100%').padding(12).backgroundColor(TC.surfaceCard()).borderRadius(12)
                .enabled(!this.uploading).onClick(() => this.select(list))
            }, (list: VoiceList) => String(list.voiceListId))
            Button(this.fileName || '选择音频文件').width('100%').height(44)
              .enabled(!this.uploading && !this.picking).onClick(() => this.pickAudio())
            DecoMediaPicker({ label: '声音封面（可选，默认使用播客封面）', value: this.cover, cropAspect: DecoRatio.SQUARE,
              onChange: (path: string) => this.cover = path }).enabled(!this.uploading)
            TextInput({ text: this.nameText, placeholder: '声音名称' }).width('100%')
              .fontColor(TC.textBody()).backgroundColor(TC.surfaceCard()).enabled(!this.uploading)
              .onChange((value: string) => this.nameText = value)
            TextArea({ text: this.description, placeholder: '声音介绍' }).width('100%').height(120)
              .fontColor(TC.textBody()).backgroundColor(TC.surfaceCard()).enabled(!this.uploading)
              .onChange((value: string) => this.description = value)
            Row() {
              Text('仅自己可见').layoutWeight(1).fontSize(14).fontColor(TC.textPrimary())
              Toggle({ type: ToggleType.Switch, isOn: this.privacy }).enabled(!this.uploading)
                .onChange((value: boolean) => { this.privacy = value; if (value) { this.autoPublish = false } })
            }.width('100%')
            if (this.lists.find((list: VoiceList) => String(list.voiceListId) === this.selectedId)?.privacy) {
              Text('私密播客内的声音始终仅自己可见').fontSize(11).fontColor(TC.textTertiary())
            }
            Row() {
              Text('定时发布').layoutWeight(1).fontSize(14).fontColor(TC.textPrimary())
              Toggle({ type: ToggleType.Switch, isOn: this.scheduled }).enabled(!this.uploading).onChange((value: boolean) => this.scheduled = value)
            }.width('100%')
            if (this.scheduled) {
              TextInput({ text: this.publishAt, placeholder: 'YYYY-MM-DD HH:mm（本地时间）' }).fontColor(TC.textBody())
                .backgroundColor(TC.surfaceCard()).enabled(!this.uploading).onChange((value: string) => this.publishAt = value)
            }
            if (!this.privacy && !this.lists.find((list: VoiceList) => String(list.voiceListId) === this.selectedId)?.privacy) {
              Row() {
                Text('同步发布动态').layoutWeight(1).fontSize(14).fontColor(TC.textPrimary())
                Toggle({ type: ToggleType.Switch, isOn: this.autoPublish }).enabled(!this.uploading).onChange((value: boolean) => this.autoPublish = value)
              }.width('100%')
              if (this.autoPublish) {
                TextInput({ text: this.dynamicText, placeholder: '动态文案（可选）' }).fontColor(TC.textBody())
                  .backgroundColor(TC.surfaceCard()).enabled(!this.uploading).onChange((value: string) => this.dynamicText = value)
              }
            }
            Text(this.scheduled ? '到设定时间后发布，审核状态可在我的播客查看。' : '默认立即提交发布；上传完成后，审核中的声音可在我的播客查看。')
              .fontSize(11).lineHeight(18).fontColor(TC.textTertiary())
            if (this.message) {
              Text(this.message).fontSize(12).fontColor(TC.accentSoft()).width('100%')
              if (!this.lists.length) {
                Button('创建播客（创作者中心）').enabled(!this.uploading).onClick(() => this.create())
                Button('重新加载').enabled(!this.loading).onClick(() => this.load())
              }
            }
            Button(this.uploading ? '正在上传…' : '发布声音').width('100%').height(46)
              .enabled(!this.uploading && !this.picking && !this.loading && this.lists.length > 0)
              .backgroundColor(TC.accent()).fontColor(TC.textOnAccent()).onClick(() => this.submit())
          }.width('100%').padding(16)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true).onBackPressed(() => this.uploading)
  }
}
