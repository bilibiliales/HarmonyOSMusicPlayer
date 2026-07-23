import { ApiClient } from '../services/ApiClient'
import { PlayerStore } from '../stores/PlayerStore'
import { common } from '@kit.AbilityKit'
import { AppSettings } from '../services/AppSettings'

@Component
export struct SettingsPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('playerStore') playerStore: PlayerStore
  @State serverUrl: string = ApiClient.baseUrl
  @State aiWorkspaceId: string = AppSettings.aiWorkspaceId
  @State aiApiKey: string = AppSettings.aiApiKey
  @State aiModel: string = AppSettings.aiModel
  @State message: string = ''

  aboutToAppear(): void {
    this.aiWorkspaceId = AppSettings.aiWorkspaceId
    this.aiApiKey = AppSettings.aiApiKey
    this.aiModel = AppSettings.aiModel
  }

  private async save(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.saveBaseUrl(context, this.serverUrl)
      this.serverUrl = ApiClient.baseUrl
      this.message = '服务地址已保存，重新启动应用后仍会生效'
    } catch (error) {
      this.message = error instanceof Error ? error.message : '设置保存失败'
    }
  }

  private async saveAiConnection(): Promise<void> {
    if (!this.aiWorkspaceId.trim() || !this.aiApiKey.trim()) {
      this.message = '请填写 Workspace ID 和 API Key'
      return
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.saveAiSettings(context, this.aiWorkspaceId, this.aiApiKey, this.aiModel)
      this.aiWorkspaceId = AppSettings.aiWorkspaceId
      this.aiApiKey = AppSettings.aiApiKey
      this.aiModel = AppSettings.aiModel
      this.message = 'AI 模型连接已保存'
    } catch (error) {
      this.message = error instanceof Error ? error.message : 'AI 模型设置保存失败'
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('设置')
            .layoutWeight(1)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .textAlign(TextAlign.Center)
          Column().width(24)
        }
        .height(56)
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 10 }) {
              Text('后端服务')
                .width('100%')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffffff')
              Text('电脑本机调试可使用 127.0.0.1；模拟器通常使用 10.0.2.2；真机填写电脑局域网 IP。')
                .width('100%')
                .fontSize(11)
                .lineHeight(18)
                .fontColor('#77777f')
              TextInput({ text: this.serverUrl, placeholder: 'http://10.0.2.2:3000' })
                .height(50)
                .fontColor('#ffffff')
                .placeholderColor('#66666e')
                .backgroundColor('#24242a')
                .borderRadius(14)
                .onChange((value: string) => this.serverUrl = value)
              Button('保存服务地址')
                .width('100%')
                .height(46)
                .borderRadius(23)
                .backgroundColor('#ef233c')
                .onClick(() => this.save())
            }
            .width('100%')
            .padding(18)
            .backgroundColor('#1b1b20')
            .borderRadius(20)

            Column({ space: 10 }) {
              Text('AI 模型连接')
                .width('100%')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffffff')
              Text('用于 AI 写歌功能。API Key 仅保存在本机应用设置中，请勿使用共享密钥。')
                .width('100%')
                .fontSize(11)
                .lineHeight(18)
                .fontColor('#77777f')
              TextInput({ text: this.aiWorkspaceId, placeholder: '阿里云百炼 Workspace ID' })
                .height(48)
                .fontColor('#ffffff')
                .placeholderColor('#66666e')
                .backgroundColor('#24242a')
                .borderRadius(14)
                .onChange((value: string) => this.aiWorkspaceId = value)
              TextInput({ text: this.aiApiKey, placeholder: 'DASHSCOPE API Key' })
                .type(InputType.Password)
                .height(48)
                .fontColor('#ffffff')
                .placeholderColor('#66666e')
                .backgroundColor('#24242a')
                .borderRadius(14)
                .onChange((value: string) => this.aiApiKey = value)
              TextInput({ text: this.aiModel, placeholder: '模型名称，例如 qwen-plus' })
                .height(48)
                .fontColor('#ffffff')
                .placeholderColor('#66666e')
                .backgroundColor('#24242a')
                .borderRadius(14)
                .onChange((value: string) => this.aiModel = value)
              Button('保存 AI 模型连接')
                .width('100%')
                .height(46)
                .borderRadius(23)
                .backgroundColor('#ef233c')
                .onClick(() => this.saveAiConnection())
            }
            .width('100%')
            .padding(18)
            .backgroundColor('#1b1b20')
            .borderRadius(20)

            Column({ space: 12 }) {
              Text('当前播放设置')
                .width('100%')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffffff')
              Row() {
                Text('播放顺序').fontSize(13).fontColor('#b9b9c0')
                Text(this.playerStore.modeTitle())
                  .layoutWeight(1)
                  .fontSize(13)
                  .fontColor('#77777f')
                  .textAlign(TextAlign.End)
              }
              Row() {
                Text('播放音质').fontSize(13).fontColor('#b9b9c0')
                Text(this.playerStore.qualityTitle())
                  .layoutWeight(1)
                  .fontSize(13)
                  .fontColor('#77777f')
                  .textAlign(TextAlign.End)
              }
            }
            .width('100%')
            .padding(18)
            .backgroundColor('#1b1b20')
            .borderRadius(20)

            if (this.message) {
              Text(this.message)
                .width('100%')
                .fontSize(12)
                .fontColor('#55c98b')
                .textAlign(TextAlign.Center)
            }
          }
          .padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#121215')
    }
    .hideTitleBar(true)
  }
}
