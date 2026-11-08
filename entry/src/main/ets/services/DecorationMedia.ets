import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'

/**
 * 装扮素材的选择与落地。
 *
 * 相册返回的是临时 URI，重启后可能失效，所以选择后统一复制到应用沙箱
 * （filesDir/decoration/），只持久化沙箱路径，保证装扮长期有效。
 */
export class DecorationMedia {
  private static readonly DIR: string = 'decoration'

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
    return DecorationMedia.copyToSandbox(context, result.photoUris[0], 'image')
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
    return DecorationMedia.copyToSandbox(context, result.photoUris[0], 'video')
  }

  /** 把相册 URI 复制进沙箱，返回新路径；失败返回原 URI（至少本次会话可用）。 */
  static copyToSandbox(context: common.Context, uri: string, fallbackKind: string): string {
    try {
      const dir = `${context.filesDir}/${DecorationMedia.DIR}`
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir)
      }
      const ext = DecorationMedia.extensionOf(uri, fallbackKind)
      const dest = `${dir}/deco_${Date.now()}_${Math.floor(Math.random() * 1000)}${ext}`
      const source = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const target = fileIo.openSync(dest,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.copyFileSync(source.fd, target.fd)
      } finally {
        fileIo.closeSync(source)
        fileIo.closeSync(target)
      }
      return dest
    } catch (_error) {
      return uri
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
