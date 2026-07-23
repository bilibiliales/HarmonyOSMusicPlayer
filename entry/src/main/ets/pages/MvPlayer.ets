import { common } from '@kit.AbilityKit'
import { PiPWindow } from '@kit.ArkUI'
import { request } from '@kit.BasicServicesKit'
import { fileIo, picker } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { systemShare } from '@kit.ShareKit'
import {
  CommentApiItem,
  CommentResponse,
  MvDetailArtist,
  MvDetailInfoResponse,
  MvDetailResponse,
  MvPlayerPageParam,
  MvUrlResponse,
  OperationResponse
} from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'

@Component
export struct MvPlayerPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: MvPlayerPageParam = { id: '', name: '' }

  @State videoUrl: string = ''
  @State loading: boolean = true
  @State message: string = ''
  @State actionMessage: string = ''
  @State selectedResolution: number = 1080
  @State actualResolution: number = 0
  @State isPlaying: boolean = false
  @State liked: boolean = false
  @State likedCount: number = 0
  @State shareCount: number = 0
  @State commentCount: number = 0
  @State mvName: string = this.pageParam.name
  @State mvCover: string = this.pageParam.cover || ''
  @State mvArtistName: string = this.pageParam.artistName || ''
  @State mvDuration: number = this.pageParam.duration || 0
  @State mvPlayCount: number = this.pageParam.playCount || 0
  @State mvPublishTime: string = this.pageParam.publishTime || ''
  @State mvDescription: string = ''
  @State likeSubmitting: boolean = false
  @State commentSheetVisible: boolean = false
  @State commentsLoading: boolean = false
  @State comments: CommentApiItem[] = []
  @State commentInput: string = ''
  @State commentSubmitting: boolean = false
  @State downloading: boolean = false
  @State downloadProgress: number = 0
  @State pipSupported: boolean = false
  @State pipActive: boolean = false
  @State pipStarting: boolean = false
  private controller: VideoController = new VideoController()
  private pipSurfaceController: XComponentController = new XComponentController()
  private pipSurfaceId: string = ''
  private pipPlayer?: media.AVPlayer
  private pipController?: PiPWindow.PiPController
  private videoPositionSeconds: number = 0
  private pipPositionMs: number = 0
  private resumeAfterPipRestore: boolean = false
  private mainWasPlaying: boolean = false
  private readonly resolutions: number[] = [1080, 720, 480, 240]
  private requestToken: number = 0
  private mvId: string = ''

  async aboutToAppear(): Promise<void> {
    this.mvId = this.pageParam.id
    await playerController.pause()
    try {
      this.pipSupported = PiPWindow.isPiPEnabled()
    } catch (_error) {
      this.pipSupported = false
    }
    await this.loadMvDetail()
    await this.loadDetailInfo()
    this.loadCommentSummary()
    await this.loadVideoUrl(this.selectedResolution)
  }

  aboutToDisappear(): void {
    this.stopPipForPageExit()
    try {
      this.controller.stop()
    } catch (_error) {
    }
  }

  private async releasePipPlayer(): Promise<void> {
    const player = this.pipPlayer
    this.pipPlayer = undefined
    if (!player || player.state === 'released') {
      return
    }
    try {
      await player.release()
    } catch (_error) {
    }
  }

  private stopPipForPageExit(): void {
    const controller = this.pipController
    this.pipController = undefined
    this.pipActive = false
    this.pipStarting = false
    if (controller) {
      try {
        controller.off('stateChange')
        controller.off('controlPanelActionEvent')
        controller.stopPiP().catch(() => {
        })
      } catch (_error) {
      }
    }
    this.releasePipPlayer()
  }

  private syncPipPlayStatus(playing: boolean): void {
    try {
      this.pipController?.updatePiPControlStatus(PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE)
    } catch (_error) {
    }
  }

  private async preparePipPlayer(): Promise<void> {
    await this.releasePipPlayer()
    const player = await media.createAVPlayer()
    this.pipPlayer = player
    this.pipPositionMs = Math.max(0, Math.floor(this.videoPositionSeconds * 1000))
    await new Promise<void>((resolve, reject) => {
      let settled = false
      const fail = (message: string): void => {
        if (!settled) {
          settled = true
          reject(new Error(message))
        }
      }
      player.on('stateChange', (state: media.AVPlayerState) => {
        if (player !== this.pipPlayer) {
          return
        }
        if (state === 'initialized') {
          try {
            player.surfaceId = this.pipSurfaceId
            player.prepare().catch(() => fail('MV 小窗准备失败'))
          } catch (_error) {
            fail('MV 小窗渲染窗口初始化失败')
          }
        } else if (state === 'prepared') {
          if (this.pipPositionMs > 0) {
            player.seek(this.pipPositionMs)
          }
          player.play().then(() => {
            if (!settled) {
              settled = true
              resolve()
            }
          }).catch(() => fail('MV 小窗播放启动失败'))
        } else if (state === 'playing') {
          this.syncPipPlayStatus(true)
        } else if (state === 'paused' || state === 'completed') {
          this.syncPipPlayStatus(false)
        }
      })
      player.on('timeUpdate', (time: number) => {
        if (player === this.pipPlayer) {
          this.pipPositionMs = Math.max(0, time)
        }
      })
      player.on('error', (error) => {
        fail(error.message || 'MV 小窗播放器发生错误')
      })
      try {
        player.url = this.videoUrl
      } catch (_error) {
        fail('MV 小窗播放地址设置失败')
      }
    })
  }

  private handlePipControl(event: PiPWindow.PiPActionEventType, status?: number): void {
    if (event !== 'playbackStateChanged' || status === undefined || !this.pipPlayer) {
      return
    }
    if (status === PiPWindow.PiPControlStatus.PLAY &&
      (this.pipPlayer.state === 'prepared' || this.pipPlayer.state === 'paused' ||
        this.pipPlayer.state === 'completed')) {
      this.pipPlayer.play().catch(() => {
      })
    } else if (status === PiPWindow.PiPControlStatus.PAUSE && this.pipPlayer.state === 'playing') {
      this.pipPlayer.pause().catch(() => {
      })
    }
  }

  private handlePipState(state: PiPWindow.PiPState, reason: string): void {
    if (state === PiPWindow.PiPState.STARTED) {
      this.pipActive = true
      this.pipStarting = false
    } else if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
      this.resumeAfterPipRestore = true
    } else if (state === PiPWindow.PiPState.STOPPED) {
      const shouldResume = this.resumeAfterPipRestore
      const wasPlaying = this.pipPlayer?.state === 'playing'
      const positionSeconds = this.pipPositionMs / 1000
      this.pipActive = false
      this.pipStarting = false
      this.resumeAfterPipRestore = false
      this.pipController = undefined
      this.releasePipPlayer()
      if (shouldResume) {
        try {
          this.controller.setCurrentTime(positionSeconds)
          if (wasPlaying || this.mainWasPlaying) {
            this.controller.start()
          }
        } catch (_error) {
        }
      }
    } else if (state === PiPWindow.PiPState.ERROR) {
      this.pipActive = false
      this.pipStarting = false
      this.actionMessage = reason || 'MV 小窗播放发生错误'
    }
  }

  private async startPip(): Promise<void> {
    if (this.pipStarting || this.pipActive) {
      return
    }
    if (!this.pipSupported) {
      this.actionMessage = '当前设备或系统设置未开启画中画功能'
      return
    }
    if (!this.videoUrl || !this.pipSurfaceId) {
      this.actionMessage = '请等待 MV 播放器加载完成后再开启小窗'
      return
    }
    this.pipStarting = true
    this.actionMessage = ''
    this.mainWasPlaying = this.isPlaying
    this.resumeAfterPipRestore = false
    try {
      this.controller.pause()
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const pipController = await PiPWindow.create({
        context: context,
        componentController: this.pipSurfaceController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: 1280,
        contentHeight: 720,
        defaultWindowSizeType: 1
      })
      this.pipController = pipController
      pipController.on('stateChange', (state: PiPWindow.PiPState, reason: string) =>
        this.handlePipState(state, reason))
      pipController.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, status?: number) =>
        this.handlePipControl(event, status))
      pipController.setAutoStartEnabled(false)
      await this.preparePipPlayer()
      await pipController.startPiP()
    } catch (error) {
      this.pipStarting = false
      this.pipActive = false
      this.actionMessage = error instanceof Error ? error.message : 'MV 小窗启动失败'
      await this.releasePipPlayer()
      try {
        if (this.mainWasPlaying) {
          this.controller.start()
        }
      } catch (_error) {
      }
    }
  }

  private async loadVideoUrl(resolution: number): Promise<void> {
    if (!this.mvId) {
      this.loading = false
      this.message = 'MV 参数无效'
      return
    }
    const requestToken = ++this.requestToken
    this.selectedResolution = resolution
    this.loading = true
    this.message = ''
    this.isPlaying = false
    try {
      this.controller.reset()
    } catch (_error) {
    }
    this.videoUrl = ''
    try {
      const response = await ApiClient.get<MvUrlResponse>('/mv/url', [
        { key: 'id', value: this.mvId },
        { key: 'r', value: resolution.toString() },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (requestToken !== this.requestToken) {
        return
      }
      if (response.code !== 200 || !response.data?.url) {
        throw new Error(response.message || '暂时无法获取该 MV 的播放地址')
      }
      this.actualResolution = response.data.r || resolution
      this.videoUrl = response.data.url
    } catch (error) {
      if (requestToken === this.requestToken) {
        this.loading = false
        this.message = error instanceof Error ? error.message : 'MV 播放地址获取失败'
      }
    }
  }

  private async loadDetailInfo(): Promise<void> {
    try {
      let response = await ApiClient.get<MvDetailInfoResponse>('/mv/detail/info', [
        { key: 'mvid', value: this.mvId },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      let data = response.data
      let hasDetailInfo = response.liked !== undefined || response.likedCount !== undefined ||
        response.shareCount !== undefined || response.commentCount !== undefined || data?.liked !== undefined ||
        data?.likedCount !== undefined || data?.shareCount !== undefined || data?.commentCount !== undefined
      if (!hasDetailInfo) {
        response = await ApiClient.get<MvDetailInfoResponse>('/mv/detail/info', [
          { key: 'id', value: this.mvId },
          { key: 'timestamp', value: Date.now().toString() }
        ])
        data = response.data
        hasDetailInfo = response.liked !== undefined || response.likedCount !== undefined ||
          response.shareCount !== undefined || response.commentCount !== undefined || data?.liked !== undefined ||
          data?.likedCount !== undefined || data?.shareCount !== undefined || data?.commentCount !== undefined
      }
      if (response.code === 200 && hasDetailInfo) {
        this.liked = response.liked !== undefined ? response.liked : (data?.liked || false)
        const likedCount = response.likedCount !== undefined ? response.likedCount : data?.likedCount
        const shareCount = response.shareCount !== undefined ? response.shareCount : data?.shareCount
        const commentCount = response.commentCount !== undefined ? response.commentCount : data?.commentCount
        if (likedCount !== undefined) {
          this.likedCount = likedCount
        }
        if (shareCount !== undefined && shareCount > 0) {
          this.shareCount = shareCount
        }
        if (commentCount !== undefined && commentCount > 0) {
          this.commentCount = commentCount
        }
      }
    } catch (_error) {
    }
  }

  private async loadCommentSummary(): Promise<void> {
    try {
      const response = await ApiClient.get<CommentResponse>('/comment/mv', [
        { key: 'id', value: this.mvId },
        { key: 'limit', value: '1' },
        { key: 'offset', value: '0' },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code === 200 && response.total !== undefined) {
        this.commentCount = response.total
      }
    } catch (_error) {
    }
  }

  private async loadMvDetail(): Promise<void> {
    try {
      const response = await ApiClient.get<MvDetailResponse>('/mv/detail', [
        { key: 'mvid', value: this.mvId },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code !== 200 || !response.data) {
        return
      }
      const data = response.data
      const artistNames = (data.artists || [])
        .map((artist: MvDetailArtist) => artist.name || '')
        .filter((name: string) => name.length > 0)
        .join(' / ')
      this.mvName = data.name || this.mvName
      this.mvCover = data.cover || this.mvCover
      this.mvArtistName = data.artistName || artistNames || this.mvArtistName
      this.mvDuration = data.duration !== undefined ? data.duration : this.mvDuration
      this.mvPlayCount = data.playCount !== undefined ? data.playCount : this.mvPlayCount
      this.mvPublishTime = data.publishTime || this.mvPublishTime
      this.mvDescription = data.desc || data.briefDesc || ''
      if (data.shareCount !== undefined && data.shareCount > 0) {
        this.shareCount = data.shareCount
      }
      if (data.commentCount !== undefined && data.commentCount > 0) {
        this.commentCount = data.commentCount
      }
    } catch (_error) {
    }
  }

  private async toggleLike(): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    if (this.likeSubmitting) {
      return
    }
    const nextLiked = !this.liked
    this.likeSubmitting = true
    try {
      const response = await ApiClient.get<OperationResponse>('/resource/like', [
        { key: 'id', value: this.mvId },
        { key: 'type', value: '1' },
        { key: 't', value: nextLiked ? '1' : '0' }
      ])
      if (response.code === 200) {
        this.liked = nextLiked
        this.likedCount = Math.max(0, this.likedCount + (nextLiked ? 1 : -1))
      } else {
        this.actionMessage = response.message || 'MV 点赞操作失败'
      }
    } catch (error) {
      this.actionMessage = error instanceof Error ? error.message : 'MV 点赞操作失败'
    } finally {
      this.likeSubmitting = false
    }
  }

  private async shareMv(): Promise<void> {
    try {
      const record: systemShare.SharedRecord = {
        utd: 'general.plain-text',
        title: this.mvName || 'MV',
        content: `分享 MV「${this.mvName || 'MV'}」\nhttps://music.163.com/#/mv?id=${this.mvId}`
      }
      const data = new systemShare.SharedData(record)
      const controller = new systemShare.ShareController(data)
      const options: systemShare.ShareControllerOptions = {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await controller.show(context, options)
    } catch (error) {
      this.actionMessage = error instanceof Error ? error.message : '无法打开系统分享面板'
    }
  }

  private async openComments(): Promise<void> {
    this.commentSheetVisible = true
    await this.loadComments()
  }

  private async loadComments(): Promise<void> {
    this.commentsLoading = true
    try {
      const response = await ApiClient.get<CommentResponse>('/comment/mv', [
        { key: 'id', value: this.mvId },
        { key: 'limit', value: '50' },
        { key: 'offset', value: '0' }
      ])
      if (response.code === 200) {
        const merged: CommentApiItem[] = []
        const source = (response.hotComments || []).concat(response.comments || [])
        source.forEach((comment: CommentApiItem) => {
          if (!merged.some((item: CommentApiItem) => item.commentId === comment.commentId)) {
            merged.push(comment)
          }
        })
        this.comments = merged
        this.commentCount = response.total || this.commentCount
      }
    } catch (error) {
      this.actionMessage = error instanceof Error ? error.message : 'MV 评论加载失败'
      this.comments = []
    } finally {
      this.commentsLoading = false
    }
  }

  private async toggleCommentLike(comment: CommentApiItem): Promise<void> {
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const nextLiked = !(comment.liked || false)
    try {
      const response = await ApiClient.get<OperationResponse>('/comment/like', [
        { key: 'id', value: this.mvId },
        { key: 'cid', value: comment.commentId.toString() },
        { key: 't', value: nextLiked ? '1' : '0' },
        { key: 'type', value: '1' }
      ])
      if (response.code === 200) {
        comment.liked = nextLiked
        comment.likedCount = Math.max(0, comment.likedCount + (nextLiked ? 1 : -1))
        this.comments = this.comments.map((item: CommentApiItem) => item)
      }
    } catch (_error) {
    }
  }

  private async submitComment(): Promise<void> {
    const content = this.commentInput.trim()
    if (!content || this.commentSubmitting) {
      return
    }
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.commentSubmitting = true
    try {
      const response = await ApiClient.get<OperationResponse>('/comment', [
        { key: 't', value: '1' },
        { key: 'type', value: '1' },
        { key: 'id', value: this.mvId },
        { key: 'content', value: content }
      ])
      if (response.code === 200) {
        this.commentInput = ''
        this.commentCount += 1
        await this.loadComments()
      } else {
        this.actionMessage = response.message || '评论发布失败'
      }
    } catch (error) {
      this.actionMessage = error instanceof Error ? error.message : '评论发布失败'
    } finally {
      this.commentSubmitting = false
    }
  }

  private safeFileName(): string {
    const base = (this.mvName || `MV_${this.mvId}`).replace(/[\\/:*?"<>|]/g, '_').trim()
    return `${base || `MV_${this.mvId}`}.mp4`
  }

  private async downloadVideo(): Promise<void> {
    if (this.downloading) {
      return
    }
    if (!this.videoUrl) {
      this.actionMessage = '请等待 MV 播放地址加载完成后再下载'
      return
    }
    this.downloading = true
    this.downloadProgress = 0
    this.actionMessage = ''
    let tempPath = ''
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const documentPicker = new picker.DocumentViewPicker(context)
      const targets = await documentPicker.save({
        newFileNames: [this.safeFileName()],
        fileSuffixChoices: ['MP4 视频|.mp4']
      })
      if (targets.length === 0) {
        this.actionMessage = '已取消下载'
        return
      }
      tempPath = `${context.cacheDir}/mv_${this.mvId}_${Date.now()}.mp4`
      const task = await request.downloadFile(context, {
        url: this.videoUrl,
        filePath: tempPath,
        title: this.mvName || 'MV',
        description: '正在下载 MV',
        enableMetered: true,
        enableRoaming: false,
        background: false
      })
      task.on('progress', (receivedSize: number, totalSize: number) => {
        if (totalSize > 0) {
          this.downloadProgress = Math.max(0, Math.min(100, Math.floor(receivedSize * 100 / totalSize)))
        }
      })
      await new Promise<void>((resolve, reject) => {
        task.on('complete', () => resolve())
        task.on('fail', (errorCode: number) => reject(new Error(`视频下载失败 (${errorCode})`)))
      })
      const source = fileIo.openSync(tempPath, fileIo.OpenMode.READ_ONLY)
      const target = fileIo.openSync(targets[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.copyFileSync(source.fd, target.fd)
      } finally {
        fileIo.closeSync(source)
        fileIo.closeSync(target)
      }
      this.downloadProgress = 100
      this.actionMessage = 'MV 已保存到所选位置'
    } catch (error) {
      this.actionMessage = error instanceof Error ? error.message : 'MV 下载失败'
    } finally {
      if (tempPath && fileIo.accessSync(tempPath)) {
        try {
          fileIo.unlinkSync(tempPath)
        } catch (_error) {
        }
      }
      this.downloading = false
    }
  }

  private resolutionTitle(resolution: number): string {
    return resolution >= 1080 ? '1080P' : `${resolution}P`
  }

  private compactCount(value: number): string {
    if (!value || value <= 0) {
      return '0'
    }
    if (value >= 100000000) {
      return `${(value / 100000000).toFixed(1)}亿`
    }
    if (value >= 10000) {
      return `${(value / 10000).toFixed(1)}万`
    }
    return value.toString()
  }

  private formatDuration(value: number): string {
    if (!value || value <= 0) {
      return ''
    }
    const totalSeconds = Math.floor(value / 1000)
    return `${Math.floor(totalSeconds / 60)}:${(totalSeconds % 60).toString().padStart(2, '0')}`
  }

  @Builder
  private VideoArea() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: 'mv_pip_surface',
        type: XComponentType.SURFACE,
        controller: this.pipSurfaceController
      })
        .width('100%').height('100%')
        .onLoad(() => {
          try {
            this.pipSurfaceId = this.pipSurfaceController.getXComponentSurfaceId()
          } catch (_error) {
            this.pipSurfaceId = ''
          }
        })
      if (this.videoUrl) {
        Video({ src: this.videoUrl, previewUri: this.mvCover, controller: this.controller })
          .width('100%').height('100%').objectFit(ImageFit.Contain)
          .autoPlay(true).controls(true).loop(false)
          .onPrepared(() => {
            this.loading = false
            this.message = ''
          })
          .onStart(() => this.isPlaying = true)
          .onPause(() => this.isPlaying = false)
          .onFinish(() => this.isPlaying = false)
          .onUpdate((info: PlaybackInfo) => this.videoPositionSeconds = Math.max(0, info.time))
          .onError(() => {
            this.loading = false
            this.isPlaying = false
            this.message = 'MV 播放失败，播放地址可能已经失效'
          })
      } else if (this.mvCover) {
        Image(this.mvCover).width('100%').height('100%').objectFit(ImageFit.Contain).opacity(0.7)
      }
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(38).height(38).color('#ef233c')
          Text('正在获取 MV 播放地址…').fontSize(11).fontColor('#b8b8bf')
        }
      }
      if (!this.loading && this.message && !this.videoUrl) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill')).fontSize(31).fontColor(['#ff8b65'])
          Text(this.message).width('80%').fontSize(12).lineHeight(19).fontColor('#c8c8ce')
            .textAlign(TextAlign.Center)
          Button('重新获取').height(38).fontSize(12).fontColor('#ffffff').backgroundColor('#ef233c')
            .borderRadius(18).onClick(() => this.loadVideoUrl(this.selectedResolution))
        }
      }
    }
    .width('100%').aspectRatio(16 / 9).backgroundColor('#000000')
  }

  @Builder
  private ActionButton(icon: () => Resource, title: () => string, value: () => string,
    active: () => boolean, action: () => void) {
    Column({ space: 6 }) {
      Stack() {
        SymbolGlyph(icon()).fontSize(22).fontColor([active() ? '#ef233c' : '#e0e0e4'])
      }.width(42).height(42).borderRadius(21).backgroundColor('#24242a')
      Text(title()).fontSize(10).fontColor('#a0a0a8')
      if (value()) {
        Text(value()).fontSize(9).fontColor(active() ? '#ef6577' : '#66666e')
      }
    }.layoutWeight(1).onClick(action)
  }

  @Builder
  private CommentSheet() {
    Column() {
      Row() {
        Text(`MV 评论 · ${this.compactCount(this.commentCount)}`).layoutWeight(1)
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(24).fontColor(['#686870'])
          .onClick(() => this.commentSheetVisible = false)
      }.height(60).padding({ left: 18, right: 18 })
      if (this.commentsLoading) {
        Column({ space: 10 }) {
          LoadingProgress().width(38).height(38).color('#ef233c')
          Text('加载评论中…').fontSize(11).fontColor('#77777f')
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.comments.length === 0) {
        Text('还没有评论，来留下第一条吧').layoutWeight(1).width('100%')
          .fontSize(12).fontColor('#77777f').textAlign(TextAlign.Center)
      } else {
        List({ space: 15 }) {
          ForEach(this.comments, (comment: CommentApiItem) => {
            ListItem() {
              Row({ space: 10 }) {
                Image(comment.user.avatarUrl).width(38).height(38).borderRadius(19).objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Row() {
                    Text(comment.user.nickname).layoutWeight(1).fontSize(12).fontColor('#aaaab2')
                    Row({ space: 4 }) {
                      SymbolGlyph(comment.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                        .fontSize(15).fontColor([comment.liked ? '#ef233c' : '#77777f'])
                      Text(`${comment.likedCount}`).fontSize(9)
                        .fontColor(comment.liked ? '#ef233c' : '#77777f')
                    }.onClick(() => this.toggleCommentLike(comment))
                  }
                  Text(comment.content).width('100%').fontSize(13).lineHeight(20).fontColor('#ededf0')
                  Text(comment.timeStr || '').fontSize(9).fontColor('#5f5f67')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.padding({ left: 16, right: 16 })
            }
          })
        }.layoutWeight(1).scrollBar(BarState.Off)
      }
      Row({ space: 9 }) {
        TextInput({ text: this.commentInput, placeholder: '写下你的评论…' })
          .layoutWeight(1).height(42).fontColor('#ffffff').placeholderColor('#66666e')
          .backgroundColor('#25252b').borderRadius(18).onChange((value: string) => this.commentInput = value)
          .onSubmit(() => this.submitComment())
        Button(this.commentSubmitting ? '发送中' : '发送').height(40).backgroundColor('#ef233c')
          .enabled(!this.commentSubmitting && this.commentInput.trim().length > 0)
          .onClick(() => this.submitComment())
      }.padding({ left: 14, right: 14, top: 8, bottom: 12 })
    }.width('100%').height('100%')
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('MV 播放').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.rectangle_on_rectangle')).fontSize(21)
            .fontColor([this.pipSupported ? (this.pipActive ? '#ef233c' : '#d8d8dd') : '#55555d'])
            .margin({ right: 18 }).onClick(() => this.startPip())
          SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right')).fontSize(20).fontColor(['#d8d8dd'])
            .onClick(() => this.controller.requestFullscreen(true))
        }.width('100%').height(56).padding({ left: 16, right: 16 })

        this.VideoArea()

        Scroll() {
          Column({ space: 18 }) {
            Column({ space: 8 }) {
              Text(this.mvName || 'MV').width('100%').fontSize(20).fontWeight(FontWeight.Bold)
                .fontColor('#f5f5f7').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.mvArtistName) {
                Text(this.mvArtistName).width('100%').fontSize(13).fontColor('#a0a0a8')
              }
              Row({ space: 12 }) {
                if (this.mvPlayCount > 0) {
                  Text(`${this.compactCount(this.mvPlayCount)} 次播放`).fontSize(11).fontColor('#686870')
                }
                if (this.mvDuration > 0) {
                  Text(this.formatDuration(this.mvDuration)).fontSize(11).fontColor('#686870')
                }
                if (this.mvPublishTime) {
                  Text(this.mvPublishTime).fontSize(11).fontColor('#686870')
                }
              }
              if (this.mvDescription) {
                Text(this.mvDescription).width('100%').fontSize(12).lineHeight(19).fontColor('#85858e')
                  .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }.width('100%').alignItems(HorizontalAlign.Start)

            Row() {
              this.ActionButton(() => $r('sys.symbol.share'), () => '分享',
                () => this.compactCount(this.shareCount), () => false,
                () => this.shareMv())
              this.ActionButton(() => this.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
                () => this.liked ? '已点赞' : '点赞', () => this.compactCount(this.likedCount), () => this.liked,
                () => this.toggleLike())
              this.ActionButton(() => $r('sys.symbol.ellipsis_bubble'), () => '评论',
                () => this.compactCount(this.commentCount), () => false,
                () => this.openComments())
              this.ActionButton(() => $r('sys.symbol.arrow_down_circle'), () => '下载',
                () => this.downloading ? `${this.downloadProgress}%` : '', () => this.downloading,
                () => this.downloadVideo())
            }.width('100%').padding({ top: 4, bottom: 4 })

            Column({ space: 11 }) {
              Row() {
                Text('播放清晰度').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                Blank()
                if (this.actualResolution > 0) {
                  Text(`当前 ${this.resolutionTitle(this.actualResolution)}`).fontSize(10).fontColor('#77777f')
                }
              }.width('100%')
              Row({ space: 9 }) {
                ForEach(this.resolutions, (resolution: number) => {
                  Text(this.resolutionTitle(resolution)).layoutWeight(1).height(38).fontSize(11)
                    .fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
                    .fontColor(this.selectedResolution === resolution ? '#ffffff' : '#8b8b93')
                    .backgroundColor(this.selectedResolution === resolution ? '#ef233c' : '#24242a')
                    .borderRadius(12).onClick(() => {
                      if (this.selectedResolution !== resolution) {
                        this.loadVideoUrl(resolution)
                      }
                    })
                })
              }.width('100%')
            }.width('100%').padding(15).backgroundColor('#1b1b20').borderRadius(17)

            if (this.actionMessage) {
              Text(this.actionMessage).width('100%').padding(12).fontSize(11).lineHeight(18)
                .fontColor(this.actionMessage.includes('已') ? '#65c98c' : '#ff9a78')
                .textAlign(TextAlign.Center).backgroundColor('#202026').borderRadius(13)
            }
            if (this.message && this.videoUrl) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill')).fontSize(18).fontColor(['#ff8b65'])
                Text(this.message).layoutWeight(1).fontSize(11).lineHeight(18).fontColor('#ff9a78')
                Text('重试').fontSize(11).fontColor('#ff6577')
                  .onClick(() => this.loadVideoUrl(this.selectedResolution))
              }.width('100%').padding(12).backgroundColor('#2b211f').borderRadius(13)
            }
          }.width('100%').padding({ left: 16, right: 16, top: 18, bottom: 34 })
        }.layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor('#121215')
      .bindSheet(this.commentSheetVisible, this.CommentSheet(), {
        height: '72%', backgroundColor: '#19191f', showClose: false, dragBar: true,
        onDisappear: () => this.commentSheetVisible = false
      })
    }.hideTitleBar(true)
  }
}
