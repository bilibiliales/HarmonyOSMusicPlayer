import { SettingsReadback, UserSettings, UserSettingsPatch, UserSettingsResponse } from '../models/userSettings'
import { ApiClient } from './ApiClient'
import { NeteaseDirectApi } from './NeteaseDirectApi'

export class UserSettingsService {
  static async read(userId: string): Promise<UserSettings> {
    const cookie = ApiClient.cookie
    if (!cookie || !userId) { throw new Error('请先登录') }
    const response = await ApiClient.get<UserSettingsResponse>('/setting', [
      { key: 'timestamp', value: Date.now().toString() }
    ])
    if (cookie !== ApiClient.cookie) { throw new Error('登录账号已变化，请重新加载设置') }
    if (response.code !== 200 || !response.setting) {
      throw new Error(response.message || response.msg || '隐私设置读取失败')
    }
    const responseUserId = response.setting['userId']
    if (responseUserId !== undefined && String(responseUserId) !== userId) {
      throw new Error('返回的设置不属于当前账号，请重新登录')
    }
    // Retain every raw field, including unverified numeric enums and null values.
    return response.setting
  }

  static async updateAndRead(userId: string, patch: UserSettingsPatch): Promise<SettingsReadback> {
    const cookie = ApiClient.cookie
    let updateError = ''
    try { await NeteaseDirectApi.updateUserSettings(patch) }
    catch (error) { updateError = error instanceof Error ? error.message : '设置修改失败' }
    if (cookie !== ApiClient.cookie) { throw new Error('登录账号已变化，请重新加载设置') }
    try {
      // Read after every attempted mutation, including ambiguous network failures.
      const settings = await UserSettingsService.read(userId)
      const matches = Object.keys(patch).every((key: string) => settings[key] === patch[key])
      return { settings: settings, confirmed: !updateError && matches,
        message: updateError || (matches ? '隐私设置已更新' : '网易返回的设置尚未变更，已显示实际值') }
    } catch (_error) {
      return { confirmed: false, message: updateError || '修改请求已提交，但回读失败，请重新读取确认' }
    }
  }
}
