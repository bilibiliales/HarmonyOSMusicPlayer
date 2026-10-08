import { http } from '@kit.NetworkKit'
import { media } from '@kit.MediaKit'
import { AudioMetadata } from './AudioMetadata'
import { NeteaseCloudUpload, CloudUploadToken } from './NeteaseCloudUpload'
import { CloudResponse, CloudSong } from '../models/cloud'
import { ApiParam, OperationResponse, mapApiSong, SongUrlResponse } from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from './ApiClient'
import { SongAudioResource } from './SongQualityService'

interface UploadTokenResponse { code: number; msg?: string; message?: string; data?: CloudUploadToken }

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

  async upload(name: string, data: ArrayBuffer, tags?: media.AVMetadata): Promise<void> {
    this.check()
    const md5 = await AudioMetadata.md5(data)
    this.check()
    const tokenBody: Record<string, string> = {
      'cookie': this.cookie, 'md5': md5, 'fileSize': data.byteLength.toString(), 'filename': name
    }
    let direct: NeteaseCloudUpload | undefined = undefined
    let token: UploadTokenResponse
    try {
      token = await ApiClient.postJson<UploadTokenResponse>('/cloud/upload/token', tokenBody)
      if (token.code === 404) { throw new Error('上传路由不存在 (404)') }
    } catch (error) {
      if (!(error instanceof Error) || !/\(404\)$/.test(error.message)) {
        throw new Error('获取上传凭证：' + (error instanceof Error ? error.message : '请求失败'))
      }
      console.info('[CloudUpload] API server upload route unavailable; using official upload flow')
      direct = new NeteaseCloudUpload(this.cookie)
      token = { code: 200, data: await direct.token(name, data.byteLength, md5) }
    }
    this.check()
    if (token.code !== 200 || !token.data) { throw new Error(token.msg || token.message || '获取云盘上传凭证失败') }
    const info = token.data
    if (typeof info.needUpload !== 'boolean' || !info.songId || !info.resourceId) {
      throw new Error('云盘上传凭证缺少歌曲或资源标识')
    }
    if (info.needUpload) {
      if (!info.uploadUrl || !/^https?:\/\//.test(info.uploadUrl) || !info.uploadToken) { throw new Error('云盘上传凭证不完整') }
      const client = http.createHttp()
      try {
        const response = await client.request(info.uploadUrl, {
          method: http.RequestMethod.POST,
          header: { 'x-nos-token': info.uploadToken, 'Content-MD5': md5, 'Content-Type': 'audio/mpeg' },
          extraData: data, connectTimeout: 15000, readTimeout: 300000,
          expectDataType: http.HttpDataType.STRING
        })
        if (response.responseCode < 200 || response.responseCode >= 300) { throw new Error('音频直传失败 (' + response.responseCode + ')') }
      } finally { client.destroy() }
    }
    this.check()
    if (direct) {
      await direct.complete(info, name, tags)
      this.check()
      return
    }
    const completeBody: Record<string, string> = {
      'cookie': this.cookie, 'songId': String(info.songId), 'resourceId': String(info.resourceId),
      'md5': info.md5 || md5, 'filename': name, 'song': tags?.title || name.replace(/\.[^.]+$/, ''),
      'artist': tags?.artist || '未知艺术家', 'album': tags?.album || '未知专辑'
    }
    let response: OperationResponse
    try {
      response = await ApiClient.postJson<OperationResponse>('/cloud/upload/complete', completeBody)
    } catch (error) {
      if (error instanceof Error && /\(404\)$/.test(error.message)) {
        await new NeteaseCloudUpload(this.cookie).complete(info, name, tags)
        this.check()
        return
      }
      throw new Error('导入云盘：' + (error instanceof Error ? error.message : '请求失败'))
    }
    this.check()
    if (response.code !== 200) { throw new Error(response.message || '云盘导入失败') }
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
