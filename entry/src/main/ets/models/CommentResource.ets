import { CommentApiItem, CommentApiUser } from './api'

// All comment entry points identify their resource in the same way.
export interface CommentResource {
  id: string
  type: number
  title?: string
  threadId?: string
}

export interface ResourceCommentUser extends CommentApiUser {
  userId?: number
}

export interface ResourceCommentReply {
  beRepliedCommentId?: number
  content?: string
  user?: ResourceCommentUser
}

export interface ResourceCommentFloor {
  replyCount?: number
  comments?: ResourceComment[]
}

export interface ResourceComment extends CommentApiItem {
  user: ResourceCommentUser
  time?: number
  parentCommentId?: number
  replyCount?: number
  showFloorComment?: ResourceCommentFloor
  beReplied?: ResourceCommentReply[]
}

export interface CommentPageData {
  comments?: ResourceComment[]
  totalCount?: number
  total?: number
  hasMore?: boolean
  more?: boolean
  cursor?: string
  time?: number
  ownerComment?: ResourceComment
}

export interface CommentPageResponse {
  code: number
  message?: string
  msg?: string
  data?: CommentPageData
}

export interface CommentPage {
  comments: ResourceComment[]
  total: number
  totalKnown?: boolean
  hasMore: boolean
  cursor: string
}

export interface CommentMutationResponse {
  code: number
  message?: string
  msg?: string
  comment?: ResourceComment
  data?: ResourceComment
}
