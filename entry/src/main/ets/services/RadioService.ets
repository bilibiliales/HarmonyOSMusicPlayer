import { ApiClient } from './ApiClient'
import { ApiParam, DjDetailResponse, DjRadioItem, SongUrlResponse, mapApiSong } from '../models/api'
import { ProgramItem } from '../models/home'
import { songItemType } from '../models/music'
import { DjProgramDetailResponse, DjProgramTopResponse, RadioCategoriesResponse, RadioCategory,
  RadioProgramsResponse, RadioStationPage, RadioStationsResponse } from '../models/radio'
import { SongAudioResource } from './SongQualityService'

export class RadioService {
  static readonly PAGE_SIZE: number = 20

  static async categories(): Promise<RadioCategory[]> {
    const result = await ApiClient.get<RadioCategoriesResponse>('/dj/catelist')
    if (result.code !== 200) { throw new Error('电台分类加载失败') }
    return result.categories || []
  }

  static async stations(mode: string, category: number, offset: number): Promise<RadioStationPage> {
    let endpoint = '/dj/recommend'
    const params: ApiParam[] = [
      { key: 'limit', value: String(RadioService.PAGE_SIZE) }, { key: 'offset', value: String(offset) }
    ]
    if (category > 0) {
      endpoint = mode === 'recommend' ? '/dj/recommend/type' : '/dj/radio/hot'
      params.push({ key: mode === 'recommend' ? 'type' : 'cateId', value: String(category) })
    } else if (mode === 'new') {
      endpoint = '/dj/toplist'
      params.push({ key: 'type', value: 'new' })
    } else if (mode === 'hot') { endpoint = '/dj/hot' }
    const result = await ApiClient.get<RadioStationsResponse>(endpoint, params)
    if (result.code !== 200) { throw new Error('电台列表加载失败') }
    const items = result.djRadios || result.toplist || []
    // Recommendation endpoints return a complete collection; they do not support offset.
    return { items: items, more: mode !== 'recommend' && (result.hasMore ?? items.length >= RadioService.PAGE_SIZE) }
  }

  static async recommendedPrograms(): Promise<ProgramItem[]> {
    const result = await ApiClient.get<RadioProgramsResponse>('/program/recommend', [{ key: 'limit', value: '6' }])
    if (result.code !== 200) { throw new Error('精选节目加载失败') }
    return result.programs || []
  }

  static async rankedPrograms(offset: number): Promise<RadioProgramsResponse> {
    const result = await ApiClient.get<DjProgramTopResponse>('/dj/program/toplist', [
      { key: 'limit', value: String(RadioService.PAGE_SIZE) }, { key: 'offset', value: String(offset) }
    ])
    if (result.code !== 200) { throw new Error('节目榜加载失败') }
    const items = (result.toplist || []).map((item) => item.program)
    return { code: 200, programs: items, more: items.length >= RadioService.PAGE_SIZE }
  }

  static async detail(id: string): Promise<DjRadioItem> {
    const result = await ApiClient.get<DjDetailResponse>('/dj/detail', [{ key: 'rid', value: id }])
    const station = result.data || result.djRadio
    if (result.code !== 200 || !station || String(station.id) !== id) { throw new Error('电台详情加载失败') }
    return station
  }

  static async programs(id: string, offset: number, asc: boolean): Promise<RadioProgramsResponse> {
    const result = await ApiClient.get<RadioProgramsResponse>('/dj/program', [
      { key: 'rid', value: id }, { key: 'limit', value: String(RadioService.PAGE_SIZE) },
      { key: 'offset', value: String(offset) }, { key: 'asc', value: String(asc) }
    ])
    if (result.code !== 200) { throw new Error('节目列表加载失败') }
    return result
  }

  static async program(id: string): Promise<ProgramItem> {
    const result = await ApiClient.get<DjProgramDetailResponse>('/dj/program/detail', [{ key: 'id', value: id }])
    if (result.code !== 200 || !result.program || String(result.program.id) !== id) { throw new Error('节目详情加载失败') }
    return result.program
  }

  static cover(program: ProgramItem): string {
    return program.coverUrl || program.radio?.picUrl || program.mainSong?.al?.picUrl || ''
  }

  static author(program: ProgramItem): string {
    return program.dj?.brand || program.dj?.nickname || program.radio?.name || '电台节目'
  }

  static song(program: ProgramItem): songItemType | undefined {
    const trackId = program.mainTrackId || program.mainSong?.id
    if (!trackId || trackId <= 0) { return undefined }
    const song: songItemType = program.mainSong ? mapApiSong(program.mainSong) :
      { id: String(trackId), name: program.name, author: '', img: '', url: '' }
    song.id = String(trackId)
    song.programId = String(program.id)
    song.isVoice = true
    song.name = program.name || song.name
    song.author = RadioService.author(program)
    song.img = RadioService.cover(program) || song.img
    song.album = program.radio?.name || ''
    song.duration = program.duration || song.duration
    return song
  }

  static async audio(trackId: string): Promise<SongAudioResource> {
    // Programme IDs and audio track IDs differ. Old mp3Url values are no longer valid.
    const result = await ApiClient.get<SongUrlResponse>('/song/url', [
      { key: 'id', value: trackId }, { key: 'br', value: '320000' }
    ])
    const item = result.data?.find((audio) => String(audio.id) === trackId)
    if (result.code !== 200 || !item?.url) { throw new Error('该节目暂无可播放音源，或需要购买后收听') }
    return { url: item.url, requestedLevel: '', selectedLevel: '', actualLevel: item.level || '',
      size: item.size || 0, type: item.type || '', encodeType: '', trial: !!item.freeTrialInfo }
  }

  static count(value: number = 0): string {
    return value >= 10000 ? (value / 10000).toFixed(1) + '万' : String(value)
  }

  static duration(value: number = 0): string {
    const seconds = Math.floor(value / 1000)
    return Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0')
  }
}
