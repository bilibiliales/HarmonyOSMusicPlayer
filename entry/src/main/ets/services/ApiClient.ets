import { http } from '@kit.NetworkKit'
import { ApiParam } from '../models/api'

export class ApiClient {
  static baseUrl: string = 'https://music.zdjlales.icu'
  static cookie: string = ''

  static setBaseUrl(value: string): void {
    const normalized = value.trim().replace(/\/$/, '')
    if (normalized.length > 0) {
      ApiClient.baseUrl = normalized
    }
  }

  static setCookie(value: string): void {
    ApiClient.cookie = value
  }

  static buildUrl(path: string, params: ApiParam[] = []): string {
    const query = params
      .filter((item: ApiParam) => item.value.length > 0)
      .map((item: ApiParam) => `${encodeURIComponent(item.key)}=${encodeURIComponent(item.value)}`)
      .join('&')
    return `${ApiClient.baseUrl}${path}${query.length > 0 ? `?${query}` : ''}`
  }

  static async get<T>(path: string, params: ApiParam[] = []): Promise<T> {
    const request = http.createHttp()
    try {
      const finalParams: ApiParam[] = params.slice()
      const hasCookieParam = finalParams.some((item: ApiParam) => item.key === 'cookie')
      if (ApiClient.cookie.length > 0 && !hasCookieParam) {
        finalParams.push({ key: 'cookie', value: ApiClient.cookie })
      }
      const response = await request.request(ApiClient.buildUrl(path, finalParams), {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json',
          'Cookie': ApiClient.cookie
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 20000,
        usingCache: false
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`服务请求失败 (${response.responseCode})`)
      }
      return JSON.parse(response.result as string) as T
    } finally {
      request.destroy()
    }
  }

  static async post<T>(path: string, params: ApiParam[] = []): Promise<T> {
    const request = http.createHttp()
    try {
      const body = params
        .filter((item: ApiParam) => item.value.length > 0)
        .map((item: ApiParam) => `${encodeURIComponent(item.key)}=${encodeURIComponent(item.value)}`)
        .join('&')
      const response = await request.request(ApiClient.buildUrl(path), {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': ApiClient.cookie
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 20000,
        usingCache: false
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`服务请求失败 (${response.responseCode})`)
      }
      return JSON.parse(response.result as string) as T
    } finally {
      request.destroy()
    }
  }

  static async postJson<T>(path: string, jsonBody: Record<string, string> = {}): Promise<T> {
    const request = http.createHttp()
    try {
      const bodyObj: Record<string, string> = {}
      const keys = Object.keys(jsonBody)
      for (let i = 0; i < keys.length; i++) {
        bodyObj[keys[i]] = jsonBody[keys[i]]
      }
      if (ApiClient.cookie.length > 0) {
        bodyObj['cookie'] = ApiClient.cookie
      }
      const response = await request.request(ApiClient.buildUrl(path), {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Cookie': ApiClient.cookie
        },
        extraData: JSON.stringify(bodyObj),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 20000,
        usingCache: false
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`服务请求失败 (${response.responseCode})`)
      }
      return JSON.parse(response.result as string) as T
    } finally {
      request.destroy()
    }
  }

  static async upload<T>(path: string, params: ApiParam[], fileField: string, fileName: string,
    fileData: ArrayBuffer, contentType: string): Promise<T> {
    const request = http.createHttp()
    try {
      const formData: http.MultiFormData[] = params
        .filter((item: ApiParam) => item.value.length > 0)
        .map((item: ApiParam): http.MultiFormData => {
          return { name: item.key, contentType: 'text/plain', data: item.value }
        })
      formData.push({
        name: fileField,
        contentType: contentType,
        remoteFileName: fileName,
        data: fileData
      })
      const response = await request.request(ApiClient.buildUrl(path), {
        method: http.RequestMethod.POST,
        header: { 'Cookie': ApiClient.cookie },
        multiFormDataList: formData,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingCache: false
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`文件上传失败 (${response.responseCode})`)
      }
      return JSON.parse(response.result as string) as T
    } finally {
      request.destroy()
    }
  }

  static async callOpenAIApi<T>(endpoint: string, body: Record<string, any>, headers: Record<string, string>): Promise<T> {
    const request = http.createHttp()
    try {
      const response = await request.request(endpoint, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: false
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`AI 服务请求失败 (${response.responseCode})`)
      }
      return JSON.parse(response.result as string) as T
    } finally {
      request.destroy()
    }
  }
}