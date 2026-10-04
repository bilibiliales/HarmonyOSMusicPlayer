export type UserSettingValue = boolean | number | string | null
export type UserSettings = Record<string, UserSettingValue>
export type UserSettingsPatch = Record<string, boolean | number | string>

export interface UserSettingsResponse {
  code: number
  setting?: UserSettings
  message?: string
  msg?: string
}

export interface UserSettingsUpdateResponse {
  code: number
  message?: string
  msg?: string
}

export interface SettingsReadback {
  settings?: UserSettings
  confirmed: boolean
  message: string
}

export function playRecordVisibilityPatch(allowed: boolean): UserSettingsPatch {
  const patch: UserSettingsPatch = {}
  patch['allowPeopleCanSeeMyPlayRecord'] = allowed
  return patch
}
