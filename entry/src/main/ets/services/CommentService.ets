import { ApiParam } from '../models/api'
import { CommentMutationResponse, CommentPage, CommentPageResponse, CommentResource, ResourceComment } from '../models/CommentResource'
import { ApiClient } from './ApiClient'

export class CommentService {
  private static validate(resource: CommentResource): void {
    if (!Number.isInteger(resource.type) || resource.type < 0 || resource.type > 7 ||
      !(resource.threadId || resource.id)) {
      throw new Error('评论资源无效')
    }
  }

  private static threadId(resource: CommentResource): string {
    const value = resource.threadId || resource.id
    if (!value.startsWith('A_EV_2_')) {
      if (!value.includes('_')) { throw new Error('缺少动态评论标识') }
      return `A_EV_2_${value}`
    }
    return value
  }

  private static readParams(resource: CommentResource): ApiParam[] {
    CommentService.validate(resource)
    // The backend's comment_new/floor prepend resourceTypeMap[type] themselves.
    const id = resource.type === 6 ? CommentService.threadId(resource).substring('A_EV_2_'.length) : resource.id
    return [{ key: 'type', value: resource.type.toString() }, { key: 'id', value: id },
      { key: 'timestamp', value: Date.now().toString() }]
  }

  private static writeParams(resource: CommentResource): ApiParam[] {
    CommentService.validate(resource)
    const params: ApiParam[] = [{ key: 'type', value: resource.type.toString() },
      { key: 'timestamp', value: Date.now().toString() }]
    params.push(resource.type === 6 ? { key: 'threadId', value: CommentService.threadId(resource) } :
      { key: 'id', value: resource.id })
    return params
  }

  private static page(response: CommentPageResponse, size: number): CommentPage {
    if (response.code !== 200 || !response.data) {
      throw new Error(response.message || response.msg || '评论加载失败')
    }
    const data = response.data
    const comments = data.comments || []
    const last = comments.length > 0 ? comments[comments.length - 1] : undefined
    const rawTotal = data.totalCount ?? data.total
    const totalKnown = typeof rawTotal === 'number' && Number.isFinite(rawTotal) && rawTotal >= 0
    return { comments: comments, total: totalKnown ? Number(rawTotal) : 0, totalKnown: totalKnown,
      hasMore: data.hasMore ?? data.more ?? comments.length >= size,
      cursor: last?.time ? last.time.toString() : String(data.time || data.cursor || '') }
  }

  static async list(resource: CommentResource, pageNo: number = 1, sortType: number = 1,
    cursor: string = '', pageSize: number = 20): Promise<CommentPage> {
    const params = CommentService.readParams(resource)
    params.push({ key: 'pageNo', value: pageNo.toString() }, { key: 'pageSize', value: pageSize.toString() },
      { key: 'sortType', value: sortType.toString() })
    if (sortType === 3 && pageNo > 1 && cursor) { params.push({ key: 'cursor', value: cursor }) }
    return CommentService.page(await ApiClient.get<CommentPageResponse>('/comment/new', params), pageSize)
  }

  static async count(resource: CommentResource): Promise<number> {
    const page = await CommentService.list(resource, 1, 1, '', 1)
    if (!page.totalKnown) { throw new Error('接口未返回评论总数') }
    return page.total
  }

  static async floor(resource: CommentResource, parentCommentId: number, time: string = ''): Promise<CommentPage> {
    const params = CommentService.readParams(resource)
    params.push({ key: 'parentCommentId', value: parentCommentId.toString() }, { key: 'limit', value: '20' })
    if (time) { params.push({ key: 'time', value: time }) }
    return CommentService.page(await ApiClient.get<CommentPageResponse>('/comment/floor', params), 20)
  }

  static async readComment(resource: CommentResource, commentId: number): Promise<ResourceComment | undefined> {
    if (!Number.isFinite(commentId) || commentId <= 0) { throw new Error('评论标识无效') }
    const params = CommentService.readParams(resource)
    params.push({ key: 'parentCommentId', value: commentId.toString() }, { key: 'limit', value: '20' })
    const response = await ApiClient.get<CommentPageResponse>('/comment/floor', params)
    if (response.code !== 200 || !response.data) {
      throw new Error(response.message || response.msg || '评论状态读取失败') }
    const owner = response.data.ownerComment
    if (owner?.commentId === commentId) { return owner }
    // A nested reply can return another owner; only an exact ID match is authoritative.
    return (response.data.comments || []).find((item: ResourceComment) => item.commentId === commentId)
  }

  static async like(resource: CommentResource, commentId: number, liked: boolean): Promise<void> {
    const params = CommentService.writeParams(resource)
    params.push({ key: 'cid', value: commentId.toString() }, { key: 't', value: liked ? '1' : '0' })
    const response = await ApiClient.get<CommentMutationResponse>('/comment/like', params)
    if (response.code !== 200) { throw new Error(response.message || response.msg || '评论点赞失败') }
  }

  static async send(resource: CommentResource, content: string, replyTo: number = 0): Promise<CommentMutationResponse> {
    const params = CommentService.writeParams(resource)
    params.push({ key: 't', value: replyTo ? '2' : '1' }, { key: 'content', value: content })
    if (replyTo) { params.push({ key: 'commentId', value: replyTo.toString() }) }
    const response = await ApiClient.get<CommentMutationResponse>('/comment', params)
    if (response.code !== 200) { throw new Error(response.message || response.msg || '评论发送失败') }
    return response
  }

  static async remove(resource: CommentResource, commentId: number): Promise<void> {
    const params = CommentService.writeParams(resource)
    params.push({ key: 't', value: '0' }, { key: 'commentId', value: commentId.toString() })
    const response = await ApiClient.get<CommentMutationResponse>('/comment', params)
    if (response.code !== 200) { throw new Error(response.message || response.msg || '评论删除失败') }
  }
}
