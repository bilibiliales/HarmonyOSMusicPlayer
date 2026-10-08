import { fileIo, fileUri } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import { AppSettings } from './AppSettings'
import { ApiClient } from './ApiClient'
import { LyricResponse } from '../models/api'
import { songItemType } from '../models/music'
import { SystemLrc } from './SystemLrc'

export class SongMetadataCache {
  private static pending: Map<string, Promise<LyricResponse>> = new Map()

  static lrc(response: LyricResponse): string {
    const standard = SystemLrc.normalize(response.lrc?.lyric || '')
    if (standard) { return standard }
    return SystemLrc.normalize((response.yrc?.lyric || '').split('\n').map((line: string) => {
      const match = /^\[(\d+),(\d+)\](.*)$/.exec(line)
      if (!match) { return '' }
      const time = Number(match[1])
      const stamp = Math.floor(time / 60000).toString().padStart(2, '0') + ':' +
        ((time % 60000) / 1000).toFixed(3).padStart(6, '0')
      return '[' + stamp + ']' + match[3].replace(/\(\d+,\d+,\d+\)/g, '')
    }).filter((line: string) => !!line).join('\n'))
  }

  static async lyrics(song: songItemType): Promise<LyricResponse> {
    if (song.localLrc || song.localYrc) {
      return { code: 200, lrc: { version: 1, lyric: song.localLrc || '' }, yrc: { version: 1, lyric: song.localYrc || '' },
        tlyric: { version: 1, lyric: song.localTranslation || '' } }
    }
    if (!/^\d+$/.test(song.id)) { return { code: 200, nolyric: true } }
    const path = AppSettings.context ? AppSettings.context.filesDir + '/lyrics_' + song.id + '.json' : ''
    if (path) {
      try {
        const cached = JSON.parse(await fileIo.readText(path)) as LyricResponse
        if (cached.code === 200 && (cached.lrc?.lyric || cached.yrc?.lyric)) { return cached }
      } catch (_error) {}
    }
    // Local playback never waits on the network; matching/download caches metadata explicitly.
    if (song.localUri) { return { code: 200, nolyric: true } }
    const existing = SongMetadataCache.pending.get(song.id)
    if (existing) { return await existing }
    const job = SongMetadataCache.fetch(song.id, path)
    SongMetadataCache.pending.set(song.id, job)
    try { return await job } finally { if (SongMetadataCache.pending.get(song.id) === job) { SongMetadataCache.pending.delete(song.id) } }
  }

  private static async fetch(id: string, path: string): Promise<LyricResponse> {
    const result = await ApiClient.get<LyricResponse>('/lyric/new', [{ key: 'id', value: id }])
    if (result.code !== 200) { throw new Error('歌词获取失败') }
    if (path && (result.lrc?.lyric || result.yrc?.lyric)) {
      try {
        const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
        try { await fileIo.write(file.fd, JSON.stringify(result)) } finally { await fileIo.close(file) }
      } catch (_error) {}
    }
    return result
  }

  static async cover(id: string, url: string): Promise<string> {
    if (!AppSettings.context || !/^\d+$/.test(id) || !/^https?:\/\//.test(url)) { return '' }
    const path = AppSettings.context.filesDir + '/cover_' + id + '.jpg'
    try { if (await fileIo.access(path)) { return fileUri.getUriFromPath(path) } } catch (_error) {}
    const client = http.createHttp()
    try {
      const result = await client.request(url, { method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER, connectTimeout: 5000, readTimeout: 10000 })
      if (result.responseCode !== 200) { return '' }
      const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try { await fileIo.write(file.fd, result.result as ArrayBuffer) } finally { await fileIo.close(file) }
      return fileUri.getUriFromPath(path)
    } finally { client.destroy() }
  }
}
