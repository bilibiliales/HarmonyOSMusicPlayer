# HarmonyOSMusicPlayer 实现状态

## 已接通

- 全部页面跳转使用 ArkUI `Navigation`、`NavPathStack` 与 `navDestination`，未使用 `router`。
- 登录：手机号密码、短信验证码、二维码扫码三种方式。
- 手机号未注册时在登录页自动进入昵称、验证码和密码补全流程，不提供独立注册入口。
- 推荐歌单、新歌、Banner、搜索、用户资料、用户歌单、歌单详情与歌曲列表。
- 发现页（`/homepage/block/page`）**不解析 `orpheus://` 深链**（`services/OrpheusLink.ets` 已删除）：
  卡片只按 `resourceType` + 纯数字 id 判断能否走原生页面——`song` 直接进播放队列（无歌曲对象时经
  `/song/detail` 补详情），`program`/`djradio` 进电台页，`digitalAlbum` 进数字专辑详情，其余同理。
  认不出的类型（`event_topic / concert / fm_radio / orpheus / 网页 / 小程序`）、缺 id 的死链、
  以及任何必须开网页的入口，由 `Find.isOpenableResource` 在 `normalizeBlock` 阶段整条过滤掉，
  过滤后为空的 creative / block 一并丢弃；区块标题只做展示，没有箭头也不可点击。
  Banner 只保留 `targetType = 1 / 10 / 1000 / 1004 / 1005`，网页类活动整条不显示。
  全程不引入 ArkWeb，也不 `openLink` 跳浏览器。
- 基于 `AVPlayer` 的真实音频播放、进度跳转、上一首/下一首。
- 在线播放与下载均为流式：CDN 支持 Range/206，播放按需分段取数（有界内存），下载分块直接写盘，不再把 100MB+ FLAC 整曲载入内存。
- 流式播放可在设置中关闭（默认开启）；关闭后回退为整曲载入内存再播放的旧策略（`MemoryAudioSource`/`MemoryAudioLoad`），用于兼容无法消费流式 `dataSrc` 的旧设备 / 虚拟机。流式开关是 `playAt` 的**外层分支**：开关 ON 时按 `resource.size` 选择 `StreamingAudioSource`（有界流式）或 `player.url` 直连（直播/电台等无 size 的流）；开关 OFF 时**始终**走 `MemoryAudioLoad` 整曲加载（不受 `resource.size` 影响，绝不走 `player.url`），即“完整加载到内存之前一直是加载状态”。
- 流式能力可复现验证与回归脚本：`entry/src/test/StreamingAudio.regression.cjs`；开关与回退：`entry/src/test/StreamingToggle.regression.cjs`。
- 后台播放开关关闭时，播放模块不加载 AVSession Kit：`MediaSessionContract.ets`（无 Kit 的中立契约）由 `PlayerController` 静态依赖；唯一静态导入 `@kit.AVSessionKit` 的 `MediaSessionBridge.ets` 仅在 `shouldLoadMediaSession()` 放行后通过常量路径动态导入加载。播放状态改用中立数值常量，避免开关关闭时求值 `avSession.*` 枚举触发 Kit 加载。
- AVSession 隔离性静态依赖扫描 + 门控真值表 + 真实门控代码运行时模拟：`entry/src/test/AvSessionIsolation.regression.cjs`。
- 顺序播放、列表循环、单曲循环、随机播放。
- 全局共享播放队列，迷你播放器与详情页状态同步。
- 播放详情页音质半屏切换、评论半屏、收藏到指定歌单半屏。
- 喜欢/取消喜欢、应用沙箱下载、系统分享、歌曲百科。
- 后端服务地址仅在侧边栏“设置”中展示和修改。
- 后端服务地址使用 Preferences 持久化，并且只在“设置”页展示和修改。
  设置页右上角为「更多」菜单（`bindMenu`）：重置后端服务地址（回到 `ApiClient.DEFAULT_BASE_URL`）、
  重置本地设置、清空播放队列、关于本应用；后端服务 / AI 连接输入框统一为胶囊纯圆角。
  「重置本地设置」只清偏好类键（`AppSettings.resetLocalSettings`），不再整库删除——
  登录 cookie 与设备别名同库，旧实现会连带把账号踢下线。
- 关注/粉丝分页列表、关系按钮、取消关注半屏确认、用户主页和歌手身份角标。
  头像统一全圆，认证号在右下角叠 `avatarDetail.identityIconUrl` 圆形角标。
  对方开启隐私保护时（`/user/follows` 返回 `用户隐私无权限查看`）显示拒绝原因，不再误报「还没有用户」。
- 「我的关注」改用 `/user/follow/mixed`：标题下方居中按 全部/歌手/用户 切场景，
  歌手可直接进歌手主页、有乐迷团的显示「乐迷团 Lv.x」入口进乐迷团详情；
  `showContent` 无资源时原文显示在昵称下，带 `boxContent` 的渲染成气泡（笔记 / MV 可点击跳转）。
  笔记气泡不能用 `/event?id=`（服务端当匿名请求拒），改走 `/user/event?uid=<作者>&limit=5`：作者 uid 取自
  `consumeParam` 的 `f`，命中 id 优先、否则取第一条（气泡展示的是该作者最新动态）。
