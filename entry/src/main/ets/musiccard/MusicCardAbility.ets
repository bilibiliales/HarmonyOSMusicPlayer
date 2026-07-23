import { Want } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit'

interface MusicCardState {
  songName: string
  artist: string
  songId: string
  isPlaying: boolean
}

class MusicCardBindingState {
  songName: string = ''
  artist: string = ''
  songId: string = ''
  isPlaying: boolean = false
}

export default class MusicCardAbility extends FormExtensionAbility {
  private static readonly FORM_IDS_FILE: string = 'music_card_ids.json'
  private saveFormId(formId: string): void {
    if (!formId) {
      return
    }
    const path = `${this.context.filesDir}/${MusicCardAbility.FORM_IDS_FILE}`
    let ids: string[] = []
    try {
      if (fileIo.accessSync(path)) {
        ids = JSON.parse(fileIo.readTextSync(path)) as string[]
      }
    } catch (_error) {
      ids = []
    }
    if (!ids.includes(formId)) {
      ids.push(formId)
      const file = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(file.fd, JSON.stringify(ids))
      } finally {
        fileIo.closeSync(file)
      }
    }
  }

  private formIdFromWant(want: Want): string {
    const value = want.parameters?.['ohos.extra.param.key.form_identity']
    return value === undefined || value === null ? '' : value.toString()
  }

  private cardState(): MusicCardState {
    const empty: MusicCardState = {
      songName: '今天听点什么？',
      artist: '打开应用开始播放',
      songId: '',
      isPlaying: false
    }
    try {
      const path = `${this.context.filesDir}/player_widget_state.json`
      if (!fileIo.accessSync(path)) {
        return empty
      }
      const value = JSON.parse(fileIo.readTextSync(path)) as MusicCardState
      return {
        songName: value.songName || empty.songName,
        artist: value.artist || empty.artist,
        songId: value.songId || '',
        isPlaying: value.isPlaying || false
      }
    } catch (_error) {
      return empty
    }
  }

  private bindingData(): formBindingData.FormBindingData {
    const state = this.cardState()
    const bindingState = new MusicCardBindingState()
    bindingState.songName = state.songName
    bindingState.artist = state.artist
    bindingState.songId = state.songId
    bindingState.isPlaying = state.isPlaying
    return formBindingData.createFormBindingData(bindingState)
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    this.saveFormId(this.formIdFromWant(want))
    return this.bindingData()
  }

  onUpdateForm(formId: string): void {
    this.saveFormId(formId)
    formProvider.updateForm(formId, this.bindingData()).catch(() => {
    })
  }

  onFormEvent(formId: string, message: string): void {
    if (message === 'refresh') {
      this.onUpdateForm(formId)
    }
  }
}
