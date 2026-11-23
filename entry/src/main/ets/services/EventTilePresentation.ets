import { UserEventItem } from '../models/api'
import { EventPresentation } from './EventPresentation'

export interface EventTileMedia {
  image: string
  ratio: number
  text: string
  video: boolean
  pictureCount: number
}

/** 瀑布流卡片只展示内容预览；转发沿用源动态的图片、歌曲封面或文字。 */
export class EventTilePresentation {
  static media(item: UserEventItem, depth: number = 0): EventTileMedia {
    const data = EventPresentation.data(item)
    const picture = item.pics?.[0]
    const pictureUrl = picture ? EventPresentation.picture(picture) : ''
    const resource = EventPresentation.resource(item)
    if (pictureUrl) {
      return { image: pictureUrl, ratio: picture?.width && picture?.height ? picture.width / picture.height : 1,
        text: EventPresentation.content(item), video: false, pictureCount: item.pics?.length || 0 }
    }
    if (resource.image) {
      return { image: resource.image, ratio: data.mv || data.video ? 16 / 9 : 1,
        text: resource.title, video: !!data.mv || !!data.video, pictureCount: 0 }
    }
    if (data.event && depth < 6) { return EventTilePresentation.media(EventPresentation.source(data.event), depth + 1) }
    return { image: '', ratio: 1, text: data.msg || data.title || resource.title || item.actName || '分享了一条动态',
      video: false, pictureCount: 0 }
  }

  static title(item: UserEventItem): string {
    const data = EventPresentation.data(item)
    return data.msg || data.title || item.actName || EventPresentation.resource(item).title ||
      (data.event ? '转发动态' : '分享了一条动态')
  }

  private static lines(text: string, width: number, fontSize: number, max: number): number {
    const perLine = Math.max(1, Math.floor(width / fontSize))
    let lineCount = 1
    let units = 0
    for (let i = 0; i < text.length; i++) {
      if (text[i] === '\n') { lineCount++; units = 0 }
      else {
        units += text.charCodeAt(i) > 255 ? 1 : 0.55
        if (units > perLine) { lineCount++; units = 1 }
      }
      if (lineCount >= max) { return max }
    }
    return lineCount
  }

  static mediaHeight(item: UserEventItem, width: number): number {
    const media = EventTilePresentation.media(item)
    if (!media.image) { return Math.max(144, Math.min(222, 48 + 22 * EventTilePresentation.lines(media.text, width - 28, 15, 7))) }
    const ratio = Math.max(0.7, Math.min(1.6, media.ratio || 1))
    return Math.round(width / ratio)
  }

  static titleHeight(item: UserEventItem, width: number): number {
    if (!EventTilePresentation.media(item).image && !EventPresentation.data(item).event) { return 0 }
    return 16 + 18 * EventTilePresentation.lines(EventTilePresentation.title(item), width - 20, 13, 2)
  }

  static height(item: UserEventItem, width: number): number {
    return EventTilePresentation.mediaHeight(item, width) + EventTilePresentation.titleHeight(item, width) + 42
  }
}