- 歌手主页新增收藏按钮，走 `/artist/sub`（t=1 收藏 / t=0 取消），已收藏显示「已关注」，不涉及互相关注。
- 用户等级、听歌时长、指定用户歌单与动态页面。
- “我的-音乐”三级分栏：创建歌单、收藏歌单、收藏专辑。
- 歌单详情分享/评论/收藏统计操作、歌单内搜索与评论半屏。
- 听歌识曲：麦克风识曲（3 次 × 5 秒）与本机文件识曲（`AudioViewPicker` 选音频文件）。
  指纹在隐藏的离线网页引擎里用官方 wasm 计算（`rawfile/audiofp/index.html` + `AudioFingerprintWeb`），
  文件由网页侧解码、混单声道、重采样到 8kHz 并挑最响的 3 秒，再查 `/audio/match`。

## 当前无法完整实现或需要额外系统能力

- AI 写歌：当前后端没有歌词生成、作曲、演唱合成与任务状态接口。
- 云贝中心、商城、票务、创作者中心：依赖网易云官方活动页、支付或创作者权限接口。
- 播客完整页、动态发布与私信：现有骨架没有对应数据模型和完整交互接口。
- 最近播放持久化：需要增加本地数据库，并定义历史记录清理策略。
- 系统媒体库中的“本地音乐”扫描：需要媒体库读取授权、格式扫描与去重。
- 后台播放、锁屏卡片、耳机按键：需要 AVSession 与后台任务配置。
- 下载到公共“音乐”目录：当前下载到应用沙箱，导出到公共目录需要用户授权和 FilePicker 流程。
- 登录态持久化：当前 Cookie 在本次应用生命周期内有效，正式版应使用 Preferences/KeyStore 加密保存。
- 内录识曲（采集其它应用正在播放的声音）：需要 API 26 的 `playbackCaptureMode` +
  `requestPlaybackCaptureStart()`；当前 SDK 6.1.1(24) 只有已废弃的 `playbackCaptureConfig`，实测拿不到可用音频。
  **功能暂时下线**，代码保留在 `SongRecognitionPage`（`PLAYBACK_CAPTURE_ENABLED = false`），
  等 2027 年初把版本下限抬到 API 26 后改回 `true` 即可接回（页面会自动多出「内录识曲」入口）。

## 平板 / 横屏（全屏）适配

统一断点在 `services/Responsive.ets`：compact(<600vp) / medium(600~900) / expanded(>=900)，
页面各自用 `onAreaChange` 取自身宽高，再按断点取列数或布局，不写死设备类型。

- 底部导航：`Tabs` 显式 `.height('100%')`。之前不设高度时 Tabs 会被内容撑高，
  平板横屏下 5 个 Tab 被顶到屏幕外，需要滑动页面才点得到。
- 侧边栏：宽度由 `84%` 改为 `min(360vp, 84%)`，大屏上保持手机版的窄栏，不再拉成半屏。
- MV 播放页：宽度 ≥840 且宽 > 高时左右分栏——画面缩到左侧约 74% 宽、垂直居中上下留白，
  标题/操作/清晰度落在右侧独立滚动；真全屏仍由右上角全屏按钮调用 `requestFullscreen`。
- 装扮中心：分类卡片 2/3/4 列自适应，列数增加时卡片加高，避免细长条。
- 动态页：发现瀑布流 2/3/4 列；关注流大屏两列（`List.lanes`）。
- 个人主页：歌单在平板/全屏下改为封面卡片 2/3 列，手机端保持原来的行列表。
- 推荐页新歌速递：大屏不再横向拉一条长列表，分类卡保持 200×120 原尺寸换行平铺，一行看全。
- 新歌速递列表页：大屏 `lanes(2)`，一屏展示更多歌曲。

## 播放器样式：图层可以压到黑胶上层

- `PlayerLayer` 新增 `above`（旧存档缺省 = false，观感不变）：
  false = 背景层，压在唱片和所有内容后面；true = 前景层，盖在旋转黑胶上面。
- 编辑器的舞台按这个字段拆两段渲染（黑胶之前 / 之后），选中的图层会多一个
  「叠在黑胶唱片上层」开关；图层列表里带「上层」小标。
- 播放页由 `PlayerBackdrop` 只画背景层，新增 `PlayerAboveLayers` 画前景层：
  它是全屏 `hitTestBehavior(None)` 覆盖层，位置与编辑器同坐标系，且仍在半模态之下。
- 顺手修正高度单位：图层的 `h` 和 `w` 一样是「按舞台宽度」的百分比，播放页之前当成
  「屏幕高度百分比」，导致实机比预览矮/扁；改用 `aspectRatio(w / h)` 换算，预览即所得。

## 听歌足迹：周期基准与刷新

- 周期基准回到「不带 endTime 的请求返回的 `endTime`」：offset=0 不传 endTime，
  往前翻一律从该基准递减（周 −7 天、月 −该月天数），不再用本地日期自己推算——
  自算会和接口的周/月切分错位（周起始日、月边界都可能差一天）。
- `endTime` 先按毫秒传（与接口返回同单位），无数据再退回秒；两次都拿不到就显示暂无。
- 新增周期校验：返回数据的 `startTime` 必须落在请求的那个周/月里（周给 1.5 天容差），
  否则视为「该周期暂无」，避免「标题是上周、内容是本周」。
- 日期网格优先用接口返回的 `startTime`（这份数据的权威周期）；接口没给时用与 endTime 同源的
  `listeningPeriodStart` 兜底，避免标题是 9 月、格子画成 11 月。
- 下面的整块内容用 `ForEach` + `周期:offset:dataRevision` 做 key 重建，
  避免有参 `@Builder` 复用旧值导致「标题变了、数据没变」。

## 联调说明

后端默认端口为 `3000`。电脑本机预览可尝试 `http://127.0.0.1:3000`，模拟器通常使用
`http://10.0.2.2:3000`，真机需填写电脑的局域网地址并确保防火墙允许访问。
