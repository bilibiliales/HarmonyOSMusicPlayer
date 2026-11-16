import { image } from '@kit.ImageKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { songItemType } from '../models/music'
import { SongMetadataCache } from './SongMetadataCache'

/**
 * AVSession（播控中心 / 锁屏 / 灵动岛）的封面来源。
 *
 * 线上歌曲的 `img` 是 https 地址，系统可以直接下载显示；
 * 本地音乐匹配成功后 `img` 指向应用沙箱内的封面文件
 * （`file://<bundle>/data/storage/el2/base/files/cover_x.jpg`），
 * 播控进程没有该沙箱目录的读取权限，直接传 uri 会得到一张空封面。
 *
 * 因此这里把本地封面解码成 PixelMap 再交给系统（AVMetadata.mediaImage
 * 原生支持 string | PixelMap，PixelMap 也不受跨进程文件权限影响）：
 *   - 网络图：原样返回 url；
 *   - 本地图：解码 PixelMap（按 uri 缓存最近若干张），失败时退回裸沙箱路径。
 */
export class SystemMediaImage {
  private static readonly MAX_CACHE: number = 4
  private static cache: Map<string, image.PixelMap> = new Map()
  private static order: string[] = []

  static async resolve(song: songItemType): Promise<string | image.PixelMap | undefined> {
    const source = (song.img || '').trim()
    const remote = (song.remoteImg || '').trim()
    if (source.length === 0) {
      if (/^https?:\/\//i.test(remote)) {
        return remote
      }
      // 本地音乐没有封面文件时，按线上歌曲 id 补一张网图（播控可自行下载）。
      const fallback = await SongMetadataCache.remoteCover(song.id)
      return fallback.length > 0 ? fallback : undefined
    }
    if (/^https?:\/\//i.test(source)) {
      return source
    }
    const cached = SystemMediaImage.cache.get(source)
    if (cached) {
      return cached
    }
    const pixelMap = await SystemMediaImage.decode(source)
    if (!pixelMap) {
      // 沙箱封面读不出来时退回线上封面地址；再不行传裸沙箱路径搏一次。
      if (/^https?:\/\//i.test(remote)) {
        return remote
      }
      return SystemMediaImage.sandboxPath(source)
    }
    SystemMediaImage.remember(source, pixelMap)
    return pixelMap
  }

  private static sandboxPath(source: string): string {
    if (!source.startsWith('file://') || source.startsWith('file://media/')) {
      return source
    }
    try {
      return new fileUri.FileUri(source).path
    } catch (_error) {
      return source
    }
  }

  private static async decode(source: string): Promise<image.PixelMap | undefined> {
    let file: fileIo.File | undefined = undefined
    let sourceImage: image.ImageSource | undefined = undefined
    try {
      // 走 fd 读取：沙箱 uri 直接交给 ImageKit 时部分版本解析不到路径。
      file = await fileIo.open(SystemMediaImage.sandboxPath(source), fileIo.OpenMode.READ_ONLY)
      sourceImage = image.createImageSource(file.fd)
      if (!sourceImage) {
        return undefined
      }
      const options: image.DecodingOptions = { editable: false }
      return await sourceImage.createPixelMap(options)
    } catch (_error) {
      return undefined
    } finally {
      if (sourceImage) {
        try {
          await sourceImage.release()
        } catch (_error) {
        }
      }
      if (file) {
        try {
          await fileIo.close(file)
        } catch (_error) {
        }
      }
    }
  }

  private static remember(key: string, pixelMap: image.PixelMap): void {
    SystemMediaImage.cache.set(key, pixelMap)
    SystemMediaImage.order.push(key)
    while (SystemMediaImage.order.length > SystemMediaImage.MAX_CACHE) {
      const dropped = SystemMediaImage.order.shift()
      if (dropped !== undefined) {
        const old = SystemMediaImage.cache.get(dropped)
        SystemMediaImage.cache.delete(dropped)
        if (old) {
          try {
            old.release().catch(() => {})
          } catch (_error) {
          }
        }
      }
    }
  }
}
