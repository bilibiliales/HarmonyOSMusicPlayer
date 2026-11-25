import { UserEventItem } from '../models/api'
import { EventTile } from './EventTile'
import { EventTilePresentation } from '../services/EventTilePresentation'
import { Responsive } from '../services/Responsive'

/** 使用系统 WaterFlow 排列内容卡片，滚动交给个人主页的外层 Scroll。 */
@Component
export struct EventWaterfall {
  @Prop items: UserEventItem[] = []
  onChanged: (item: UserEventItem, deleted: boolean) => void = () => {}
  @State private viewWidth: number = 0

  private columns(): number {
    return Responsive.columns(this.viewWidth, 2, 3, 4)
  }

  private cardWidth(): number {
    return this.viewWidth > 0 ? (this.viewWidth - (this.columns() - 1) * 10) / this.columns() : 180
  }

  private flowHeight(): number {
    const heights: number[] = []
    for (let i = 0; i < this.columns(); i++) { heights.push(0) }
    for (const item of this.items) {
      let shortest = 0
      for (let i = 1; i < heights.length; i++) {
        if (heights[i] < heights[shortest]) { shortest = i }
      }
      heights[shortest] += (heights[shortest] > 0 ? 10 : 0) + EventTilePresentation.height(item, this.cardWidth())
    }
    return Math.max(1, ...heights)
  }

  build() {
    WaterFlow() {
      ForEach(this.items, (item: UserEventItem) => {
        FlowItem() {
          EventTile({ item: item, cardWidth: this.cardWidth(), onChanged: this.onChanged })
        }.width(this.cardWidth()).height(EventTilePresentation.height(item, this.cardWidth()))
      }, (item: UserEventItem) => item.id.toString())
    }
    .columnsTemplate(Responsive.waterFlowColumns(this.columns()))
    .columnsGap(10).rowsGap(10)
    .width('100%').height(this.flowHeight())
    .scrollBar(BarState.Off).enableScrollInteraction(false)
    .onAreaChange((_old: Area, area: Area) => {
      const width = Number(area.width)
      if (width > 0 && Math.abs(width - this.viewWidth) > 1) {
        this.viewWidth = width
      }
    })
  }
}
