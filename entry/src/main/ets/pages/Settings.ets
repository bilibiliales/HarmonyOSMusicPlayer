import { common } from '@kit.AbilityKit'
import { PlayMode, QUALITY_OPTIONS, QualityOption } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { AppSettings } from '../services/AppSettings'
import { BubbleTip } from '../services/BubbleTip'
import { PlayerStore } from '../stores/PlayerStore'

@Component
export struct SettingsPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('playerStore') playerStore: PlayerStore
  @State serverUrl: string = ApiClient.baseUrl
  @State aiBaseUrl: string = AppSettings.aiBaseUrl
  @State aiApiKey: string = AppSettings.aiApiKey
  @State aiModel: string = AppSettings.aiModel
  @State defaultPlayMode: PlayMode = AppSettings.defaultPlayMode
  @State defaultOnlineQuality: string = AppSettings.defaultOnlineQuality
  @State defaultDownloadQuality: string = AppSettings.defaultDownloadQuality

  private async savePlaybackDefaults(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.savePlaybackDefaults(context, this.defaultPlayMode, this.defaultOnlineQuality,
        this.defaultDownloadQuality)
      this.playerStore.playMode = this.defaultPlayMode
      this.playerStore.quality = this.defaultOnlineQuality
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

  @Builder
  private QualitySelector(selected: string, onSelect: (level: string) => void) {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(QUALITY_OPTIONS, (item: QualityOption) => {
          Text(item.title).fontSize(12).fontColor(selected === item.level ? '#ffffff' : '#9a9aa2')
            .padding({ left: 14, right: 14, top: 9, bottom: 9 })
            .backgroundColor(selected === item.level ? '#ef233c' : '#29292f').borderRadius(18)
            .onClick(() => onSelect(item.level))
        }, (item: QualityOption) => item.level)
      }
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('设置').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          Column().width(24)
        }.height(56).width('100%').padding({ left: 16, right: 16 })
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 12 }) {
              Text('默认播放设置').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              Text('播放顺序').width('100%').fontSize(12).fontColor('#b9b9c0')
              Row({ space: 8 }) {
                ForEach([PlayMode.LOOP, PlayMode.SINGLE, PlayMode.SHUFFLE], (mode: PlayMode) => {
                  Text(mode === PlayMode.LOOP ? '列表循环' : mode === PlayMode.SINGLE ? '单曲循环' : '随机播放')
                    .fontSize(12).fontColor(this.defaultPlayMode === mode ? '#ffffff' : '#9a9aa2')
                    .padding({ left: 13, right: 13, top: 9, bottom: 9 })
                    .backgroundColor(this.defaultPlayMode === mode ? '#ef233c' : '#29292f').borderRadius(18)
                    .onClick(() => this.defaultPlayMode = mode)
                })
              }.width('100%')
              Text('在线播放音质').width('100%').fontSize(12).fontColor('#b9b9c0')
              this.QualitySelector(this.defaultOnlineQuality,
                (level: string) => this.defaultOnlineQuality = level)
              Text('下载音质').width('100%').fontSize(12).fontColor('#b9b9c0')
              this.QualitySelector(this.defaultDownloadQuality,
                (level: string) => this.defaultDownloadQuality = level)
              Button('保存默认播放设置').width('100%').height(46).borderRadius(23)
                .backgroundColor('#ef233c').onClick(() => this.savePlaybackDefaults())
            }.width('100%').padding(18).backgroundColor('#1b1b20').borderRadius(20)

            Column({ space: 10 }) {
              Text('后端服务').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              TextInput({ text: this.serverUrl, placeholder: 'https://apis.netstart.cn/music' })
                .height(50).fontColor('#ffffff').placeholderColor('#66666e').backgroundColor('#24242a')
                .borderRadius(14).onChange((value: string) => this.serverUrl = value)
              Button('保存服务地址').width('100%').height(46).borderRadius(23)
                .backgroundColor('#ef233c').onClick(() => this.saveServer())
            }.width('100%').padding(18).backgroundColor('#1b1b20').borderRadius(20)

            Column({ space: 10 }) {
              Text('AI 模型连接').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
              TextInput({ text: this.aiBaseUrl, placeholder: 'AI 服务 Base URL，例如 https://api.openai.com/v1' })
                .height(48).fontColor('#ffffff').placeholderColor('#66666e').backgroundColor('#24242a')
                .borderRadius(14).onChange((value: string) => this.aiBaseUrl = value)
              TextInput({ text: this.aiApiKey, placeholder: 'API Key' }).type(InputType.Password)
                .height(48).fontColor('#ffffff').placeholderColor('#66666e').backgroundColor('#24242a')
                .borderRadius(14).onChange((value: string) => this.aiApiKey = value)
              TextInput({ text: this.aiModel, placeholder: '模型名称，例如 gpt-3.5-turbo' })
                .height(48).fontColor('#ffffff').placeholderColor('#66666e').backgroundColor('#24242a')
                .borderRadius(14).onChange((value: string) => this.aiModel = value)
              Button('保存 AI 模型连接').width('100%').height(46).borderRadius(23)
                .backgroundColor('#ef233c').onClick(() => this.saveAiConnection())
            }.width('100%').padding(18).backgroundColor('#1b1b20').borderRadius(20)
          }.padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.layoutWeight(1)
      }.width('100%').height('100%').backgroundColor('#121215')
    }.hideTitleBar(true)
  }
}
