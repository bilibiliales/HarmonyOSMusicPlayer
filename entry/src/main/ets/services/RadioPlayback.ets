import { ProgramItem } from '../models/home'
import { songItemType } from '../models/music'
import { RadioService } from './RadioService'
import { playerController } from './PlayerController'

export class RadioPlayback {
  static async play(programs: ProgramItem[], index: number = 0): Promise<void> {
    if (programs.length === 0 || !programs[index]) { throw new Error('暂无可播放节目') }
    const target = programs[index]
    const resolved = RadioService.song(target) || RadioService.song(await RadioService.program(String(target.id)))
    if (!resolved) { throw new Error('该节目暂无音源') }
    const queue: songItemType[] = []
    let selected = 0
    for (const program of programs) {
      const song = program.id === target.id ? resolved : RadioService.song(program)
      if (song) {
        if (program.id === target.id) { selected = queue.length }
        queue.push(song)
      }
    }
    await playerController.setQueue(queue, selected, true)
  }
}
