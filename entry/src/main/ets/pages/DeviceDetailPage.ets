import { DeviceItem, DeviceService } from '../services/DeviceService'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'

export interface DeviceDetailParam {
  device: DeviceItem
}

interface InfoEntry {
  label: string
  value: string
}

@Component
export struct DeviceDetailPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number

  @State pageParam: DeviceDetailParam = { device: DeviceService.emptyDevice() }
  @State device: DeviceItem = DeviceService.emptyDevice()
  @State infoEntries: InfoEntry[] = []
  @State kicking: boolean = false

  aboutToAppear(): void {
    if (this.pageParam && this.pageParam.device) {
      this.device = this.pageParam.device
    }
    this.infoEntries = this.buildEntries()
  }

  private buildEntries(): InfoEntry[] {
    const device = this.device
    const list: InfoEntry[] = []
    const push = (label: string, value: string): void => {
      const text = (value || '').trim()
      if (text.length > 0) {
        list.push({ label: label, value: text })
      }
    }
    push('登录状态', device.online ? '在线' : '离线')
    push('设备类型', DeviceService.deviceTypeLabel(device.deviceType))
    push('设备型号', device.deviceModel)
    push('品牌', device.deviceBrand)
    push('系统版本', device.os)
    push('客户端平台', device.platform)
    push('IP 地址', device.ip)
    push('最近活跃', DeviceService.formatTime(device.lastActiveTime))
    push('设备标识', device.deviceKey)
    // 只展示已知的强类型字段；接口里未识别到的原始键一律不展示。
    return list
  }

  private async kick(): Promise<void> {
    if (this.kicking || this.device.deviceKey.length === 0) { return }
    this.kicking = true
    try {
      await DeviceService.kickDevice(this.device.deviceKey)
      BubbleTip.show(this.getUIContext(), `已强制下线：${this.device.deviceName}`)
      this.device.online = false
      this.device.isCurrent = false
      this.pageStack.pop()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '强制下线失败')
    } finally {
      this.kicking = false
    }
  }

  @Builder
  InfoRow(entry: InfoEntry, last: boolean) {
    Column() {
      Row({ space: 12 }) {
        Text(entry.label).fontSize(13).fontColor(TC.textSecondary()).width(88)
        Text(entry.value).fontSize(13).fontColor(TC.textPrimary()).layoutWeight(1)
          .textAlign(TextAlign.End).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ top: 12, bottom: 12 })
      if (!last) {
        Divider().color(TC.divider()).strokeWidth(0.5)
      }
    }.width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('设备详情').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          Row().width(24).height(24)
        }.height(56).constraintSize({ minHeight: 56 }).width('100%').padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 12 }) {
              Stack() {
                Text(DeviceService.initial(this.device.deviceName))
                  .fontSize(26).fontWeight(FontWeight.Bold).fontColor(TC.accentSoft())
              }.width(64).height(64).borderRadius(20).backgroundColor(TC.accentContainer())

              Row({ space: 6 }) {
                Text(this.device.deviceName).fontSize(18).fontWeight(FontWeight.Bold)
                  .fontColor(TC.textPrimary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.device.isCurrent) {
                  Text('本机').fontSize(10).fontColor(TC.textOnAccent())
                    .backgroundColor(TC.accent()).borderRadius(8).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                }
              }

              Row({ space: 6 }) {
                Column().width(6).height(6).borderRadius(3)
                  .backgroundColor(this.device.online ? '#22c55e' : TC.textQuaternary())
                Text(this.device.online ? '在线' : '离线').fontSize(12).fontColor(TC.textSecondary())
              }
            }.width('100%').padding({ top: 22, bottom: 22 })
            .backgroundColor(TC.surfaceCard()).borderRadius(20)

            Column({ space: 0 }) {
              Text('设备信息').width('100%').fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor(TC.textPrimary()).padding({ bottom: 4 })
              if (this.infoEntries.length === 0) {
                Text('暂无更多设备信息').fontSize(12).fontColor(TC.textSecondary()).padding({ top: 12, bottom: 12 })
              } else {
                ForEach(this.infoEntries, (entry: InfoEntry, index: number) => {
                  this.InfoRow(entry, index === this.infoEntries.length - 1)
                }, (entry: InfoEntry, index: number) => `${entry.label}-${index}`)
              }
            }.width('100%').padding({ left: 18, right: 18, top: 16, bottom: 8 })
            .backgroundColor(TC.surfaceCard()).borderRadius(20)

            if (!this.device.isCurrent && this.device.online && this.device.deviceKey.length > 0) {
              Button(this.kicking ? '下线中…' : '强制下线该设备')
                .width('100%').height(46).borderRadius(23)
                .fontColor(TC.accentSoft()).backgroundColor(TC.accentContainer())
                .enabled(!this.kicking).onClick(() => this.kick())
              Text('下线后该设备需要重新登录才能继续同步数据').fontSize(11).fontColor(TC.textQuaternary())
                .textAlign(TextAlign.Center).width('100%')
            } else if (this.device.isCurrent) {
              Text('这是当前正在使用的设备，无法在此下线').fontSize(11).fontColor(TC.textQuaternary())
                .textAlign(TextAlign.Center).width('100%')
            }
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.width('100%').layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(TC.pageBackground())
    }.hideTitleBar(true)
  }
}
