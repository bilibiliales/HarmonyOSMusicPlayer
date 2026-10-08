import { ApiClient } from './ApiClient'
import { ApiParam } from '../models/api'

export interface YunbeiEntry {
  title: string
  description: string
  amount?: number
  time: string
  taskId?: number
  userTaskId?: number
  completed?: boolean
  link?: string
  linkText?: string
  depositCode?: string
}

export interface YunbeiOverview {
  balance?: number
  signed?: boolean
  signDays?: number
  todayAmount?: number
  warnings: string[]
}

export interface YunbeiSignResult {
  signedNow: boolean
  amount: number
}

interface YunbeiUserPoint { balance?: number }

interface YunbeiResponse {
  code: number
  message?: string
  msg?: string
  data?: Object
  userPoint?: YunbeiUserPoint
}

export class YunbeiService {
  private static record(value: Object | undefined): Record<string, Object> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) { return {} }
    return value as Record<string, Object>
  }

  private static numeric(value: Object | undefined): number | undefined {
    return typeof value === 'number' && Number.isFinite(value) ? value : undefined
  }

  private static text(record: Record<string, Object>, keys: string[]): string {
    for (const key of keys) {
      const value = record[key]
      if (typeof value === 'string' && value.trim()) { return value }
    }
    return ''
  }

  private static async request(path: string, params: ApiParam[] = []): Promise<YunbeiResponse> {
    const cookie = ApiClient.cookie
    if (!cookie) { throw new Error('请先登录查看云贝') }
    const response = await ApiClient.get<YunbeiResponse>(path,
      params.concat([{ key: 'timestamp', value: Date.now().toString() }]))
    if (cookie !== ApiClient.cookie) { throw new Error('登录账号已变化，请重新加载') }
    if (!response || response.code !== 200) {
      throw new Error(response?.message || response?.msg || '云贝服务未返回有效数据')
    }
    return response
  }

  static async overview(): Promise<YunbeiOverview> {
    const result: YunbeiOverview = { warnings: [] }
    await Promise.all([
      YunbeiService.request('/yunbei/info').then((response: YunbeiResponse) => {
        result.balance = YunbeiService.numeric(response.userPoint?.balance)
        if (result.balance === undefined) { result.warnings.push('账户接口未返回有效余额') }
      }).catch((error: Error) => { result.warnings.push('账户：' + error.message) }),
      YunbeiService.request('/yunbei').then((response: YunbeiResponse) => {
        const data = YunbeiService.record(response.data)
        result.signDays = YunbeiService.numeric(data['signDays'])
        if (typeof data['signed'] === 'boolean') { result.signed = data['signed'] as boolean }
      }).catch((error: Error) => { result.warnings.push('签到信息：' + error.message) }),
      YunbeiService.request('/yunbei/today').then((response: YunbeiResponse) => {
        const data = YunbeiService.record(response.data)
        result.todayAmount = YunbeiService.numeric(data['todayPoint'])
      }).catch((error: Error) => { result.warnings.push('今日信息：' + error.message) })
    ])
    return result
  }

  static async sign(): Promise<YunbeiSignResult> {
    const response = await YunbeiService.request('/yunbei/sign')
    const data = YunbeiService.record(response.data)
    const amount = YunbeiService.numeric(data['yunbeiNum'])
    if (typeof data['sign'] !== 'boolean' || amount === undefined || amount < 0) {
      throw new Error('签到返回信息不完整，请稍后重试')
    }
    return { signedNow: data['sign'] as boolean, amount: amount }
  }

  static async finish(task: YunbeiEntry): Promise<void> {
    if (!task.userTaskId || task.userTaskId <= 0) { throw new Error('任务尚未生成有效记录，请先前往任务并完成要求') }
    const result = await YunbeiService.request('/yunbei/task/finish', [
      { key: 'userTaskId', value: task.userTaskId.toString() },
      { key: 'depositCode', value: task.depositCode || '0' }
    ])
    // SUCCESS with data:false is valid; always read authoritative task state again.
    if (typeof result.data !== 'boolean') { throw new Error('任务提交返回异常，请刷新查看实际状态') }
  }

  static async entries(kind: string, start: number): Promise<YunbeiEntry[]> {
    let endpoint = '/yunbei/tasks'
    if (kind === 'todo') { endpoint = '/yunbei/tasks/todo' }
    if (kind === 'income') { endpoint = '/yunbei/tasks/receipt' }
    if (kind === 'expense') { endpoint = '/yunbei/tasks/expense' }
    if (kind === 'history') { endpoint = '/yunbei/rcmd/song/history' }
    const response = await YunbeiService.request(endpoint, [
      { key: 'limit', value: '20' }, { key: 'size', value: '20' }, { key: 'offset', value: start.toString() }
    ])
    const data = YunbeiService.record(response.data)
    const raw = Array.isArray(response.data) ? response.data :
      (data['list'] || data['records'] || data['tasks'])
    if (!Array.isArray(raw)) { throw new Error('接口返回的列表结构尚不支持，未展示不确定的数据') }
    return (raw as Object[]).map((item: Object) => {
      const row = YunbeiService.record(item)
      const title = YunbeiService.text(row, ['taskName', 'name', 'description', 'reason'])
      if (!title) { throw new Error('接口返回的条目缺少可识别说明，请稍后重试') }
      const stamp = YunbeiService.numeric(row['createTime']) ?? YunbeiService.numeric(row['time'])
      const entry: YunbeiEntry = {
        title: title,
        description: YunbeiService.text(row, ['taskDescription', 'taskDesc', 'desc']),
        taskId: YunbeiService.numeric(row['taskId']),
        userTaskId: YunbeiService.numeric(row['userTaskId']),
        completed: typeof row['completed'] === 'boolean' ? row['completed'] as boolean : undefined,
        link: YunbeiService.text(row, ['link']),
        linkText: YunbeiService.text(row, ['linkText']),
        depositCode: typeof row['depositCode'] === 'number' || typeof row['depositCode'] === 'string' ? String(row['depositCode']) : '0',
        amount: YunbeiService.numeric(row['taskPoint']) ?? YunbeiService.numeric(row['amount']) ?? YunbeiService.numeric(row['point']),
        time: stamp !== undefined && stamp > 0 ? new Date(stamp).toLocaleString() : ''
      }
      return entry
    })
  }
}
