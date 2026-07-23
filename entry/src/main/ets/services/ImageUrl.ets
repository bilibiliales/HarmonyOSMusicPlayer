/**
 * 网易云图片 CDN 支持通过 param 返回指定尺寸的缩略图。
 * 列表中直接解码原图会让 ImageSource 的目标尺寸保持为 (0, 0)，
 * 4000px 图片单张就可能占用数十 MB 内存。
 */
export function resizeImageUrl(url: string, width: number, height: number): string {
  if (!url) {
    return url
  }
  const normalizedUrl = url.startsWith('yyimgs/') ? `https://p1.music.126.net/${url.substring(7)}` : url
  if (!normalizedUrl.includes('music.126.net')) {
    return normalizedUrl
  }
  const queryIndex = normalizedUrl.indexOf('?')
  const baseUrl = queryIndex >= 0 ? normalizedUrl.substring(0, queryIndex) : normalizedUrl
  return `${baseUrl}?param=${Math.max(1, Math.round(width))}y${Math.max(1, Math.round(height))}`
}
