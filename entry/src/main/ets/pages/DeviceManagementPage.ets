import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { AppSettings } from '../services/AppSettings'
import { DeviceItem, DeviceService } from '../services/DeviceService'
import { BubbleTip } from '../services/BubbleTip'
import { AuthStore } from '../stores/AuthStore'
import { TC } from '../services/ThemeColors'

@Component
export struct DeviceManagementPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore

  @State devices: DeviceItem[] = []
  @State loading: boolean = false
  @State alias: string = AppSettings.deviceAlias || deviceInfo.marketName
  @State aliasSaving: boolean = false
  @State kickingKey: string = ''

  aboutToAppear(): void {
    this.loadDevices()
  }

  private async loadDevices(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.devices = []
      return
    }
    this.loading = true
    try {
      this.devices = await DeviceService.getDevices()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '获取设备列表失败')
    } finally {
      this.loading = false
    }
  }

  private async kick(device: DeviceItem): Promise<void> {
    if (this.kickingKey) { return }
    this.kickingKey = device.deviceKey
    try {
      await DeviceService.kickDevice(device.deviceKey)
      BubbleTip.show(this.getUIContext(), `已强制下线：${device.deviceName}`)
      await this.loadDevices()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '强制下线失败')
    } finally {
      this.kickingKey = ''
    }
  }

  private async saveAlias(): Promise<void> {
    if (this.aliasSaving) { return }
    this.aliasSaving = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.saveDeviceAlias(context, this.alias)
      BubbleTip.show(this.getUIContext(), '设备别名已上报')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '上报失败')
    } finally {
      this.aliasSaving = false
    }
  }

  private formatTime(value: number): string {
    if (!value) { return '' }
    const date = new Date(value)
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n)
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`
  }

  private deviceSubtitle(device: DeviceItem): string {
    const status = device.online ? '在线' : '离线'
    const parts: string[] = [status]
    if (device.ip) { parts.push(device.ip) }
    if (device.os) { parts.push(device.os) }
    if (!device.online && device.lastActiveTime) {
      parts.push('最近活跃 ' + this.formatTime(device.lastActiveTime))
    }
    return parts.join(' · ')
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('设备管理').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(22).fontColor([TC.textTertiary()])
            .onClick(() => this.loadDevices())
        }.height(56).constraintSize({ minHeight: 56 }).width('100%').padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 12 }) {
              Text('本机设备别名').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              Text('上报到设备中心，便于在其他端识别本机。').fontSize(11).fontColor(TC.textSecondary())
              TextInput({ text: this.alias, placeholder: '例如：我的手机' })
                .height(50).fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceInset())
                .borderRadius(14).onChange((value: string) => this.alias = value)
              Button(this.aliasSaving ? '上报中…' : '上报设备别名')
                .width('100%').height(46).borderRadius(23).fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
                .enabled(!this.aliasSaving).onClick(() => this.saveAlias())
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)

            Column({ space: 12 }) {
              Text('在线设备').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              if (!this.authStore.loggedIn) {
                Text('登录后查看在线设备列表').fontSize(12).fontColor(TC.textSecondary())
              } else if (this.loading) {
                LoadingProgress().width(28).height(28).color(TC.accent())
              } else if (this.devices.length === 0) {
                Text('没有发现其他在线设备').fontSize(12).fontColor(TC.textSecondary())
              } else {
                ForEach(this.devices, (device: DeviceItem) => {
                  Row({ space: 12 }) {
                    Column({ space: 5 }) {
                      Row({ space: 8 }) {
                        Text(device.deviceName).fontSize(14).fontColor(TC.textPrimary()).maxLines(1)
                        if (device.isCurrent) {
                          Text('本机').fontSize(10).fontColor(TC.textOnAccent())
                            .backgroundColor(TC.accent()).borderRadius(8).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        }
                      }
                      Text(this.deviceSubtitle(device)).fontSize(11).fontColor(TC.textSecondary()).maxLines(1)
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    if (device.online && !device.isCurrent) {
                      Button(this.kickingKey === device.deviceKey ? '下线中…' : '强制下线')
                        .fontSize(12).height(36).borderRadius(18).backgroundColor(TC.chipBackground())
                        .fontColor(TC.accentSoft()).enabled(this.kickingKey === '').onClick(() => this.kick(device))
                    }
                  }.width('100%').padding({ top: 8, bottom: 8 })
                }, (device: DeviceItem) => device.deviceKey)
              }
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.width('100%').layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true)
  }
}
