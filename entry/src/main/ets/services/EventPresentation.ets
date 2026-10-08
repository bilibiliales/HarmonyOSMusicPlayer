import {
  AlbumPageParam, EventForwardData, EventJsonData, EventPicture, mapApiSong, mapPlaylist,
  MvPlayerPageParam, SharePageParam, UserEventItem
} from '../models/api'
import { playlistType, songItemType } from '../models/music'

export interface EventResourceView {
  kind: string
  title: string
  subtitle: string
  image: string
  song?: songItemType
  playlist?: playlistType
  album?: AlbumPageParam
  mv?: MvPlayerPageParam
}

export class EventPresentation {
  static empty(): UserEventItem {
    return { id: 0, json: '', user: { userId: 0, nickname: '', avatarUrl: '', followed: false, mutual: false },
      info: { commentCount: 0, likedCount: 0, shareCount: 0 } }
  }

  static copy(item: UserEventItem): UserEventItem {
    return {
      id: item.id, type: item.type, eventTime: item.eventTime, showTime: item.showTime,
      json: item.json, user: item.user, pics: item.pics, actName: item.actName,
      info: { commentCount: item.info.commentCount, likedCount: item.info.likedCount,
        shareCount: item.info.shareCount, liked: item.info.liked, threadId: item.info.threadId }
    }
  }

  static changeList(events: UserEventItem[], changed: UserEventItem, deleted: boolean): UserEventItem[] {
    return events.filter((event: UserEventItem) => !deleted || event.id !== changed.id)
      .map((event: UserEventItem) => EventPresentation.change(event, changed, deleted))
  }

  static change(event: UserEventItem, changed: UserEventItem, deleted: boolean): UserEventItem {
    if (event.id === changed.id) { return EventPresentation.copy(changed) }
    const data = EventPresentation.data(event)
    if (!data.event) { return event }
    if (data.event.id === changed.id && deleted) {
      const removed: EventJsonData = { msg: '原动态已删除' }
      data.event = { json: JSON.stringify(removed) }
      const result = EventPresentation.copy(event)
      result.json = JSON.stringify(data)
      return result
    }
    const source = EventPresentation.source(data.event)
    const updated = EventPresentation.change(source, changed, deleted)
    if (updated === source) { return event }
    data.event = { id: updated.id, type: updated.type, eventTime: updated.eventTime,
      showTime: updated.showTime, json: updated.json, user: updated.user, info: updated.info,
      pics: updated.pics, actName: updated.actName }
    const result = EventPresentation.copy(event)
    result.json = JSON.stringify(data)
    return result
  }

  static data(item: UserEventItem): EventJsonData {
    try { return JSON.parse(item.json) as EventJsonData } catch (_error) { return {} }
  }

  static content(item: UserEventItem): string {
    const data = EventPresentation.data(item)
    return data.msg || data.title || item.actName || '分享了一条动态'
  }

  static picture(picture: EventPicture): string {
    return picture.originUrl || picture.rectangleUrl || picture.pcSquareUrl || picture.squareUrl || ''
  }

  static time(value: number): string {
    if (!value) { return '' }
    const elapsed = Math.max(0, Date.now() - value)
    if (elapsed < 60000) { return '刚刚' }
    if (elapsed < 3600000) { return Math.floor(elapsed / 60000) + '分钟前' }
    if (elapsed < 86400000) { return Math.floor(elapsed / 3600000) + '小时前' }
    if (elapsed < 604800000) { return Math.floor(elapsed / 86400000) + '天前' }
    const date = new Date(value)
    return (date.getMonth() + 1) + '-' + date.getDate()
  }

  static source(source: EventForwardData): UserEventItem {
    return { id: source.id || 0, json: source.json || '', user: source.user || EventPresentation.empty().user,
      info: source.info || EventPresentation.empty().info, pics: source.pics, type: source.type,
      eventTime: source.eventTime, showTime: source.showTime, actName: source.actName }
  }

  static share(item: UserEventItem): SharePageParam {
    return { type: 'event', id: item.id.toString(), eventUserId: item.user.userId.toString(),
      name: EventPresentation.content(item).slice(0, 100), author: item.user.nickname,
      img: item.pics?.length ? EventPresentation.picture(item.pics[0]) :
        EventPresentation.resource(item).image || item.user.avatarUrl }
  }

  static resource(item: UserEventItem): EventResourceView {
    const data = EventPresentation.data(item)
    if (data.song) {
      const song = mapApiSong(data.song)
      return { kind: '歌曲', title: song.name, subtitle: song.author, image: song.img, song: song }
    }
    if (data.playlist) {
      const playlist = mapPlaylist(data.playlist)
      return { kind: '歌单', title: playlist.name, subtitle: playlist.creator, image: playlist.cover, playlist: playlist }
    }
    if (data.album) {
      const album: AlbumPageParam = { id: String(data.album.id || ''), name: data.album.name || '专辑',
        picUrl: data.album.picUrl || '', artist: (data.album.artists || (data.album.artist ? [data.album.artist] : []))
          .map((artist) => artist.name).join(' / ') }
      return { kind: '专辑', title: album.name || '专辑', subtitle: album.artist || '', image: album.picUrl || '', album: album }
    }
    if (data.mv) {
      const mv: MvPlayerPageParam = { id: String(data.mv.id || ''), name: data.mv.name || 'MV',
        cover: data.mv.imgurl16v9 || data.mv.imgurl || '', artistName: data.mv.artistName || '',
        duration: data.mv.duration, playCount: data.mv.playCount }
      return { kind: 'MV', title: mv.name, subtitle: mv.artistName || '', image: mv.cover || '', mv: mv }
    }
    if (data.video) {
      return { kind: '视频', title: data.video.title || '视频', subtitle: data.video.creator?.nickname || '',
        image: data.video.coverUrl || '' }
    }
    const resource = data.program || data.djRadio || data.resource
    return { kind: data.program ? '播客节目' : data.djRadio ? '播客' : '分享内容',
      title: resource?.name || resource?.title || '', subtitle: resource?.description || '',
      image: resource?.picUrl || resource?.coverUrl || '' }
  }
}
