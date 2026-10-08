import { http } from '@kit.NetworkKit'
import { media } from '@kit.MediaKit'
import { ApiClient } from './ApiClient'
import { NeteaseDirectApi } from './NeteaseDirectApi'
import { WeApiCrypto } from './WeApiCrypto'

export interface CloudUploadToken {
  needUpload: boolean
  uploadUrl?: string
  uploadToken?: string
  songId: string | number
  resourceId: string | number
  md5: string
}
interface CloudResult { code: number; msg?: string; message?: string; songId?: string | number }
interface CloudCheck extends CloudResult { needUpload?: boolean }
interface NosToken { objectKey: string; token: string; resourceId: string | number }
interface NosResult extends CloudResult { result?: NosToken }
interface NosServers { upload?: string[] }

// Mirrors module/cloud_upload_token.js and cloud_upload_complete.js when the API
// server has not deployed those routes. Login state still belongs to ApiClient.
export class NeteaseCloudUpload {
  private cookie: string
  constructor(cookie: string) { this.cookie = cookie }

  private check(): void {
    if (!this.cookie || this.cookie !== ApiClient.cookie) { throw new Error('登录账号已变化，请重新上传') }
  }

  private async official<T>(path: string, payload: Record<string, Object>): Promise<T> {
    this.check()
    const csrf = NeteaseDirectApi.cookieValue(this.cookie, '__csrf')
    if (!NeteaseDirectApi.cookieValue(this.cookie, 'MUSIC_U')) { throw new Error('缺少网易登录凭据，请重新登录') }
    payload['csrf_token'] = csrf
    const encrypted = await WeApiCrypto.encrypt(JSON.stringify(payload))
    this.check()
    const request = http.createHttp()
    try {
      const response = await request.request('https://music.163.com/weapi' + path + '?csrf_token=' + encodeURIComponent(csrf), {
        method: http.RequestMethod.POST,
        header: { 'Cookie': this.cookie, 'Referer': 'https://music.163.com/',
          'Origin': 'https://music.163.com', 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: 'params=' + encodeURIComponent(encrypted.params) + '&encSecKey=' + encodeURIComponent(encrypted.encSecKey),
        expectDataType: http.HttpDataType.STRING, usingCache: false, maxRedirects: 0,
        connectTimeout: 10000, readTimeout: 30000
      })
      this.check()
      if (response.responseCode !== 200) { throw new Error('网易云盘 ' + path + ' 请求失败 (' + response.responseCode + ')') }
      const result = JSON.parse(response.result as string) as CloudResult
      if (result.code !== 200) { throw new Error(result.message || result.msg || '网易云盘返回 ' + result.code) }
      return JSON.parse(response.result as string) as T
    } finally { request.destroy() }
  }

  async token(name: string, size: number, md5: string): Promise<CloudUploadToken> {
    const check = await this.official<CloudCheck>('/cloud/upload/check', {
      'bitrate': '999000', 'ext': '', 'length': size, 'md5': md5, 'songId': '0', 'version': 1
    })
    if (typeof check.needUpload !== 'boolean' || check.songId === undefined) { throw new Error('网易云盘校验未返回有效歌曲标识') }
    const bucket = 'jd-musicrep-privatecloud-audio-public'
    const token = await this.official<NosResult>('/nos/token/alloc', {
      'bucket': bucket, 'ext': name.split('.').pop() || 'mp3',
      'filename': name.replace(/\.[^.]+$/, '').replace(/\s/g, '').replace(/\./g, '_'),
      'local': false, 'nos_product': 3, 'type': 'audio', 'md5': md5
    })
    const result = token.result
    if (!result?.objectKey || !result.token || !result.resourceId) { throw new Error('网易未返回完整上传凭证') }
    const ticket: CloudUploadToken = { needUpload: check.needUpload, songId: check.songId,
      resourceId: result.resourceId, md5: md5, uploadToken: result.token }
    if (!check.needUpload) { return ticket }
    const request = http.createHttp()
    try {
      const response = await request.request('https://wanproxy.127.net/lbs?version=1.0&bucketname=' + bucket, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000, readTimeout: 10000, usingCache: false
      })
      this.check()
      if (response.responseCode !== 200) { throw new Error('获取网易上传服务器失败 (' + response.responseCode + ')') }
      const servers = JSON.parse(response.result as string) as NosServers
      const server = servers.upload?.[0]
      if (!server || !/^https?:\/\//.test(server)) { throw new Error('网易未返回有效上传服务器') }
      ticket.uploadUrl = server.replace(/\/$/, '') + '/' + bucket + '/' +
        encodeURIComponent(result.objectKey) + '?offset=0&complete=true&version=1.0'
      return ticket
    } finally { request.destroy() }
  }

  async complete(ticket: CloudUploadToken, name: string, tags?: media.AVMetadata): Promise<void> {
    const result = await this.official<CloudResult>('/upload/cloud/info/v2', {
      'md5': ticket.md5, 'songid': ticket.songId, 'filename': name,
      'song': tags?.title || name.replace(/\.[^.]+$/, ''), 'album': tags?.album || '未知专辑',
      'artist': tags?.artist || '未知艺术家', 'bitrate': '999000', 'resourceId': ticket.resourceId
    })
    if (!result.songId) { throw new Error('网易未返回云盘导入歌曲标识') }
    await this.official<CloudResult>('/cloud/pub/v2', { 'songid': result.songId })
  }
}
