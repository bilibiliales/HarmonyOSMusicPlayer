# 主题 / 皮肤取色架构审计（TC 版）

## 架构：三层解析，装扮优先

```
页面/组件  ──只许调用──▶  TC.xxx()（services/ThemeColors.ets）
                            │
                 ① SkinService.colorOverride(token)   ← 装扮皮肤固定色（最高优先）
                 ② $r('app.color.*')                  ← base/dark 资源（跟随深浅色）
```

- 皮肤为某 token 指定固定色后，深色/浅色切换都不再影响它；未指定的 token 正常跟随主题。
- 皮肤变化时 SkinService 递增 AppStorage `skinVersion`，声明了 `@StorageProp('skinVersion')` 的组件原地刷新（61 个组件已全部注入）。
- 新页面约定：取色只用 TC.xxx()；压图文字用 TC.textOnMedia*()；不直接写 $r('app.color.*') / hex。

## 深度清扫（第二轮）

- TC 调用总数：**2048** 处；剩余 hex 字面量 146 处，全部为刻意保留：
  - Play / MvPlayer 媒体画布色、Sidebar 暗红渐变体（两类页面恒定深色，由装扮中心接管）
  - VIP 金卡（#f0d3ac 等）、语义消息色（绿 #65c98c / 橙 #ff9a78 / 链接蓝 #97b9e5）
  - #000000 媒体底、LyricSettingsSheet 用户自选色板、LevelTaskRing string 型 @Prop
  - SongList / playerNav 演示页、ListeningStats 热力图渐变、登录二维码
- 新增 token `accent_container`（深 #2B2024 / 浅 #FCEBEC）：修复浅色下深红文字压深棕底的对比度 BUG
- 全部 bindSheet 底板（#19191f/#151519）→ TC.sheetBackground()，浅色下不再黑底

## 数据

- 文件：58（pages + components）
- TC 取色调用：**1734** 处
- 残留硬编码属性色：66 处（SongList 演示页、VIP 品牌金卡、封面遮罩等刻意保留）
- 渐变层：33 处（头图蒙版已主题化；封面遮罩保留）
- 图片上常白文字：38 处

| 文件 | TC 调用 | 残留硬编码 | 渐变 | 压图文字 |
| --- | ---: | ---: | ---: | ---: |
| Mine.ets | 109 | 4 | 1 | 0 |
| Play.ets | 90 | 0 | 1 | 23 |
| Settings.ets | 69 | 0 | 0 | 0 |
| ListeningStats.ets | 67 | 0 | 3 | 0 |
| StyleDetail.ets | 66 | 2 | 2 | 0 |
| AiSongStudio.ets | 64 | 1 | 0 | 0 |
| SongWiki.ets | 60 | 3 | 1 | 0 |
| PlaylistDetail.ets | 53 | 1 | 1 | 0 |
| Search.ets | 48 | 0 | 0 | 0 |
| Recommend.ets | 45 | 2 | 7 | 0 |
| Artist.ets | 42 | 0 | 2 | 0 |
| UserProfile.ets | 42 | 2 | 2 | 0 |
| PublishEvent.ets | 40 | 0 | 0 | 0 |
| ProfileEditor.ets | 38 | 0 | 0 | 0 |
| Ranking.ets | 38 | 0 | 2 | 0 |
| Sati.ets | 37 | 0 | 1 | 0 |
| CloudDrive.ets | 36 | 0 | 0 | 0 |
| EventDetail.ets | 35 | 0 | 0 | 0 |
| LocalMusic.ets | 34 | 4 | 0 | 0 |
| PrivateChat.ets | 34 | 1 | 0 | 0 |
| AlbumDetail.ets | 32 | 0 | 1 | 0 |
| DigitalAlbum.ets | 32 | 0 | 0 | 0 |
| Style.ets | 32 | 0 | 2 | 0 |
| RadioDetail.ets | 30 | 2 | 0 | 0 |
| MessageCenter.ets | 29 | 0 | 0 | 0 |
| DigitalAlbumDetail.ets | 28 | 0 | 0 | 0 |
| Login.ets | 26 | 4 | 0 | 0 |
| MvPlayer.ets | 26 | 1 | 0 | 0 |
| ResourceComments.ets | 26 | 1 | 0 | 0 |
| Sidebar.ets | 26 | 12 | 1 | 5 |
| Find.ets | 24 | 0 | 1 | 0 |
| PlaylistEditor.ets | 24 | 0 | 0 | 0 |
| DeviceManagementPage.ets | 22 | 0 | 0 | 0 |
| Difm.ets | 22 | 0 | 0 | 0 |
| PlaylistCoverPreview.ets | 22 | 0 | 1 | 0 |
| PlaylistSongManager.ets | 22 | 0 | 0 | 0 |
| UserLevel.ets | 22 | 0 | 0 | 0 |
| Radio.ets | 21 | 0 | 0 | 0 |
| RelationshipList.ets | 21 | 0 | 0 | 0 |
| DailyRecommend.ets | 20 | 0 | 2 | 0 |
| Moment.ets | 19 | 0 | 0 | 0 |
| EventCard.ets | 19 | 0 | 0 | 0 |
| FanClubDetailPage.ets | 18 | 0 | 0 | 0 |
| NewSongList.ets | 17 | 0 | 2 | 0 |
| Yunbei.ets | 17 | 5 | 0 | 0 |
| ShareSheet.ets | 16 | 0 | 0 | 0 |
| FanClubListPage.ets | 14 | 0 | 0 | 0 |
| RecentPlayback.ets | 13 | 0 | 0 | 0 |
| FloatingMusicCard.ets | 13 | 0 | 0 | 7 |
| Index.ets | 7 | 0 | 0 | 0 |
| RadioCards.ets | 7 | 3 | 0 | 0 |
| LyricSettingsSheet.ets | 6 | 0 | 0 | 0 |
| ListeningPlaylistCard.ets | 5 | 0 | 0 | 0 |
| LevelTaskRing.ets | 3 | 0 | 0 | 0 |
| EventImages.ets | 2 | 1 | 0 | 2 |
| playerNav.ets | 2 | 4 | 0 | 0 |
| SongList.ets | 1 | 13 | 0 | 0 |
| VinylRecord.ets | 1 | 0 | 0 | 1 |