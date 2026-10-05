import { CloudResponse, CloudSong } from '../models/cloud'
import { ApiParam, OperationResponse, mapApiSong, SongUrlResponse } from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from './ApiClient'
import { SongAudioResource } from './SongQualityService'

export class CloudService {
  private cookie: string
  readonly uid: string
  constructor(uid: string) { this.uid = uid; this.cookie = ApiClient.cookie }

  check(): void {
    if (!this.uid || !this.cookie || ApiClient.cookie !== this.cookie) { throw new Error('登录状态已改变，请重新进入云盘') }
  }

  private async get<T>(path: string, params: ApiParam[] = []): Promise<T> {
    this.check()
    const result = await ApiClient.get<T>(path, params.concat([{ key: 'timestamp', value: Date.now().toString() }]))
    this.check()
    return result
  }

  async list(offset: number): Promise<CloudResponse> {
    const response = await this.get<CloudResponse>('/user/cloud', [
      { key: 'limit', value: '200' }, { key: 'offset', value: offset.toString() }])
    if (response.code !== 200) { throw new Error(response.message || response.msg || '云盘加载失败') }
    return response
  }

  async detail(id: string): Promise<CloudSong> {
    const response = await this.get<CloudResponse>('/user/cloud/detail', [{ key: 'id', value: id }])
    const song = response.data?.find((item: CloudSong) => String(item.songId) === id)
    if (response.code !== 200 || !song) { throw new Error(response.message || '云盘歌曲详情加载失败') }
    return song
  }

  async remove(ids: string[]): Promise<void> {
    if (!ids.length) { throw new Error('请先选择歌曲') }
    const response = await this.get<OperationResponse>('/user/cloud/del', [{ key: 'id', value: ids.join(',') }])
    if (response.code !== 200) { throw new Error(response.message || '删除失败') }
  }

  async match(id: string, matchedId: string): Promise<void> {
    const response = await this.get<OperationResponse>('/cloud/match', [
      { key: 'uid', value: this.uid }, { key: 'sid', value: id }, { key: 'asid', value: matchedId }])
    if (response.code !== 200) { throw new Error(response.message || '纠偏失败') }
  }

  async upload(name: string, data: ArrayBuffer): Promise<void> {
    this.check()
    const response = await ApiClient.upload<OperationResponse>('/cloud', [{ key: 'cookie', value: this.cookie }],
      'songFile', name, data, 'audio/mpeg', 300000)
    this.check()
    if (response.code !== 200) { throw new Error(response.message || '上传失败') }
  }

  static song(item: CloudSong): songItemType {
    const song: songItemType = item.simpleSong ? mapApiSong(item.simpleSong) :
      { id: '', name: '', author: '', img: '', url: '' }
    song.id = String(item.songId)
    song.isCloud = true
    song.name = song.name || item.songName || item.fileName || '未命名歌曲'
    song.author = song.author || item.artist || '未知歌手'
    song.album = song.album || item.album || ''
    return song
  }

  static async playback(id: string): Promise<SongAudioResource> {
    if (!ApiClient.cookie) { throw new Error('登录后才能播放云盘歌曲') }
    // Unmatched uploads have no song/music/detail entry; use the cloud-supported URL endpoint.
    const response = await ApiClient.get<SongUrlResponse>('/song/url', [
      { key: 'id', value: id }, { key: 'br', value: '999000' }, { key: 'timestamp', value: Date.now().toString() }])
    const item = response.data?.find((song) => String(song.id) === id)
    if (response.code !== 200 || !item?.url) { throw new Error('暂无可播放的云盘音源') }
    return { url: item.url, requestedLevel: '', selectedLevel: '', actualLevel: item.level || '',
      type: item.type || '', encodeType: '', size: item.size || 0, trial: !!item.freeTrialInfo }
  }
}
