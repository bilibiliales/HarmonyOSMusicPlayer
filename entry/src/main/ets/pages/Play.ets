import { ResourceComments } from '../components/ResourceComments'
import { CommentResource } from '../models/CommentResource'
import { CommentService } from '../services/CommentService'
import { connection } from '@kit.NetworkKit'
import { SongMetadataCache } from '../services/SongMetadataCache'
import { LocalLibrary } from '../services/LocalLibrary'
import { LyricPreferences } from '../models/lyricPreferences'
import { LyricSettingsSheet } from '../components/LyricSettingsSheet'
import { RadioPageParam } from '../models/radio'
import { common } from '@kit.AbilityKit'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { http } from '@kit.NetworkKit'
import { request } from '@kit.BasicServicesKit'
import curves from '@ohos.curves'
import {
  AlbumPageParam,
  ArtistPageParam,
  CommentResponse,
  LikeListResponse,
  LyricResponse,
  mapApiSong,
  mapPlaylist,
  SharePageParam,
  SongDetailResponse,
  SongRedCountResponse,
  UserPlaylistResponse
} from '../models/api'
import { PlayMode, playlistType, QualityOption, SongArtist, songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { SongQualityService } from '../services/SongQualityService'
import { AudioFileFormat } from '../services/AudioFileFormat'
import { playerController } from '../services/PlayerController'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { ShareSheet } from '../components/ShareSheet'
import { VinylRecord } from '../components/VinylRecord'
import { AppSettings } from '../services/AppSettings'
import { BubbleTip } from '../services/BubbleTip'
import { RectShape } from '@kit.ArkUI'

@Component
export struct Play {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('playerStore') playerStore: PlayerStore
  @Consume('authStore') authStore: AuthStore

  @State activeSheet: string = ''
  @State commentsVisible: boolean = false
  @State commentTarget: CommentResource = { id: '', type: 0 }
  @State playlists: playlistType[] = []
  @State liked: boolean = false
  @State vinylDiameter: number = 280
  @State downloadProgress: number = 0
  @State shareSheetVisible: boolean = false
  @State showLyrics: boolean = false
  @State lyricsImmersive: boolean = false
  @State lyricsLoading: boolean = false
  @State lyricLines: LyricLine[] = []
  @State currentLyricIndex: number = -1
  @State lyricMessage: string = ''
  @State lyricCanRetry: boolean = false
  @State pageReloading: boolean = false
  @State lyricUserScrolling: boolean = false
  @State lyricProgressPosition: number = 0
  @State lyricAppearance: LyricPreferences = AppSettings.lyricPreferences
  @State redCount: number = 0
  @State redCountLoading: boolean = false
  @State vinylOffsetX: number = 0
  @State vinylOpacity: number = 1
  @State switchingSong: boolean = false
  @State availableQualities: QualityOption[] = []
  @State qualityLoading: boolean = false
  @State qualityError: string = ''
  @State downloadQualities: QualityOption[] = []
  @State downloadQualityLoading: boolean = false
  @State downloadQualityError: string = ''
  @State downloadSongName: string = ''
  @State preferredDownloadLevel: string = ''
  @State downloading: boolean = false
  private downloadTarget?: songItemType
  private downloadQualityToken: number = 0
  private qualityRequestToken: number = 0
  @State coverPreviewVisible: boolean = false
  @State coverSaving: boolean = false
  @State coverMessage: string = ''
  @State progressSeeking: boolean = false
  @State seekPreviewPosition: number = 0
  private shareParam: SharePageParam = { type: 'song', id: '', name: '', img: '' }
  private lyricTimer: number = -1
  private lyricResumeTimer: number = -1
  private lyricAutoScrollTimer: number = -1
  @State networkAvailable: boolean = true
  private lastNetworkCheck: number = 0
  private loadedLyricSongId: string = ''
  private lyricLoadRevision: number = 0
  private loadedRedSongId: string = ''
  private loadedQualitySongId: string = ''
  private likedSongIds: string[] = []
  private likeListRequestToken: number = 0
  private lyricAutoScrolling: boolean = false
  private preciseLyricsLoaded: boolean = false
  private lyricViewportHeight: number = 0
  private lyricScroller: Scroller = new Scroller()
  private lyricClockPosition: number = 0
  private lyricClockTimestamp: number = 0
  private lastPlayerPosition: number = -1

  aboutToAppear(): void {
    if (!this.playerStore.hasQueue()) {
      this.pageStack.pop()
      return
    }
    this.checkNetwork()
    this.liked = this.playerStore.currentSong.liked || false
    this.loadCommentSummary()
    this.loadRedCount()
    this.loadMusicQualities()
    this.loadLikedState()
    this.loadLyrics()
    this.startLyricTracking()
  }

  aboutToDisappear(): void {
    if (this.lyricTimer !== -1) {
      clearInterval(this.lyricTimer)
      this.lyricTimer = -1
    }
    if (this.lyricResumeTimer !== -1) {
      clearTimeout(this.lyricResumeTimer)
      this.lyricResumeTimer = -1
    }
    if (this.lyricAutoScrollTimer !== -1) {
      clearTimeout(this.lyricAutoScrollTimer)
      this.lyricAutoScrollTimer = -1
    }
  }

  private formatTime(value: number): string {
    const totalSeconds = Math.floor(Math.max(0, value) / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
  }

  private progressPosition(): number {
    return this.progressSeeking ? this.seekPreviewPosition : this.playerStore.position
  }

  private handleProgressChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.progressSeeking = true
      this.seekPreviewPosition = value
      return
    }
    this.seekPreviewPosition = value
    playerController.seek(value)
    this.progressSeeking = false
  }

  private startLyricTracking(): void {
    if (this.lyricTimer !== -1) {
      return
    }
    this.lyricTimer = setInterval(() => {
      if (!this.playerStore.hasQueue()) { return }
      if (Date.now() - this.lastNetworkCheck > 1000) { this.checkNetwork() }
      if (this.loadedLyricSongId !== this.lyricKey()) {
        this.loadLyrics()
        this.loadRedCount()
        this.loadMusicQualities()
        this.loadLikedState()
        this.loadCommentSummary()
        return
      }
      if (this.showLyrics && this.preciseLyricsLoaded) {
        this.updateLyricProgressClock()
      }
      this.updateCurrentLyric()
    }, 32)
  }

  private updateLyricProgressClock(): void {
    const now = Date.now()
    const playerPosition = this.playerStore.position
    if (!this.playerStore.isPlaying) {
      this.lyricClockPosition = playerPosition
      this.lyricClockTimestamp = now
      this.lastPlayerPosition = playerPosition
      this.lyricProgressPosition = playerPosition
      return
    }
    if (this.lyricClockTimestamp <= 0) {
      this.lyricClockPosition = playerPosition
      this.lyricClockTimestamp = now
      this.lastPlayerPosition = playerPosition
    } else if (playerPosition !== this.lastPlayerPosition) {
      const predicted = this.lyricClockPosition + now - this.lyricClockTimestamp
      this.lyricClockPosition = Math.abs(playerPosition - predicted) > 250 ? playerPosition :
        predicted + (playerPosition - predicted) * 0.2
      this.lyricClockTimestamp = now
      this.lastPlayerPosition = playerPosition
    }
    const interpolated = this.lyricClockPosition + now - this.lyricClockTimestamp
    this.lyricProgressPosition = Math.max(0, Math.min(this.playerStore.duration || interpolated, interpolated))
  }

  private parseLyricTime(tag: string): number {
    if (tag.length < 5) {
      return 0
    }
    const cleanTag = tag.substring(1, tag.length - 1)
    const parts = cleanTag.split(':')
    if (parts.length !== 2) {
      return 0
    }
    const minutes = Number(parts[0])
    const seconds = Number(parts[1].replace(':', '.'))
    if (!Number.isFinite(minutes) || !Number.isFinite(seconds)) {
      return 0
    }
    return Math.round(minutes * 60000 + seconds * 1000)
  }

  private parseTimedLyrics(raw: string, keepEmpty: boolean): LyricLine[] {
    const result: LyricLine[] = []
    raw.split('\n').forEach((line: string) => {
      const tags = line.match(/\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]/g) || []
      if (tags.length === 0) {
        return
      }
      const lyricText = line.replace(/\[[^\]]+\]/g, '').trim()
      if (!lyricText && !keepEmpty) {
        return
      }
      tags.forEach((tag: string) => {
        result.push({
          time: this.parseLyricTime(tag),
          text: lyricText || '♪',
          translation: ''
        })
      })
    })
    result.sort((left: LyricLine, right: LyricLine) => left.time - right.time)
    return result
  }

  private parseYrcLyrics(raw: string): LyricLine[] {
    const result: LyricLine[] = []
    raw.split('\n').forEach((line: string) => {
      const lineMatch = /^\[(\d+),(\d+)\](.*)$/.exec(line.trim())
      if (!lineMatch) {
        return
      }
      const lineTime = Number(lineMatch[1])
      const lineDuration = Number(lineMatch[2])
      const body = lineMatch[3]
      const tags: YrcWordTag[] = []
      const tagPattern = /\((\d+),(\d+),\d+\)/g
      let tagMatch = tagPattern.exec(body)
      while (tagMatch) {
        tags.push({
          start: Number(tagMatch[1]),
          duration: Number(tagMatch[2]),
          markerIndex: tagMatch.index,
          textStart: tagPattern.lastIndex
        })
        tagMatch = tagPattern.exec(body)
      }
      const words: LyricWord[] = []
      tags.forEach((tag: YrcWordTag, index: number) => {
        const textEnd = index + 1 < tags.length ? tags[index + 1].markerIndex : body.length
        const text = body.substring(tag.textStart, textEnd)
        if (text.length > 0) {
          words.push({ start: tag.start, duration: tag.duration, text: text })
        }
      })
      const lyricText = words.map((word: LyricWord) => word.text).join('').trim()
      if (lyricText.length > 0) {
        result.push({
          time: Number.isFinite(lineTime) ? lineTime : 0,
          duration: Number.isFinite(lineDuration) ? lineDuration : 0,
          text: lyricText,
          translation: '',
          words: words
        })
      }
    })
    result.sort((left: LyricLine, right: LyricLine) => left.time - right.time)
    return result
  }

  private mergeTranslations(lines: LyricLine[], translations: LyricLine[]): LyricLine[] {
    if (translations.length === 0) {
      return lines
    }
    return lines.map((line: LyricLine) => {
      let translation = ''
      for (let index = 0; index < translations.length; index++) {
        if (Math.abs(translations[index].time - line.time) <= 80) {
          translation = translations[index].text
          break
        }
      }
      const merged: LyricLine = {
        time: line.time,
        duration: line.duration,
        text: line.text,
        translation: translation,
        words: line.words
      }
      return merged
    })
  }

  private checkNetwork(): void {
    this.lastNetworkCheck = Date.now()
    try { this.networkAvailable = connection.hasDefaultNetSync() } catch (_error) { this.networkAvailable = false }
  }

  private lyricKey(): string {
    const song = this.playerStore.currentSong
    return song.id + (song.localUri || '') + (song.localLrc || '') + (song.localYrc || '')
  }

  private isNonCatalogAudio(): boolean {
    return (!!this.playerStore.currentSong.localUri && (!/^\d+$/.test(this.playerStore.currentSong.id) || !this.networkAvailable)) || !!this.playerStore.currentSong.programId || this.playerStore.currentSong.isDifm === true
  }

  private openAudioDetails(): void {
    const song = this.playerStore.currentSong
    this.activeSheet = ''
    if (song.localUri) { this.pageStack.pushPathByName('LocalMusicPage', null); return }
    if (song.programId) {
      const param: RadioPageParam = { id: song.programId }
      this.pageStack.pushPathByName('RadioProgramPage', param)
    } else {
      this.pageStack.pushPathByName('DifmPage', null)
    }
  }

  private async loadLyrics(): Promise<void> {
    const revision = ++this.lyricLoadRevision
    const key = this.lyricKey()
    this.loadedLyricSongId = key
    this.lyricsLoading = true
    this.lyricMessage = ''
    this.lyricCanRetry = false
    this.lyricLines = []
    this.currentLyricIndex = -1
    this.lyricProgressPosition = this.playerStore.position
    this.preciseLyricsLoaded = false
    if (this.isNonCatalogAudio() && !this.playerStore.currentSong.localUri) {
      this.lyricMessage = this.playerStore.currentSong.localUri ? '本地音频暂无歌词' : '电台音源暂无歌词'
      this.lyricsLoading = false
      return
    }
    try {
      const response = await SongMetadataCache.lyrics(this.playerStore.currentSong)
      if (revision !== this.lyricLoadRevision || key !== this.lyricKey()) {
        return
      }
      if (response.code !== 200 || response.nolyric || response.uncollected ||
        (!response.yrc?.lyric && !response.lrc?.lyric)) {
        this.lyricMessage = response.uncollected ? '歌词暂未收录' : '这首歌暂无歌词'
        return
      }
      const preciseLyrics = response.yrc?.lyric ? this.parseYrcLyrics(response.yrc.lyric) : []
      this.preciseLyricsLoaded = preciseLyrics.length > 0
      const original = preciseLyrics.length > 0 ? preciseLyrics : this.parseTimedLyrics(response.lrc?.lyric || '', true)
      const translationSource = response.tlyric?.lyric || response.romalrc?.lyric || ''
      const translations = this.parseTimedLyrics(translationSource, false)
      this.lyricLines = this.mergeTranslations(original, translations)
      if (this.lyricLines.length === 0) {
        this.lyricMessage = '歌词格式暂时无法解析'
      } else {
        this.updateCurrentLyric()
        if (this.showLyrics) {
          setTimeout(() => this.scrollToCurrentLyric(false), 80)
        }
      }
    } catch (error) {
      if (revision === this.lyricLoadRevision) {
        this.lyricMessage = error instanceof Error ? error.message : '歌词加载失败'
        this.lyricCanRetry = true
      }
    } finally {
      if (revision === this.lyricLoadRevision) {
        this.lyricsLoading = false
      }
    }
  }

  private async reloadSongPage(): Promise<void> {
    if (this.playerStore.currentSong.localUri) { await this.loadLyrics(); return }
    if (this.isNonCatalogAudio()) { this.openAudioDetails(); return }
    if (this.pageReloading || !this.playerStore.currentSong.id) {
      return
    }
    this.pageReloading = true
    this.activeSheet = ''
    try {
      const response = await ApiClient.get<SongDetailResponse>('/song/detail', [
        { key: 'ids', value: this.playerStore.currentSong.id }
      ])
      if (response.songs && response.songs.length > 0) {
        const detailed = mapApiSong(response.songs[0])
        const current = this.playerStore.currentSong
        detailed.url = current.url
        detailed.liked = current.liked
        detailed.commentCount = current.commentCount
        this.playerStore.queue[this.playerStore.currentIndex] = detailed
        this.playerStore.currentSong = detailed
      }
      await this.loadLyrics()
      this.loadRedCount()
      this.loadMusicQualities()
      this.loadCommentSummary()
      BubbleTip.show(this.getUIContext(), '歌曲页面已重新加载')
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '重新加载失败')
    } finally {
      this.pageReloading = false
    }
  }

  private findCurrentLyricIndex(position: number): number {
    let low = 0
    let high = this.lyricLines.length - 1
    let result = -1
    const target = position + this.lyricAppearance.offset * 1000 + 120
    while (low <= high) {
      const middle = Math.floor((low + high) / 2)
      if (this.lyricLines[middle].time <= target) {
        result = middle
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    return result
  }

  private updateCurrentLyric(): void {
    if (this.lyricLines.length === 0) {
      return
    }
    const nextIndex = this.findCurrentLyricIndex(this.playerStore.position)
    if (nextIndex === this.currentLyricIndex) {
      return
    }
    this.currentLyricIndex = nextIndex
    if (this.showLyrics && !this.lyricUserScrolling && nextIndex >= 0) {
      this.scrollToCurrentLyric(true)
    }
  }

  private scrollToCurrentLyric(smooth: boolean): void {
    if (!this.showLyrics || this.currentLyricIndex < 0 || this.lyricLines.length === 0) {
      return
    }
    this.lyricAutoScrolling = true
    try {
      const itemIndex = this.currentLyricIndex + 1
      if (smooth && this.lyricViewportHeight > 0) {
        const itemRect = this.lyricScroller.getItemRect(itemIndex)
        const currentOffset = this.lyricScroller.currentOffset()
        const targetOffset = Math.max(0,
          currentOffset.yOffset + itemRect.y + itemRect.height / 2 - this.lyricViewportHeight / 2)
        this.lyricScroller.scrollTo({
          xOffset: currentOffset.xOffset,
          yOffset: targetOffset,
          animation: {
            curve: curves.springMotion(0.5, 0.76, 0.22)
          }
        })
      } else {
        this.lyricScroller.scrollToIndex(itemIndex, false, ScrollAlign.CENTER)
      }
    } catch (_error) {
      try {
        this.lyricScroller.scrollToIndex(this.currentLyricIndex + 1, smooth, ScrollAlign.CENTER)
      } catch (_fallbackError) {
        this.lyricAutoScrolling = false
        return
      }
    }
    if (this.lyricAutoScrollTimer !== -1) {
      clearTimeout(this.lyricAutoScrollTimer)
    }
    this.lyricAutoScrollTimer = setTimeout(() => {
      this.lyricAutoScrolling = false
      this.lyricAutoScrollTimer = -1
    }, smooth ? 720 : 100)
  }

  private openLyrics(): void {
    this.showLyrics = true
    this.lyricsImmersive = false
    this.lyricProgressPosition = this.playerStore.position
    if (this.loadedLyricSongId !== this.lyricKey()) {
      this.loadLyrics()
    }
    setTimeout(() => this.scrollToCurrentLyric(false), 100)
  }

  private closeLyrics(): void {
    this.lyricsImmersive = false
    this.showLyrics = false
  }

  private toggleLyricsImmersive(): void {
    const nextImmersive = !this.lyricsImmersive
    this.getUIContext().animateTo({
      curve: curves.springMotion(0.44, 0.8, 0.2),
      onFinish: () => this.scrollToCurrentLyric(false)
    }, () => {
      this.lyricsImmersive = nextImmersive
    })
  }

  private handleLyricScrollStart(): void {
    if (this.lyricAutoScrolling) {
      return
    }
    this.lyricUserScrolling = true
    if (this.lyricResumeTimer !== -1) {
      clearTimeout(this.lyricResumeTimer)
      this.lyricResumeTimer = -1
    }
  }

  private handleLyricScrollStop(): void {
    if (!this.lyricUserScrolling || this.lyricAutoScrolling) {
      return
    }
    this.lyricResumeTimer = setTimeout(() => {
      this.lyricUserScrolling = false
      this.lyricResumeTimer = -1
      this.scrollToCurrentLyric(true)
    }, 3500)
  }

  private seekToLyric(line: LyricLine, index: number): void {
    if (this.lyricResumeTimer !== -1) {
      clearTimeout(this.lyricResumeTimer)
      this.lyricResumeTimer = -1
    }
    this.lyricUserScrolling = false
    this.currentLyricIndex = index
    this.lyricProgressPosition = Math.max(0, line.time - this.lyricAppearance.offset * 1000)
    playerController.seek(Math.max(0, line.time - this.lyricAppearance.offset * 1000))
    this.scrollToCurrentLyric(true)
  }

  private lyricColor(index: number): string {
    if (index === this.currentLyricIndex) {
      return this.lyricAppearance.highlight
    }
    if (index < this.currentLyricIndex) {
      return 'rgba(255,255,255,0.25)'
    }
    return 'rgba(255,255,255,0.46)'
  }

  private lyricLineDistance(index: number): number {
    if (this.currentLyricIndex < 0) {
      return 0
    }
    return Math.abs(index - this.currentLyricIndex)
  }

  private lyricLineDelay(index: number): number {
    if (this.lyricUserScrolling || this.currentLyricIndex < 0) {
      return 0
    }
    const distance = Math.min(this.lyricLineDistance(index), 6)
    if (index < this.currentLyricIndex) {
      return distance * 20
    }
    return distance === 0 ? 0 : 10 + distance * 28
  }

  private lyricLineOffset(index: number): number {
    if (this.lyricUserScrolling || this.currentLyricIndex < 0) {
      return 0
    }
    const relativeIndex = index - this.currentLyricIndex
    if (relativeIndex < 0) {
      return -Math.min(Math.abs(relativeIndex), 6) * 18 * this.lyricAppearance.amplitude
    }
    return Math.min(relativeIndex, 6) * 16 * this.lyricAppearance.amplitude
  }

  private lyricLineOpacity(index: number): number {
    if (index === this.currentLyricIndex) {
      return 1
    }
    return Math.max(0.72, 0.9 - Math.min(this.lyricLineDistance(index), 5) * 0.035)
  }

  private lyricLineScale(index: number): number {
    if (index === this.currentLyricIndex) {
      return 1 + 0.08 * this.lyricAppearance.amplitude
    }
    return 1 - (1 - Math.max(0.92, 0.975 - Math.min(this.lyricLineDistance(index), 3) * 0.018)) * this.lyricAppearance.amplitude
  }

  private lyricFontSize(index: number): number {
    if (index === this.currentLyricIndex) {
      return this.lyricAppearance.fontSize + 9
    }
    return this.lyricAppearance.fontSize
  }

  private lyricLineHeight(index: number): number {
    if (index === this.currentLyricIndex) {
      return this.lyricAppearance.fontSize + 20
    }
    return this.lyricAppearance.fontSize + 11
  }

  private hasPreciseLyrics(): boolean {
    return this.lyricLines.some((line: LyricLine) => !!line.words && line.words.length > 0)
  }

  private lyricCharacterProgress(word: LyricWord, characterIndex: number, characterCount: number): number {
    if (characterCount <= 0 || word.duration <= 0) {
      return this.lyricProgressPosition + this.lyricAppearance.offset * 1000 >= word.start ? 1 : 0
    }
    const characterDuration = word.duration / characterCount
    const characterStart = word.start + characterDuration * characterIndex
    return Math.max(0, Math.min(1, (this.lyricProgressPosition + this.lyricAppearance.offset * 1000 - characterStart) / characterDuration))
  }

  @Builder
  private PrimaryLyricText(line: LyricLine, index: number) {
    if (index === this.currentLyricIndex && line.words && line.words.length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(line.words, (word: LyricWord, wordIndex: number) => {
          ForEach(word.text.split(''), (character: string, characterIndex: number) => {
            Stack({ alignContent: Alignment.TopStart }) {
              Text(character)
                .fontSize(this.lyricFontSize(index))
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffffff')
                .lineHeight(this.lyricLineHeight(index))
              Text(character)
                .fontSize(this.lyricFontSize(index))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.lyricAppearance.highlight)
                .lineHeight(this.lyricLineHeight(index))
                .clipShape(new RectShape({
                  width: `${this.lyricCharacterProgress(word, characterIndex, word.text.length) * 100}%`,
                  height: '100%'
                }).position({ x: 0, y: 0 }))
            }
          }, (character: string, characterIndex: number) => `${wordIndex}-${characterIndex}-${character}`)
        }, (word: LyricWord, wordIndex: number) => `${word.start}-${wordIndex}`)
      }
      .width('100%')
    } else {
      Text(line.text)
        .width('100%')
        .fontSize(this.lyricFontSize(index))
        .fontWeight(index === this.currentLyricIndex ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.lyricColor(index))
        .lineHeight(this.lyricLineHeight(index))
    }
  }

  private modeSymbol(): Resource {
    if (this.playerStore.playMode === PlayMode.SINGLE) {
      return $r('sys.symbol.repeat_1')
    }
    if (this.playerStore.playMode === PlayMode.SHUFFLE) {
      return $r('sys.symbol.shuffle')
    }
    return $r('sys.symbol.repeat')
  }

  private async loadRedCount(): Promise<void> {
    if (this.isNonCatalogAudio()) {
      this.loadedRedSongId = this.playerStore.currentSong.id
      this.redCount = 0
      this.redCountLoading = false
      return
    }
    const songId = this.playerStore.currentSong.id
    if (this.redCountLoading && this.loadedRedSongId === songId) {
      return
    }
    this.loadedRedSongId = songId
    this.redCountLoading = true
    try {
      const response = await ApiClient.get<SongRedCountResponse>('/song/red/count', [
        { key: 'id', value: songId }
      ])
      if (songId === this.playerStore.currentSong.id && response.code === 200 && response.data) {
        this.redCount = response.data.count || 0
      }
    } catch (_error) {
      if (songId === this.playerStore.currentSong.id) {
        this.redCount = 0
      }
    } finally {
      if (songId === this.playerStore.currentSong.id) {
        this.redCountLoading = false
      }
    }
  }

  private formatMetricCount(value: number): string {
    if (value >= 100000000) {
      return `${(value / 100000000).toFixed(1)}亿`
    }
    if (value >= 10000) {
      return `${(value / 10000).toFixed(1)}万`
    }
    return value.toString()
  }

  private async loadMusicQualities(): Promise<void> {
    if (this.playerStore.currentSong.localUri) { return }
    if (this.isNonCatalogAudio()) {
      this.qualityRequestToken++
      this.loadedQualitySongId = this.playerStore.currentSong.id
      this.availableQualities = []
      this.qualityLoading = false
      return
    }
    const songId = this.playerStore.currentSong.id
    if (!songId || (this.qualityLoading && this.loadedQualitySongId === songId)) { return }
    const token = ++this.qualityRequestToken
    this.loadedQualitySongId = songId
    this.qualityLoading = true
    this.qualityError = ''
    this.availableQualities = []
    try {
      const qualities = await SongQualityService.available(songId)
      if (token === this.qualityRequestToken && songId === this.playerStore.currentSong.id) {
        this.availableQualities = qualities
      }
    } catch (error) {
      if (token === this.qualityRequestToken && songId === this.playerStore.currentSong.id) {
        this.qualityError = error instanceof Error ? error.message : '音质查询失败，点击重试'
      }
    } finally {
      if (token === this.qualityRequestToken) { this.qualityLoading = false }
    }
  }

  private openQualitySheet(): void {
    if (this.playerStore.currentSong.localUri) { BubbleTip.show(this.getUIContext(), '本地文件使用原始音质'); return }
    if (this.isNonCatalogAudio()) { this.openAudioDetails(); return }
    this.activeSheet = 'quality'
    this.loadMusicQualities()
  }

  private async openDownloadQualitySheet(): Promise<void> {
    if (this.isNonCatalogAudio()) { this.openAudioDetails(); return }
    if (this.downloading) {
      BubbleTip.show(this.getUIContext(), `正在下载 · ${this.downloadProgress}%`)
      return
    }
    const song = this.playerStore.currentSong
    if (!song.id) { return }
    const token = ++this.downloadQualityToken
    this.downloadTarget = song
    this.downloadSongName = song.name
    this.downloadQualities = []
    this.preferredDownloadLevel = ''
    this.downloadQualityError = ''
    this.downloadQualityLoading = true
    this.activeSheet = 'downloadQuality'
    try {
      const qualities = await SongQualityService.available(song.id)
      if (token !== this.downloadQualityToken) { return }
      this.downloadQualities = qualities
      this.preferredDownloadLevel = SongQualityService.candidates(AppSettings.defaultDownloadQuality, qualities)[0] || ''
    } catch (error) {
      if (token === this.downloadQualityToken) {
        this.downloadQualityError = error instanceof Error ? error.message : '音质查询失败，点击重试'
      }
    } finally {
      if (token === this.downloadQualityToken) { this.downloadQualityLoading = false }
    }
  }

  private async loadLikedState(): Promise<void> {
    if (this.isNonCatalogAudio()) { this.likeListRequestToken++; this.liked = false; return }
    const songId = this.playerStore.currentSong.id
    if (!this.authStore.loggedIn || !this.authStore.userId) {
      this.liked = this.playerStore.currentSong.liked || false
      return
    }
    const requestToken = ++this.likeListRequestToken
    try {
      const response = await ApiClient.get<LikeListResponse>('/likelist', [
        { key: 'uid', value: this.authStore.userId }
      ])
      if (requestToken !== this.likeListRequestToken) {
        return
      }
      this.likedSongIds = (response.ids || []).map((id: number) => id.toString())
      this.playerStore.queue.forEach((item: songItemType) => {
        item.liked = this.likedSongIds.includes(item.id)
      })
      if (songId === this.playerStore.currentSong.id) {
        this.liked = this.likedSongIds.includes(songId)
        this.playerStore.currentSong.liked = this.liked
      }
    } catch (_error) {
      if (songId === this.playerStore.currentSong.id) {
        this.liked = this.playerStore.currentSong.liked || false
      }
    }
  }

  private async toggleLike(): Promise<void> {
    if (this.isNonCatalogAudio()) { this.openAudioDetails(); return }
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    const nextLiked = !this.liked
    try {
      const response = await ApiClient.get<CommentResponse>('/like', [
        { key: 'id', value: this.playerStore.currentSong.id },
        { key: 'like', value: nextLiked.toString() }
      ])
      if (response.code === 200) {
        this.liked = nextLiked
        this.playerStore.currentSong.liked = nextLiked
        if (nextLiked) {
          if (!this.likedSongIds.includes(this.playerStore.currentSong.id)) {
            this.likedSongIds.push(this.playerStore.currentSong.id)
          }
        } else {
          this.likedSongIds = this.likedSongIds.filter((id: string) => id !== this.playerStore.currentSong.id)
        }
        this.redCount = Math.max(0, this.redCount + (nextLiked ? 1 : -1))
        BubbleTip.show(this.getUIContext(), nextLiked ? '已加入我喜欢的音乐' : '已取消喜欢')
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '操作失败')
    }
  }




  private currentCommentResource(): CommentResource {
    const song = this.playerStore.currentSong
    return { id: song.programId || song.id, type: song.programId ? 4 : 0, title: song.name }
  }

  private canComment(): boolean {
    const song = this.playerStore.currentSong
    return song.isDifm !== true && /^\d+$/.test(song.programId || song.id) &&
      (!song.localUri || this.networkAvailable)
  }

  private async loadCommentSummary(): Promise<void> {
    if (!this.canComment()) { return }
    const resource = this.currentCommentResource()
    try {
      const total = await CommentService.count(resource)
      const current = this.currentCommentResource()
      if (resource.id === current.id && resource.type === current.type) {
        this.playerStore.currentSong.commentCount = total
      }
    } catch (_error) {}
  }

  private openComments(): void {
    if (!this.canComment()) { return }
    this.commentTarget = this.currentCommentResource()
    this.commentsVisible = true
  }

  @Builder
  private CommentsSheet() {
    ResourceComments({
      resource: this.commentTarget,
      onClose: () => this.commentsVisible = false,
      onCountChange: (total: number) => {
        const current = this.currentCommentResource()
        if (current.id === this.commentTarget.id && current.type === this.commentTarget.type) {
          this.playerStore.currentSong.commentCount = total
        }
      }
    })
  }

  private async openCollectSheet(): Promise<void> {
    if (this.isNonCatalogAudio()) { this.openAudioDetails(); return }
    if (!this.authStore.loggedIn) {
      this.pageStack.pushPathByName('LoginPage', null)
      return
    }
    this.activeSheet = 'collect'
    if (!this.authStore.userId) {
      return
    }
    try {
      const response = await ApiClient.get<UserPlaylistResponse>('/user/playlist', [
        { key: 'uid', value: this.authStore.userId },
        { key: 'limit', value: '100' }
      ])
      this.playlists = (response.playlist || [])
        .map((item) => mapPlaylist(item))
        .filter((item: playlistType) => item.creatorId === this.authStore.userId)
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '歌单加载失败')
    }
  }

  private async collectTo(playlist: playlistType): Promise<void> {
    try {
      const response = await ApiClient.get<CommentResponse>('/playlist/tracks', [
        { key: 'op', value: 'add' },
        { key: 'pid', value: playlist.id },
        { key: 'tracks', value: this.playerStore.currentSong.id }
      ])
      if (response.code === 200) {
        this.activeSheet = ''
        BubbleTip.show(this.getUIContext(), `已收藏到「${playlist.name}」`)
      } else {
        BubbleTip.show(this.getUIContext(), '收藏失败，请确认歌单权限')
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '收藏失败')
    }
  }

  private async downloadSong(level: string): Promise<void> {
    const song = this.downloadTarget
    if (!song || this.downloading || this.downloadQualityLoading) { return }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.downloading = true
    this.activeSheet = ''
    this.downloadProgress = 0
    let tempPath = ''
    try {
      let saveMode = AppSettings.downloadSaveMode
      if (AppSettings.askDownloadSaveMode) {
        const result = await this.getUIContext().getPromptAction().showActionMenu({
          title: '保存方式',
          buttons: [{ text: '保存到下载目录', color: '#ef233c' }, { text: '另存为…', color: '#777777' }]
        })
        saveMode = result.index === 1 ? 'saveAs' : 'download'
      }
      BubbleTip.show(this.getUIContext(), '正在获取下载地址…')
      const resource = await SongQualityService.download(song.id, level)
      const qualityTitle = SongQualityService.title(resource.actualLevel)
      BubbleTip.show(this.getUIContext(), `正在下载 · ${qualityTitle}`)
      tempPath = `${context.cacheDir}/song_${song.id}_${Date.now()}.audio`
      const task = await request.downloadFile(context, {
        url: resource.url,
        filePath: tempPath,
        header: { 'Referer': 'https://music.163.com/' },
        enableMetered: true,
        background: false
      })
      task.on('progress', (received: number, total: number) => {
        if (total > 0) { this.downloadProgress = Math.min(99, Math.floor(received * 100 / total)) }
      })
      await new Promise<void>((resolve, reject) => {
        task.on('complete', () => resolve())
        task.on('fail', (code: number) => reject(new Error(`下载失败 (${code})`)))
      })
      const source = fileIo.openSync(tempPath, fileIo.OpenMode.READ_ONLY)
      try {
        const fileSize = fileIo.statSync(source.fd).size
        if (fileSize <= 0 || (resource.size > 0 && resource.size !== fileSize)) {
          throw new Error('音频文件下载不完整，请重试')
        }
        const header = new ArrayBuffer(64)
        const bytesRead = fileIo.readSync(source.fd, header, { offset: 0, length: 64 })
        const extension = AudioFileFormat.extension(resource.url, resource.type, resource.encodeType,
          new Uint8Array(header, 0, bytesRead))
        const safeName = this.safeCoverFileName(`${song.name}-${song.author}`)
        const saved = await LocalLibrary.saveDownload(context, tempPath, `${safeName}.${extension}`, song, saveMode)
        if (!saved) { BubbleTip.show(this.getUIContext(), '已取消保存'); return }
        this.downloadProgress = 100
        BubbleTip.show(this.getUIContext(), `${saved} · ${qualityTitle}`)
      } finally {
        fileIo.closeSync(source)
      }
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '下载失败')
    } finally {
      this.downloading = false
      if (tempPath) {
        try { if (fileIo.accessSync(tempPath)) { fileIo.unlinkSync(tempPath) } } catch (_error) {}
      }
    }
  }

  private safeCoverFileName(value: string): string {
    return value.replace(/[\\/:*?"<>|]/g, '_')
  }

  private async cacheCoverImage(): Promise<string> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cacheDir = `${context.cacheDir}/song_cover`
    try {
      fileIo.mkdirSync(cacheDir, true)
    } catch (_error) {
    }
    const filePath = `${cacheDir}/${this.safeCoverFileName(this.playerStore.currentSong.name)}-${this.playerStore.currentSong.id}.jpg`
    const client = http.createHttp()
    try {
      const response = await client.request(this.playerStore.currentSong.img, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: true
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`封面下载失败 (${response.responseCode})`)
      }
      const file = fileIo.openSync(filePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(file.fd, response.result as ArrayBuffer)
      } finally {
        fileIo.closeSync(file)
      }
      return fileUri.getUriFromPath(filePath)
    } finally {
      client.destroy()
    }
  }

  private async saveCoverToGallery(): Promise<void> {
    if (this.coverSaving || !this.playerStore.currentSong.img) {
      return
    }
    this.coverSaving = true
    this.coverMessage = '正在准备封面图片…'
    try {
      const sourceUri = await this.cacheCoverImage()
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      try {
        const configs: photoAccessHelper.PhotoCreationConfig[] = [{
          title: this.safeCoverFileName(`${this.playerStore.currentSong.name}-${this.playerStore.currentSong.author}`),
          fileNameExtension: 'jpg',
          photoType: photoAccessHelper.PhotoType.IMAGE
        }]
        const savedUris = await helper.showAssetsCreationDialog([sourceUri], configs)
        this.coverMessage = savedUris.length > 0 ? '封面已保存到相册' : '已取消保存'
      } finally {
        await helper.release()
      }
    } catch (error) {
      this.coverMessage = error instanceof Error ? error.message : '封面保存失败'
    } finally {
      this.coverSaving = false
    }
  }

  private async saveCoverFromMenu(): Promise<void> {
    this.activeSheet = ''
    await this.saveCoverToGallery()
    if (this.coverMessage) {
      BubbleTip.show(this.getUIContext(), this.coverMessage)
    }
  }

  private async openCurrentAlbum(): Promise<void> {
    if (this.isNonCatalogAudio()) { this.openAudioDetails(); return }
    const song = this.playerStore.currentSong
    if (!song.id || !song.album) {
      return
    }
    let albumId = song.albumId || ''
    if (!albumId) {
      try {
        const response = await ApiClient.get<SongDetailResponse>('/song/detail', [
          { key: 'ids', value: song.id }
        ])
        if (response.songs && response.songs.length > 0) {
          const detailed = mapApiSong(response.songs[0])
          albumId = detailed.albumId || ''
          this.playerStore.currentSong.albumId = albumId
          if (this.playerStore.currentIndex >= 0) {
            this.playerStore.queue[this.playerStore.currentIndex].albumId = albumId
          }
        }
      } catch (_error) {
      }
    }
    if (!albumId) {
      BubbleTip.show(this.getUIContext(), '暂时无法获取专辑信息')
      return
    }
    const param: AlbumPageParam = {
      id: albumId,
      name: song.album,
      picUrl: song.img,
      artist: song.author
    }
    this.pageStack.pushPathByName('AlbumDetailPage', param)
  }

  private shareSong(): void {
    if (this.isNonCatalogAudio()) { this.openAudioDetails(); return }
    this.shareParam = {
      type: 'song',
      id: this.playerStore.currentSong.id,
      name: this.playerStore.currentSong.name,
      img: this.playerStore.currentSong.img,
      author: this.playerStore.currentSong.author
    }
    this.shareSheetVisible = true
  }

  private openArtist(artist: SongArtist): void {
    if (this.isNonCatalogAudio()) { this.openAudioDetails(); return }
    if (!artist.id || artist.id === '0') {
      return
    }
    const param: ArtistPageParam = { id: artist.id, name: artist.name, picUrl: artist.picUrl || '' }
    this.pageStack.pushPathByName('ArtistPage', param)
  }

  @Builder
  private CurrentArtistLinks(fontSize: number, color: string) {
    Row({ space: 4 }) {
      if (this.playerStore.currentSong.artists && this.playerStore.currentSong.artists.length > 0) {
        ForEach(this.playerStore.currentSong.artists, (artist: SongArtist, index: number) => {
          Text(artist.name).fontSize(fontSize).fontColor(color).maxLines(1)
            .onClick(() => this.openArtist(artist))
          if (index < (this.playerStore.currentSong.artists || []).length - 1) {
            Text('/').fontSize(fontSize).fontColor('#66666e')
          }
        })
      } else {
        Text(this.playerStore.currentSong.author).fontSize(fontSize).fontColor(color).maxLines(1)
      }
    }
    .width('100%')
  }

  private switchSong(direction: number): void {
    if (this.switchingSong) {
      return
    }
    if (direction < 0 && this.playerStore.position > 5000) {
      playerController.previous()
      return
    }
    this.switchingSong = true
    if (this.showLyrics) {
      this.performSongSwitch(direction, false)
      return
    }
    animateTo({
      duration: 230,
      curve: Curve.EaseIn,
      onFinish: () => this.performSongSwitch(direction, true)
    }, () => {
      this.vinylOffsetX = direction > 0 ? -360 : 360
      this.vinylOpacity = 0
    })
  }

  private async performSongSwitch(direction: number, animateVinyl: boolean): Promise<void> {
    const previousId = this.playerStore.currentSong.id
    if (direction > 0) {
      await playerController.next()
    } else {
      await playerController.previous()
    }
    if (previousId === this.playerStore.currentSong.id) {
      this.vinylOffsetX = 0
      this.vinylOpacity = 1
      this.switchingSong = false
      return
    }
    this.liked = this.playerStore.currentSong.liked || false
    this.loadCommentSummary()
    this.loadLyrics()
    this.loadRedCount()
    this.loadMusicQualities()
    this.loadLikedState()
    if (!animateVinyl) {
      this.switchingSong = false
      return
    }
    this.vinylOffsetX = direction > 0 ? 360 : -360
    this.vinylOpacity = 0
    setTimeout(() => {
      animateTo({
        duration: 320,
        curve: Curve.EaseOut,
        onFinish: () => this.switchingSong = false
      }, () => {
        this.vinylOffsetX = 0
        this.vinylOpacity = 1
      })
    }, 20)
  }

  private async selectQueueSong(index: number): Promise<void> {
    await playerController.playAt(index, true)
    this.liked = this.playerStore.currentSong.liked || false
    this.activeSheet = ''
    this.loadCommentSummary()
    this.loadLyrics()
    this.loadRedCount()
    this.loadMusicQualities()
    this.loadLikedState()
  }

  @Builder
  private LyricsPanel() {
    Column({ space: 8 }) {
      if (this.lyricsImmersive) {
        Row() {
          Blank()
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
              .fontSize(14).fontColor(['#d9d9de'])
            Text('退出沉浸').fontSize(10).fontColor('#d9d9de')
          }
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(14)
          .onClick(() => this.toggleLyricsImmersive())
        }
        .width('100%')
        .padding({ left: 22, right: 22 })
        .position({ left: 0, top: this.topAvoidHeight + 10 })
        .zIndex(10)
      } else {
        Row() {
        Column({ space: 2 }) {
          Text('歌词')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
          Text(this.lyricUserScrolling ? '正在浏览，3.5 秒后恢复跟随' :
            (this.hasPreciseLyrics() ? '逐字歌词 · 点击任意歌词可跳转' : '点击任意歌词可跳转播放'))
            .fontSize(9)
            .fontColor(this.lyricUserScrolling ? '#ff8b9a' : '#85858e')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(18).fontColor(['#d9d9de'])
            .onClick(() => this.activeSheet = 'lyricSettings')
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
              .fontSize(14).fontColor([this.lyricsImmersive ? '#ff7b8b' : '#d9d9de'])
            Text(this.lyricsImmersive ? '退出沉浸' : '沉浸歌词')
              .fontSize(10).fontColor(this.lyricsImmersive ? '#ff7b8b' : '#d9d9de')
          }
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor(this.lyricsImmersive ? 'rgba(239,35,60,0.16)' : 'rgba(255,255,255,0.08)')
          .borderRadius(14)
          .onClick(() => this.toggleLyricsImmersive())
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.music')).fontSize(14).fontColor(['#d9d9de'])
            Text('返回唱片').fontSize(10).fontColor('#d9d9de')
          }
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(14)
          .onClick(() => this.closeLyrics())
        }
        }
        .width('100%')
        .padding({ left: 22, right: 22 })
      }

      if (this.lyricsLoading) {
        Column({ space: 12 }) {
          LoadingProgress().width(40).color('#ffffff')
          Text('正在加载歌词…').fontSize(11).fontColor('#85858e')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.lyricMessage) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.text_alignleft')).fontSize(40).fontColor(['#55555d'])
          Text(this.lyricMessage).fontSize(12).fontColor('#85858e')
          if (this.lyricCanRetry) {
            Row({ space: 7 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor(['#ffffff'])
              Text('重新加载歌词').fontSize(12).fontColor('#ffffff')
            }
            .padding({ left: 14, right: 14, top: 9, bottom: 9 })
            .backgroundColor('rgba(255,255,255,0.10)').borderRadius(18)
            .onClick(() => this.loadLyrics())
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Stack() {
          List({ space: this.lyricAppearance.spacing, scroller: this.lyricScroller }) {
            ListItem() {
              Column().height(this.lyricsImmersive ? this.topAvoidHeight + 58 : 175)
            }
            ForEach(this.lyricLines, (line: LyricLine, index: number) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column()
                    .width(index === this.currentLyricIndex ? 3 : 0)
                    .height(index === this.currentLyricIndex ? 28 : 0)
                    .borderRadius(2)
                    .backgroundColor(this.lyricAppearance.highlight)
                  Column({ space: 5 }) {
                    this.PrimaryLyricText(line, index)
                    if (line.translation) {
                      Text(line.translation)
                        .width('100%')
                        .fontSize(index === this.currentLyricIndex ? 14 : 12)
                        .fontColor(index === this.currentLyricIndex ? '#c8c8ce' : 'rgba(255,255,255,0.25)')
                        .lineHeight(20)
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding({ left: 22 + this.lyricAppearance.horizontal, right: 22, top: 3, bottom: 3 })
                .opacity(this.lyricLineOpacity(index))
                .scale({
                  x: this.lyricLineScale(index),
                  y: this.lyricLineScale(index)
                })
                .translate({ y: this.lyricLineOffset(index) })
                .animation({
                  curve: curves.springMotion(0.56, 0.68, 0.24),
                  delay: this.lyricLineDelay(index)
                })
                .onClick(() => this.seekToLyric(line, index))
              }
            })
            ListItem() {
              Column().height(this.lyricsImmersive ? 280 : 195)
            }
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const height = Number(newArea.height)
            if (Number.isFinite(height) && height > 0) {
              this.lyricViewportHeight = height
            }
          })
          .onScrollStart(() => this.handleLyricScrollStart())
          .onScrollStop(() => this.handleLyricScrollStop())

          if (this.lyricUserScrolling) {
            Row({ space: 7 }) {
              SymbolGlyph($r('sys.symbol.hand_draw')).fontSize(13).fontColor(['#ff8b9a'])
              Text('已暂停自动跟随').fontSize(10).fontColor('#ffffff')
            }
            .padding({ left: 11, right: 11, top: 7, bottom: 7 })
            .backgroundColor('rgba(22,18,22,0.86)')
            .borderRadius(15)
            .align(Alignment.Bottom)
            .margin({ bottom: 12 })
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ top: 8 })
  }

  @Builder
  private SmallAction(icon: Resource, text: string, onClick: () => void) {
    Column({ space: 7 }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontColor(['#e8e8ec'])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor('rgba(255,255,255,0.08)')
      Text(text)
        .fontSize(10)
        .fontColor('#a9a9b0')
    }
    .layoutWeight(1)
    .onClick(onClick)
  }

  @Builder
  private QualitySheet() {
    Column() {
      this.SheetHeader('选择播放音质', `当前：${this.playerStore.qualityTitle()} · 目标：${this.playerStore.requestedQualityTitle()}`)
      if (this.qualityLoading) {
        LoadingProgress().width(36).height(36).color('#ef233c').margin({ top: 28 })
      } else if (this.qualityError) {
        Text(`${this.qualityError} · 点击重试`).fontSize(14).fontColor('#a9a9b0').margin({ top: 28 })
          .onClick(() => this.loadMusicQualities())
      } else if (this.availableQualities.length === 0) {
        Text('暂无可用音质').fontSize(14).fontColor('#888890').margin({ top: 28 })
      } else {
        List({ space: 4 }) {
        ForEach(this.availableQualities, (item: QualityOption) => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(item.title)
                  .fontSize(15)
                  .fontWeight(item.level === this.playerStore.quality ? FontWeight.Bold : FontWeight.Regular)
                  .fontColor(item.level === this.playerStore.quality ? '#FE010D' : '#eeeeee')
                Text(item.description)
                  .fontSize(11)
                  .fontColor('#777777')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              if (item.level === this.playerStore.quality) {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(22)
                  .fontColor(['#ef233c'])
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .onClick(() => {
              playerController.changeQuality(item.level)
              this.activeSheet = ''
            })
          }
        })
        }
        .layoutWeight(1)
      }
    }
  }

  @Builder
  private DownloadQualitySheet() {
    Column() {
      this.SheetHeader('选择下载音质', this.downloadSongName)
      if (this.downloadQualityLoading) {
        LoadingProgress().width(36).height(36).color('#ef233c').margin({ top: 28 })
      } else if (this.downloadQualityError) {
        Text(`${this.downloadQualityError} · 点击重试`).fontSize(14).fontColor('#a9a9b0').margin({ top: 28 })
          .onClick(() => this.openDownloadQualitySheet())
      } else if (this.downloadQualities.length === 0) {
        Text('暂无可下载音质').fontSize(14).fontColor('#888890').margin({ top: 28 })
      } else {
        Text('按原始音频格式保存，实际音质以账号可下载资源为准')
          .fontSize(11).fontColor('#888890').padding({ left: 20, right: 20, bottom: 8 })
        List({ space: 4 }) {
          ForEach(this.downloadQualities, (item: QualityOption) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text(item.level === this.preferredDownloadLevel ? `${item.title} · 默认可用` : item.title)
                    .fontSize(15).fontColor(item.level === this.preferredDownloadLevel ? '#ef233c' : '#eeeeee')
                  Text(item.description).fontSize(11).fontColor('#777777')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(22).fontColor(['#a9a9b0'])
              }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 12 })
                .onClick(() => this.downloadSong(item.level))
            }
          }, (item: QualityOption) => item.level)
        }.layoutWeight(1)
      }
    }.height('100%')
  }

  private closeSheet(): void {
    this.activeSheet = ''
    if (!this.playerStore.hasQueue()) { this.pageStack.pop() }
  }

  @Builder
  private QueueSheet() {
    Column() {
      this.SheetHeader(`播放队列 · ${this.playerStore.queue.length} 首`, this.playerStore.modeTitle())
      if (this.playerStore.queue.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.music')).fontSize(38).fontColor(['#55555d'])
          Text('播放列表为空').fontSize(14).fontColor('#888890')
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.playerStore.queue, (item: songItemType, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                if (index === this.playerStore.currentIndex) {
                  SymbolGlyph($r('sys.symbol.text_alignleft')).width(24).fontSize(18).fontColor(['#FE010D'])
                } else {
                  Text((index + 1).toString()).width(24).fontSize(12).fontColor('#66666e')
                    .textAlign(TextAlign.Center)
                }
                Column({ space: 3 }) {
                  Text(item.name).fontSize(14)
                    .fontColor(index === this.playerStore.currentIndex ? '#FE010D' : '#e8e8eb').maxLines(1)
                  Text(item.author).fontSize(11).fontColor('#77777f').maxLines(1)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                  .onClick(() => this.selectQueueSong(index))
                SymbolGlyph($r('sys.symbol.xmark')).fontSize(15).fontColor(['#66666e'])
                  .onClick(() => playerController.removeAt(index))
              }
              .height(58).padding({ left: 18, right: 18 })
            }
          })
        }
        .layoutWeight(1)
        Text('清空播放列表').width('100%').height(48).fontSize(13).fontColor('#ef4058')
          .textAlign(TextAlign.Center).onClick(async () => {
            await playerController.clearQueue()
          })
      }
    }
  }

  @Builder
  private MoreSheet() {
    Column() {
      this.SheetHeader('歌曲选项', '刷新当前歌曲的封面、歌词和页面信息')
      Row({ space: 14 }) {
        if (this.pageReloading) {
          LoadingProgress().width(24).height(24).color('#ffffff')
        } else {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(24).fontColor(['#ffffff'])
        }
        Column({ space: 4 }) {
          Text(this.pageReloading ? '正在重新加载…' : '重新加载').fontSize(15).fontColor('#ffffff')
          Text('重新获取歌曲详情、封面与歌词').fontSize(11).fontColor('#77777f')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
      .width('100%').height(68).padding({ left: 20, right: 20 })
      .enabled(!this.pageReloading).onClick(() => this.reloadSongPage())
      Row({ space: 14 }) {
        if (this.coverSaving) {
          LoadingProgress().width(24).height(24).color('#ffffff')
        } else {
          SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(24).fontColor(['#ffffff'])
        }
        Column({ space: 4 }) {
          Text(this.coverSaving ? '正在保存封面…' : '保存歌曲封面').fontSize(15).fontColor('#ffffff')
          Text('将当前歌曲封面保存到系统图库').fontSize(11).fontColor('#77777f')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
      .width('100%').height(68).padding({ left: 20, right: 20 })
      .enabled(!this.coverSaving && this.playerStore.currentSong.img.length > 0)
      .onClick(() => this.saveCoverFromMenu())
    }
  }


  @Builder
  private CollectSheet() {
    Column() {
      this.SheetHeader('收藏到歌单', '选择一个自己创建的歌单')
      if (this.playlists.length === 0) {
        Column({ space: 12 }) {
          LoadingProgress().width(38).height(38).color('#ef233c')
          Text('正在加载歌单…').fontSize(12).fontColor('#77777f')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.playlists, (item: playlistType) => {
            ListItem() {
              Row({ space: 12 }) {
                Image(item.cover)
                  .width(48)
                  .height(48)
                  .borderRadius(10)
                  .objectFit(ImageFit.Cover)
                Column({ space: 4 }) {
                  Text(item.name).fontSize(14).fontColor('#ededf0').maxLines(1)
                  Text(`${item.count} 首`).fontSize(11).fontColor('#77777f')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.plus_circle'))
                  .fontSize(22)
                  .fontColor(['#ff6577'])
              }
              .height(66)
              .padding({ left: 18, right: 18 })
              .onClick(() => this.collectTo(item))
            }
          })
        }
        .layoutWeight(1)
      }
    }
  }

  @Builder
  private SheetHeader(title: string, subtitle: string) {
    Row() {
      Column({ space: 4 }) {
        Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#ffffff')
        Text(subtitle).fontSize(10).fontColor('#77777f')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(24)
        .fontColor(['#686870'])
        .onClick(() => this.closeSheet())
    }
    .width('100%')
    .height(68)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  private CoverPreview() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#050507')

      Image(this.playerStore.currentSong.img)
        .width('100%')
        .height('72%')
        .objectFit(ImageFit.Contain)

      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(30)
            .fontColor(['rgba(255,255,255,0.82)'])
            .onClick(() => this.coverPreviewVisible = false)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 20, right: 20, top: 18 })

        Blank()

        Column({ space: 12 }) {
          Text(this.playerStore.currentSong.name)
            .width('100%')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
          this.CurrentArtistLinks(12, '#92929a')
          Button() {
            Row({ space: 7 }) {
              if (this.coverSaving) {
                LoadingProgress().width(18).height(18).color('#ffffff')
              } else {
                SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                  .fontSize(18)
                  .fontColor(['#ffffff'])
              }
              Text(this.coverSaving ? '正在保存…' : '保存图片')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#ffffff')
            }
          }
          .width(176)
          .height(46)
          .backgroundColor('#ef233c')
          .borderRadius(23)
          .enabled(!this.coverSaving)
          .onClick(() => this.saveCoverToGallery())
          if (this.coverMessage) {
            Text(this.coverMessage)
              .fontSize(11)
              .fontColor(this.coverMessage.indexOf('已保存') >= 0 ? '#66c98b' : '#ff8292')
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 30 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050507')
  }

  @Builder
  private BottomSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.58)')
        .onClick(() => this.closeSheet())
      Column() {
        if (this.activeSheet === 'lyricSettings') {
          LyricSettingsSheet({ value: this.lyricAppearance,
            onPreview: (value: LyricPreferences) => { this.lyricAppearance = value; this.updateCurrentLyric() },
            onClose: () => this.closeSheet() })
        } else if (this.activeSheet === 'quality') {
          this.QualitySheet()
        } else if (this.activeSheet === 'downloadQuality') {
          this.DownloadQualitySheet()
        } else if (this.activeSheet === 'queue') {
          this.QueueSheet()
        } else if (this.activeSheet === 'collect') {
          this.CollectSheet()
        } else if (this.activeSheet === 'more') {
          this.MoreSheet()
        }
      }
      .width('100%')
      .height(this.activeSheet === 'quality' || this.activeSheet === 'downloadQuality' ? '62%' : this.activeSheet === 'more' ? '28%' : '68%')
      .backgroundColor('#19191f')
      .borderRadius({ topLeft: 28, topRight: 28 })
      .shadow({ radius: 28, color: 'rgba(0,0,0,0.45)', offsetY: -5 })
      .transition(TransitionEffect.translate({ y: 700 }).animation({ duration: 260, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
        Stack() {
        Image(this.playerStore.currentSong.img)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(90)
          .opacity(0.44)
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [['rgba(12,12,16,0.42)', 0], ['rgba(15,15,20,0.82)', 0.58], ['#121215', 1]]
          })

        Scroll() {
        Column() {
          if (!this.lyricsImmersive) {
            Column().width('100%').height(this.topAvoidHeight)
            Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor(['#ffffff'])
              .onClick(() => this.pageStack.pop())
            Column({ space: 2 }) {
              Text('正在播放').fontSize(10).fontColor('#a2a2aa')
              Text(this.playerStore.currentSong.album || '网易云音乐')
                .fontSize(12)
                .fontColor('#e4e4e8')
                .maxLines(1)
                .onClick(() => this.openCurrentAlbum())
            }
            .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(24)
              .fontColor(['#ffffff'])
              .onClick(() => this.activeSheet = 'more')
            }
            .width('100%')
            .height(58)
            .constraintSize({ minHeight: 58 })
            .padding({ left: 18, right: 18 })
          }

          if (this.showLyrics) {
            this.LyricsPanel()
          } else {
            Column({ space: 14 }) {
              Stack() {
                VinylRecord({
                  coverUrl: this.playerStore.currentSong.img,
                  isPlaying: this.playerStore.isPlaying && !this.playerStore.isLoading,
                  diameter: this.vinylDiameter
                })
              }
              .width(this.vinylDiameter).height(this.vinylDiameter)
              .borderRadius('50%')
              .translate({ x: this.vinylOffsetX })
              .opacity(this.vinylOpacity)
              .shadow({
                radius: 26,
                color: 'rgba(0,0,0,0.42)',
                offsetX: 0,
                offsetY: 0
              })
              .gesture(
                LongPressGesture({ fingers: 1, repeat: false, duration: 550 })
                  .onAction(() => {
                    this.coverMessage = ''
                    this.coverPreviewVisible = true
                  })
              )

              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.text_alignleft')).fontSize(13).fontColor(['#b8b8bf'])
                Text('点击唱片查看滚动歌词').fontSize(10).fontColor('#b8b8bf')
              }
              .padding({ left: 11, right: 11, top: 7, bottom: 7 })
              .backgroundColor('rgba(255,255,255,0.07)')
              .borderRadius(15)
            }
            .width('100%')
            .layoutWeight(1)
            .constraintSize({ minHeight: 220 })
            .justifyContent(FlexAlign.Center)
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.vinylDiameter = Math.max(1,
                Math.min(360, Number(newArea.width) * 0.78, Number(newArea.height) - 64))
            })
            .onClick(() => this.openLyrics())
          }

          if (!this.lyricsImmersive) {
            Row({ space: 16 }) {
            Column({ space: 5 }) {
              Row({ space: 7 }) {
                Text(this.playerStore.currentSong.name)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (this.playerStore.currentSong.fee === 1) {
                  Text('VIP')
                    .fontSize(9)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#ff4058')
                    .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                    .border({ width: 1, color: '#ff4058' })
                    .borderRadius(4)
                }
              }
              .width('100%')
              this.CurrentArtistLinks(14, '#a6a6ae')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            if (!this.isNonCatalogAudio()) {
            Column({ space: 3 }) {
              SymbolGlyph(this.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(27)
                .fontColor([this.liked ? '#ff4058' : '#ffffff'])
              Text(this.redCountLoading ? '…' : this.formatMetricCount(this.redCount))
                .fontSize(9).fontColor('#9b9ba3')
            }
            .onClick(() => this.toggleLike())
            }

            if (this.canComment()) {
            Column({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.ellipsis_bubble'))
                .fontSize(25)
                .fontColor(['#ffffff'])
              Text((this.playerStore.currentSong.commentCount || 0).toString())
                .fontSize(9)
                .fontColor('#9b9ba3')
            }
            .onClick(() => this.openComments())
            }
            }
            .width('100%')
            .constraintSize({ minHeight: 70 })
            .padding({ left: 24, right: 24, bottom: 12 })

            Column({ space: 2 }) {
            Slider({
              value: this.progressPosition(),
              min: 0,
              max: Math.max(this.playerStore.duration, 1)
            })
              .width('100%')
              .blockColor('#ffffff')
              .blockSize({ width: 11, height: 11 })
              .selectedColor('#ffffff')
              .trackColor('rgba(255,255,255,0.22)')
              .trackThickness(2)
              .onChange((value: number, mode: SliderChangeMode) => this.handleProgressChange(value, mode))
            Row() {
              Text(this.formatTime(this.progressPosition())).fontSize(10).fontColor('#92929a')
              Row({ space: 4 }) {
                Text(this.playerStore.qualityTitle()).fontSize(10).fontColor('#d8d8dd')
                if (!this.isNonCatalogAudio()) {
                  SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(10).fontColor(['#8d8d95'])
                }
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('rgba(255,255,255,0.08)')
              .borderRadius(10)
              .onClick(() => { if (!this.isNonCatalogAudio()) { this.openQualitySheet() } })
              Text(this.formatTime(this.playerStore.duration)).fontSize(10).fontColor('#92929a')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            }
            .constraintSize({ minHeight: 60 })
            .padding({ left: 20, right: 20 })

            Row() {
            Column({ space: 4 }) {
              SymbolGlyph(this.modeSymbol())
                .fontSize(24)
                .fontColor(['#dedee2'])
              Text(this.playerStore.modeTitle()).fontSize(8).fontColor('#77777f')
            }
            .width(60)
            .onClick(() => playerController.cycleMode())

            SymbolGlyph($r('sys.symbol.backward_fill'))
              .fontSize(31)
              .fontColor(['#ffffff'])
              .opacity(this.switchingSong ? 0.45 : 1)
              .onClick(() => this.switchSong(-1))

            Stack() {
              if (this.playerStore.isLoading) {
                LoadingProgress().width(58).height(58).color('#ffffff')
              } else {
                SymbolGlyph(this.playerStore.isPlaying ? $r('sys.symbol.pause_circle_fill') :
                  $r('sys.symbol.play_circle_fill'))
                  .fontSize(64)
                  .fontColor(['#ffffff'])
              }
            }
            .width(72)
            .height(72)
            .onClick(() => playerController.toggle())

            SymbolGlyph($r('sys.symbol.forward_end_fill'))
              .fontSize(31)
              .fontColor(['#ffffff'])
              .opacity(this.switchingSong ? 0.45 : 1)
              .onClick(() => this.switchSong(1))

            Column({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.list_bullet'))
                .fontSize(24)
                .fontColor(['#dedee2'])
              Text(`${this.playerStore.queue.length} 首`).fontSize(8).fontColor('#77777f')
            }
            .width(60)
            .onClick(() => this.activeSheet = 'queue')
            }
            .width('100%')
            .height(94)
            .constraintSize({ minHeight: 94 })
            .justifyContent(FlexAlign.SpaceAround)
            .alignItems(VerticalAlign.Center)

            Row() {
            if (this.isNonCatalogAudio()) {
              this.SmallAction($r('sys.symbol.info_circle'), this.playerStore.currentSong.localUri ? '本地音乐' : this.playerStore.currentSong.programId ? '节目详情' : '音乐电台', () => this.openAudioDetails())
            } else {
            this.SmallAction($r('sys.symbol.folder_badge_plus'), '收藏歌单', () => this.openCollectSheet())
            this.SmallAction($r('sys.symbol.arrow_down_circle'), '下载', () => this.openDownloadQualitySheet())
            this.SmallAction($r('sys.symbol.arrow_right_up_and_square'), '分享', () => this.shareSong())
            this.SmallAction($r('sys.symbol.info_circle'), '歌曲百科', () => {
              this.pageStack.pushPathByName('SongWikiPage', this.playerStore.currentSong)
            })
            }
            }
            .width('100%')
            .constraintSize({ minHeight: 60 })
            .padding({ left: 16, right: 16, bottom: 18 })

            if (this.playerStore.errorMessage) {
              Text(this.playerStore.errorMessage)
                .fontSize(10)
                .fontColor('#ef4058')
                .maxLines(2)
                .textAlign(TextAlign.Center)
                .padding({ left: 20, right: 20, bottom: 8 })
            }
          }
        }
        .width('100%')
        .height('100%')
        .constraintSize({ minHeight: this.lyricsImmersive ? 0 : this.topAvoidHeight + 660 })
        }
        .width('100%').height('100%').scrollBar(BarState.Off)
        .scrollable(this.lyricsImmersive ? ScrollDirection.None : ScrollDirection.Vertical)

        if (this.activeSheet) {
          this.BottomSheet()
        }

        if (this.shareSheetVisible) {
          ShareSheet({
            shareParam: this.shareParam,
            visible: this.shareSheetVisible,
            onClose: () => this.shareSheetVisible = false
          })
        }

        if (this.coverPreviewVisible) {
          this.CoverPreview()
        }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#121215')
        .bindSheet(this.commentsVisible, this.CommentsSheet(), {
          height: '72%', backgroundColor: '#19191f', showClose: false, dragBar: true,
          onDisappear: () => this.commentsVisible = false
        })
    }
    .hideTitleBar(true)
  }
}

interface LyricLine {
  time: number
  duration?: number
  text: string
  translation: string
  words?: LyricWord[]
}

interface LyricWord {
  start: number
  duration: number
  text: string
}

interface YrcWordTag {
  start: number
  duration: number
  markerIndex: number
  textStart: number
}
