import { StylePageInfo, StyleProfessionalReview, StyleTag } from '../models/style'

export function styleReviewText(review?: StyleProfessionalReview): string {
  if (!review?.templateContent) { return '' }
  const pattern = review.pattern || {}
  return review.templateContent.replace(/\$\{([^}]+)\}/g, (_match: string, key: string): string => pattern[key]?.text || '')
}

export function styleTagId(type: string, id: string, url: string): number {
  let decoded = url
  for (let i = 0; i < 2; i++) { try { decoded = decodeURIComponent(decoded) } catch (_error) { break } }
  const match = /[?&#](?:tagId|musicTagId|styleId)=([0-9]+)/i.exec(decoded)
  if (match) { return Number(match[1]) }
  if (/STYLE|GENRE|MUSIC_TAG|MUSICTAG/i.test(type) && /^\d+$/.test(id)) { return Number(id) }
  return 0
}

export function findStyleByName(tags: StyleTag[], name: string): StyleTag | undefined {
  for (const tag of tags) {
    if (tag.tagName === name || tag.enName === name) { return tag }
    const child = findStyleByName(tag.childrenTags || [], name)
    if (child) { return child }
  }
  return undefined
}

// Keep the hierarchy intact; only first-level entries belong in the discovery grid.
export function styleRoots(tags: StyleTag[]): StyleTag[] {
  const roots: StyleTag[] = []
  for (const tag of tags) {
    if (tag.level === 1 || tag.level === undefined) {
      if (!roots.some((item: StyleTag) => item.tagId === tag.tagId)) { roots.push(tag) }
    }
  }
  return roots
}

export function stylePath(tags: StyleTag[], tagId: number): StyleTag[] {
  for (const tag of tags) {
    if (tag.tagId === tagId) { return [tag] }
    const children = stylePath(tag.childrenTags || [], tagId)
    if (children.length) { return [tag].concat(children) }
  }
  return []
}

// Searching a descendant must preserve its parents so selection still shows context.
export function filterStyleTree(tags: StyleTag[], query: string): StyleTag[] {
  const keyword = query.trim().toLowerCase()
  if (!keyword) { return tags }
  const matches: StyleTag[] = []
  for (const tag of tags) {
    if (tag.tagName.toLowerCase().includes(keyword) || (tag.enName || '').toLowerCase().includes(keyword)) {
      matches.push(tag)
    } else {
      const children = filterStyleTree(tag.childrenTags || [], keyword)
      if (children.length) {
        matches.push({
          tagId: tag.tagId, tagName: tag.tagName, enName: tag.enName, level: tag.level,
          childrenTags: children, picUrl: tag.picUrl, colorDeep: tag.colorDeep,
          colorShallow: tag.colorShallow, link: tag.link, showText: tag.showText, tabs: tag.tabs
        })
      }
    }
  }
  return matches
}

export function styleImageUrl(value: string | undefined): string {
  if (!value) { return '' }
  // Child styles may return a CDN-relative path instead of an absolute URL.
  if (value.startsWith('yyimgs/')) { return `https://p5.music.126.net/${value.slice(7)}` }
  return value.startsWith('http://') ? value.replace('http://', 'https://') : value
}

export function nextStyleCursor(page: StylePageInfo | undefined, requested: string, count: number): string | undefined {
  if (!page?.more || count === 0 || page.cursor === undefined || page.cursor === null) { return undefined }
  const returned = String(page.cursor)
  if (returned !== requested) { return returned }
  // Current servers echo the consumed offset (verified with cursor 0/1/2).
  // Other versions return the next cursor; preserve those tokens verbatim above.
  if (/^\d+$/.test(returned)) { return String(Number(returned) + count) }
  return undefined
}
