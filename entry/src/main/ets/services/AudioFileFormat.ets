export class AudioFileFormat {
  private static normalize(value: string): string {
    const format = value.toLowerCase().replace(/^\./, '')
    const supported = ['flac', 'mp3', 'm4a', 'mp4', 'aac', 'wav', 'ogg', 'opus', 'ape', 'ac3', 'eac3']
    return supported.indexOf(format) >= 0 ? format : ''
  }

  private static matches(bytes: Uint8Array, offset: number, value: string): boolean {
    if (bytes.length < offset + value.length) { return false }
    for (let i = 0; i < value.length; i++) {
      if (bytes[offset + i] !== value.charCodeAt(i)) { return false }
    }
    return true
  }

  static extension(url: string, type: string, encodeType: string, header: Uint8Array): string {
    const path = url.split(/[?#]/)[0]
    const name = path.substring(path.lastIndexOf('/') + 1)
    const dot = name.lastIndexOf('.')
    const fromUrl = dot >= 0 ? AudioFileFormat.normalize(name.substring(dot + 1)) : ''
    // The downloaded bytes outrank both URL suffix and sometimes-inaccurate API metadata.
    if (AudioFileFormat.matches(header, 0, 'fLaC')) { return 'flac' }
    if (AudioFileFormat.matches(header, 0, 'RIFF') && AudioFileFormat.matches(header, 8, 'WAVE')) { return 'wav' }
    if (AudioFileFormat.matches(header, 0, 'OggS')) { return fromUrl === 'opus' ? 'opus' : 'ogg' }
    if (AudioFileFormat.matches(header, 0, 'MAC ')) { return 'ape' }
    if (AudioFileFormat.matches(header, 4, 'ftyp')) { return fromUrl === 'mp4' ? 'mp4' : 'm4a' }
    if (AudioFileFormat.matches(header, 0, 'ID3')) { return 'mp3' }
    if (header.length >= 2 && header[0] === 0xff) {
      if ((header[1] & 0xf6) === 0xf0) { return 'aac' }
      if ((header[1] & 0xe0) === 0xe0 && (header[1] & 0x06) !== 0) { return 'mp3' }
    }
    if (header.length >= 6 && header[0] === 0x0b && header[1] === 0x77) {
      return (header[5] >> 3) > 10 ? 'eac3' : 'ac3'
    }
    if (header.length === 0 || AudioFileFormat.matches(header, 0, '<') || AudioFileFormat.matches(header, 0, '{')) {
      throw new Error('下载内容不是有效的音频文件')
    }
    // A .flac URL must not be renamed .mp3 merely because type is absent or incorrect.
    const extension = fromUrl || AudioFileFormat.normalize(encodeType) || AudioFileFormat.normalize(type)
    if (!extension) { throw new Error('无法识别原始音频格式，请重试') }
    return extension
  }
}
