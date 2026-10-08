import { AudioMetadata } from './AudioMetadata'
import { SongMetadataCache } from './SongMetadataCache'
import { ApiClient } from './ApiClient'
import { ApiSong, mapApiSong } from '../models/api'
import { common } from '@kit.AbilityKit'
import { fileIo, fileUri, fileShare, picker } from '@kit.CoreFileKit'
import { SongArtist, songItemType } from '../models/music'

export interface LocalTrack {
  uri: string
  name: string
  artist: string
  size: number
  modified: number
  managed: boolean
  persistent: boolean
  format: string
  songId?: string
  album?: string
  albumId?: string
  artists?: SongArtist[]
  duration?: number
  cover?: string
  lrc?: string
  yrc?: string
  translation?: string
  md5?: string
}

interface MatchResponse { code: number; result?: MatchResult }
interface MatchResult { songs?: ApiSong[] }

interface LocalIndex { directory: string; tracks: LocalTrack[] }
export interface LocalScan { tracks: LocalTrack[]; message: string }

export class LocalLibrary {
  private static context?: common.Context
  private static revision: number = 0
  private static initialization?: Promise<void>
  private static loaded: boolean = false
  private static index: LocalIndex = { directory: '', tracks: [] }
  private static saving: Promise<void> = Promise.resolve()

  static async init(context: common.Context): Promise<void> {
    if (LocalLibrary.loaded) { return }
    if (LocalLibrary.initialization) { return await LocalLibrary.initialization }
    const job = LocalLibrary.loadIndex(context)
    LocalLibrary.initialization = job
    try { await job } finally { LocalLibrary.initialization = undefined }
  }

  private static async loadIndex(context: common.Context): Promise<void> {
    LocalLibrary.context = context
    const path = context.filesDir + '/local_music_index.json'
    try {
      const parsed = JSON.parse(await fileIo.readText(path)) as LocalIndex
      if (parsed && typeof parsed.directory === 'string' && Array.isArray(parsed.tracks)) {
        LocalLibrary.index = { directory: parsed.directory, tracks: parsed.tracks.filter((track: LocalTrack) =>
          typeof track.uri === 'string' && track.uri.startsWith('file://') && typeof track.name === 'string') }
      }
    } catch (_error) {}
    LocalLibrary.loaded = true
  }

