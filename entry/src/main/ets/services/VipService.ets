import { VipInfoData, VipPackageInfo } from '../models/api'

export interface VipDisplayInfo {
  active: boolean
  isSvip: boolean
  level: number
}

function packageActive(info: VipPackageInfo | undefined, now: number): boolean {
  return !!info && info.vipLevel > 0 && info.expireTime > now
}

export function parseVipInfo(data: VipInfoData | undefined): VipDisplayInfo {
  if (!data) {
    return { active: false, isSvip: false, level: 0 }
  }
  const now = data.now || Date.now()
  if (packageActive(data.redplus, now)) {
    return { active: true, isSvip: true, level: data.redplus?.vipLevel || data.redVipLevel || 0 }
  }
  const standardPackage = packageActive(data.associator, now) ? data.associator : data.musicPackage
  if (packageActive(standardPackage, now)) {
    return {
      active: true,
      isSvip: false,
      level: standardPackage?.vipLevel || data.redVipLevel || 0
    }
  }
  return { active: false, isSvip: false, level: 0 }
}
