# 播客与声音接口

参考[全量文档](https://ncme.scfd.top/docs/)和 [API Enhanced 源码](https://github.com/neteasecloudmusicapienhanced/api-enhanced)。接口始终使用应用设置的服务地址。

播客是可以订阅的声音集合；声音是其中的单集。公开收听与创作者管理使用不同接口，声音 ID 与音频主轨 ID 也应分别保存。

| 场景 | 接口 | 页面行为 |
| --- | --- | --- |
| 最近收听播客 | `/record/recent/dj` | 按最近收听顺序显示播客，点击进入播客详情；`limit=100`，不使用 offset |
| 订阅列表 | `/dj/sublist` | 分页读取，点击收听或取消订阅 |
| 订阅与取消订阅 | `/dj/sub` | `rid` 是播客 ID，`t=1/0`；成功后刷新播客库 |
| 我的播客 | `/voicelist/my/created` | 只用自己创建的播客作为发布目标；返回列表在 `data.data` |
| 播客管理信息 | `/voicelist/detail` | 获取封面、分类等发布所需信息 |
| 我的声音 | `/voicelist/list/search` | 按声音名称和发布状态筛选，支持分页 |
| 声音管理详情 | `/voice/detail` | 展示介绍、发布状态 |
| 声音排序 | `/voicelist/trans` | `programId=voiceId`、`radioId=voiceListId`，可移到播客第一位 |
| 发布声音 | `/voice/upload` | `songFile` 上传音频，`imgFile` 可选封面；支持私密、定时和同步动态 |
| 公开播客与声音详情 | `/dj/detail`、`/dj/program`、`/dj/program/detail` | 展示节目、播放单集；播放仍由主轨音频 ID 解析地址 |

`/voicelist/search` 是播客搜索接口，不能作为“自己的播客”或上传目标。文档中声音搜索的播客参数写作 `radioId`，当前 `voicelist_list_search.js` 模块实际读取 `voiceListId`，再映射为上游 `radioId`；应用按模块参数发送。

发布状态包括 `ONLINE`（已发布）、`AUDITING`（审核中）、`ONLY_SELF_SEE`（仅自己可见）、`SCHEDULE_PUBLISH`（定时发布）、`PUBLISHING`（发布中）、`TRANSCODE_FAILED`（转码失败）和 `FAILED`（发布失败）。上传成功表示文件和发布请求已经提交，不能直接当作审核通过。

当前文档和模块清单均没有独立的创建播客接口。应用中的创建入口打开网易云创作者中心；用户创建后返回刷新，便可在应用内发布和管理声音。不会用上传声音冒充创建播客。

接口逻辑可用 `node tools/check_podcast_contract.cjs <SDK 中 typescript.js 的路径>` 验证。测试只使用本地模拟响应，不访问账号、不发布真实内容。系统动画、审核进度和登录后的实际返回需在设备上复验。