  private static async save(): Promise<void> {
    const text = JSON.stringify(LocalLibrary.index)
    const path = LocalLibrary.context!.filesDir + '/local_music_index.json'
    const job = LocalLibrary.saving.catch(() => {}).then(async () => {
      const temp = path + '.tmp'
      const file = await fileIo.open(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try { await fileIo.write(file.fd, text) } finally { await fileIo.close(file) }
      await fileIo.rename(temp, path)
    })
    LocalLibrary.saving = job
    await job
  }

  static cached(): LocalTrack[] { return LocalLibrary.index.tracks.slice() }

  static song(track: LocalTrack): songItemType {
    return { id: track.songId || 'local:' + track.uri, name: track.name, author: track.artist || '本地音乐',
      img: track.cover || '', url: '', duration: track.duration, localLrc: track.lrc, localYrc: track.yrc,
      localTranslation: track.translation, localUri: track.uri, localManaged: track.managed,
      localFormat: track.format, album: track.album || '本地音乐', albumId: track.albumId, artists: track.artists }
  }

  private static format(name: string): string {
    return name.slice(name.lastIndexOf('.') + 1).toLowerCase()
  }

  private static supported(name: string): boolean {
    return ['mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'ape'].includes(LocalLibrary.format(name))
  }

  private static policy(uri: string): fileShare.PolicyInfo[] {
    return [{ uri: uri, operationMode: fileShare.OperationMode.READ_MODE }]
  }

  private static async persist(uri: string): Promise<boolean> {
    try { await fileShare.persistPermission(LocalLibrary.policy(uri)); return true } catch (_error) { return false }
  }

  static async open(uri: string, managed: boolean = false): Promise<fileIo.File> {
    if (!uri.startsWith('file://')) { throw new Error('本地文件地址无效') }
    if (!managed) {
      try {
        const policies = LocalLibrary.policy(uri)
        const allowed = await fileShare.checkPersistentPermission(policies)
        if (allowed[0]) { await fileShare.activatePermission(policies) }
      } catch (_error) {}
    }
    try { return await fileIo.open(managed ? new fileUri.FileUri(uri).path : uri, fileIo.OpenMode.READ_ONLY) }
    catch (_error) { throw new Error('本地文件不可访问，请在“本地与下载”重新授权；文件也可能已被移动或删除') }
  }

  private static async directory(context: common.UIAbilityContext): Promise<string> {
    if (LocalLibrary.index.directory) {
      try {
        const root = new fileUri.FileUri(LocalLibrary.index.directory).path
        if ((await fileIo.stat(root)).isDirectory()) { return LocalLibrary.index.directory }
      } catch (_error) {}
      LocalLibrary.index.directory = ''
    }
    const options = new picker.DocumentSaveOptions()
    options.pickerMode = picker.DocumentPickerMode.DOWNLOAD
    const uris = await new picker.DocumentViewPicker(context).save(options)
    if (!uris.length) { return '' }
    if (!uris[0].startsWith('file://docs/')) { throw new Error('系统未返回有效的下载目录，请重新选择') }
    const root = new fileUri.FileUri(uris[0]).path
    try { await fileIo.mkdir(root, true) } catch (_error) {
      if (!(await fileIo.stat(root)).isDirectory()) { throw new Error('下载目录不可用') }
    }
    LocalLibrary.index.directory = uris[0]
    await LocalLibrary.save()
    return uris[0]
  }

  static async saveDownload(context: common.UIAbilityContext, source: string, name: string,
    song: songItemType, mode: string): Promise<string> {
    await LocalLibrary.init(context)
    let uri = ''
    const managed = mode === 'download'
    if (managed) {
      const directory = await LocalLibrary.directory(context)
      if (!directory) { return '' }
      // DOWNLOAD returns an authorized directory, not a pre-created destination file.
      const root = new fileUri.FileUri(directory).path
      const dot = name.lastIndexOf('.')
      const stem = dot > 0 ? name.slice(0, dot) : name
      const suffix = dot > 0 ? name.slice(dot) : ''
      let candidate = root + '/' + name
      let number = 1
      while (await LocalLibrary.exists(candidate)) { candidate = root + '/' + stem + ' (' + number++ + ')' + suffix }
      uri = directory.replace(/\/$/, '') + '/' + encodeURIComponent(candidate.slice(root.length + 1))
    } else {
      const options = new picker.DocumentSaveOptions()
      options.newFileNames = [name]
      const uris = await new picker.DocumentViewPicker(context).save(options)
      if (!uris.length) { return '' }
      uri = uris[0]
    }
    const targetPath = managed ? new fileUri.FileUri(uri).path : uri
    const target = await fileIo.open(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE |
      (managed ? 0 : fileIo.OpenMode.TRUNC))
    let copied = false
    try { await fileIo.copyFile(source, target.fd); copied = true }
    finally {
      await fileIo.close(target)
      if (!copied && managed) { try { await fileIo.unlink(targetPath) } catch (_error) {} }
    }
    const persistent = managed || await LocalLibrary.persist(uri)
    const stat = await fileIo.stat(targetPath)
    const track: LocalTrack = { uri: uri, name: song.name, artist: song.author,
      size: stat.size, modified: stat.mtime, managed: managed, persistent: persistent, format: LocalLibrary.format(name), songId: /^\d+$/.test(song.id) ? song.id : undefined,
      album: song.album, albumId: song.albumId, artists: song.artists, duration: song.duration }
    LocalLibrary.revision++
    LocalLibrary.index.tracks = LocalLibrary.index.tracks.filter((item: LocalTrack) => item.uri !== uri).concat([track])
    await LocalLibrary.save()
    try { await LocalLibrary.cacheMetadata(track, song) } catch (_error) {}
    return persistent ? '已保存并加入本地音乐' : '已保存并加入本地音乐；下次访问可能需要重新授权'
  }

  private static async exists(path: string): Promise<boolean> {
    try { return await fileIo.access(path) } catch (_error) { return false }
  }

  private static async cacheMetadata(track: LocalTrack, song: songItemType, persist: boolean = true): Promise<void> {
    await Promise.all([
      SongMetadataCache.lyrics(song).then((lyrics) => {
        track.lrc = SongMetadataCache.lrc(lyrics)
        track.yrc = lyrics.yrc?.lyric || ''
        track.translation = lyrics.tlyric?.lyric || ''
      }).catch(() => {}),
      SongMetadataCache.cover(song.id, song.img).then((cover: string) => { if (cover) { track.cover = cover } }).catch(() => {})
    ])
    if (persist) {
      LocalLibrary.revision++
      await LocalLibrary.save()
    }
  }

  static async linkMetadata(track: LocalTrack, song: songItemType): Promise<LocalTrack> {
    if (!/^\d+$/.test(song.id) || !song.name.trim()) { throw new Error('关联歌曲无效，请重新选择') }
    const current = LocalLibrary.index.tracks.find((item: LocalTrack) => item.uri === track.uri)
    if (!current) { throw new Error('本地歌曲已不存在，请重新扫描') }
    const linked: LocalTrack = { uri: current.uri, size: current.size, modified: current.modified,
      managed: current.managed, persistent: current.persistent, format: current.format, md5: current.md5,
      songId: song.id, name: song.name, artist: song.author,
      album: song.album, albumId: song.albumId, artists: song.artists,
      duration: current.duration || song.duration, cover: '', lrc: '', yrc: '', translation: '' }
    // Cache the selected catalog metadata, while preserving the local file and its access policy.
    await LocalLibrary.cacheMetadata(linked, song, false)
    if (!LocalLibrary.index.tracks.some((item: LocalTrack) => item.uri === track.uri)) {
      throw new Error('本地歌曲已不存在，请重新扫描')
    }
    const previous = LocalLibrary.index.tracks
    LocalLibrary.revision++
    LocalLibrary.index.tracks = previous.map((item: LocalTrack) => item.uri === track.uri ? linked : item)
    try { await LocalLibrary.save() }
    catch (error) {
      LocalLibrary.index.tracks = LocalLibrary.index.tracks.map((item: LocalTrack) => item === linked ? current : item)
      throw new Error(error instanceof Error ? error.message : '保存歌曲关联失败')
    }
    return linked
  }

  static async matchMetadata(track: LocalTrack): Promise<LocalTrack> {
    const file = await LocalLibrary.open(track.uri, track.managed)
    try {
      const metadata = await AudioMetadata.read(file.fd, track.size)
      track.name = metadata.title || track.name
      track.artist = metadata.artist || track.artist
      track.album = metadata.album || track.album
      track.duration = Number(metadata.duration) || track.duration
    } finally { await fileIo.close(file) }
    const hashFile = await LocalLibrary.open(track.uri, track.managed)
    try { track.md5 = await AudioMetadata.fileHash(hashFile.fd, track.size) } finally { await fileIo.close(hashFile) }
    await LocalLibrary.save()
    const response = await ApiClient.get<MatchResponse>('/search/match', [
      { key: 'title', value: track.name }, { key: 'artist', value: track.artist === '本地音乐' ? '' : track.artist },
      { key: 'album', value: track.album || '' }, { key: 'duration', value: ((track.duration || 0) / 1000).toString() },
      { key: 'md5', value: track.md5 || '' }
    ])
    const match = response.result?.songs?.[0]
    if (response.code !== 200 || !match?.id) { throw new Error('未找到匹配歌曲，仍可正常离线播放') }
    return await LocalLibrary.linkMetadata(track, mapApiSong(match))
  }

  static async importFiles(context: common.UIAbilityContext): Promise<void> {
    await LocalLibrary.init(context)
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 100
    options.fileSuffixFilters = ['音频|.mp3,.flac,.m4a,.aac,.wav,.ogg,.opus,.ape']
    const uris = await new picker.DocumentViewPicker(context).select(options)
    for (const uri of uris) {
      const name = new fileUri.FileUri(uri).name
      if (!LocalLibrary.supported(name)) { continue }
      const stat = await fileIo.stat(uri)
      const track: LocalTrack = { uri: uri, name: name.replace(/\.[^.]+$/, ''), artist: '本地音乐',
        size: stat.size, modified: stat.mtime, managed: false, persistent: await LocalLibrary.persist(uri),
        format: LocalLibrary.format(name) }
      LocalLibrary.index.tracks = LocalLibrary.index.tracks.filter((item: LocalTrack) => item.uri !== uri).concat([track])
    }
    await LocalLibrary.save()
  }

  static async reauthorize(context: common.UIAbilityContext, track: LocalTrack): Promise<void> {
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 1
    options.defaultFilePathUri = track.uri
    const uris = await new picker.DocumentViewPicker(context).select(options)
    if (!uris.length) { return }
    if (uris[0] !== track.uri) { throw new Error('请选择原文件；其他文件请使用“导入音乐”') }
    track.persistent = await LocalLibrary.persist(track.uri)
    await LocalLibrary.save()
  }

  static async scan(): Promise<LocalScan> {
    const revision = LocalLibrary.revision
    const directory = LocalLibrary.index.directory
    if (!directory) { return { tracks: LocalLibrary.cached(), message: '' } }
    try {
      const root = new fileUri.FileUri(directory).path
      const names = await fileIo.listFile(root)
      const refreshed: LocalTrack[] = []
      for (const name of names) {
        if (!LocalLibrary.supported(name)) { continue }
        const path = root + '/' + name
        const stat = await fileIo.stat(path)
        if (!stat.isFile() || stat.size === 0) { continue }
        const uri = directory.replace(/\/$/, '') + '/' + encodeURIComponent(name)
        const previous = LocalLibrary.index.tracks.find((item: LocalTrack) => item.uri === uri)
        if (previous && previous.size === stat.size && previous.modified === stat.mtime) { refreshed.push(previous); continue }
        refreshed.push({ uri: uri, name: previous?.name || name.replace(/\.[^.]+$/, ''),
          artist: previous?.artist || '本地音乐', size: stat.size, modified: stat.mtime,
          managed: true, persistent: true, format: LocalLibrary.format(name) })
      }
      if (revision !== LocalLibrary.revision) { return { tracks: LocalLibrary.cached(), message: '' } }
      LocalLibrary.index.tracks = LocalLibrary.index.tracks.filter((item: LocalTrack) => !item.managed || !item.uri.startsWith(directory.replace(/\/$/, '') + '/')).concat(refreshed)
      await LocalLibrary.save()
      return { tracks: LocalLibrary.cached(), message: '' }
    } catch (_error) {
      return { tracks: LocalLibrary.cached(), message: '下载目录暂不可访问，已保留原有记录；可重新选择下载目录授权' }
    }
  }

  static async chooseDirectory(context: common.UIAbilityContext): Promise<void> {
    await LocalLibrary.init(context)
    const previous = LocalLibrary.index.directory
    LocalLibrary.index.directory = ''
    try {
      const selected = await LocalLibrary.directory(context)
      if (!selected) { LocalLibrary.index.directory = previous }
      else { LocalLibrary.revision++ }
    } catch (error) { LocalLibrary.index.directory = previous; throw new Error(error instanceof Error ? error.message : '目录选择失败') }
  }
}
