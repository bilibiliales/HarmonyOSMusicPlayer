import { rpc } from '@kit.IPCKit'
export interface MusicCardCommand { musicCardAction: string; musicCardSongId: string; requestId: string }
interface CardEnvelope { params?: MusicCardCommand; musicCardAction?: string; musicCardSongId?: string; requestId?: string }
export class MusicCardProtocol {
  static readonly METHOD: string = 'musicCardControl'
  static readonly BUNDLE_NAME: string = 'com.hmos.cloudmusic'
  static readonly EVENT: string = 'com.hmos.cloudmusic.MUSIC_CARD_CONTROL'
  static parse(text: string): MusicCardCommand | undefined {
    try {
      const raw = JSON.parse(text) as CardEnvelope
      const value = raw.params || raw
      if (!value.musicCardAction || !['previous', 'toggle', 'next', 'like', 'mode'].includes(value.musicCardAction)) { return undefined }
      return { musicCardAction: value.musicCardAction, musicCardSongId: value.musicCardSongId || '', requestId: value.requestId || '' }
    } catch (_error) { return undefined }
  }
}
export class MusicCardReply implements rpc.Parcelable {
  marshalling(data: rpc.MessageSequence): boolean { data.writeString('accepted'); return true }
  unmarshalling(data: rpc.MessageSequence): boolean { return data.readString() === 'accepted' }
}
