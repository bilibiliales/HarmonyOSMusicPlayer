import { common } from '@kit.AbilityKit'
import { ApiClient } from '../services/ApiClient'
import { AppSettings } from '../services/AppSettings'
import { DeviceItem, DeviceQuotaTier, DeviceService } from '../services/DeviceService'
import { DeviceDetailParam } from './DeviceDetailPage'
import { BubbleTip } from '../services/BubbleTip'
import { AuthStore } from '../stores/AuthStore'
import { TC } from '../services/ThemeColors'
import { VipInfoResponse } from '../models/api'
import { parseVipInfo } from '../services/VipService'

@Component
export struct DeviceManagementPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore

  @State devices: DeviceItem[] = []
  @State loading: boolean = false
  @State alias: string = AppSettings.deviceAlias || AppSettings.localDeviceName()
  @State aliasSaving: boolean = false
  @State vipActive: boolean = false
  @State vipSvip: boolean = false
  private firstShown: boolean = true

  aboutToAppear(): void {
    this.loadDevices()
    this.loadVip()
  }

  private quotaTierIndex(): number {
    return this.vipSvip ? 2 : (this.vipActive ? 1 : 0)
  }

  private quotaLimit(): number {
    return DeviceService.tierLimit(this.quotaTierIndex())
  }

  private currentDeviceName(): string {
    const current = this.devices.find((item: DeviceItem) => item.isCurrent)
    return current ? current.deviceName : ''
  }

  private async loadVip(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.vipActive = false
      this.vipSvip = false
      return
    }
    try {
      const response = await ApiClient.get<VipInfoResponse>('/vip/info', [
        { key: 'uid', value: this.authStore.userId }
      ])
      const display = parseVipInfo(response.data)
      this.vipActive = display.active
      this.vipSvip = display.isSvip
    } catch (_error) {
      this.vipActive = false
      this.vipSvip = false
    }
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

  private async saveAlias(): Promise<void> {
    if (this.aliasSaving) { return }
    this.aliasSaving = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await AppSettings.saveDeviceAlias(context, this.alias)
      this.alias = AppSettings.deviceAlias
      BubbleTip.show(this.getUIContext(), '设备别名已上报')
      await this.loadDevices()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '上报失败')
    } finally {
      this.aliasSaving = false
    }
  }

  private openDetail(device: DeviceItem): void {
    const param: DeviceDetailParam = { device: device }
    this.pageStack.pushPathByName('DeviceDetailPage', param)
  }

  @Builder
  QuotaTier(tier: DeviceQuotaTier, active: boolean) {
    Column({ space: 3 }) {
      Row({ space: 4 }) {
        Text(tier.name).fontSize(11).fontColor(active ? TC.accentSoft() : TC.textSecondary())
          .fontWeight(active ? FontWeight.Medium : FontWeight.Normal).maxLines(1)
        if (active) {
          Text('当前').fontSize(9).fontColor(TC.textOnAccent())
            .backgroundColor(TC.accent()).borderRadius(6).padding({ left: 4, right: 4, top: 1, bottom: 1 })
        }
      }.justifyContent(FlexAlign.Center).width('100%')

      Text(`${tier.limit} 台`).fontSize(14).fontWeight(FontWeight.Bold)
        .fontColor(active ? TC.accentSoft() : TC.textPrimary())
    }
    .layoutWeight(1).padding({ top: 9, bottom: 9 })
    .backgroundColor(active ? TC.accentContainer() : TC.surfaceInset())
    .borderRadius(12)
    .border({ width: active ? 1 : 0, color: TC.accentSoft() })
  }

  @Builder
  DeviceRow(device: DeviceItem) {
    Row({ space: 12 }) {
      Stack() {
        Text(DeviceService.initial(device.deviceName)).fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor(TC.accentSoft())
      }.width(38).height(38).borderRadius(12).backgroundColor(TC.accentContainer())

      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(device.deviceName).fontSize(14).fontColor(TC.textPrimary()).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (device.isCurrent) {
            Text('本机').fontSize(10).fontColor(TC.textOnAccent())
              .backgroundColor(TC.accent()).borderRadius(8).padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
        }.width('100%')

        Text(this.deviceSubtitle(device)).fontSize(11).fontColor(TC.textSecondary()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([TC.textQuaternary()])
    }
    .width('100%').padding({ top: 10, bottom: 10 })
    .onClick(() => this.openDetail(device))
  }

  private deviceSubtitle(device: DeviceItem): string {
    const status = device.online ? '在线' : '离线'
    const parts: string[] = [status]
    if (device.ip) { parts.push(device.ip) }
    if (device.os) { parts.push(device.os) }
    if (!device.online && device.lastActiveTime) {
      parts.push('最近活跃 ' + DeviceService.formatTime(device.lastActiveTime))
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
            Column({ space: 14 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('我的设备').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                  Text(this.authStore.loggedIn ?
                    `已登录 ${this.devices.length} 台，当前档位最多可管理 ${this.quotaLimit()} 台` :
                    '登录后可查看并管理已登录设备').fontSize(11).fontColor(TC.textSecondary())
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.authStore.loggedIn) {
                  Text(`${this.devices.length}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(TC.accent())
                  Text(` / ${this.quotaLimit()}`).fontSize(12).fontColor(TC.textTertiary())
                }
              }.width('100%')

              Row({ space: 8 }) {
                ForEach(DeviceService.TIERS, (tier: DeviceQuotaTier, index: number) => {
                  this.QuotaTier(tier, index === this.quotaTierIndex())
                }, (tier: DeviceQuotaTier, index: number) =>
                `${tier.name}-${index === this.quotaTierIndex() ? 'on' : 'off'}`)
              }.width('100%')

              if (this.currentDeviceName().length > 0) {
                Row({ space: 6 }) {
                  Text('本机').fontSize(10).fontColor(TC.textOnAccent())
                    .backgroundColor(TC.accent()).borderRadius(8).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  Text(this.currentDeviceName()).fontSize(12).fontColor(TC.textBody()).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                }.width('100%')
              }
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)

            Column({ space: 12 }) {
              Text('本机设备别名').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              Text('上报到设备中心，便于在其他端识别本机；默认取本机型号名。').fontSize(11).fontColor(TC.textSecondary())
              TextInput({ text: this.alias, placeholder: AppSettings.localDeviceName() })
                .height(50).fontColor(TC.textPrimary()).placeholderColor(TC.textQuaternary()).backgroundColor(TC.surfaceInset())
                .borderRadius(14).onChange((value: string) => this.alias = value)
              Button(this.aliasSaving ? '上报中…' : '上报设备别名')
                .width('100%').height(46).borderRadius(23).fontColor(TC.textOnAccent()).backgroundColor(TC.accent())
                .enabled(!this.aliasSaving).onClick(() => this.saveAlias())
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)

            Column({ space: 12 }) {
              Text('登录设备').width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              if (!this.authStore.loggedIn) {
                Text('登录后查看设备列表').fontSize(12).fontColor(TC.textSecondary())
              } else if (this.loading) {
                LoadingProgress().width(28).height(28).color(TC.accent())
              } else if (this.devices.length === 0) {
                Text('暂无登录设备记录').fontSize(12).fontColor(TC.textSecondary())
              } else {
                ForEach(this.devices, (device: DeviceItem, index: number) => {
                  Column() {
                    this.DeviceRow(device)
                    if (index < this.devices.length - 1) {
                      Divider().color(TC.divider()).strokeWidth(0.5)
                    }
                  }.width('100%')
                }, (device: DeviceItem) => `${device.deviceKey}|${device.deviceName}|${device.isCurrent ? 1 : 0}|` +
                  `${device.online ? 1 : 0}|${device.ip}|${device.lastActiveTime}`)
              }
            }.width('100%').padding(18).backgroundColor(TC.surfaceCard()).borderRadius(20)

            if (this.devices.length > 0) {
              Text('点击设备可查看详细信息，非本机设备可在详情页强制下线')
                .fontSize(11).fontColor(TC.textQuaternary()).textAlign(TextAlign.Center).width('100%')
            }
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.width('100%').layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true).onShown(() => {
      if (this.firstShown) {
        this.firstShown = false
        return
      }
      this.loadDevices()
    })
  }
}
