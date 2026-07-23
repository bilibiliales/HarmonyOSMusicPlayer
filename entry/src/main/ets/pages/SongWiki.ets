import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { http } from '@kit.NetworkKit'
import { systemShare } from '@kit.ShareKit'
import {
  AlbumPageParam,
  ArtistPageParam,
  MusicSheetSimpleInfo,
  SheetInstrumentType,
  SheetListResponse,
  SheetPreviewPage,
  SheetPreviewResponse,
  SongDetailResponse,
  SongWikiRawBlock,
  SongWikiResponse,
  WikiCreative,
  WikiResource,
  WikiUiElement
} from '../models/api'
import { playlistType, SongArtist, songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { PlayerStore } from '../stores/PlayerStore'

@Component
export struct SongWiki {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('playerStore') playerStore: PlayerStore
  song: songItemType = { id: '', name: '', author: '', img: '', url: '' }

  @State loading: boolean = true
  @State message: string = ''
  @State actionMessage: string = ''
  @State wikiMetaItems: WikiValueItem[] = []
  @State basicFields: WikiField[] = []
  @State relatedSections: WikiRelatedSection[] = []
  @State instrumentTypes: SheetInstrumentType[] = []
  @State musicSheets: MusicSheetSimpleInfo[] = []
  @State selectedInstrumentCode: number = 0
  @State detailSheetVisible: boolean = false
  @State detailSheetTitle: string = ''
  @State detailSheetItems: WikiValueItem[] = []
  @State scoreSheetVisible: boolean = false
  @State selectedSheet: MusicSheetSimpleInfo | null = null
  @State previewLoading: boolean = false
  @State previewPages: SheetPreviewPage[] = []
  @State previewMessage: string = ''
  @State previewActionRunning: boolean = false
  @State memoryTitle: string = ''
  @State memoryBgImage: string = ''
  @State memoryFirstListen: WikiMemoryFirstListen | null = null
  @State memoryTotalPlay: WikiMemoryTotalPlay | null = null

  aboutToAppear(): void {
    this.loadPage()
  }

  private async loadPage(): Promise<void> {
    this.loading = true
    this.message = ''
    let wikiError: string = ''
    try {
      const response = await ApiClient.get<SongWikiResponse>('/song/wiki/summary', [
        { key: 'id', value: this.song.id }
      ])
      if (response.code !== 200) {
        wikiError = response.message || '歌曲百科加载失败'
      } else {
        this.mapWikiResponse(response.data?.blocks || [])
      }
    } catch (error) {
      wikiError = error instanceof Error ? error.message : '歌曲百科加载失败'
    }

    try {
      const response = await ApiClient.get<SheetListResponse>('/sheet/list', [
        { key: 'id', value: this.song.id }
      ])
      if (response.code === 200 && response.data) {
        this.instrumentTypes = response.data.sheetInstrumentTypeVOList || []
        this.musicSheets = response.data.musicSheetSimpleInfoVOS || []
      }
    } catch (_error) {
      this.instrumentTypes = []
      this.musicSheets = []
    }

    if (!this.hasPageContent()) {
      this.message = wikiError || '这首歌暂时没有可展示的百科内容'
    } else if (wikiError.length > 0) {
      this.actionMessage = wikiError
    }
    this.loading = false
  }

  private mapWikiResponse(blocks: SongWikiRawBlock[]): void {
    const fields: WikiField[] = []
    const sections: WikiRelatedSection[] = []
    const metaItems: WikiValueItem[] = []

    blocks.forEach((block: SongWikiRawBlock) => {
      if (block.code === 'SONG_PLAY_ABOUT_MUSIC_MEMORY') {
        this.parseMemoryBlock(block)
        return
      }
      if (block.code === 'SONG_PLAY_ABOUT_SONG_BASIC') {
        this.appendUiItems(block.uiElement, metaItems)
        ;(block.creatives || []).forEach((creative: WikiCreative) => {
          if (creative.creativeType === 'sheet') {
            return
          }
          const items = this.itemsFromCreative(creative)
          if (items.length === 0) {
            return
          }
          const title = creative.uiElement?.mainTitle?.title || '百科信息'
          fields.push({
            title: title,
            creativeType: creative.creativeType || '',
            items: items,
            expandable: this.isMovieField(title, creative.creativeType || '') && items.length > 1
          })
        })
        return
      }

      const sectionItems: WikiValueItem[] = []
      ;(block.creatives || []).forEach((creative: WikiCreative) => {
        const items = this.itemsFromCreative(creative)
        items.forEach((item: WikiValueItem) => sectionItems.push(item))
      })
      if (sectionItems.length > 0) {
        sections.push({
          code: block.code || '',
          showType: block.showType || '',
          title: block.title || block.uiElement?.mainTitle?.title || '相关内容',
          items: sectionItems
        })
      }
    })

    this.wikiMetaItems = metaItems
    this.basicFields = fields
    this.relatedSections = sections
  }

  private appendUiItems(ui: WikiUiElement | undefined, target: WikiValueItem[]): void {
    if (!ui) {
      return
    }
    ;(ui.subTitles || []).forEach((item) => {
      if (item.title) {
        target.push({
          title: item.title,
          subtitle: '',
          image: '',
          targetUrl: item.action?.clickAction?.targetUrl || '',
          playCount: 0,
          resourceType: '',
          resourceId: ''
        })
      }
    })
    ;(ui.descriptions || []).forEach((item) => {
      const text = item.text || item.title || ''
      if (text) {
        target.push({ title: text, subtitle: '', image: '', targetUrl: '', playCount: 0, resourceType: '', resourceId: '' })
      }
    })
    ;(ui.textLinks || []).forEach((item) => {
      if (item.text) {
        target.push({ title: item.text, subtitle: '', image: '', targetUrl: item.url || '', playCount: 0,
          resourceType: '', resourceId: '' })
      }
    })
    ;(ui.labels || []).forEach((item) => {
      if (item.text) {
        target.push({ title: item.text, subtitle: '', image: '', targetUrl: '', playCount: 0,
          resourceType: '', resourceId: '' })
      }
    })
    ;(ui.buttons || []).forEach((item) => {
      if (item.text) {
        target.push({
          title: item.text,
          subtitle: '',
          image: item.imageUrl || '',
          targetUrl: item.action?.clickAction?.targetUrl || '',
          playCount: 0,
          resourceType: '',
          resourceId: ''
        })
      }
    })
  }

  private uiTextValues(ui: WikiUiElement | undefined): string[] {
    const values: string[] = []
    if (!ui) {
      return values
    }
    ;(ui.subTitles || []).forEach((item) => {
      if (item.title) {
        values.push(item.title)
      }
    })
    ;(ui.descriptions || []).forEach((item) => {
      const value = item.text || item.title || ''
      if (value) {
        values.push(value)
      }
    })
    ;(ui.textLinks || []).forEach((item) => {
      if (item.text) {
        values.push(item.text)
      }
    })
    ;(ui.labels || []).forEach((item) => {
      if (item.text) {
        values.push(item.text)
      }
    })
    ;(ui.buttons || []).forEach((item) => {
      if (item.text) {
        values.push(item.text)
      }
    })
    return values
  }

  private itemsFromCreative(creative: WikiCreative): WikiValueItem[] {
    const result: WikiValueItem[] = []
    const resources = creative.resources || []
    resources.forEach((resource: WikiResource) => {
      const item = this.itemFromResource(resource)
      if (item.title || item.subtitle || item.image) {
        result.push(item)
      }
    })

    if (resources.length === 0) {
      const values = this.uiTextValues(creative.uiElement)
      values.forEach((value: string) => {
        result.push({
          title: value,
          subtitle: '',
          image: creative.uiElement?.images?.[0]?.imageUrl || '',
          targetUrl: creative.action?.clickAction?.targetUrl || '',
          playCount: 0,
          resourceType: '',
          resourceId: ''
        })
      })
      if (values.length === 0 && creative.uiElement?.images?.[0]?.imageUrl) {
        result.push({
          title: creative.uiElement.images[0].title || '',
          subtitle: '',
          image: creative.uiElement.images[0].imageUrl || '',
          targetUrl: creative.action?.clickAction?.targetUrl || '',
          playCount: 0,
          resourceType: '',
          resourceId: ''
        })
      }
    }
    return result
  }

  private itemFromResource(resource: WikiResource): WikiValueItem {
    const ui = resource.uiElement
    const values = this.uiTextValues(ui)
    const title = ui?.mainTitle?.title || values[0] || resource.resourceType || ''
    const subtitles: string[] = []
    values.forEach((value: string) => {
      if (value !== title) {
        subtitles.push(value)
      }
    })
    return {
      title: title,
      subtitle: subtitles.join(' · '),
      image: ui?.images?.[0]?.imageUrl || ui?.images?.[0]?.imageWithoutTextUrl || '',
      targetUrl: resource.action?.clickAction?.targetUrl || ui?.mainTitle?.action?.clickAction?.targetUrl || '',
      playCount: resource.resourceExt?.playCount || 0,
      resourceType: resource.resourceType || '',
      resourceId: resource.resourceId || ''
    }
  }

  private isMovieField(title: string, creativeType: string): boolean {
    const type = creativeType.toLowerCase()
    return title.indexOf('影综') >= 0 || title.indexOf('影视') >= 0 || title.indexOf('电影') >= 0 ||
      title.indexOf('综艺') >= 0 || type.indexOf('movie') >= 0 || type.indexOf('film') >= 0 ||
      type.indexOf('tv') >= 0
  }

  private parseMemoryBlock(block: SongWikiRawBlock): void {
    this.memoryTitle = block.uiElement?.mainTitle?.title || '回忆坐标'
    this.memoryBgImage = block.uiElement?.images?.[0]?.imageUrl || ''
    this.memoryFirstListen = null
    this.memoryTotalPlay = null
    ;(block.creatives || []).forEach((creative: WikiCreative) => {
      if (creative.creativeType !== 'memoryGrid') {
        return
      }
      ;(creative.resources || []).forEach((resource: WikiResource) => {
        const resType = resource.resourceType || ''
        if (resType === 'FIRST_LISTEN') {
          const dto = resource.resourceExt?.musicFirstListenDto
          if (dto) {
            this.memoryFirstListen = {
              title: resource.uiElement?.mainTitle?.title || '第一次听',
              date: dto.date || '',
              season: dto.season || '',
              period: dto.period || ''
            }
          }
        } else if (resType === 'TOTAL_PLAY') {
          const dto = resource.resourceExt?.musicTotalPlayDto
          if (dto) {
            this.memoryTotalPlay = {
              title: resource.uiElement?.mainTitle?.title || '累计播放',
              playCount: dto.playCount || 0,
              text: dto.text || ''
            }
          }
        }
      })
    })
  }

  private hasPageContent(): boolean {
    return this.wikiMetaItems.length > 0 || this.basicFields.length > 0 || this.relatedSections.length > 0 ||
      this.musicSheets.length > 0 || this.memoryFirstListen !== null || this.memoryTotalPlay !== null
  }

  private showDetailSheet(field: WikiField): void {
    this.detailSheetTitle = field.title
    this.detailSheetItems = field.items
    this.detailSheetVisible = true
  }

  private notifyOrpheus(item: WikiValueItem): void {
    if (item.targetUrl.startsWith('orpheus://')) {
      this.actionMessage = '该内容来自网易云音乐客户端内页，本应用仅展示信息'
    }
  }

  private async openWikiItem(item: WikiValueItem): Promise<void> {
    const resourceType = item.resourceType.toUpperCase()
    if (resourceType === 'SONG' && item.resourceId) {
      const similarSong: songItemType = {
        id: item.resourceId,
        name: item.title,
        author: item.subtitle.split(' · ')[0] || '未知歌手',
        img: item.image,
        url: ''
      }
      const queue = this.playerStore.queue.map((song: songItemType) => song)
      let index = queue.findIndex((song: songItemType) => song.id === similarSong.id)
      if (index < 0) {
        queue.push(similarSong)
        index = queue.length - 1
      }
      await playerController.setQueue(queue, index, true)
      this.pageStack.pushPathByName('PlayPage', null)
      return
    }
    if (resourceType === 'PLAYLIST' && item.resourceId) {
      const playlist: playlistType = {
        id: item.resourceId,
        name: item.title,
        cover: item.image,
        count: 0,
        creator: item.subtitle
      }
      this.pageStack.pushPathByName('PlaylistDetailPage', playlist)
      return
    }
    if (resourceType === 'ARTIST' && item.resourceId) {
      const param: ArtistPageParam = { id: item.resourceId, name: item.title, picUrl: item.image }
      this.pageStack.pushPathByName('ArtistPage', param)
      return
    }
    this.notifyOrpheus(item)
  }

  private openSongArtist(artist: SongArtist): void {
    if (!artist.id || artist.id === '0') {
      return
    }
    const param: ArtistPageParam = { id: artist.id, name: artist.name, picUrl: artist.picUrl || '' }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  @Builder
  private SongArtistLinks() {
    Row({ space: 4 }) {
      if (this.song.artists && this.song.artists.length > 0) {
        ForEach(this.song.artists, (artist: SongArtist, index: number) => {
          Text(artist.name).fontSize(13).fontColor('#b4b4bd').maxLines(1)
            .onClick(() => this.openSongArtist(artist))
          if (index < (this.song.artists || []).length - 1) {
            Text('/').fontSize(13).fontColor('#66666e')
          }
        })
      } else {
        Text(this.song.author).fontSize(13).fontColor('#92929a')
      }
    }
    .width('100%')
  }

  private filteredSheets(): MusicSheetSimpleInfo[] {
    if (this.selectedInstrumentCode === 0) {
      return this.musicSheets
    }
    const result: MusicSheetSimpleInfo[] = []
    this.musicSheets.forEach((sheet: MusicSheetSimpleInfo) => {
      let matched = false
      sheet.type.forEach((type: SheetInstrumentType) => {
        if (type.code === this.selectedInstrumentCode) {
          matched = true
        }
      })
      if (matched) {
        result.push(sheet)
      }
    })
    return result
  }

  private sheetMeta(sheet: MusicSheetSimpleInfo): string {
    const values: string[] = []
    if (sheet.type.length > 0 && sheet.type[0].name) {
      values.push(sheet.type[0].name)
    }
    if (sheet.playVersion) {
      values.push(sheet.playVersion)
    }
    if (sheet.difficulty) {
      values.push(`难度 ${sheet.difficulty}`)
    }
    if (sheet.musicKey) {
      values.push(`${sheet.musicKey} 调`)
    }
    if (sheet.bpm > 0) {
      values.push(`${sheet.bpm} BPM`)
    }
    values.push(`${sheet.totalPageSize} 页`)
    return values.join(' · ')
  }

  private async openSheetPreview(sheet: MusicSheetSimpleInfo): Promise<void> {
    this.selectedSheet = sheet
    this.previewPages = []
    this.previewMessage = ''
    this.previewLoading = true
    this.scoreSheetVisible = true
    try {
      const response = await ApiClient.get<SheetPreviewResponse>('/sheet/preview', [
        { key: 'id', value: sheet.id.toString() }
      ])
      if (response.code === 200) {
        this.previewPages = (response.data || []).sort((left: SheetPreviewPage, right: SheetPreviewPage) =>
          left.pageNumber - right.pageNumber)
        if (this.previewPages.length === 0) {
          this.previewMessage = '这份乐谱暂时没有可预览的页面'
        }
      } else {
        this.previewMessage = response.message || '乐谱预览加载失败'
      }
    } catch (error) {
      this.previewMessage = error instanceof Error ? error.message : '乐谱预览加载失败'
    } finally {
      this.previewLoading = false
    }
  }

  private safeFileName(value: string): string {
    return value.replace(/[\\/:*?"<>|]/g, '_')
  }

  private async cachePreviewPage(page: SheetPreviewPage): Promise<string> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cacheDir = `${context.cacheDir}/sheet_preview`
    try {
      fileIo.mkdirSync(cacheDir, true)
    } catch (_error) {
      // Directory already exists.
    }
    const sheetName = this.selectedSheet ? this.selectedSheet.name : 'music-sheet'
    const filePath = `${cacheDir}/${this.safeFileName(this.song.name)}-${this.safeFileName(sheetName)}-${page.pageNumber}.jpg`
    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(page.url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 30000,
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
      httpRequest.destroy()
    }
  }

  private async shareScore(): Promise<void> {
    if (!this.selectedSheet || this.previewPages.length === 0 || this.previewActionRunning) {
      return
    }
    this.previewActionRunning = true
    this.previewMessage = '正在准备全部乐谱页…'
    try {
      const records: systemShare.SharedRecord[] = []
      for (let index = 0; index < this.previewPages.length; index++) {
        this.previewMessage = `正在准备分享第 ${index + 1}/${this.previewPages.length} 页…`
        const uri = await this.cachePreviewPage(this.previewPages[index])
        records.push({
          utd: 'general.jpeg',
          uri: uri,
          title: `${this.song.name} - ${this.selectedSheet.name} - 第 ${index + 1} 页`,
          description: `${this.sheetMeta(this.selectedSheet)}，共 ${this.previewPages.length} 页`
        })
      }
      const data = new systemShare.SharedData(records[0])
      for (let index = 1; index < records.length; index++) {
        data.addRecord(records[index])
      }
      const controller = new systemShare.ShareController(data)
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await controller.show(context, {})
      this.previewMessage = ''
    } catch (error) {
      this.previewMessage = error instanceof Error ? error.message : '分享乐谱失败'
    } finally {
      this.previewActionRunning = false
    }
  }

  private async saveScoreToGallery(): Promise<void> {
    if (!this.selectedSheet || this.previewPages.length === 0 || this.previewActionRunning) {
      return
    }
    this.previewActionRunning = true
    this.previewMessage = '正在下载全部乐谱页…'
    try {
      const uris: string[] = []
      const configs: photoAccessHelper.PhotoCreationConfig[] = []
      for (let index = 0; index < this.previewPages.length; index++) {
        this.previewMessage = `正在准备第 ${index + 1}/${this.previewPages.length} 页…`
        const uri = await this.cachePreviewPage(this.previewPages[index])
        uris.push(uri)
        configs.push({
          title: `${this.song.name}-${this.selectedSheet.name}-${index + 1}`,
          fileNameExtension: 'jpg',
          photoType: photoAccessHelper.PhotoType.IMAGE
        })
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      try {
        const savedUris = await helper.showAssetsCreationDialog(uris, configs)
        this.previewMessage = savedUris.length > 0 ? `已保存 ${savedUris.length} 页到图库` : '已取消保存'
      } finally {
        await helper.release()
      }
    } catch (error) {
      this.previewMessage = error instanceof Error ? error.message : '保存到图库失败'
    } finally {
      this.previewActionRunning = false
    }
  }

  private formatCount(value: number): string {
    if (value >= 100000000) {
      return `${(value / 100000000).toFixed(1)} 亿播放`
    }
    if (value >= 10000) {
      return `${(value / 10000).toFixed(1)} 万播放`
    }
    return value > 0 ? `${value} 次播放` : ''
  }

  @Builder
  private SectionTitle(title: string, subtitle: string = '') {
    Row() {
      Text(title)
        .layoutWeight(1)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#f4f4f6')
      if (subtitle) {
        Text(subtitle).fontSize(11).fontColor('#686870')
      }
    }
    .width('100%')
  }

  @Builder
  private WikiItemRow(item: WikiValueItem, showCover: boolean = true) {
    Row({ space: 12 }) {
      if (showCover && item.image) {
        Image(item.image)
          .width(58)
          .height(58)
          .borderRadius(11)
          .objectFit(ImageFit.Cover)
      }
      Column({ space: 5 }) {
        if (item.title) {
          Text(item.title)
            .width('100%')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#e8e8eb')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (item.subtitle) {
          Text(item.subtitle)
            .width('100%')
            .fontSize(11)
            .fontColor('#8c8c94')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (item.playCount > 0) {
          Text(this.formatCount(item.playCount)).fontSize(10).fontColor('#686870')
        }
        if (item.targetUrl.startsWith('orpheus://')) {
          Text('网易云音乐客户端内容')
            .fontSize(9)
            .fontColor('#7f6a70')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .onClick(() => this.openWikiItem(item))
  }

  @Builder
  private BasicFieldCard(field: WikiField) {
    Column({ space: 10 }) {
      Row() {
        Text(field.title)
          .width(76)
          .fontSize(13)
          .fontColor('#85858e')
        if (field.expandable) {
          Column() {
            this.WikiItemRow(field.items[0], true)
          }
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor(['#77777f'])
        } else {
          Text(field.items.map((item: WikiValueItem) => item.title || item.subtitle).join(' / '))
            .layoutWeight(1)
            .fontSize(13)
            .lineHeight(20)
            .fontColor('#eeeeF1')
            .textAlign(TextAlign.End)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (field.expandable) {
          this.showDetailSheet(field)
        } else if (field.items.length > 0) {
          this.openWikiItem(field.items[0])
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 14, top: 13, bottom: 13 })
    .backgroundColor('#1b1b20')
    .borderRadius(14)
  }

  @Builder
  private ScoreCard(sheet: MusicSheetSimpleInfo) {
    Row({ space: 13 }) {
      Image(sheet.coverImageUrl)
        .width(76)
        .height(100)
        .borderRadius(10)
        .objectFit(ImageFit.Cover)
        .backgroundColor('#292930')
      Column({ space: 7 }) {
        Row({ space: 7 }) {
          if (sheet.type.length > 0 && sheet.type[0].icon) {
            Image(sheet.type[0].icon).width(18).height(18).objectFit(ImageFit.Cover)
          }
          Text(sheet.name)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#f3f3f5')
        }
        Text(this.sheetMeta(sheet))
          .width('100%')
          .fontSize(11)
          .lineHeight(18)
          .fontColor('#92929a')
          .maxLines(3)
        Row({ space: 5 }) {
          Text('查看完整乐谱').fontSize(11).fontColor('#ff7587')
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11).fontColor(['#ff7587'])
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(13)
    .backgroundColor('#1b1b20')
    .borderRadius(16)
    .onClick(() => this.openSheetPreview(sheet))
  }

  @Builder
  private MemoryCoordinateCard() {
    Column() {
      // 顶部背景图 + 歌曲名
      Stack({ alignContent: Alignment.BottomStart }) {
        if (this.memoryBgImage) {
          Image(this.memoryBgImage)
            .width('100%')
            .height(180)
            .objectFit(ImageFit.Cover)
            .borderRadius({ topLeft: 16, topRight: 16 })
          // 渐变遮罩让文字更清晰
          Column()
            .width('100%')
            .height(180)
            .borderRadius({ topLeft: 16, topRight: 16 })
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [['#00000000', 0.3], ['#cc000000', 1.0]]
            })
        } else {
          Column()
            .width('100%')
            .height(120)
            .backgroundColor('#1f1f26')
            .borderRadius({ topLeft: 16, topRight: 16 })
        }
        Column({ space: 4 }) {
          Text(this.memoryTitle)
            .fontSize(12)
            .fontColor('#b8b8c0')
          Text(this.song.name)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 16 })
      }
      .width('100%')

      // 回忆内容区域
      Column({ space: 16 }) {
        if (this.memoryFirstListen) {
          Column({ space: 6 }) {
            Text(this.memoryFirstListen.title)
              .fontSize(12)
              .fontColor('#8c8c94')
            Row({ space: 6 }) {
              Text(this.memoryFirstListen.date)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#e8e8eb')
              if (this.memoryFirstListen.season && this.memoryFirstListen.period) {
                Text(`${this.memoryFirstListen.season} ${this.memoryFirstListen.period}`)
                  .fontSize(12)
                  .fontColor('#6d6d75')
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        if (this.memoryFirstListen && this.memoryTotalPlay) {
          Divider().color('#2a2a32')
        }

        if (this.memoryTotalPlay) {
          Column({ space: 6 }) {
            Text(this.memoryTotalPlay.title)
              .fontSize(12)
              .fontColor('#8c8c94')
            if (this.memoryTotalPlay.playCount > 0) {
              Text(`${this.memoryTotalPlay.playCount}`)
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffffff')
            }
            if (this.memoryTotalPlay.text) {
              Text(this.memoryTotalPlay.text)
                .fontSize(13)
                .fontColor('#aaaab2')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16, bottom: 20 })
    }
    .width('100%')
    .backgroundColor('#1b1b20')
    .borderRadius(16)
    .clip(true)
  }

  @Builder
  private SimilarSongSection(section: WikiRelatedSection) {
    Column({ space: 0 }) {
      ForEach(section.items, (item: WikiValueItem, index: number) => {
        Column() {
          this.WikiItemRow(item, true)
        }
        .padding({ left: 13, right: 13, top: 10, bottom: 10 })
        if (index < section.items.length - 1) {
          Divider().color('#292930').margin({ left: 83 })
        }
      })
    }
    .width('100%')
    .backgroundColor('#1b1b20')
    .borderRadius(16)
  }

  @Builder
  private PlaylistSection(section: WikiRelatedSection) {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(section.items, (item: WikiValueItem) => {
          Column({ space: 8 }) {
            Image(item.image)
              .width(132)
              .height(132)
              .borderRadius(15)
              .objectFit(ImageFit.Cover)
              .backgroundColor('#25252b')
            Text(item.title)
              .width(132)
              .fontSize(12)
              .fontColor('#dedee2')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (item.playCount > 0) {
              Text(this.formatCount(item.playCount)).width(132).fontSize(9).fontColor('#686870')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .onClick(() => this.openWikiItem(item))
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private GenericRelatedSection(section: WikiRelatedSection) {
    Column({ space: 10 }) {
      ForEach(section.items, (item: WikiValueItem) => {
        Column() {
          this.WikiItemRow(item, true)
        }
        .padding(13)
        .backgroundColor('#1b1b20')
        .borderRadius(14)
      })
    }
    .width('100%')
  }

  @Builder
  private DetailSheetContent() {
    Column({ space: 14 }) {
      Row() {
        Text(this.detailSheetTitle)
          .layoutWeight(1)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
        Text(`${this.detailSheetItems.length} 项`).fontSize(11).fontColor('#77777f')
      }
      .width('100%')
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.detailSheetItems, (item: WikiValueItem) => {
            Column() {
              this.WikiItemRow(item, true)
            }
            .padding(13)
            .backgroundColor('#222228')
            .borderRadius(14)
          })
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18, top: 20, bottom: 16 })
  }

  @Builder
  private ScorePreviewContent() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text(this.selectedSheet ? this.selectedSheet.name : '乐谱预览')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
          if (this.selectedSheet) {
            Text(this.sheetMeta(this.selectedSheet)).fontSize(10).fontColor('#7f7f87').maxLines(1)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(25)
          .fontColor(['#6d6d75'])
          .onClick(() => this.scoreSheetVisible = false)
      }
      .width('100%')

      Row({ space: 10 }) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.share')).fontSize(16).fontColor(['#ffffff'])
            Text('分享').fontSize(13).fontColor('#ffffff')
          }
        }
        .layoutWeight(1)
        .height(42)
        .backgroundColor('#303037')
        .enabled(!this.previewActionRunning && this.previewPages.length > 0)
        .onClick(() => this.shareScore())

        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(16).fontColor(['#ffffff'])
            Text('保存到图库').fontSize(13).fontColor('#ffffff')
          }
        }
        .layoutWeight(1)
        .height(42)
        .backgroundColor('#ef233c')
        .enabled(!this.previewActionRunning && this.previewPages.length > 0)
        .onClick(() => this.saveScoreToGallery())
      }
      .width('100%')

      if (this.previewMessage) {
        Text(this.previewMessage)
          .width('100%')
          .fontSize(11)
          .fontColor(this.previewMessage.indexOf('已保存') >= 0 ? '#66c98b' : '#ff8292')
          .textAlign(TextAlign.Center)
      }

      if (this.previewLoading) {
        Column({ space: 12 }) {
          LoadingProgress().width(42).color('#ef233c')
          Text('正在加载完整乐谱…').fontSize(12).fontColor('#77777f')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.previewPages, (page: SheetPreviewPage) => {
              Column({ space: 7 }) {
                Text(`第 ${page.pageNumber} 页`)
                  .width('100%')
                  .fontSize(10)
                  .fontColor('#77777f')
                  .textAlign(TextAlign.Center)
                Image(page.url)
                  .width('100%')
                  .aspectRatio(0.72)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor('#ffffff')
                  .borderRadius(10)
              }
            })
          }
          .padding({ bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 18 })
  }

  private async openSongAlbum(): Promise<void> {
    if (!this.song.id || !this.song.album) {
      return
    }
    let albumId = this.song.albumId || ''
    if (!albumId) {
      try {
        const response = await ApiClient.get<SongDetailResponse>('/song/detail', [
          { key: 'ids', value: this.song.id }
        ])
        if (response.songs && response.songs.length > 0) {
          albumId = response.songs[0].al?.id?.toString() || response.songs[0].album?.id?.toString() || ''
          this.song.albumId = albumId
        }
      } catch (_error) {
      }
    }
    if (!albumId) {
      this.actionMessage = '暂时无法获取专辑信息'
      return
    }
    const param: AlbumPageParam = {
      id: albumId,
      name: this.song.album,
      picUrl: this.song.img,
      artist: this.song.author
    }
    this.pageStack.pushPathByName('AlbumDetailPage', param)
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('歌曲百科')
            .layoutWeight(1)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .textAlign(TextAlign.Center)
          Column().width(24)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })

        if (this.loading) {
          LoadingProgress().layoutWeight(1).width(46).color('#ef233c')
        } else if (this.message) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(46)
              .fontColor(['#55555d'])
            Text(this.message).fontSize(13).fontColor('#77777f')
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 20 }) {
              Row({ space: 14 }) {
                Image(this.song.img)
                  .width(86)
                  .height(86)
                  .borderRadius(17)
                  .objectFit(ImageFit.Cover)
                Column({ space: 7 }) {
                  Text(this.song.name)
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#ffffff')
                    .maxLines(2)
                  this.SongArtistLinks()
                  if (this.song.album) {
                    Text(this.song.album).fontSize(11).fontColor('#ff7d8e')
                      .onClick(() => this.openSongAlbum())
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')

              /*
              if (this.wikiMetaItems.length > 0) {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(this.wikiMetaItems, (item: WikiValueItem) => {
                      Text(item.title)
                        .fontSize(11)
                        .fontColor(item.targetUrl ? '#ff7d8e' : '#aaaab2')
                        .padding({ left: 11, right: 11, top: 7, bottom: 7 })
                        .backgroundColor('#202026')
                        .borderRadius(14)
                        .onClick(() => this.openWikiItem(item))
                    })
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
              }
              */

              if (this.memoryFirstListen !== null || this.memoryTotalPlay !== null) {
                Column({ space: 0 }) {
                  this.SectionTitle('回忆坐标')
                  Column().width('100%').height(12)
                  this.MemoryCoordinateCard()
                }
                .width('100%')
              }

              if (this.basicFields.length > 0) {
                Column({ space: 11 }) {
                  this.SectionTitle('音乐百科', '仅展示非空信息')
                  ForEach(this.basicFields, (field: WikiField) => {
                    this.BasicFieldCard(field)
                  })
                }
                .width('100%')
              }

              if (this.musicSheets.length > 0) {
                Column({ space: 12 }) {
                  this.SectionTitle('乐谱', `${this.musicSheets.length} 份`)
                  Scroll() {
                    Row({ space: 8 }) {
                      Text('全部')
                        .fontSize(11)
                        .fontColor(this.selectedInstrumentCode === 0 ? '#ffffff' : '#9a9aa2')
                        .padding({ left: 13, right: 13, top: 8, bottom: 8 })
                        .backgroundColor(this.selectedInstrumentCode === 0 ? '#ef233c' : '#24242a')
                        .borderRadius(16)
                        .onClick(() => this.selectedInstrumentCode = 0)
                      ForEach(this.instrumentTypes, (item: SheetInstrumentType) => {
                        Row({ space: 6 }) {
                          Image(item.icon).width(16).height(16).objectFit(ImageFit.Cover)
                          Text(item.name)
                            .fontSize(11)
                            .fontColor(this.selectedInstrumentCode === item.code ? '#ffffff' : '#9a9aa2')
                        }
                        .padding({ left: 11, right: 12, top: 7, bottom: 7 })
                        .backgroundColor(this.selectedInstrumentCode === item.code ? '#ef233c' : '#24242a')
                        .borderRadius(16)
                        .onClick(() => this.selectedInstrumentCode = item.code)
                      })
                    }
                  }
                  .scrollable(ScrollDirection.Horizontal)
                  .scrollBar(BarState.Off)
                  .width('100%')

                  ForEach(this.filteredSheets(), (sheet: MusicSheetSimpleInfo) => {
                    this.ScoreCard(sheet)
                  })
                }
                .width('100%')
              }

              ForEach(this.relatedSections, (section: WikiRelatedSection) => {
                Column({ space: 12 }) {
                  this.SectionTitle(section.title, `${section.items.length} 项`)
                  if (section.code.indexOf('SIMILAR_SONG') >= 0 || section.showType === 'LIST_SONG') {
                    this.SimilarSongSection(section)
                  } else if (section.code.indexOf('PLAYLIST') >= 0 || section.showType.indexOf('PLAYLIST') >= 0) {
                    this.PlaylistSection(section)
                  } else {
                    this.GenericRelatedSection(section)
                  }
                }
                .width('100%')
              })

              if (this.actionMessage) {
                Text(this.actionMessage)
                  .width('100%')
                  .fontSize(11)
                  .lineHeight(18)
                  .fontColor('#a97d84')
                  .textAlign(TextAlign.Center)
                  .padding(12)
                  .backgroundColor('#201a1e')
                  .borderRadius(12)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 30 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#121215')
      .bindSheet(this.detailSheetVisible, this.DetailSheetContent(), {
        height: '50%',
        backgroundColor: '#19191f',
        showClose: false,
        dragBar: true,
        onDisappear: () => this.detailSheetVisible = false
      })
      .bindSheet(this.scoreSheetVisible, this.ScorePreviewContent(), {
        height: '94%',
        backgroundColor: '#151519',
        showClose: false,
        dragBar: false,
        onDisappear: () => this.scoreSheetVisible = false
      })
    }
    .hideTitleBar(true)
  }
}

interface WikiValueItem {
  title: string
  subtitle: string
  image: string
  targetUrl: string
  playCount: number
  resourceType: string
  resourceId: string
}

interface WikiField {
  title: string
  creativeType: string
  items: WikiValueItem[]
  expandable: boolean
}

interface WikiMemoryFirstListen {
  title: string
  date: string
  season: string
  period: string
}

interface WikiMemoryTotalPlay {
  title: string
  playCount: number
  text: string
}

interface WikiRelatedSection {
  code: string
  showType: string
  title: string
  items: WikiValueItem[]
}
