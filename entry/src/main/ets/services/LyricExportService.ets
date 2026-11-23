import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { fileIo, picker } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { LyricMarkVO } from '../models/lyricmark'
import { LyricMarkService } from './LyricMarkService'
import { SystemShareService } from './SystemShareService'

/** 导出歌词本当前摘录，复制和分享使用原文及译文，下载保留时间戳。 */
export class LyricExportService {
  static text(mark: LyricMarkVO): string {
    const blocks: string[] = []
    for (const detail of mark.detailList || []) {
      const lines: string[] = []
      if (detail.originalLyricsText?.trim()) { lines.push(detail.originalLyricsText.trim()) }
      if (detail.translateType > 0 && detail.translateLyricsText?.trim()) {
        lines.push(detail.translateLyricsText.trim())
      }
      if (lines.length > 0) { blocks.push(lines.join('\n')) }
    }
    const text = blocks.join('\n\n')
    if (!text) { throw new Error('没有可用的歌词内容') }
    return text
  }

  private static clean(value: string): string {
    return value.replace(/[\r\n\[\]]/g, ' ').trim()
  }

  private static stamp(ms: number): string {
    const time = Number.isFinite(ms) ? Math.max(0, Math.round(ms)) : 0
    const minutes = Math.floor(time / 60000).toString().padStart(2, '0')
    const seconds = Math.floor(time / 1000 % 60).toString().padStart(2, '0')
    return `[${minutes}:${seconds}.${(time % 1000).toString().padStart(3, '0')}]`
  }

  static lrc(mark: LyricMarkVO): string {
    LyricExportService.text(mark)
    const song = LyricMarkService.toSong(mark)
    const lines: string[] = [`[ti:${LyricExportService.clean(song.name)}]`,
      `[ar:${LyricExportService.clean(song.author)}]`]
    const details = (mark.detailList || []).slice().sort((a, b) => a.startTimeStamp - b.startTimeStamp)
    for (const detail of details) {
      const stamp = LyricExportService.stamp(detail.startTimeStamp)
      for (const line of (detail.originalLyricsText || '').split(/\r?\n/)) {
        if (line.trim()) { lines.push(stamp + LyricExportService.clean(line)) }
      }
      if (detail.translateType > 0) {
        for (const line of (detail.translateLyricsText || '').split(/\r?\n/)) {
          if (line.trim()) { lines.push(stamp + LyricExportService.clean(line)) }
        }
      }
    }
    return lines.join('\n') + '\n'
  }

  static async copy(mark: LyricMarkVO): Promise<void> {
    await pasteboard.getSystemPasteboard().setData(
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, LyricExportService.text(mark)))
  }

  static async share(context: common.UIAbilityContext, mark: LyricMarkVO): Promise<void> {
    const song = LyricMarkService.toSong(mark)
    await SystemShareService.showText(context, { content: LyricExportService.text(mark),
      title: `${song.name} - ${song.author}`, description: '歌词摘录', label: '歌词', image: song.img })
  }

  /** 系统文件选择器负责选择保存位置；取消时不写文件。 */
  static async download(context: common.UIAbilityContext, mark: LyricMarkVO): Promise<boolean> {
    const text = LyricExportService.lrc(mark)
    const song = LyricMarkService.toSong(mark)
    const name = (song.name || '歌词摘录').replace(/[\\/:*?"<>|\r\n]/g, '_').slice(0, 80)
    const targets = await new picker.DocumentViewPicker(context).save({
      newFileNames: [`${name}-歌词摘录.lrc`], fileSuffixChoices: ['LRC 歌词|.lrc']
    })
    if (!targets.length) { return false }
    const bytes = new util.TextEncoder().encodeInto(text)
    const file = await fileIo.open(targets[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    try {
      let offset = 0
      while (offset < bytes.byteLength) {
        const count = await fileIo.write(file.fd, bytes.slice(offset).buffer as ArrayBuffer)
        if (count <= 0) { throw new Error('歌词文件写入失败') }
        offset += count
      }
    } finally {
      await fileIo.close(file)
    }
    return true
  }
}
