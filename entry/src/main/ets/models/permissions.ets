export interface PermissionExplanation {
  name: string
  description: string
  purpose: string
}

/** 与 entry/src/main/module.json5 中实际声明的权限保持一致。 */
export const APP_PERMISSION_EXPLANATIONS: PermissionExplanation[] = [
  {
    name: 'ohos.permission.INTERNET',
    description: '允许应用访问互联网。',
    purpose: '连接配置的音乐服务，获取歌曲、歌词、封面、搜索和账号数据，播放在线音频、下载音乐及上传播客声音。'
  },
  {
    name: 'ohos.permission.GET_NETWORK_INFO',
    description: '允许应用读取当前网络连接状态。',
    purpose: '在播放页判断网络是否可用，决定本地歌曲能否使用在线歌词和其他网络功能。'
  },
  {
    name: 'ohos.permission.KEEP_BACKGROUND_RUNNING',
    description: '允许应用在符合系统规则的场景下继续后台运行。',
    purpose: '开启后台播放后，在应用切到后台或锁屏时继续播放音频，并响应系统媒体播控操作。'
  },
  {
    name: 'ohos.permission.MICROPHONE',
    description: '允许应用使用麦克风采集声音。',
    purpose: '仅在用户启动麦克风听歌识曲时申请，用短时录音生成音频指纹并查询匹配歌曲；录音结束后停止采集。'
  },
  {
    name: 'ohos.permission.FILE_ACCESS_PERSIST',
    description: '允许应用持久化用户已授权的文件访问权限。',
    purpose: '保存通过系统文件选择器导入的本地音频读取授权，应用重启后仍可访问和播放这些文件。'
  }
]
