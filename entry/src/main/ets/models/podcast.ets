import { ApiSong } from './api'
import { VoiceList } from '../services/VoiceUploadService'

export interface PodcastLibraryParam { section?: string }
export interface PodcastVoicesParam { list: VoiceList; owner: string }

export interface PodcastStation {
  id: string
  name: string
  cover: string
  subtitle: string
  subscribed?: boolean
  list?: VoiceList
}

export interface PodcastStationPage { items: PodcastStation[]; more: boolean }

export interface PodcastVoice {
  voiceId?: number | string
  id?: number | string
  voiceName?: string
  name?: string
  coverUrl?: string
  description?: string
  duration?: number
  displayStatus?: string
  mainTrackId?: number
  mainSong?: ApiSong
}

export interface PodcastVoicePage { items: PodcastVoice[]; more: boolean; total?: number }
