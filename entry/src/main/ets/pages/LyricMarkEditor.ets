import { LyricMarkEditorParam } from '../models/lyricmark'
import { LyricMarkService } from '../services/LyricMarkService'
import { LyricMarkPickPage } from './LyricMarkPick'

/** 歌词本编辑与摘录共用歌词选行组件。 */
@Component
export struct LyricMarkEditorPage {
  pageParam: LyricMarkEditorParam = {
    mark: { markId: 0, songId: 0, songData: { id: 0, name: '' }, detailList: [] },
    onSaved: () => {}
  }

  build() {
    LyricMarkPickPage({
      pageParam: {
        song: LyricMarkService.toSong(this.pageParam.mark),
        editing: true,
        onSaved: this.pageParam.onSaved
      }
    })
  }
}
