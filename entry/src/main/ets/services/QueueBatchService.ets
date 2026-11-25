import { common } from '@kit.AbilityKit'
import { songItemType } from '../models/music'
import { OperationResponse } from '../models/api'
import { ApiClient } from './ApiClient'
import { SongQualityService } from './SongQualityService'
import { StreamingDownload } from './StreamingAudio'
import { AudioFileFormat } from './AudioFileFormat'
import { LocalLibrary } from './LocalLibrary'
import { AppSettings } from './AppSettings'

export class QueueBatchService {
  static async collect(playlistId: string, songs: songItemType[]): Promise<void> {
    const ids = Array.from(new Set(songs.map((song: songItemType) => song.id)))
    for (let start = 0; start < ids.length; start += 100) {
      const response = await ApiClient.get<OperationResponse>('/playlist/tracks', [
        { key: 'op', value: 'add' }, { key: 'pid', value: playlistId }, { key: 'tracks', value: ids.slice(start, start + 100).join(',') }
      ])
      if (response.code !== 200) { throw new Error(response.message || '批量收藏失败') }
    }
  }

  static async download(context: common.UIAbilityContext, songs: songItemType[],
    notify: (message: string) => void): Promise<string> {
    let success = 0
    const failed: string[] = []
    for (let i = 0; i < songs.length; i++) {
      const song = songs[i]
      notify(`正在下载 ${i + 1}/${songs.length}：${song.name}`)
      try {
        const audio = await SongQualityService.download(song.id, AppSettings.defaultDownloadQuality)
        const head = await StreamingDownload.probe(audio.url, 64)
        const extension = AudioFileFormat.extension(audio.url, audio.type, audio.encodeType, head)
        const name = `${song.name}-${song.author}`.replace(/[\\/:*?"<>|]/g, '_')
        const task = new StreamingDownload()
        const result = await LocalLibrary.saveDownload(context, `${name}.${extension}`, song, 'download',
          async (fd: number): Promise<number> => task.run(audio.url, fd, audio.size))
        if (!result) { return `已取消下载，完成 ${success}/${songs.length}` }
        success++
      } catch (_error) { failed.push(song.name) }
    }
    return `已下载 ${success}/${songs.length} 首${failed.length ? `；失败：${failed.join('、')}` : ''}`
  }
}
