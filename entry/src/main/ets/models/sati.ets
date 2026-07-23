export interface SatiScene {
  sceneId?: string
  text?: string
  startTime?: string
  endTime?: string
}

export interface SatiResource {
  id: number
  djProgramId?: number
  trackId: number
  name: string
  pic: string
  dynamicEffectUrl?: string
  category?: string
  resourceType?: number
}

export interface SatiTimeSceneData {
  sceneVO?: SatiScene
  voiceSatiResourceVOList?: SatiResource[]
}

export interface SatiTimeSceneResponse {
  code: number
  data?: SatiTimeSceneData
  message?: string
}

export interface SatiTag {
  tag: string
  tagDesc: string
  text?: string
}

export interface SatiTagResponse {
  code: number
  data?: SatiTag[]
  message?: string
}

export interface SatiResourceListResponse {
  code: number
  data?: SatiResource[]
  message?: string
}

export interface SatiMoreData {
  tagDesc?: string
  resourceList?: SatiResource[]
}

export interface SatiMoreResponse {
  code: number
  data?: SatiMoreData
  message?: string
}

export interface SatiSubListResponse {
  code: number
  data?: SatiResource[]
  message?: string
}

export interface SatiOperationResponse {
  code: number
  message?: string
}
