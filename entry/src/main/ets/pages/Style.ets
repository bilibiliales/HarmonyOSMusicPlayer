import {
  StyleDetailPageParam,
  StyleListResponse,
  StylePreferenceResponse,
  StyleTag,
  StyleTagPreference
} from '../models'
import { ApiClient } from '../services/ApiClient'
import { resizeImageUrl } from '../services/ImageUrl'

interface StyleTagRow {
  key: string
  tags: StyleTag[]
}

class StyleTagRowDataSource implements IDataSource {
  private rows: StyleTagRow[] = []
  private listeners: DataChangeListener[] = []

  public totalCount(): number {
    return this.rows.length
  }

  public getData(index: number): StyleTagRow {
    return this.rows[index]
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) {
      this.listeners.splice(index, 1)
    }
  }

  public reset(tags: StyleTag[]): void {
    const rows: StyleTagRow[] = []
    for (let index = 0; index < tags.length; index += 2) {
      const rowTags = tags.slice(index, Math.min(index + 2, tags.length))
      rows.push({
        key: rowTags.map((tag: StyleTag) => tag.tagId.toString()).join('-'),
        tags: rowTags
      })
    }
    this.rows = rows
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded())
  }
}

@Component
export struct StylePage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  embedded: boolean = false
  @State preferences: StyleTagPreference[] = []
  @State tags: StyleTag[] = []
  @State allTags: StyleTag[] = []
  @State loading: boolean = true
  @State refreshing: boolean = false
  @State message: string = ''
  private tagRows: StyleTagRowDataSource = new StyleTagRowDataSource()

  aboutToAppear(): void {
    this.loadData()
  }

  private async loadData(): Promise<void> {
    this.message = ''
    try {
      const response = await ApiClient.get<StylePreferenceResponse>('/style/preference')
      if (response.code === 200 && response.data) {
        this.preferences = response.data.tagPreferenceVos || []
      }
    } catch (error) {
      this.preferences = []
    }
    try {
      const listResponse = await ApiClient.get<StyleListResponse>('/style/list')
      if (listResponse.code === 200) {
        this.tags = listResponse.data || []
        this.allTags = this.flattenTags(this.tags)
        this.tagRows.reset(this.allTags)
      }
      if (this.allTags.length === 0) {
        this.message = '暂时没有可展示的曲风'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '曲风加载失败'
    } finally {
      this.loading = false
    }
  }

  private flattenTags(tags: StyleTag[] | null | undefined): StyleTag[] {
    const result: StyleTag[] = []
    if (!tags) {
      return result
    }
    tags.forEach((tag: StyleTag) => {
      result.push(tag)
      const children = this.flattenTags(tag.childrenTags)
      children.forEach((child: StyleTag) => result.push(child))
    })
    return result
  }

  private findTag(tagId: number, tags: StyleTag[] | null | undefined = this.tags): StyleTag | undefined {
    if (!tags) {
      return undefined
    }
    for (let index = 0; index < tags.length; index++) {
      const tag = tags[index]
      if (tag.tagId === tagId) {
        return tag
      }
      const child = this.findTag(tagId, tag.childrenTags)
      if (child) {
        return child
      }
    }
    return undefined
  }

  private tagDescription(tag: StyleTag): string {
    const levelText = tag.level === 1 ? '一级曲风' : tag.level === 2 ? '二级曲风' : tag.level === 3 ? '三级曲风' : '曲风'
    const childCount = tag.childrenTags?.length || 0
    return childCount > 0 ? `${levelText} · ${childCount} 个子曲风` : levelText
  }

  private openStyle(tag: StyleTag): void {
    const param: StyleDetailPageParam = {
      tagId: tag.tagId,
      name: tag.tagName,
      cover: tag.picUrl || '',
      colorDeep: tag.colorDeep || '',
      colorShallow: tag.colorShallow || ''
    }
    this.pageStack.pushPathByName('StyleDetailPage', param)
  }

  private openPreference(item: StyleTagPreference): void {
    const tag = this.findTag(item.tagId)
    const param: StyleDetailPageParam = {
      tagId: item.tagId,
      name: item.tagName,
      cover: item.picUrl,
      colorDeep: tag?.colorDeep || '',
      colorShallow: tag?.colorShallow || ''
    }
    this.pageStack.pushPathByName('StyleDetailPage', param)
  }

  @Builder
  private PageHeader() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
        .onClick(() => this.pageStack.pop())
      Column({ space: 3 }) {
        Text('曲风').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text('从偏好出发探索音乐类型').fontSize(11).fontColor('#6f6f77')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Stack() {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(19).fontColor(['#ddddE2'])
      }.width(42).height(42).borderRadius(14).backgroundColor('#1e1e24')
        .onClick(() => this.pageStack.pushPathByName('SearchPage', null))
    }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 5 })
  }

  @Builder
  private DiscoveryTabs() {
    Scroll() {
      Row({ space: 6 }) {
      Text('发现').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor('#1d1d22').borderRadius(18).onClick(() => this.pageStack.pop())
      Text('排行榜').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('RankingPage', null))
      Text('曲风').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#ef233c').borderRadius(18)
      Text('电台').fontSize(13).fontColor('#85858e').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('RadioPage', null))
      Text('数字专辑').fontSize(13).fontColor('#85858e')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('DigitalAlbumPage', null))
      Text('助眠解压').fontSize(13).fontColor('#85858e')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 }).backgroundColor('#1d1d22').borderRadius(18)
        .onClick(() => this.pageStack.replacePathByName('SatiPage', null))
      }.padding({ left: 16, right: 16 })
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .margin({ top: 10, bottom: 4 })
  }

  @Builder
  private PreferenceSection() {
    if (this.preferences.length > 0) {
      Row() {
        Text('我的曲风偏好').layoutWeight(1).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text('近 30 天').fontSize(10).fontColor('#707078')
      }.width('100%').padding({ left: 16, right: 16, top: 22, bottom: 11 })
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.preferences, (item: StyleTagPreference) => {
            Stack({ alignContent: Alignment.BottomStart }) {
              Image(item.picUrl).width(142).height(172)
                .borderRadius(17).objectFit(ImageFit.Cover)
                .backgroundColor('#202026')
              Column().width(142).height(92).borderRadius({ bottomLeft: 17, bottomRight: 17 })
                .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.88)', 1]] })
              Column({ space: 3 }) {
                Text(item.tagName).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                Text(`偏好 ${item.ratio}%`).fontSize(10).fontColor('#e2e2e6')
              }.margin({ left: 11, bottom: 11 }).alignItems(HorizontalAlign.Start)
            }.width(142).height(172).onClick(() => this.openPreference(item))
          }, (item: StyleTagPreference) => item.tagId.toString())
        }.padding({ left: 16, right: 16 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }
  }

  @Builder
  private AllStylesHeader() {
    Row() {
      Text('全部曲风').layoutWeight(1).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#ffffff')
      Text(`${this.allTags.length} 个`).fontSize(10).fontColor('#707078')
    }.width('100%').padding({ left: 16, right: 16, top: 24, bottom: 12 })
  }

  @Builder
  private StyleCard(tag: StyleTag) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(tag.picUrl).width('100%').height(112)
          .borderRadius(15).objectFit(ImageFit.Cover)
          .backgroundColor('#202026')
        Column().width('100%').height(62).borderRadius({ bottomLeft: 15, bottomRight: 15 })
          .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.82)', 1]] })
        Column({ space: 2 }) {
          Text(tag.tagName).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#ffffff').maxLines(1)
          Text(tag.enName || '').fontSize(9).fontColor('#d0d0d5').maxLines(1)
        }.margin({ left: 10, right: 8, bottom: 9 }).alignItems(HorizontalAlign.Start)
      }.width('100%').height(112)
      Text(this.tagDescription(tag)).width('100%').fontSize(10).fontColor('#77777f').maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('48%').margin({ bottom: 16 }).alignItems(HorizontalAlign.Start).onClick(() => this.openStyle(tag))
  }

  @Builder
  private StyleRow(row: StyleTagRow) {
    Row() {
      ForEach(row.tags, (tag: StyleTag) => {
        this.StyleCard(tag)
      }, (tag: StyleTag) => tag.tagId.toString())
    }.width('100%').padding({ left: 16, right: 16 }).justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private PageContent(showChrome: boolean) {
    Refresh({ refreshing: this.refreshing }) {
      List() {
        if (showChrome) {
          ListItem() {
            Column() {
            Column().width('100%').height(this.topAvoidHeight)
            this.PageHeader()
            this.DiscoveryTabs()
            }.width('100%')
          }
        }
        if (this.loading) {
          ListItem() {
            Column() {
              LoadingProgress().width(42).height(42).color('#ef233c')
            }.width('100%').height(300).justifyContent(FlexAlign.Center)
          }
        } else if (this.allTags.length === 0) {
          ListItem() {
            Text(this.message || '暂无曲风').width('100%').height(300).fontSize(13).fontColor('#77777f')
              .textAlign(TextAlign.Center)
          }
        } else {
          ListItem() {
            Column() {
              this.PreferenceSection()
              this.AllStylesHeader()
            }.width('100%')
          }
          LazyForEach(this.tagRows, (row: StyleTagRow) => {
            ListItem() {
              this.StyleRow(row)
            }
          }, (row: StyleTagRow) => row.key)
          ListItem() {
            Column() {
              Blank()
            }.width('100%').height(this.embedded ? 145 : 50)
          }
        }
      }.width('100%').height('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor('#121215').onRefreshing(async () => {
      this.refreshing = true
      await this.loadData()
      this.refreshing = false
    })
  }

  build() {
    if (this.embedded) {
      this.PageContent(false)
    } else {
      NavDestination() {
        this.PageContent(true)
      }.hideTitleBar(true).backgroundColor('#121215')
    }
  }
}
