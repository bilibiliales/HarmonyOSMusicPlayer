import { ApiClient } from './ApiClient'

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

interface DeviceListResponse {
  code: number
  message?: string
  data: object
}

export class DeviceService {
  // 获取在线设备列表（需登录）
  static async getDevices(): Promise<DeviceItem[]> {
    const resp = await ApiClient.get<DeviceListResponse>('/device/list')
    if (!resp || resp.code !== 200 || !resp.data) {
      return []
    }
    let list: DeviceItem[] = []
    const data = resp.data as Object
    if (Array.isArray(data)) {
      list = data as DeviceItem[]
    } else if (typeof data === 'object' && data !== null) {
      const obj = data as Record<string, Object>
      for (const key of Object.keys(obj)) {
        const value = obj[key]
        if (Array.isArray(value)) {
          list = value as DeviceItem[]
          break
        }
      }
    }
    return list.map((item: DeviceItem) => DeviceService.normalize(item))
  }

  private static normalize(item: DeviceItem): DeviceItem {
    const fallbackName = item.deviceName || item.deviceModel || item.deviceBrand ||
      item.deviceType || '未知设备'
    return {
      deviceKey: String(item.deviceKey || ''),
      deviceName: String(fallbackName),
      deviceType: String(item.deviceType || ''),
      deviceModel: String(item.deviceModel || ''),
      deviceBrand: String(item.deviceBrand || ''),
      os: String(item.os || ''),
      ip: String(item.ip || ''),
      online: !!item.online,
      isCurrent: !!item.isCurrent,
      lastActiveTime: Number(item.lastActiveTime || 0),
      platform: String(item.platform || '')
    }
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
