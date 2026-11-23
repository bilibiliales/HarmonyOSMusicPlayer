import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { formBindingData, formProvider } from '@kit.FormKit'
import { http } from '@kit.NetworkKit'
import { resizeImageUrl } from './ImageUrl'

export interface MusicWidgetState {
  songName: string
  artist: string
  songId: string
  isPlaying: boolean
  liked: boolean
  playMode: number
  cover: string
}
class WidgetBinding {
  dimension: number = 2
  songName: string = ''
  artist: string = ''
  songId: string = ''
  isPlaying: boolean = false
  liked: boolean = false
  playMode: number = 0
  cover: string = ''
  formImages: Record<string, number> = {}
}
export interface WidgetBindingLease { data: formBindingData.FormBindingData; file?: fileIo.File }

export class MusicWidgetService {
  static readonly STATE_FILE: string = 'player_widget_state.json'
  static readonly IDS_FILE: string = 'music_card_ids.json'
  static readonly DIMENSIONS_FILE: string = 'music_card_dimensions.json'
  private static revision: number = 0

  static empty(): MusicWidgetState {
    return { songName: '今天听点什么？', artist: '打开应用开始播放', songId: '', isPlaying: false, liked: false, playMode: 0, cover: '' }
  }

  static read(context: common.Context): MusicWidgetState {
    try {
      const raw = JSON.parse(fileIo.readTextSync(`${context.filesDir}/${MusicWidgetService.STATE_FILE}`)) as MusicWidgetState
      return { songName: raw.songName || '今天听点什么？', artist: raw.artist || '打开应用开始播放',
        songId: raw.songId || '', isPlaying: raw.isPlaying === true, liked: raw.liked === true,
        playMode: raw.playMode === 1 || raw.playMode === 2 ? raw.playMode : 0, cover: raw.cover || '' }
    } catch (_error) { return MusicWidgetService.empty() }
  }

  static dimensions(context: common.Context): Record<string, number> {
    try { return JSON.parse(fileIo.readTextSync(`${context.filesDir}/${MusicWidgetService.DIMENSIONS_FILE}`)) as Record<string, number> }
    catch (_error) { return {} }
  }

  static binding(state: MusicWidgetState, dimension: number = 2): WidgetBindingLease {
    const value = new WidgetBinding()
    value.dimension = dimension
    value.songName = state.songName
    value.artist = state.artist
    value.songId = state.songId
    value.isPlaying = state.isPlaying
    value.liked = state.liked
    value.playMode = state.playMode
    let file: fileIo.File | undefined = undefined
    if (state.cover && !/^https?:/.test(state.cover)) {
      try {
        file = fileIo.openSync(state.cover, fileIo.OpenMode.READ_ONLY)
        const key = `music_cover_${state.songId.replace(/[^a-zA-Z0-9_-]/g, '_')}`
        value.cover = `memory://${key}`
        value.formImages[key] = file.fd
      } catch (_error) {}
    }
    return { data: formBindingData.createFormBindingData(value), file: file }
  }

  private static async cover(context: common.Context, state: MusicWidgetState): Promise<string> {
    if (!state.cover || !/^https?:/.test(state.cover)) { return state.cover }
    const safeId = state.songId.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 80)
    if (!safeId) { return '' }
    const path = `${context.filesDir}/widget_cover_${safeId}.jpg`
    try { if (fileIo.accessSync(path)) { return path } } catch (_error) {}
    const client = http.createHttp()
    try {
      const response = await client.request(resizeImageUrl(state.cover, 480, 480), {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 5000, readTimeout: 10000
      })
      if (response.responseCode !== 200) { return '' }
      const bytes = response.result as ArrayBuffer
      if (!bytes.byteLength) { return '' }
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try {
        let offset = 0
        while (offset < bytes.byteLength) {
          const count = fileIo.writeSync(file.fd, bytes.slice(offset))
          if (count <= 0) { throw new Error('封面写入失败') }
          offset += count
        }
      } finally { fileIo.closeSync(file.fd) }
      return path
    } catch (_error) {
      try { fileIo.unlinkSync(path) } catch (_ignored) {}
      return ''
    } finally { client.destroy() }
  }

  static async publish(context: common.Context, state: MusicWidgetState): Promise<void> {
    const revision = ++MusicWidgetService.revision
    let local = !/^https?:/.test(state.cover) ? state.cover : ''
    if (!local && state.cover) {
      const previous = MusicWidgetService.read(context)
      if (previous.songId === state.songId) { local = previous.cover }
      if (!local) {
        const path = `${context.filesDir}/widget_cover_${state.songId.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 80)}.jpg`
        try { if (fileIo.accessSync(path)) { local = path } } catch (_error) {}
      }
    }
    // 状态先推送，网络封面不阻塞暂停/切歌按钮的更新。
    const initial: MusicWidgetState = { songName: state.songName, artist: state.artist, songId: state.songId,
      isPlaying: state.isPlaying, liked: state.liked, playMode: state.playMode, cover: local }
    await MusicWidgetService.deliver(context, initial, revision)
    if (!/^https?:/.test(state.cover)) { return }
    const cover = await MusicWidgetService.cover(context, state)
    if (revision !== MusicWidgetService.revision) { return }
    const current: MusicWidgetState = { songName: state.songName, artist: state.artist, songId: state.songId,
      isPlaying: state.isPlaying, liked: state.liked, playMode: state.playMode, cover: cover }
    await MusicWidgetService.deliver(context, current, revision)
  }

  private static async deliver(context: common.Context, current: MusicWidgetState, revision: number): Promise<void> {
    if (revision !== MusicWidgetService.revision) { return }
    const file = fileIo.openSync(`${context.filesDir}/${MusicWidgetService.STATE_FILE}`,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    try { fileIo.writeSync(file.fd, JSON.stringify(current)) } finally { fileIo.closeSync(file.fd) }
    let ids: string[] = []
    try { ids = JSON.parse(fileIo.readTextSync(`${context.filesDir}/${MusicWidgetService.IDS_FILE}`)) as string[] }
    catch (_error) { return }
    const dimensions = MusicWidgetService.dimensions(context)
    for (const id of ids) {
      if (revision !== MusicWidgetService.revision) { break }
      const lease = MusicWidgetService.binding(current, dimensions[id] || 2)
      try { await formProvider.updateForm(id, lease.data) } catch (_error) {}
      finally { if (lease.file) { fileIo.closeSync(lease.file.fd) } }
    }
  }
}
