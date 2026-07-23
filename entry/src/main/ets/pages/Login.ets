import { ApiClient } from '../services/ApiClient'
import { AppSettings } from '../services/AppSettings'
import { AuthStore } from '../stores/AuthStore'
import { CellphoneExistenceResponse, LoginResponse, LoginStatusResponse, QrCheckResponse, QrKeyResponse } from '../models/api'

interface LoginMethodItem {
  key: string
  title: string
}

@Component
export struct Login {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore

  @State currentMethod: string = 'password'
  @State phone: string = ''
  @State password: string = ''
  @State captcha: string = ''
  @State nickname: string = ''
  @State registrationMode: boolean = false
  @State loading: boolean = false
  @State message: string = ''
  @State qrKey: string = ''
  @State qrUrl: string = ''
  @State qrStatus: string = '正在生成二维码…'
  @State countdown: number = 0

  private qrTimer: number = -1
  private countdownTimer: number = -1
  private methods: LoginMethodItem[] = [
    { key: 'password', title: '手机密码' },
    { key: 'captcha', title: '短信验证码' },
    { key: 'qr', title: '扫码登录' }
  ]

  aboutToDisappear(): void {
    this.clearTimers()
  }

  private clearTimers(): void {
    if (this.qrTimer !== -1) {
      clearInterval(this.qrTimer)
      this.qrTimer = -1
    }
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer)
      this.countdownTimer = -1
    }
  }

  private validPhone(): boolean {
    if (!/^1\d{10}$/.test(this.phone.trim())) {
      this.message = '请输入正确的 11 位手机号码'
      return false
    }
    return true
  }

  private async phoneExists(): Promise<boolean> {
    const response = await ApiClient.get<CellphoneExistenceResponse>('/cellphone/existence/check', [
      { key: 'phone', value: this.phone.trim() },
      { key: 'countrycode', value: '86' }
    ])
    if (response.code !== 200) {
      throw new Error(response.message || '无法确认手机号状态')
    }
    if (response.exist === -1) {
      this.registrationMode = true
      this.message = '这个手机号尚未注册，请补充昵称和密码完成创建'
      return false
    }
    return true
  }

  private async passwordLogin(): Promise<void> {
    if (!this.validPhone() || !this.password) {
      if (!this.password) {
        this.message = '请输入登录密码'
      }
      return
    }
    this.loading = true
    this.message = ''
    try {
      if (!await this.phoneExists()) {
        return
      }
      const response = await ApiClient.get<LoginResponse>('/login/cellphone', [
        { key: 'phone', value: this.phone.trim() },
        { key: 'password', value: this.password }
      ])
      await this.finishLogin(response)
    } catch (error) {
      this.message = error instanceof Error ? error.message : '登录失败，请检查手机号或密码'
    } finally {
      this.loading = false
    }
  }

  private async captchaLogin(): Promise<void> {
    if (!this.validPhone() || !this.captcha.trim()) {
      if (!this.captcha.trim()) {
        this.message = '请输入短信验证码'
      }
      return
    }
    this.loading = true
    this.message = ''
    try {
      if (!await this.phoneExists()) {
        return
      }
      const response = await ApiClient.get<LoginResponse>('/login/cellphone', [
        { key: 'phone', value: this.phone.trim() },
        { key: 'captcha', value: this.captcha.trim() }
      ])
      await this.finishLogin(response)
    } catch (error) {
      this.message = error instanceof Error ? error.message : '验证码登录失败'
    } finally {
      this.loading = false
    }
  }

  private async finishLogin(response: LoginResponse, isQr: boolean = false): Promise<void> {
    if (!isQr && (response.code !== 200 || !response.cookie)) {
      this.message = response.message || response.msg || `登录失败 (${response.code})`
      return
    }
    if (response.cookie) {
      this.authStore.applyLogin(response)
    }
    try {
      const valid = await this.authStore.refreshAccount()
      if (!valid && isQr) {
        this.message = '已取得 Cookie，但登录状态验证失败'
      }
    } catch (_error) {
    }
    this.clearTimers()
    if (isQr) {
      this.pageStack.clear()
    } else {
      this.pageStack.pop()
    }
  }

  private startCountdown(): void {
    this.countdown = 60
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer)
    }
    this.countdownTimer = setInterval(() => {
      this.countdown -= 1
      if (this.countdown <= 0 && this.countdownTimer !== -1) {
        clearInterval(this.countdownTimer)
        this.countdownTimer = -1
      }
    }, 1000)
  }

  private async sendCaptcha(checkRegistration: boolean = true): Promise<void> {
    if (!this.validPhone()) {
      return
    }
    this.message = ''
    try {
      if (checkRegistration) {
        await this.phoneExists()
      }
      const response = await ApiClient.get<LoginResponse>('/captcha/sent', [
        { key: 'phone', value: this.phone.trim() }
      ])
      if (response.code !== 200) {
        this.message = response.message || response.msg || '验证码发送失败'
        return
      }
      this.startCountdown()
      this.message = this.registrationMode ? '验证码已发送，填写资料后即可完成注册' : '验证码已发送'
    } catch (error) {
      this.message = error instanceof Error ? error.message : '验证码发送失败'
    }
  }

  private async completeRegistration(): Promise<void> {
    if (!this.validPhone() || !this.captcha.trim() || !this.nickname.trim() || !this.password) {
      this.message = '请完整填写验证码、昵称和密码'
      return
    }
    if (this.password.length < 6) {
      this.message = '密码至少需要 6 位'
      return
    }
    this.loading = true
    this.message = ''
    try {
      const response = await ApiClient.get<LoginResponse>('/register/cellphone', [
        { key: 'phone', value: this.phone.trim() },
        { key: 'captcha', value: this.captcha.trim() },
        { key: 'nickname', value: this.nickname.trim() },
        { key: 'password', value: this.password }
      ])
      if (response.code !== 200) {
        this.message = response.message || response.msg || `注册失败 (${response.code})`
        return
      }
      const loginResponse = await ApiClient.get<LoginResponse>('/login/cellphone', [
        { key: 'phone', value: this.phone.trim() },
        { key: 'password', value: this.password }
      ])
      await this.finishLogin(loginResponse)
    } catch (error) {
      this.message = error instanceof Error ? error.message : '注册失败'
    } finally {
      this.loading = false
    }
  }

  private async createQrCode(): Promise<void> {
    this.qrStatus = '正在生成二维码…'
    this.message = ''
    if (this.qrTimer !== -1) {
      clearInterval(this.qrTimer)
    }
    try {
      const response = await ApiClient.get<QrKeyResponse>('/login/qr/key', [
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code !== 200 || !response.data?.unikey) {
        this.qrStatus = '二维码生成失败'
        return
      }
      this.qrKey = response.data.unikey
      this.qrUrl = `https://music.163.com/login?codekey=${this.qrKey}`
      this.qrStatus = '请使用网易云音乐 App 扫码'
      this.qrTimer = setInterval(() => this.checkQrStatus(), 2000)
    } catch (error) {
      this.qrStatus = error instanceof Error ? error.message : '二维码生成失败'
    }
  }

  private async checkQrStatus(): Promise<void> {
    if (!this.qrKey) {
      return
    }
    try {
      const response = await ApiClient.get<QrCheckResponse>('/login/qr/check', [
        { key: 'key', value: this.qrKey },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code === 800) {
        this.qrStatus = '二维码已过期，点击刷新'
        if (this.qrTimer !== -1) {
          clearInterval(this.qrTimer)
          this.qrTimer = -1
        }
      } else if (response.code === 802) {
        const nickname = response.nickname || ''
        this.qrStatus = nickname ? `${nickname} 已扫码，请在手机上确认` : '扫码成功，请在手机上确认'
      } else if (response.code === 803) {
        if (this.qrTimer !== -1) {
          clearInterval(this.qrTimer)
          this.qrTimer = -1
        }
        const cookie = response.cookie || ''
        if (cookie.length === 0) {
          this.qrStatus = '授权成功但未返回 Cookie，请重试'
          return
        }
        this.qrStatus = '授权成功，正在验证登录状态…'
        await this.finishLogin(response, true)
      }
    } catch (_error) {
      this.qrStatus = '连接中断，正在重试…'
    }
  }

  @Builder
  private MethodTab(item: LoginMethodItem) {
    Column({ space: 6 }) {
      Text(item.title)
        .fontSize(14)
        .fontWeight(this.currentMethod === item.key ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.currentMethod === item.key ? '#ffffff' : '#77777f')
      Column()
        .width(this.currentMethod === item.key ? 24 : 0)
        .height(3)
        .borderRadius(2)
        .backgroundColor('#ff3b4f')
        .animation({ duration: 180, curve: Curve.EaseOut })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 8 })
    .onClick(() => {
      this.currentMethod = item.key
      this.registrationMode = false
      this.message = ''
      if (item.key === 'qr' && !this.qrKey) {
        this.createQrCode()
      }
    })
  }

  @Builder
  private Field(value: string, placeholder: string, type: InputType, onChange: (value: string) => void) {
    TextInput({ text: value, placeholder: placeholder })
      .type(type)
      .height(52)
      .fontColor('#ffffff')
      .placeholderColor('#696972')
      .backgroundColor('#202026')
      .borderRadius(14)
      .padding({ left: 16, right: 16 })
      .onChange(onChange)
  }

  @Builder
  private CaptchaField() {
    Row({ space: 10 }) {
      TextInput({ text: this.captcha, placeholder: '短信验证码' })
        .type(InputType.Number)
        .layoutWeight(1)
        .height(52)
        .fontColor('#ffffff')
        .placeholderColor('#696972')
        .backgroundColor('#202026')
        .borderRadius(14)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => this.captcha = value)
      Button(this.countdown > 0 ? `${this.countdown}s` : '获取验证码')
        .height(52)
        .fontSize(13)
        .fontColor('#ff6577')
        .backgroundColor('#2b2024')
        .borderRadius(14)
        .enabled(this.countdown <= 0)
        .onClick(() => this.sendCaptcha(!this.registrationMode))
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text(this.registrationMode ? '完善账号信息' : '手机号登录')
            .layoutWeight(1)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .textAlign(TextAlign.Center)
          Column().width(24)
        }
        .width('100%')
        .height(56)

        Scroll() {
          Column({ space: 20 }) {
            Column({ space: 10 }) {
              Stack() {
                Image($r('app.media.ic_logo')).width(38).height(38).fillColor('#ffffff')
              }
              .width(72).height(72).borderRadius(22).backgroundColor('#ef233c')
              .shadow({ radius: 18, color: 'rgba(239,35,60,0.32)', offsetY: 8 })
              Text(this.registrationMode ? '注册「网易云音乐」账号' : '登录「网易云音乐」账号')
                .fontSize(22).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              Text(this.registrationMode ? '验证码通过后会直接创建账号并登录' : '仅支持中国大陆手机号登录')
                .fontSize(12).fontColor('#85858e').textAlign(TextAlign.Center)
            }
            .width('100%')

            if (!this.registrationMode) {
              Row() {
                ForEach(this.methods, (item: LoginMethodItem) => this.MethodTab(item))
              }
              .width('100%').backgroundColor('#18181d').borderRadius(14)
            }

            if (this.registrationMode) {
              Column({ space: 12 }) {
                Row() {
                  Text(this.phone).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                  Text('更换手机号')
                    .layoutWeight(1).fontSize(12).fontColor('#ff6577').textAlign(TextAlign.End)
                    .onClick(() => {
                      this.registrationMode = false
                      this.phone = ''
                      this.captcha = ''
                      this.message = ''
                    })
                }
                .width('100%').padding(16).backgroundColor('#202026').borderRadius(14)
                this.CaptchaField()
                this.Field(this.nickname, '设置昵称', InputType.Normal, (value: string) => this.nickname = value)
                this.Field(this.password, '设置密码（至少 6 位）', InputType.Password,
                  (value: string) => this.password = value)
                Button(this.loading ? '创建中…' : '完成并登录')
                  .width('100%').height(50).borderRadius(25).backgroundColor('#ef233c')
                  .enabled(!this.loading).onClick(() => this.completeRegistration())
              }
            } else if (this.currentMethod === 'password') {
              Column({ space: 12 }) {
                this.Field(this.phone, '手机号码', InputType.PhoneNumber, (value: string) => this.phone = value)
                this.Field(this.password, '密码', InputType.Password, (value: string) => this.password = value)
                Button(this.loading ? '登录中…' : '登录')
                  .width('100%').height(50).borderRadius(25).backgroundColor('#ef233c')
                  .enabled(!this.loading).onClick(() => this.passwordLogin())
              }
            } else if (this.currentMethod === 'captcha') {
              Column({ space: 12 }) {
                this.Field(this.phone, '手机号码', InputType.PhoneNumber, (value: string) => this.phone = value)
                this.CaptchaField()
                Button(this.loading ? '登录中…' : '验证码登录')
                  .width('100%').height(50).borderRadius(25).backgroundColor('#ef233c')
                  .enabled(!this.loading).onClick(() => this.captchaLogin())
              }
            } else {
              Column({ space: 16 }) {
                if (this.qrUrl) {
                  QRCode(this.qrUrl).width(210).height(210).color('#121215').backgroundColor('#ffffff')
                } else {
                  LoadingProgress().width(48).height(48).color('#ef233c')
                }
                Text(this.qrStatus).fontSize(13).fontColor('#a1a1a8')
                Button('刷新二维码').fontColor('#ff6577').backgroundColor('#2b2024')
                  .onClick(() => this.createQrCode())
              }
              .width('100%').height(310).justifyContent(FlexAlign.Center)
            }

            if (this.message) {
              Text(this.message)
                .width('100%').fontSize(12).fontColor('#ff6577').textAlign(TextAlign.Center)
            }

            Text('服务地址请在侧边栏的“设置”页面中修改')
              .width('100%').fontSize(11).fontColor('#55555d').textAlign(TextAlign.Center)
          }
          .padding({ left: 24, right: 24, top: 12, bottom: 36 })
        }
        .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor('#121215')
    }
    .hideTitleBar(true)
  }
}
