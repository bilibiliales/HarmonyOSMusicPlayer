import { AppBackdrop } from './AppBackdrop'

/**
 * 页面内可复用的皮肤底图层。
 *
 * Index 里的 AppBackdrop 位于 Navigation 的首页内容中，push 出来的
 * NavDestination 页面会把它整个盖住，所以二级页面（聊天、专辑、歌单、
 * 歌手、设置……）看不到皮肤背景图。把这一层以绝对定位挂在页面最底层，
 * 皮肤图就能覆盖到所有内容页，且不占布局空间、不拦截点击。
 *
 * 播放页 / 看图页 / 视频页等自带全屏背景的页面不需要挂这一层。
 */
@Component
export struct SkinBackdrop {
  build() {
    AppBackdrop()
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .hitTestBehavior(HitTestMode.None)
  }
}
