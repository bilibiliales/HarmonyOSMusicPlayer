import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { SkinBackdrop } from '../components/SkinBackdrop'
import { LyricMarkDraft, LyricMarkPickParam, LyricMarkVO } from '../models/lyricmark'
import { songItemType } from '../models/music'
import { LyricMarkService } from '../services/LyricMarkService'
import { SongMetadataCache } from '../services/SongMetadataCache'
import { ShareText, SystemShareService } from '../services/SystemShareService'
import { BubbleTip } from '../services/BubbleTip'
import { AuthStore } from '../stores/AuthStore'
import { TC } from '../services/ThemeColors'

interface TimedLine {
  time: number
  text: string
}

interface PickLine {
  time: number
  text: string
  translation: string
  roma: string
  /** >0 表示这句已经摘录过，删除 / 修改都要带上它。 */
  markId: number
  /** 是否被选中（选中的会写进歌词本）。 */
  picked: boolean
}

/**
 * 歌词摘录：播放页长按歌词进入。
 * 布局参考铃声制作页：顶部歌曲信息、中间歌词列表、底部删除 / 复制 / 分享与摘录按钮。
 * 点击歌词行选中或取消，已摘录的句子进入时默认选中。
 */
@Component
export struct LyricMarkPickPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore

  pageParam: LyricMarkPickParam = { song: {} as songItemType }

  @State lines: PickLine[] = []
  @State loading: boolean = false
  @State message: string = ''
  @State saving: boolean = false
  @State deleting: boolean = false
  /** 是否已经拉过这支歌的摘录（登录页回来后会补拉一次）。 */
  private marksLoaded: boolean = false

  aboutToAppear(): void {
    const song = this.pageParam.song
    if (!song || !song.id) {
      this.message = '没有可用的歌曲信息'
      return
    }
    this.load()
  }

  private song(): songItemType {
    return this.pageParam.song
  }

  private async load(): Promise<void> {
    this.loading = true
    this.message = ''
    this.lines = []
    this.marksLoaded = false
    try {
      const response = await SongMetadataCache.lyrics(this.song())
      if (response.code !== 200 || response.nolyric || response.uncollected ||
        (!response.lrc?.lyric && !response.yrc?.lyric)) {
        this.message = response.uncollected ? '歌词暂未收录' : '这首歌暂无歌词'
        return
      }
      const original = this.parseTimed(SongMetadataCache.lrc(response))
      if (original.length === 0) {
        this.message = '歌词格式暂时无法解析'
        return
      }
      const translations = this.mapOf(this.parseTimed(response.tlyric?.lyric || ''))
      const romas = this.mapOf(this.parseTimed(response.romalrc?.lyric || ''))
      const merged: PickLine[] = []
      for (let i = 0; i < original.length; i++) {
        const time = original[i].time
        merged.push({
          time: time,
          text: original[i].text,
          translation: this.textOf(translations, time),
          roma: this.textOf(romas, time),
          markId: 0,
          picked: false
        })
      }
      this.lines = merged
      await this.loadMarks()
    } catch (error) {
      this.message = error instanceof Error ? error.message : '歌词加载失败'
    } finally {
      this.loading = false
    }
  }

  /** 把这支歌已有的摘录合进列表，并把它们默认选中。 */
  private async loadMarks(): Promise<void> {
    if (this.marksLoaded) {
      return
    }
    if (!this.authStore.loggedIn || !/^\d+$/.test(String(this.song().id))) {
      return
    }
    this.marksLoaded = true
    let marks: LyricMarkVO[] = []
    try {
      marks = await LyricMarkService.bySong(String(this.song().id))
    } catch (_error) {
      return
    }
    const next: PickLine[] = []
    for (let i = 0; i < this.lines.length; i++) {
      const line = this.lines[i]
      const markId = this.markIdFor(marks, line.time)
      next.push({
        time: line.time,
        text: line.text,
        translation: line.translation,
        roma: line.roma,
        markId: markId,
        picked: markId > 0
      })
    }
    this.lines = next
  }

  private markIdFor(marks: LyricMarkVO[], time: number): number {
    let best = 0
    let bestDiff = 1200
    for (let i = 0; i < marks.length; i++) {
      const details = marks[i].detailList || []
      for (let d = 0; d < details.length; d++) {
        const diff = Math.abs(details[d].startTimeStamp - time)
        if (diff <= bestDiff) {
          bestDiff = diff
          best = marks[i].markId
        }
      }
    }
    return best
  }

  private parseTime(tag: string): number {
    if (tag.length < 5) {
      return 0
    }
    const parts = tag.substring(1, tag.length - 1).split(':')
    if (parts.length !== 2) {
      return 0
    }
    const minutes = Number(parts[0])
    const seconds = Number(parts[1])
    if (!Number.isFinite(minutes) || !Number.isFinite(seconds)) {
      return 0
    }
    return Math.round(minutes * 60000 + seconds * 1000)
  }

  private parseTimed(raw: string): TimedLine[] {
    const result: TimedLine[] = []
    const rows = raw.split('\n')
    for (let i = 0; i < rows.length; i++) {
      const tags = rows[i].match(/\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]/g)
      if (!tags || tags.length === 0) {
        continue
      }
      const text = rows[i].replace(/\[[^\]]+\]/g, '').trim()
      if (text.length === 0) {
        continue
      }
      for (let t = 0; t < tags.length; t++) {
        result.push({ time: this.parseTime(tags[t]), text: text })
      }
    }
    result.sort((left: TimedLine, right: TimedLine) => left.time - right.time)
    return result
  }

  private mapOf(list: TimedLine[]): Map<number, string> {
    const map: Map<number, string> = new Map()
    for (let i = 0; i < list.length; i++) {
      if (!map.has(list[i].time)) {
        map.set(list[i].time, list[i].text)
      }
    }
    return map
  }

  private textOf(map: Map<number, string>, time: number): string {
    const value = map.get(time)
    return value === undefined ? '' : value
  }

  private stampText(ms: number): string {
    const total = Math.floor(Math.max(0, ms) / 1000)
    const minute = Math.floor(total / 60)
    const second = total % 60
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value)
    return `${pad(minute)}:${pad(second)}`
  }

  private toggle(index: number): void {
    this.lines = this.lines.map((line: PickLine, i: number) => {
      if (i !== index) {
        return line
      }
      const copy: PickLine = {
        time: line.time,
        text: line.text,
        translation: line.translation,
        roma: line.roma,
        markId: line.markId,
        picked: !line.picked
      }
      return copy
    })
  }

  private selectedCount(): number {
    let count = 0
    for (let i = 0; i < this.lines.length; i++) {
      if (this.lines[i].picked) {
        count++
      }
    }
    return count
  }

  private deletableIds(): number[] {
    const ids: number[] = []
    for (let i = 0; i < this.lines.length; i++) {
      const line = this.lines[i]
      if (line.picked && line.markId > 0) {
        ids.push(line.markId)
      }
    }
    return ids
  }

  /** 选中行拼成纯文本，供复制 / 分享。 */
  private selectedText(): string {
    const parts: string[] = []
    for (let i = 0; i < this.lines.length; i++) {
      const line = this.lines[i]
      if (!line.picked) {
        continue
      }
      let block = line.text
      if (line.translation.length > 0) {
        block = `${block}\n${line.translation}`
      }
      if (line.roma.length > 0) {
        block = `${block}\n${line.roma}`
      }
      parts.push(block)
    }
    return parts.join('\n\n')
  }

  private async copyLyrics(): Promise<void> {
    const text = this.selectedText()
    if (text.length === 0) {
      BubbleTip.show(this.getUIContext(), '请先选中要复制的歌词')
      return
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      await pasteboard.getSystemPasteboard().setData(data)
      BubbleTip.show(this.getUIContext(), `已复制 ${this.selectedCount()} 句歌词`)
    } catch (_error) {
      BubbleTip.show(this.getUIContext(), '复制失败')
    }
  }

  private async shareLyrics(): Promise<void> {
    const text = this.selectedText()
    if (text.length === 0) {
      BubbleTip.show(this.getUIContext(), '请先选中要分享的歌词')
      return
    }
    const body: ShareText = {
      content: text,
      title: `${this.song().name} - ${this.song().author}`,
      description: '歌词摘录',
      label: '歌词摘录',
      image: this.song().img
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await SystemShareService.showText(context, body)
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '分享失败')
    }
  }

  private confirmDelete(): void {
    const ids = this.deletableIds()
    if (ids.length === 0) {
      BubbleTip.show(this.getUIContext(), '选中的歌词还没有摘录')
      return
    }
    this.getUIContext().showAlertDialog({
      title: '删除摘录',
      message: `将从歌词本删除选中的 ${ids.length} 句歌词，此操作无法撤销。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: TC.accent(),
        action: () => { this.removeSelected(ids) }
      }
    })
  }

  private async removeSelected(ids: number[]): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    if (this.deleting) {
      return
    }
    this.deleting = true
    try {
      for (let i = 0; i < ids.length; i++) {
        await LyricMarkService.remove(ids[i])
      }
      const next: PickLine[] = this.lines.map((line: PickLine) => {
        if (ids.indexOf(line.markId) < 0) {
          return line
        }
        const copy: PickLine = {
          time: line.time,
          text: line.text,
          translation: line.translation,
          roma: line.roma,
          markId: 0,
          picked: false
        }
        return copy
      })
      this.lines = next
      BubbleTip.show(this.getUIContext(), `已删除 ${ids.length} 句摘录`)
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '删除失败')
    } finally {
      this.deleting = false
    }
  }

  private async save(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    if (this.saving) {
      return
    }
    const selected = this.selectedCount()
    if (selected === 0) {
      BubbleTip.show(this.getUIContext(), '请先选中要摘录的歌词')
      return
    }
    const songId = String(this.song().id)
    const toAdd: LyricMarkDraft[] = []
    const toRemove: number[] = []
    for (let i = 0; i < this.lines.length; i++) {
      const line = this.lines[i]
      if (line.picked && line.markId === 0) {
        const translateType = line.translation.length > 0 ? 1 : (line.roma.length > 0 ? 2 : 0)
        toAdd.push({
          songId: songId,
          markId: 0,
          startTimeStamp: line.time,
          originalLyricsText: line.text,
          translateType: translateType,
          translateLyricsText: translateType === 1 ? line.translation : (translateType === 2 ? line.roma : '')
        })
      } else if (!line.picked && line.markId > 0) {
        toRemove.push(line.markId)
      }
    }
    if (toAdd.length === 0 && toRemove.length === 0) {
      BubbleTip.show(this.getUIContext(), '歌词本没有变化')
      return
    }
    this.saving = true
    try {
      if (toAdd.length > 0) {
        await LyricMarkService.saveMany(songId, toAdd)
      }
      for (let i = 0; i < toRemove.length; i++) {
        await LyricMarkService.remove(toRemove[i])
      }
      const added = toAdd.length
      const removed = toRemove.length
      if (added > 0 && removed > 0) {
        BubbleTip.show(this.getUIContext(), `已摘录 ${added} 句、移除 ${removed} 句`)
      } else if (added > 0) {
        BubbleTip.show(this.getUIContext(), `已摘录 ${added} 句到歌词本`)
      } else {
        BubbleTip.show(this.getUIContext(), `已从歌词本移除 ${removed} 句`)
      }
      this.pageStack.pop()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '摘录保存失败')
    } finally {
      this.saving = false
    }
  }

  @Builder
  private SongHeader() {
    Row({ space: 12 }) {
      if (this.song().img.length > 0) {
        Image(this.song().img).width(46).height(46).borderRadius(11).objectFit(ImageFit.Cover)
      } else {
        Stack() { SymbolGlyph($r('sys.symbol.music')).fontSize(20).fontColor([TC.textQuaternary()]) }
          .width(46).height(46).borderRadius(11).backgroundColor(TC.surfaceRaised())
      }
      Column({ space: 4 }) {
        Text(this.song().name).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(TC.textPrimary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.song().author).width('100%').fontSize(11).fontColor(TC.textSecondary())
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(`已选 ${this.selectedCount()} 句`).fontSize(11).fontColor(TC.accentSoft())
    }
    .width('100%').padding({ left: 4, right: 4, top: 6, bottom: 8 })
  }

  @Builder
  private LyricRow(line: PickLine) {
    Row({ space: 10 }) {
      Text(this.stampText(line.time)).width(36).fontSize(9).fontColor(TC.textQuaternary())
      Column({ space: 3 }) {
        Text(line.text).width('100%').fontSize(14).lineHeight(21)
          .fontColor(line.picked ? TC.textPrimary() : TC.textSecondary())
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (line.translation.length > 0) {
          Text(line.translation).width('100%').fontSize(10).lineHeight(15).fontColor(TC.textTertiary())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (line.roma.length > 0) {
          Text(line.roma).width('100%').fontSize(10).lineHeight(15).fontColor(TC.textQuaternary())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph(line.picked ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(18).fontColor([line.picked ? TC.accent() : TC.textQuaternary()])
    }
    .width('100%')
    .padding({ left: 11, right: 11, top: 9, bottom: 9 })
    .backgroundColor(line.picked ? TC.accentContainer() : Color.Transparent)
    .borderRadius(12)
  }

  @Builder
  private LyricWindow() {
    Column() {
      if (this.lines.length > 0) {
        List({ space: 2 }) {
          ForEach(this.lines, (line: PickLine, index: number) => {
            ListItem() {
              this.LyricRow(line)
            }
            .onClick(() => this.toggle(index))
          }, (line: PickLine, index: number) => `${index}-${line.time}-${line.markId}-${line.picked ? 1 : 0}`)
        }
        .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        .padding({ left: 4, right: 4, top: 4, bottom: 4 })
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(26).fontColor([TC.textQuaternary()])
          Text('这首歌暂无歌词').fontSize(12).fontColor(TC.textTertiary())
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .borderRadius(18)
    .backgroundColor('rgba(128,128,128,0.06)')
    .border({ width: 1, color: 'rgba(128,128,128,0.14)' })
    .clip(true)
  }

  @Builder
  private DeleteTool() {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.trash')).fontSize(19).fontColor([TC.textPrimary()])
      Text('删除歌词').fontSize(10).fontColor(TC.textSecondary())
    }
    .layoutWeight(1).height(52).justifyContent(FlexAlign.Center)
    .backgroundColor(TC.chipBackground()).borderRadius(14)
    .opacity(this.deletableIds().length > 0 ? 1 : 0.4)
    .enabled(this.deletableIds().length > 0 && !this.deleting)
    .onClick(() => this.confirmDelete())
  }

  @Builder
  private CopyTool() {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.rectangle_on_rectangle')).fontSize(19).fontColor([TC.textPrimary()])
      Text('复制歌词').fontSize(10).fontColor(TC.textSecondary())
    }
    .layoutWeight(1).height(52).justifyContent(FlexAlign.Center)
    .backgroundColor(TC.chipBackground()).borderRadius(14)
    .opacity(this.selectedCount() > 0 ? 1 : 0.4)
    .enabled(this.selectedCount() > 0)
    .onClick(() => this.copyLyrics())
  }

  @Builder
  private ShareTool() {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.share')).fontSize(19).fontColor([TC.textPrimary()])
      Text('分享歌词').fontSize(10).fontColor(TC.textSecondary())
    }
    .layoutWeight(1).height(52).justifyContent(FlexAlign.Center)
    .backgroundColor(TC.chipBackground()).borderRadius(14)
    .opacity(this.selectedCount() > 0 ? 1 : 0.4)
    .enabled(this.selectedCount() > 0)
    .onClick(() => this.shareLyrics())
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('摘录歌词').layoutWeight(1).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.text_alignleft')).fontSize(14).fontColor([TC.textSecondary()])
            Text('歌词本').fontSize(12).fontColor(TC.textSecondary())
          }.onClick(() => this.pageStack.pushPathByName('LyricBookPage', null))
        }.width('100%').height(52).padding({ left: 12, right: 12 })

        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).color(TC.accent())
            Text('正在加载歌词…').fontSize(11).fontColor(TC.textTertiary())
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.message.length > 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.text_alignleft')).fontSize(34).fontColor([TC.textQuaternary()])
            Text(this.message).fontSize(12).fontColor(TC.textSecondary())
            Text('重新加载').fontSize(12).fontColor(TC.accent())
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor(TC.chipBackground()).borderRadius(16)
              .onClick(() => this.load())
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Column({ space: 8 }) {
            this.SongHeader()
            this.LyricWindow()
            Text('点击歌词选中或取消，已摘录的句子会自动选中')
              .width('100%').fontSize(10).fontColor(TC.textTertiary()).textAlign(TextAlign.Center)
            Row({ space: 10 }) {
              this.DeleteTool()
              this.CopyTool()
              this.ShareTool()
            }.width('100%').padding({ top: 2 })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 4 })
          .constraintSize({ maxWidth: 720 })
          .alignSelf(ItemAlign.Center)
        }

        if (!this.loading && this.message.length === 0) {
          Row() {
            Button() {
              Row({ space: 6 }) {
                if (this.saving) {
                  LoadingProgress().width(16).height(16).color(TC.textOnAccent())
                } else {
                  SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(16).fontColor([TC.textOnAccent()])
                }
                Text(this.saving ? '保存中…' : (this.selectedCount() > 0 ? `摘录 ${this.selectedCount()} 句` : '摘录歌词'))
                  .fontSize(15).fontColor(TC.textOnAccent())
              }
            }
            .width('100%').height(46)
            .backgroundColor(TC.accent()).borderRadius(23)
            .opacity(this.selectedCount() > 0 ? 1 : 0.5)
            .enabled(!this.saving && this.selectedCount() > 0)
            .onClick(() => this.save())
          }
          .width('100%')
          .constraintSize({ maxWidth: 720 })
          .alignSelf(ItemAlign.Center)
          .padding({ left: 16, right: 16, top: 10, bottom: 24 })
        }
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true).onShown(() => {
      // 从登录页回来时，补拉一次已摘录的句子
      if (this.authStore.loggedIn && !this.marksLoaded && this.lines.length > 0) {
        this.loadMarks()
      }
    })
  }
}
