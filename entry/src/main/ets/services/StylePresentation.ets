import { StyleProfessionalReview, StyleTag } from '../models/style'

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
