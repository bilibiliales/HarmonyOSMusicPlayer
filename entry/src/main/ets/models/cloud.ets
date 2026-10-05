import { ApiSong } from './api'

export interface CloudSong {
  songId: number
  songName?: string
  artist?: string
  album?: string
  fileName?: string
  fileSize?: number
  bitrate?: number
  addTime?: number
  simpleSong?: ApiSong
}

export interface CloudResponse {
  code: number
  message?: string
  msg?: string
  data?: CloudSong[]
  count?: number
  hasMore?: boolean
  size?: string
  maxSize?: string
}
