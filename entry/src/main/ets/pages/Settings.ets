import { common } from '@kit.AbilityKit'
import { PlayMode, QUALITY_OPTIONS, QualityOption } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { AppSettings } from '../services/AppSettings'
import { BubbleTip } from '../services/BubbleTip'
import { PlayerStore } from '../stores/PlayerStore'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'
import { UserSettings, playRecordVisibilityPatch } from '../models/userSettings'
import { UserSettingsService } from '../services/UserSettingsService'
import { ThemeMode, ThemeService } from '../services/ThemeService'
import { TC } from '../services/ThemeColors'

@Component
struct QualitySelector {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Link selected: string

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(QUALITY_OPTIONS, (item: QualityOption) => {
        Button(item.title)
          .fontSize(12).fontColor(this.selected === item.level ? TC.textOnAccent() : TC.textTertiary())
          .constraintSize({ minHeight: 44 }).padding({ left: 14, right: 14 })
          .backgroundColor(this.selected === item.level ? TC.accent() : TC.chipBackground())
          .borderRadius(22).margin({ right: 8, bottom: 8 })
          .onClick(() => this.selected = item.level)
      }, (item: QualityOption) => item.level)
    }.width('100%').constraintSize({ minHeight: 52 })
  }
}

@Component
export struct SettingsPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('playerStore') playerStore: PlayerStore
  @Consume('authStore') authStore: AuthStore
  @State privacySettings: UserSettings = {}
  @State privacyAllowed: boolean = false
  @State privacyLoading: boolean = false
  @State privacySaving: boolean = false
  @State privacyMessage: string = ''
  @State privacyReady: boolean = false
  private privacyRequest: number = 0
  private privacyCookie: string = ''
  private privacyVisible: boolean = false
  private privacyReloadPending: boolean = false
  @State serverUrl: string = ApiClient.baseUrl
  @State aiBaseUrl: string = AppSettings.aiBaseUrl
  @State aiApiKey: string = AppSettings.aiApiKey
  @State aiModel: string = AppSettings.aiModel
  @State defaultPlayMode: PlayMode = AppSettings.defaultPlayMode
  @State defaultOnlineQuality: string = AppSettings.defaultOnlineQuality
  @State defaultDownloadQuality: string = AppSettings.defaultDownloadQuality
  @State backgroundPlaybackEnabled: boolean = AppSettings.backgroundPlaybackEnabled
  @State streamingPlaybackEnabled: boolean = AppSettings.streamingPlaybackEnabled
  @State effectsEnabled: boolean = AppSettings.effectsEnabled
  @State downloadSaveMode: string = AppSettings.downloadSaveMode
  @State askDownloadSaveMode: boolean = AppSettings.askDownloadSaveMode
  @StorageProp('themeMode') themeMode: string = 'system'
  @StorageProp('systemDarkMode') systemDark: boolean = false

  private isFollowSystem(): boolean {
    return this.themeMode === ThemeMode.SYSTEM
  }

  private isDarkActive(): boolean {
    return this.themeMode === ThemeMode.DARK || (this.isFollowSystem() && this.systemDark)
  }

  private async setFollowSystem(follow: boolean): Promise<void> {
    try {
      // 关闭跟随系统时，保留当前真实观感，避免闪变
      await ThemeService.setMode(follow ? ThemeMode.SYSTEM : (this.systemDark ? ThemeMode.DARK : ThemeMode.LIGHT))
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '保存失败') }
  }

  private async setDark(on: boolean): Promise<void> {
    try {
      await ThemeService.setMode(on ? ThemeMode.DARK : ThemeMode.LIGHT)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '保存失败') }
  }

  @Builder
  private ThemeSection() {
    Column({ space: 12 }) {
      Text('外观').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Text('跟随系统').fontSize(14).fontColor(TC.textPrimary())
          Text('开启后应用深浅色自动跟随系统设置').fontSize(11).fontColor(TC.textSecondary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.isFollowSystem() })
          .selectedColor(TC.accent())
          .onChange((follow: boolean) => this.setFollowSystem(follow))
      }.width('100%')
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Text('深色模式').fontSize(14)
            .fontColor(this.isFollowSystem() ? TC.textTertiary() : TC.textPrimary())
          Text(this.isFollowSystem() ? '跟随系统时不可手动调整' : '仅影响本应用，不改变系统设置')
            .fontSize(11).fontColor(TC.textSecondary())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.isDarkActive() })
          .selectedColor(TC.accent())
          .enabled(!this.isFollowSystem())
          .onChange((on: boolean) => this.setDark(on))
      }.width('100%').opacity(this.isFollowSystem() ? 0.45 : 1)
    }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)
  }

  private async saveDownloadOption(mode: string, ask: boolean): Promise<void> {
    try {
      await AppSettings.saveFeature('download_save_mode', mode)
      await AppSettings.saveFeature('ask_download_save_mode', ask)
      AppSettings.downloadSaveMode = mode
      AppSettings.askDownloadSaveMode = ask
      this.downloadSaveMode = mode
      this.askDownloadSaveMode = ask
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '保存失败') }
  }

  @State featureBusy: boolean = false

  private async changeDesktop(enabled: boolean, locked: boolean): Promise<void> {
    if (this.featureBusy) { return }
    this.featureBusy = true
    try {
      await playerController.setDesktopLyrics(enabled, locked)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '桌面歌词设置失败') }
    finally { this.featureBusy = false }
  }

  private async changeEffects(enabled: boolean): Promise<void> {
    if (this.featureBusy) { return }
    this.featureBusy = true
    try { await playerController.setEffects(enabled); this.effectsEnabled = enabled }
    catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '音效设置失败') }
    finally { this.featureBusy = false }
  }

  @State changingPlayback: boolean = false

  aboutToDisappear(): void { this.privacyRequest++; this.privacyVisible = false }

  private privacyAccountMatches(uid: string, cookie: string): boolean {
    return this.authStore.loggedIn && this.authStore.userId === uid && ApiClient.cookie === cookie
  }

  private async loadPrivacySettings(): Promise<void> {
    if (this.privacySaving) { this.privacyReloadPending = true; return }
    const request = ++this.privacyRequest
    const uid = this.authStore.userId
    const cookie = ApiClient.cookie
    this.privacyReady = false
    this.privacyMessage = ''
    this.privacySettings = {}
    if (!this.authStore.loggedIn) { this.privacyLoading = false; this.privacyAllowed = false; return }
    this.privacyLoading = true
    try {
      const settings = await UserSettingsService.read(uid)
      if (request !== this.privacyRequest || !this.privacyAccountMatches(uid, cookie)) { return }
      this.privacySettings = settings
      this.privacyCookie = cookie
      this.privacyAllowed = settings['allowPeopleCanSeeMyPlayRecord'] === true
      this.privacyReady = typeof settings['allowPeopleCanSeeMyPlayRecord'] === 'boolean'
      if (!this.privacyReady) { this.privacyMessage = '当前账号未返回可修改的听歌记录设置' }
    } catch (error) {
      if (request === this.privacyRequest) { this.privacyMessage = error instanceof Error ? error.message : '隐私设置读取失败' }
    } finally { if (request === this.privacyRequest) { this.privacyLoading = false } }
  }

  private async changePlayRecordVisibility(allowed: boolean): Promise<void> {
    if (this.privacySaving || !this.privacyReady || !this.authStore.loggedIn || this.privacyCookie !== ApiClient.cookie ||
      allowed === this.privacySettings['allowPeopleCanSeeMyPlayRecord']) { return }
    const uid = this.authStore.userId
    const cookie = ApiClient.cookie
    const request = ++this.privacyRequest
    this.privacySaving = true
    this.privacyAllowed = allowed
    this.privacyMessage = ''
    try {
      const result = await UserSettingsService.updateAndRead(uid, playRecordVisibilityPatch(allowed))
      if (request !== this.privacyRequest || !this.privacyAccountMatches(uid, cookie)) { return }
      if (result.settings) { this.privacySettings = result.settings }
      this.privacyReady = !!result.settings && typeof result.settings['allowPeopleCanSeeMyPlayRecord'] === 'boolean'
      this.privacyAllowed = this.privacySettings['allowPeopleCanSeeMyPlayRecord'] === true
      this.privacyMessage = result.confirmed ? '' : result.message
      BubbleTip.show(this.getUIContext(), result.message)
    } catch (error) {
      if (request === this.privacyRequest) {
        this.privacyAllowed = this.privacySettings['allowPeopleCanSeeMyPlayRecord'] === true
        this.privacyReady = false
        this.privacyMessage = error instanceof Error ? error.message : '设置修改失败'
      }
    } finally {
      this.privacySaving = false
      if (this.privacyReloadPending && this.privacyVisible) {
        this.privacyReloadPending = false
        this.loadPrivacySettings()
      }
    }
  }

  @Builder
  private PrivacySection() {
    Column({ space: 12 }) {
      Text('隐私设置').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
      if (!this.authStore.loggedIn) {
        Text('登录后管理账号隐私设置').fontSize(12).fontColor(TC.textSecondary())
        Button('去登录').backgroundColor(TC.accent()).onClick(() => this.pageStack.pushPathByName('LoginPage', null))
      } else if (this.privacyLoading) {
        LoadingProgress().width(28).height(28).color(TC.accent())
      } else {
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text('允许他人查看我的听歌记录').fontSize(14).fontColor(TC.textBody())
            Text(this.privacySaving ? '正在保存并确认…' : '控制他人对听歌记录的访问')
              .fontSize(11).fontColor(TC.textSecondary())
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.privacyAllowed }).selectedColor(TC.accent())
            .enabled(this.privacyReady && !this.privacySaving && this.privacyCookie === ApiClient.cookie)
            .onChange((allowed: boolean) => this.changePlayRecordVisibility(allowed))
        }.width('100%')
        if (this.privacyMessage) {
          Text(this.privacyMessage).width('100%').fontSize(12).fontColor(TC.accentSoft())
          Button('重新读取').fontSize(12).backgroundColor(TC.chipBackground()).enabled(!this.privacySaving)
            .onClick(() => this.loadPrivacySettings())
        }
      }
    }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)
  }

  private async changeBackgroundPlayback(enabled: boolean): Promise<void> {
    if (this.changingPlayback || enabled === AppSettings.backgroundPlaybackEnabled) { return }
    this.changingPlayback = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await playerController.setBackgroundPlayback(context, enabled)
      BubbleTip.show(this.getUIContext(), enabled ? '已开启后台播放' : '已关闭后台播放')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '切换播放方式失败')
    } finally {
      this.backgroundPlaybackEnabled = AppSettings.backgroundPlaybackEnabled
      this.changingPlayback = false
    }
  }

  private async changeStreamingPlayback(enabled: boolean): Promise<void> {
    if (enabled === AppSettings.streamingPlaybackEnabled) { return }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.saveStreamingPlayback(context, enabled)
      BubbleTip.show(this.getUIContext(), enabled ? '已开启流式播放' : '已关闭流式播放，将整曲载入内存')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '流式播放设置失败')
    } finally {
      this.streamingPlaybackEnabled = AppSettings.streamingPlaybackEnabled
    }
  }

  private async savePlaybackDefaults(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.savePlaybackDefaults(context, this.defaultPlayMode, this.defaultOnlineQuality,
        this.defaultDownloadQuality)
      this.playerStore.playMode = this.defaultPlayMode
      await playerController.changeQuality(this.defaultOnlineQuality)
      BubbleTip.show(this.getUIContext(), '默认播放设置已保存并应用')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '默认播放设置保存失败')
    }
  }

  private async saveServer(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.saveBaseUrl(context, this.serverUrl)
      this.serverUrl = ApiClient.baseUrl
      BubbleTip.show(this.getUIContext(), '服务地址已保存')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '服务地址保存失败')
    }
  }

  private async saveAiConnection(): Promise<void> {
    if (!this.aiBaseUrl.trim() || !this.aiApiKey.trim()) {
      BubbleTip.show(this.getUIContext(), '请填写 Base URL 和 API Key')
      return
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.saveAiSettings(context, this.aiBaseUrl, this.aiApiKey, this.aiModel)
      BubbleTip.show(this.getUIContext(), 'AI 模型连接已保存')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : 'AI 模型设置保存失败')
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('设置').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          Column().width(24)
        }.height(56).constraintSize({ minHeight: 56 }).width('100%').padding({ left: 16, right: 16 })
        Scroll() {
          Column({ space: 16 }) {
            this.ThemeSection()
            this.PrivacySection()
            Column({ space: 12 }) {
              Text('账号').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('设备管理').fontSize(14).fontColor(TC.textPrimary())
                  Text('查看在线设备、强制下线或上报设备别名').fontSize(11).fontColor(TC.textSecondary())
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([TC.textQuaternary()])
              }.width('100%').onClick(() => this.pageStack.pushPathByName('DeviceManagementPage', null))
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)
            Column({ space: 12 }) {
              Text('默认播放设置').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              Row({ space: 12 }) {
                Text('开启后台播放').layoutWeight(1).fontSize(14).fontColor(TC.textPrimary())
                Toggle({ type: ToggleType.Switch, isOn: this.backgroundPlaybackEnabled })
                  .selectedColor(TC.accent()).enabled(!this.changingPlayback)
                  .onChange((enabled: boolean) => this.changeBackgroundPlayback(enabled))
              }.width('100%')
              Text('关闭后仅在前台播放，切到后台自动暂停；开启后支持后台播放和系统媒体控制。')
                .width('100%').fontSize(12).fontColor(TC.textBody())
              Row({ space: 12 }) {
                Column({ space: 6 }) {
                  Text('流式加载播放').fontSize(14).fontColor(TC.textPrimary())
                  Text('开启后按需分段拉取，内存占用与文件大小无关；关闭则整曲下载到内存后再播放（兼容旧设备）。')
                    .fontSize(11).fontColor(TC.textSecondary()).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.streamingPlaybackEnabled })
                  .selectedColor(TC.accent()).enabled(!this.changingPlayback)
                  .onChange((enabled: boolean) => this.changeStreamingPlayback(enabled))
              }.width('100%').margin({ top: 6 })
              Text('播放顺序').width('100%').fontSize(12).fontColor(TC.textBody())
              Row({ space: 8 }) {
                ForEach([PlayMode.LOOP, PlayMode.SINGLE, PlayMode.SHUFFLE], (mode: PlayMode) => {
                  Text(mode === PlayMode.LOOP ? '列表循环' : mode === PlayMode.SINGLE ? '单曲循环' : '随机播放')
                    .fontSize(12).fontColor(this.defaultPlayMode === mode ? TC.textOnAccent() : TC.textTertiary())
                    .padding({ left: 13, right: 13, top: 9, bottom: 9 })
                    .backgroundColor(this.defaultPlayMode === mode ? TC.accent() : TC.chipBackground()).borderRadius(18)
                    .onClick(() => this.defaultPlayMode = mode)
                })
              }.width('100%')
              Row() {
                Text('系统桌面歌词').fontSize(14).fontColor(TC.textPrimary()).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.playerStore.desktopLyricsVisible })
                  .selectedColor(TC.accent()).enabled(!this.featureBusy)
                  .onChange((enabled: boolean) => this.changeDesktop(enabled, this.playerStore.desktopLyricsLocked))
              }.width('100%')
              Row() {
                Text('锁定桌面歌词').fontSize(14).fontColor(TC.textPrimary()).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.playerStore.desktopLyricsLocked })
                  .selectedColor(TC.accent()).enabled(this.playerStore.desktopLyricsVisible && !this.featureBusy)
                  .onChange((locked: boolean) => this.changeDesktop(this.playerStore.desktopLyricsVisible, locked))
              }.width('100%')
              Text('桌面歌词需要开启后台播放；外观与媒体控制由系统提供。').fontSize(11).fontColor(TC.textSecondary())
              Row() {
                Text('系统音效').fontSize(14).fontColor(TC.textPrimary()).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.effectsEnabled })
                  .selectedColor(TC.accent()).enabled(!this.featureBusy)
                  .onChange((enabled: boolean) => this.changeEffects(enabled))
              }.width('100%')
              Text('使用设备默认音效，关闭后使用原始音频。当前系统未开放多频段均衡器调节。').fontSize(11).fontColor(TC.textSecondary())
              Text('在线播放音质').width('100%').fontSize(12).fontColor(TC.textBody())
              QualitySelector({ selected: $defaultOnlineQuality })
              Text('下载保存方式').width('100%').fontSize(14).fontColor(TC.textPrimary())
              Row({ space: 12 }) {
                Button('下载目录').fontSize(12).backgroundColor(this.downloadSaveMode === 'download' ? TC.accent() : TC.chipBackground())
                  .onClick(() => this.saveDownloadOption('download', this.askDownloadSaveMode))
                Button('另存为').fontSize(12).backgroundColor(this.downloadSaveMode === 'saveAs' ? TC.accent() : TC.chipBackground())
                  .onClick(() => this.saveDownloadOption('saveAs', this.askDownloadSaveMode))
              }
              Row() {
                Text('下载前询问保存方式').layoutWeight(1).fontSize(14).fontColor(TC.textPrimary())
                Toggle({ type: ToggleType.Switch, isOn: this.askDownloadSaveMode })
                  .selectedColor(TC.accent())
                  .onChange((value: boolean) => this.saveDownloadOption(this.downloadSaveMode, value))
              }.width('100%')
              Text('下载目录支持自动扫描；另存文件会记住位置，授权失效时请在本地音乐中重新选择文件。')
                .fontSize(11).fontColor(TC.textSecondary())
              Text('下载音质').width('100%').fontSize(12).fontColor(TC.textBody())
              QualitySelector({ selected: $defaultDownloadQuality })
              Button('保存默认播放设置').width('100%').height(46).borderRadius(23)
                .backgroundColor(TC.accent()).onClick(() => this.savePlaybackDefaults())
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)

            Column({ space: 10 }) {
              Text('后端服务').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              TextInput({ text: this.serverUrl, placeholder: '后端服务 Base URL，例如 https://neteaseapi.gksm.store' })
                .height(50).fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceInset())
                .borderRadius(14).onChange((value: string) => this.serverUrl = value)
              Button('保存服务地址').width('100%').height(46).borderRadius(23)
                .backgroundColor(TC.accent()).onClick(() => this.saveServer())
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)

            Column({ space: 10 }) {
              Text('AI 模型连接').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              TextInput({ text: this.aiBaseUrl, placeholder: 'AI 服务 Base URL，例如 https://api.openai.com/v1' })
                .height(48).fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceInset())
                .borderRadius(14).onChange((value: string) => this.aiBaseUrl = value)
              TextInput({ text: this.aiApiKey, placeholder: 'API Key' }).type(InputType.Password)
                .height(48).fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceInset())
                .borderRadius(14).onChange((value: string) => this.aiApiKey = value)
              TextInput({ text: this.aiModel, placeholder: '模型名称，例如 gpt-3.5-turbo' })
                .height(48).fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceInset())
                .borderRadius(14).onChange((value: string) => this.aiModel = value)
              Button('保存 AI 模型连接').width('100%').height(46).borderRadius(23)
                .backgroundColor(TC.accent()).onClick(() => this.saveAiConnection())
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.width('100%').layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true).onShown(() => {
      playerController.refreshDesktopLyrics().catch(() => {})
      this.privacyVisible = true
      this.loadPrivacySettings()
    }).onHidden(() => this.privacyVisible = false)
  }
}
