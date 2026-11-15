import { deviceInfo } from '@kit.BasicServicesKit'
import { ApiClient } from './ApiClient'
import { AppSettings } from './AppSettings'

export interface DeviceItem {
  deviceKey: string
  deviceName: string
  deviceType: string
  deviceModel: string
  deviceBrand: string
  os: string
  ip: string
  online: boolean
  isCurrent: boolean
  lastActiveTime: number
  platform: string
}

/** 设备数上限档位：非会员 5 台 / 黑胶VIP 8 台 / 黑胶SVIP 10 台。 */
export interface DeviceQuotaTier {
  name: string
  limit: number
}

interface DeviceListResponse {
  code: number
  message?: string
  data: object
}

export class DeviceService {
  static readonly TIERS: DeviceQuotaTier[] = [
    { name: '非会员', limit: 5 },
    { name: '黑胶VIP', limit: 8 },
    { name: '黑胶SVIP', limit: 10 }
  ]

  static tierLimit(tierIndex: number): number {
    const safe = Math.max(0, Math.min(tierIndex, DeviceService.TIERS.length - 1))
    return DeviceService.TIERS[safe].limit
  }

  static emptyDevice(): DeviceItem {
    return {
      deviceKey: '', deviceName: '', deviceType: '', deviceModel: '', deviceBrand: '', os: '', ip: '',
      online: false, isCurrent: false, lastActiveTime: 0, platform: ''
    }
  }

  /** 设备头像用的首字（含代理对字符安全）。 */
  static initial(name: string): string {
    const text = (name || '').trim()
    if (text.length === 0) {
      return '设'
    }
    const first = text.charCodeAt(0)
    if (first >= 0xD800 && first <= 0xDBFF) {
      return text.slice(0, 2)
    }
    return text.slice(0, 1).toUpperCase()
  }

  static formatTime(value: number): string {
    if (!value) {
      return ''
    }
    // 兼容秒级 / 毫秒级时间戳
    const millis = value < 100000000000 ? value * 1000 : value
    const date = new Date(millis)
    if (Number.isNaN(date.getTime())) {
      return ''
    }
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n)
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}`
  }

  /** 设备类型的中文名（接口可能给 phone / tablet / pc 等英文枚举）。 */
  static deviceTypeLabel(type: string): string {
    const key = (type || '').trim().toLowerCase()
    if (key === 'phone' || key === 'mobile' || key === 'smartphone') { return '手机' }
    if (key === 'tablet' || key === 'pad') { return '平板' }
    if (key === 'pc' || key === 'laptop' || key === 'computer' || key === 'desktop') { return '电脑' }
    if (key === 'tv' || key === 'smarttv') { return '智慧屏' }
    if (key === 'watch' || key === 'wearable') { return '手表' }
    if (key === 'car' || key === 'headunit') { return '车机' }
    if (key === 'speaker' || key === 'sound') { return '音箱' }
    return (type || '').trim()
  }

  // 获取在线设备列表（需登录）
  static async getDevices(): Promise<DeviceItem[]> {
    const resp = await ApiClient.get<DeviceListResponse>('/device/list')
    if (!resp || resp.code !== 200 || !resp.data) {
      return []
    }
    let raw: Object[] = []
    const data = resp.data as Object
    if (Array.isArray(data)) {
      raw = data as Object[]
    } else if (typeof data === 'object' && data !== null) {
      const obj = data as Record<string, Object>
      for (const key of Object.keys(obj)) {
        const value = obj[key]
        if (Array.isArray(value)) {
          raw = value as Object[]
          break
        }
      }
    }
    const list = raw.filter((item: Object) => item !== null && typeof item === 'object')
      .map((item: Object) => DeviceService.normalize(item as Record<string, Object>))
    return DeviceService.markCurrent(list)
  }

  private static textOf(obj: Record<string, Object>, key: string): string {
    const value = obj[key]
    if (typeof value === 'string') {
      return value
    }
    if (typeof value === 'number') {
      return value.toString()
    }
    if (typeof value === 'boolean') {
      return value ? 'true' : 'false'
    }
    return ''
  }

  private static truthy(value: string): boolean {
    const text = value.trim().toLowerCase()
    return text === 'true' || text === '1' || text === 'yes'
  }

  private static number(value: string): number {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) {
      return parsed
    }
    // 兼容日期字符串（部分服务端直接下发 ISO 时间）
    const time = Date.parse(value)
    return Number.isNaN(time) ? 0 : time
  }

  private static normalize(item: Record<string, Object>): DeviceItem {
    const name = DeviceService.textOf(item, 'deviceName')
    const model = DeviceService.textOf(item, 'deviceModel')
    const brand = DeviceService.textOf(item, 'deviceBrand')
    const type = DeviceService.textOf(item, 'deviceType')
    // 只映射已知字段；接口里多余/未识别的键不进模型，详情页也不会展示。
    return {
      deviceKey: DeviceService.textOf(item, 'deviceKey') || DeviceService.textOf(item, 'deviceId') ||
        DeviceService.textOf(item, 'clientId'),
      deviceName: name || model || brand || type || '未知设备',
      deviceType: type,
      deviceModel: model,
      deviceBrand: brand,
      os: DeviceService.textOf(item, 'os'),
      ip: DeviceService.textOf(item, 'ip'),
      online: DeviceService.truthy(DeviceService.textOf(item, 'online')),
      isCurrent: DeviceService.truthy(DeviceService.textOf(item, 'isCurrent')),
      lastActiveTime: DeviceService.number(DeviceService.textOf(item, 'lastActiveTime')),
      platform: DeviceService.textOf(item, 'platform')
    }
  }

  /** 本机可能出现在设备中心里的名字（别名优先，其次系统型号名）。 */
  private static localNames(): string[] {
    const names: string[] = []
    const push = (value: string): void => {
      const text = (value || '').trim()
      if (text.length > 0 && !names.includes(text)) {
        names.push(text)
      }
    }
    push(AppSettings.deviceAlias)
    push(deviceInfo.marketName)
    push(deviceInfo.productModel)
    return names
  }

  /**
   * 接口没有返回 isCurrent 时，用「上报别名 / 本机型号名」在列表里认领本机；
   * 只有一个设备时直接认定（此时必然就是本机）。无法确认时不打标签，避免标错。
   */
  static markCurrent(list: DeviceItem[]): DeviceItem[] {
    if (list.some((item: DeviceItem) => item.isCurrent)) {
      return list
    }
    const names = DeviceService.localNames()
    let target = -1
    for (let index = 0; index < list.length; index++) {
      const name = (list[index].deviceName || '').trim()
      const model = (list[index].deviceModel || '').trim()
      if (names.includes(name) || (model.length > 0 && names.includes(model))) {
        target = index
        break
      }
    }
    if (target < 0 && list.length === 1) {
      target = 0
    }
    if (target >= 0) {
      list[target].isCurrent = true
    }
    return list
  }

  // 强制下线指定设备
  static async kickDevice(deviceKey: string): Promise<void> {
    await ApiClient.get<Object>('/device/kickoff', [
      { key: 'deviceKey', value: deviceKey }
    ])
  }

  // 上报设备中心设备别名：/deviceinfo/center/upload?deviceName=XXXXX
  static async uploadDeviceName(name: string): Promise<void> {
    await ApiClient.get<Object>('/deviceinfo/center/upload', [
      { key: 'deviceName', value: name }
    ])
  }
}
