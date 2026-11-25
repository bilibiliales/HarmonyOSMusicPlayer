import { Want } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit'
import { MusicWidgetService } from '../services/MusicWidgetService'
import { commonEventManager } from '@kit.BasicServicesKit'
import { MusicCardProtocol } from '../services/MusicCardProtocol'

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
  private imageFile?: fileIo.File
  private static readonly FORM_IDS_FILE: string = 'music_card_ids.json'
  private saveFormId(formId: string, dimension?: number): void {
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
    if (dimension !== undefined && dimension > 0) {
      const dimensions = MusicWidgetService.dimensions(this.context)
      dimensions[formId] = dimension
      const file = fileIo.openSync(`${this.context.filesDir}/${MusicWidgetService.DIMENSIONS_FILE}`,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try { fileIo.writeSync(file.fd, JSON.stringify(dimensions)) } finally { fileIo.closeSync(file.fd) }
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

  private bindingData(dimension: number = 2): formBindingData.FormBindingData {
    if (this.imageFile) { fileIo.closeSync(this.imageFile.fd); this.imageFile = undefined }
    const lease = MusicWidgetService.binding(MusicWidgetService.read(this.context), dimension)
    this.imageFile = lease.file
    return lease.data
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const dimension = Number(want.parameters?.['ohos.extra.param.key.form_dimension']) || 2
    this.saveFormId(this.formIdFromWant(want), dimension)
    return this.bindingData(dimension)
  }

  onUpdateForm(formId: string): void {
    this.saveFormId(formId)
    const lease = MusicWidgetService.binding(MusicWidgetService.read(this.context), MusicWidgetService.dimensions(this.context)[formId] || 2)
    formProvider.updateForm(formId, lease.data).catch(() => {}).finally(() => {
      if (lease.file) { fileIo.closeSync(lease.file.fd) }
    })
  }

  onRemoveForm(formId: string): void {
    const path = `${this.context.filesDir}/${MusicCardAbility.FORM_IDS_FILE}`
    try {
      const ids = (JSON.parse(fileIo.readTextSync(path)) as string[]).filter((id: string) => id !== formId)
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      try { fileIo.writeSync(file.fd, JSON.stringify(ids)) } finally { fileIo.closeSync(file.fd) }
    } catch (_error) {}
  }

  onDestroy(): void {
    if (this.imageFile) { fileIo.closeSync(this.imageFile.fd); this.imageFile = undefined }
  }

  onFormEvent(formId: string, message: string): void {
    if (message === 'refresh') {
      this.onUpdateForm(formId)
      return
    }
    const command = MusicCardProtocol.parse(message)
    if (!command) { return }
    commonEventManager.publish(MusicCardProtocol.EVENT, { data: JSON.stringify(command) }, (error) => {
      if (error) { console.error(`[MusicCard] message delivery failed: ${error.code}`) }
    })
  }
}
