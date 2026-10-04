import { http } from '@kit.NetworkKit'
import { UserSettingsPatch, UserSettingsUpdateResponse } from '../models/userSettings'
import { ApiClient } from './ApiClient'
import { WeApiCrypto } from './WeApiCrypto'

export class NeteaseDirectApi {
  private static readonly SETTING_URL: string = 'https://music.163.com/weapi/user/setting/update'

  static cookieValue(cookie: string, name: string): string {
    for (const part of cookie.split(';')) {
      const separator = part.indexOf('=')
      if (separator >= 0 && part.substring(0, separator).trim() === name) {
        return part.substring(separator + 1).trim()
      }
    }
    return ''
  }

  static settingPayload(settings: UserSettingsPatch, csrf: string): UserSettingsPatch {
    const payload: UserSettingsPatch = {}
    const keys = Object.keys(settings)
    if (keys.length === 0) { throw new Error('没有需要修改的设置') }
    for (const key of keys) {
      if (!/^[a-zA-Z][a-zA-Z0-9_]*$/.test(key) || key === 'csrf_token' || key === 'cookie' || key === 'userId' ||
        key === '__proto__' || key === 'constructor' || key === 'prototype') {
        throw new Error('设置参数无效')
      }
      const value = settings[key]
      if ((typeof value !== 'boolean' && typeof value !== 'number' && typeof value !== 'string') ||
        (typeof value === 'number' && !Number.isFinite(value))) { throw new Error('设置值无效') }
      payload[key] = value
    }
    payload['csrf_token'] = csrf
    return payload
  }

  static async updateUserSettings(settings: UserSettingsPatch): Promise<UserSettingsUpdateResponse> {
    const cookie = ApiClient.cookie
    const csrf = NeteaseDirectApi.cookieValue(cookie, '__csrf')
    if (!NeteaseDirectApi.cookieValue(cookie, 'MUSIC_U') || !csrf) {
      throw new Error('当前登录态缺少 MUSIC_U 或 __csrf，请重新登录')
    }
    const payload = NeteaseDirectApi.settingPayload(settings, csrf)
    const encrypted = await WeApiCrypto.encrypt(JSON.stringify(payload))
    if (cookie !== ApiClient.cookie) { throw new Error('登录账号已变化，请重试') }
    const request = http.createHttp()
    try {
      const response = await request.request(`${NeteaseDirectApi.SETTING_URL}?csrf_token=${encodeURIComponent(csrf)}`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': cookie,
          'Referer': 'https://music.163.com/',
          'Origin': 'https://music.163.com'
        },
        extraData: `params=${encodeURIComponent(encrypted.params)}&encSecKey=${encodeURIComponent(encrypted.encSecKey)}`,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 20000,
        usingCache: false,
        maxRedirects: 0
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`网易设置更新请求失败 (${response.responseCode})`)
      }
      const result = JSON.parse(response.result as string) as UserSettingsUpdateResponse
      if (result.code !== 200) { throw new Error(result.message || result.msg || `网易未接受设置修改 (${result.code})`) }
      if (cookie !== ApiClient.cookie) { throw new Error('登录账号已变化，请重新加载设置') }
      return result
    } finally { request.destroy() }
  }
}
