import { ApiUser, LoginResponse, LoginStatusResponse } from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AppSettings } from '../services/AppSettings'

@Observed
export class AuthStore {
  loggedIn: boolean = false
  cookie: string = ''
  userId: string = ''
  nickname: string = '立即登录'
  avatarUrl: string = ''
  signature: string = ''

  applyLogin(response: LoginResponse): void {
    const cookie = response.cookie || ''
    if (cookie.length > 0) {
      this.cookie = cookie
      ApiClient.setCookie(this.cookie)
    }
    this.loggedIn = this.cookie.length > 0
    if (response.account) {
      this.userId = response.account.id.toString()
    }
    if (response.profile) {
      this.applyProfile(response.profile)
    } else {
      AppSettings.saveAuth(this)
    }
  }

  applyProfile(profile: ApiUser): void {
    if (profile.userId) {
      this.userId = profile.userId.toString()
    }
    this.nickname = profile.nickname || '网易云用户'
    this.avatarUrl = profile.avatarUrl || ''
    this.signature = profile.signature || ''
    this.loggedIn = true
    AppSettings.saveAuth(this)
  }

  async refreshAccount(): Promise<boolean> {
    if (this.cookie.length === 0) {
      return false
    }
    try {
      const response = await ApiClient.postJson<LoginStatusResponse>('/login/status', {})
      const data = response.data
      const profile = data?.profile
      if (profile) {
        this.applyProfile(profile)
        return true
      }
      this.loggedIn = false
      AppSettings.saveAuth(this)
      return false
    } catch (_error) {
      return false
    }
  }

  async logout(): Promise<void> {
    try {
      await ApiClient.postJson<LoginResponse>('/logout', {})
    } catch (_error) {
    }
    this.loggedIn = false
    this.cookie = ''
    this.userId = ''
    this.nickname = '立即登录'
    this.avatarUrl = ''
    this.signature = ''
    ApiClient.setCookie('')
    AppSettings.saveAuth(this)
  }
}
