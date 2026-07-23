import { PlayMode, songItemType } from '../models/music'

function emptySong(): songItemType {
  return {
    id: '',
    name: '暂无播放歌曲',
    author: '播放列表为空',
    img: '',
    url: '',
    duration: 0,
    album: ''
  }
}

@Observed
export class PlayerStore {
  queue: songItemType[] = []
  currentIndex: number = -1
  currentSong: songItemType = emptySong()
  isPlaying: boolean = false
  isLoading: boolean = false
  position: number = 0
  duration: number = 0
  playMode: PlayMode = PlayMode.LOOP
  quality: string = 'exhigh'
  errorMessage: string = ''

  hasQueue(): boolean {
    return this.queue.length > 0 && this.currentIndex >= 0
  }

  setQueue(queue: songItemType[], index: number = 0, preservePlayback: boolean = false): void {
    if (queue.length === 0) {
      this.clearQueue()
      return
    }
    const previousPosition = this.position
    const previousDuration = this.duration
    this.queue = queue.map((item: songItemType) => item)
    this.currentIndex = Math.max(0, Math.min(index, this.queue.length - 1))
    this.currentSong = this.queue[this.currentIndex]
    if (preservePlayback) {
      this.position = previousPosition
      this.duration = previousDuration > 0 ? previousDuration : (this.currentSong.duration || 0)
    } else {
      this.position = 0
      this.duration = this.currentSong.duration || 0
    }
  }

  selectAt(index: number, preservePlayback: boolean = false): void {
    if (this.queue.length === 0) {
      this.clearQueue()
      return
    }
    const previousPosition = this.position
    const previousDuration = this.duration
    this.currentIndex = Math.max(0, Math.min(index, this.queue.length - 1))
    this.currentSong = this.queue[this.currentIndex]
    if (preservePlayback) {
      this.position = previousPosition
      this.duration = previousDuration > 0 ? previousDuration : (this.currentSong.duration || 0)
    } else {
      this.position = 0
      this.duration = this.currentSong.duration || 0
    }
  }

  clearQueue(): void {
    this.queue = []
    this.currentIndex = -1
    this.currentSong = emptySong()
    this.isPlaying = false
    this.isLoading = false
    this.position = 0
    this.duration = 0
    this.errorMessage = ''
  }

  removeAt(index: number): boolean {
    if (index < 0 || index >= this.queue.length) {
      return false
    }
    const removingCurrent = index === this.currentIndex
    const nextQueue = this.queue.filter((_item: songItemType, itemIndex: number) => itemIndex !== index)
    if (nextQueue.length === 0) {
      this.clearQueue()
      return true
    }
    if (index < this.currentIndex) {
      this.currentIndex -= 1
    } else if (removingCurrent) {
      this.currentIndex = Math.min(index, nextQueue.length - 1)
      this.position = 0
    }
    this.queue = nextQueue
    this.currentSong = this.queue[this.currentIndex]
    this.duration = removingCurrent ? (this.currentSong.duration || 0) : this.duration
    return removingCurrent
  }

  modeTitle(): string {
    if (this.playMode === PlayMode.SINGLE) {
      return '单曲循环'
    }
    if (this.playMode === PlayMode.SHUFFLE) {
      return '随机播放'
    }
    return '列表循环'
  }

  qualityTitle(): string {
    if (this.quality === 'hires') {
      return 'Hi-Res'
    }
    if (this.quality === 'lossless') {
      return '无损'
    }
    if (this.quality === 'exhigh') {
      return '极高'
    }
    if (this.quality === 'higher') {
      return '较高'
    }
    return '标准'
  }
}
