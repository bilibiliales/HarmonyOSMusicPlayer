import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { fileIo } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'

export class AudioMetadata {
  static async md5(data: ArrayBuffer): Promise<string> {
    const digest = cryptoFramework.createMd('MD5')
    await digest.update({ data: new Uint8Array(data) })
    const result = await digest.digest()
    return Array.from(result.data).map((value: number) => value.toString(16).padStart(2, '0')).join('')
  }

  static async fileHash(fd: number, size: number): Promise<string> {
    const digest = cryptoFramework.createMd('MD5')
    let offset = 0
    while (offset < size) {
      const buffer = new ArrayBuffer(Math.min(1048576, size - offset))
      const count = await fileIo.read(fd, buffer, { length: buffer.byteLength })
      if (count <= 0) { throw new Error('读取音频文件不完整') }
      await digest.update({ data: new Uint8Array(buffer, 0, count) })
      offset += count
    }
    const result = await digest.digest()
    return Array.from(result.data).map((value: number) => value.toString(16).padStart(2, '0')).join('')
  }

  static async read(fd: number, size: number): Promise<media.AVMetadata> {
    const extractor = await media.createAVMetadataExtractor()
    try {
      extractor.fdSrc = { fd: fd, offset: 0, length: size }
      return await extractor.fetchMetadata()
    } finally { await extractor.release() }
  }
}
