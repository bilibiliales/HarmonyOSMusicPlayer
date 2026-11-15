import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'

/**
 * 装扮素材的选择与落地。
 *
 * 相册返回的是临时 URI（file://media/Photo/...），Image 组件和 ImageKit 都
 * 不一定能直接读，重启后还会失效，所以选择后统一复制成应用沙箱里的普通文件，
 * 只持久化沙箱路径。
 *
 * 两个必须注意的坑：
 * 1) fileIo.accessSync(path) 在「路径不存在」时是抛异常，不是返回 false，
 *    用它来判断目录是否存在会让整段复制逻辑被 catch 吞掉（表现就是图片空白）；
 *    创建目录直接用 mkdirSync(dir, true) 并包 try/catch。
 * 2) read / write 一次调用不保证读满 / 写满，必须循环处理，否则大图会截断。
 */
export class DecorationMedia {
  private static readonly DIR: string = 'decoration'
  private static readonly CHUNK: number = 256 * 1024

  /** 选一张图片（支持 GIF），返回沙箱路径；取消返回空串。 */
  static async pickImage(context: common.Context): Promise<string> {
    const picker = new photoAccessHelper.PhotoViewPicker()
    const result = await picker.select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 1
    })
    if (result.photoUris.length === 0) {
      return ''
    }
    return await DecorationMedia.copyToSandbox(context, result.photoUris[0], 'image')
  }

  /** 选一个视频，返回沙箱路径；取消返回空串。 */
  static async pickVideo(context: common.Context): Promise<string> {
    const picker = new photoAccessHelper.PhotoViewPicker()
    const result = await picker.select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE,
      maxSelectNumber: 1
    })
    if (result.photoUris.length === 0) {
      return ''
    }
    return await DecorationMedia.copyToSandbox(context, result.photoUris[0], 'video')
  }

  /**
   * 把相册 / 外部 URI 复制进沙箱持久化目录，返回沙箱裸路径。
   * 已经是沙箱裸路径时原样返回；失败时退回原 URI，保证至少本次会话还能用。
   */
  static async copyToSandbox(context: common.Context, uri: string, fallbackKind: string): Promise<string> {
    const source = (uri || '').trim()
    if (source.length === 0) { return '' }
    if (!DecorationMedia.isUri(source)) { return source }
    try {
      const dir = DecorationMedia.ensureDir(context)
      const ext = DecorationMedia.extensionOf(source, fallbackKind)
      const dest = `${dir}/deco_${Date.now()}_${Math.floor(Math.random() * 1000)}${ext}`
      const bytes = await DecorationMedia.readAll(source)
      await DecorationMedia.writeAll(dest, bytes)
      return dest
    } catch (error) {
      console.error(`[DecorationMedia] copyToSandbox failed: ${JSON.stringify(error)}`)
      return source
    }
  }

  /**
   * 裁剪页专用：把任何来源（相册 URI / 外部 file:// / 裸路径）落成 cacheDir 下的
   * 普通沙箱文件。返回的一定是可直接 ImageKit 解码的路径，失败时抛出异常由页面提示。
   */
  static async materialize(context: common.Context, source: string): Promise<string> {
    const text = (source || '').trim()
    if (text.length === 0) { return '' }
    if (!DecorationMedia.isUri(text)) { return text }
    const dir = `${context.cacheDir}/crop_src`
    try {
      fileIo.mkdirSync(dir, true)
    } catch (_error) {
    }
    const ext = DecorationMedia.extensionOf(text, 'image')
    const dest = `${dir}/src_${Date.now()}_${Math.floor(Math.random() * 1000)}${ext}`
    const bytes = await DecorationMedia.readAll(text)
    await DecorationMedia.writeAll(dest, bytes)
    return dest
  }

  /**
   * Image 组件用的地址：沙箱裸路径要转成 file:// URI，网络图与已经是 URI 的原样返回。
   * 装扮路径持久化时仍存裸路径，只在渲染时调这个方法。
   */
  static displayUri(path: string): string {
    const text = (path || '').trim()
    if (text.length === 0) { return '' }
    if (/^(https?:\/\/|file:\/\/|content:\/\/|data:)/i.test(text)) { return text }
    if (!text.startsWith('/')) { return text }
    try {
      return fileUri.getUriFromPath(text)
    } catch (_error) {
      return text
    }
  }

  /** 循环读，保证拿到完整字节（相册 URI 走 fd，不能用 copyFileSync）。 */
  private static async readAll(source: string): Promise<ArrayBuffer> {
    const file = await fileIo.open(source, fileIo.OpenMode.READ_ONLY)
    try {
      const size = (await fileIo.stat(file.fd)).size
      const buffer = new ArrayBuffer(size)
      const view = new Uint8Array(buffer)
      let offset = 0
      while (offset < size) {
        const want = Math.min(DecorationMedia.CHUNK, size - offset)
        const chunk = new ArrayBuffer(want)
        const count = await fileIo.read(file.fd, chunk, { offset: offset, length: want })
        if (count <= 0) { break }
        view.set(new Uint8Array(chunk, 0, count), offset)
        offset += count
      }
      return offset === size ? buffer : buffer.slice(0, offset)
    } finally {
      await fileIo.close(file)
    }
  }

  /** 循环写，避免大图一次性 write 没写完。 */
  private static async writeAll(dest: string, data: ArrayBuffer): Promise<void> {
    const file = await fileIo.open(dest,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      let offset = 0
      while (offset < data.byteLength) {
        const end = Math.min(data.byteLength, offset + DecorationMedia.CHUNK)
        const chunk = data.slice(offset, end)
        const count = await fileIo.write(file.fd, chunk)
        if (count <= 0) { break }
        offset += count
      }
    } finally {
      await fileIo.close(file)
    }
  }

  private static isUri(value: string): boolean {
    return /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(value)
  }

  private static ensureDir(context: common.Context): string {
    const dir = `${context.filesDir}/${DecorationMedia.DIR}`
    // 目录不存在时 mkdirSync 会抛异常，不能先用 accessSync 判断（它也会抛）。
    try {
      fileIo.mkdirSync(dir, true)
    } catch (_error) {
    }
    return dir
  }

  /** 把裁剪/编码后的图片字节写入沙箱，返回持久路径。 */
  static saveCropped(context: common.Context, data: ArrayBuffer, ext: string = '.png'): string {
    const dir = DecorationMedia.ensureDir(context)
    const dest = `${dir}/crop_${Date.now()}_${Math.floor(Math.random() * 1000)}${ext}`
    const file = fileIo.openSync(dest,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      const bytes = new Uint8Array(data)
      let offset = 0
      while (offset < bytes.length) {
        const end = Math.min(bytes.length, offset + DecorationMedia.CHUNK)
        const chunk = data.slice(offset, end)
        const count = fileIo.writeSync(file.fd, chunk)
        if (count <= 0) { break }
        offset += count
      }
    } finally {
      fileIo.closeSync(file)
    }
    return dest
  }

  /** 丢弃一次不满意的裁剪结果，避免沙箱里堆积中间文件。 */
  static removeFile(path: string): void {
    if (!path) { return }
    // 只清理本应用沙箱里的普通文件；绝不能对相册 URI 执行 unlink
    if (!path.startsWith('/')) { return }
    try {
      fileIo.unlinkSync(path)
    } catch (_error) {
      // 临时文件清理失败不影响主流程
    }
  }

  private static extensionOf(uri: string, fallbackKind: string): string {
    const match = uri.match(/\.(png|jpe?g|webp|gif|bmp|heic|mp4|mov|m4v)(?:\?|$)/i)
    if (match) {
      return `.${match[1].toLowerCase()}`
    }
    return fallbackKind === 'video' ? '.mp4' : '.jpg'
  }
}
