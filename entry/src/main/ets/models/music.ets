export interface songItemType {
  img: string
  name: string
  author: string
  url: string
  id: string
  duration?: number
  album?: string
  albumId?: string
  fee?: number
  liked?: boolean
  commentCount?: number
  recommendTag?: string
  artists?: SongArtist[]
}

export interface SongArtist {
  id: string
  name: string
  picUrl?: string
}

export enum PlayMode {
  LOOP = 0,
  SINGLE = 1,
  SHUFFLE = 2
}

export interface QualityOption {
  level: string
  title: string
  description: string
}

export const QUALITY_OPTIONS: QualityOption[] = [
  { level: 'standard', title: '标准', description: '128 kbps · 更省流量' },
  { level: 'higher', title: '较高', description: '192 kbps' },
  { level: 'exhigh', title: '极高', description: '320 kbps' },
  { level: 'lossless', title: '无损', description: 'FLAC' },
  { level: 'hires', title: 'Hi-Res', description: '高解析度无损' }
]

export interface recommendListType {
  img: string
  title: string
  count:string
}
export interface recommendDailyType {
  img: string
  title: string
  type:string
  top:string
  bottom: string
}
export interface favoriteListType {
  name:string
  nickName:string
  avatar:ResourceStr
  songs:songItemType[]
}
export interface momentListType {
  author:string
  avatar:string
  content:string
  comment:number
  like:number
  song:songItemType
}

// 发现页 - Banner轮播数据（预留API：/homepage/block/page HOMEPAGE_BANNER）
export interface findBannerType {
  pic: string       // 图片URL
  title: string     // 类型标题（歌单/独家策划等）
  targetId: number  // 目标ID
  targetType: number // 目标类型
}

// 发现页 - 圆形图标入口数据（预留API：/homepage/block/page HOMEPAGE_BLOCK_OLD_DRAGON_BALL）
export interface findDragonBallType {
  title: string     // 入口名称（每日推荐/私人FM等）
  imageUrl: string  // 图标URL
  action: string    // 跳转动作
}
export class songItemTypeModel implements songItemType {
  img: string = ''
  name: string = ''
  author: string = ''
  url: string = ''
  id: string = ''
  duration: number = 0
  album: string = ''
  albumId: string = ''
  fee: number = 0
  liked: boolean = false
  commentCount: number = 0

  constructor(model: songItemType) {
    this.img = model.img
    this.name = model.name
    this.author = model.author
    this.url = model.url
    this.id = model.id
    this.duration = model.duration || 0
    this.album = model.album || ''
    this.albumId = model.albumId || ''
    this.fee = model.fee || 0
    this.liked = model.liked || false
    this.commentCount = model.commentCount || 0
  }
}
export class recommendListTypeModel implements recommendListType {
  img: string = ''
  title: string = ''
  count: string = ''

  constructor(model: recommendListType) {
    this.img = model.img
    this.title = model.title
    this.count = model.count
  }
}
export class recommendDailyTypeModel implements recommendDailyType {
  img: string = ''
  title: string = ''
  type: string = ''
  top: string = ''
  bottom: string = ''

  constructor(model: recommendDailyType) {
    this.img = model.img
    this.title = model.title
    this.type = model.type
    this.top = model.top
    this.bottom = model.bottom
  }
}
export class favoriteListTypeModel implements favoriteListType {
  name: string = ''
  nickName: string = ''
  avatar: ResourceStr = ''
  songs: songItemType[] = []

  constructor(model: favoriteListType) {
    this.name = model.name
    this.nickName = model.nickName
    this.avatar = model.avatar
    this.songs = model.songs
  }
}
export class momentListTypeModel implements momentListType {
  author: string = ''
  avatar: string = ''
  content: string = ''
  comment: number = 0
  like: number = 0
  song: songItemType = new songItemTypeModel({} as songItemType)

  constructor(model: momentListType) {
    this.author = model.author
    this.avatar = model.avatar
    this.content = model.content
    this.comment = model.comment
    this.like = model.like
    this.song = model.song
  }
}

// 我的页面 - 歌单数据（预留API：/user/playlist）
export interface playlistType {
  id: string
  name: string
  cover: string
  count: number      // 歌曲数量
  creator: string    // 创建者
  isLiked?: boolean  // 是否为我喜欢的音乐
  creatorId?: string
  description?: string
  tags?: string[]
  privacy?: number
  onChanged?: () => void
}

export interface CommentUser {
  nickname: string
  avatarUrl: string
}

export interface MusicComment {
  commentId: string
  content: string
  likedCount: number
  liked: boolean
  timeStr: string
  user: CommentUser
}
