import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppSettings } from '../services/AppSettings';
import { ThemeService } from '../services/ThemeService';
import { SkinService } from '../services/SkinService';
import { DecorationStore } from '../services/DecorationStore';
import { playerController } from '../services/PlayerController';
import { PlaybackControlBridge } from '../services/PlaybackControlBridge';
import { ShortcutBridge } from '../services/ShortcutBridge';
import { MusicCardActionBridge } from '../services/MusicCardActionBridge';
import { MusicCardCommand, MusicCardProtocol, MusicCardReply } from '../services/MusicCardProtocol';
import { commonEventManager } from '@kit.BasicServicesKit';
import { PlayerStore } from '../stores/PlayerStore';
import { AuthStore } from '../stores/AuthStore';
import { NearbyShareSession, SystemShareService } from '../services/SystemShareService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;
  private cardSubscriber?: commonEventManager.CommonEventSubscriber;
  private cardRuntime?: Promise<void>;

  private async prepareCardRuntime(): Promise<void> {
    if (MusicCardActionBridge.ready()) { return; }
    await AppSettings.load(this.context);
    const auth = new AuthStore();
    await AppSettings.loadAuth(auth);
    const store = new PlayerStore();
    await AppSettings.loadPlayerState(store);
    if (!MusicCardActionBridge.ready()) {
      playerController.bind(store);
      MusicCardActionBridge.bind(store, auth);
    }
  }

  private async executeCardCommand(command: MusicCardCommand): Promise<void> {
    if (!MusicCardActionBridge.ready()) {
      if (!this.cardRuntime) { this.cardRuntime = this.prepareCardRuntime(); }
      try { await this.cardRuntime; } catch (error) {
        this.cardRuntime = undefined;
        throw new Error(error instanceof Error ? error.message : '卡片播放器初始化失败');
      }
    }
    await MusicCardActionBridge.execute(command.musicCardAction, command.musicCardSongId, command.requestId);
  }

  private registerCardControls(): void {
    this.callee.on(MusicCardProtocol.METHOD, (data) => {
      const command = MusicCardProtocol.parse(data.readString());
      if (command) { this.executeCardCommand(command).catch((error: Error) => hilog.warn(DOMAIN, 'card', '%{public}s', error.message)); }
      return new MusicCardReply();
    });
    commonEventManager.createSubscriber({ events: [MusicCardProtocol.EVENT], publisherBundleName: MusicCardProtocol.BUNDLE_NAME })
      .then((subscriber: commonEventManager.CommonEventSubscriber) => {
        this.cardSubscriber = subscriber;
        commonEventManager.subscribe(subscriber, (error, event) => {
          if (error?.code) { return; }
          const command = MusicCardProtocol.parse(event.data || '');
          if (command) { this.executeCardCommand(command).catch((failure: Error) => hilog.warn(DOMAIN, 'card', '%{public}s', failure.message)); }
        });
      }).catch((error: Error) => hilog.warn(DOMAIN, 'card', '%{public}s', error.message));
  }

  /** 沉浸式布局下，状态栏/导航条图标颜色跟随当前有效主题（深底白图标、浅底深图标）。 */
  private updateSystemBar(isDark: boolean): void {
    if (!this.mainWindow) { return; }
    const contentColor: string = isDark ? '#FFFFFF' : '#111114';
    const props: window.SystemBarProperties = {
      statusBarContentColor: contentColor,
      navigationBarContentColor: contentColor
    };
    this.mainWindow.setWindowSystemBarProperties(props)
      .catch((err: Error) => hilog.warn(DOMAIN, 'systemBar', 'set bar properties failed: %{public}s', err.message));
  }

  private handlePlaybackWant(want: Want): void {
    const action = want.parameters?.playbackAction;
    if (want.action === PlaybackControlBridge.CONTROL_ACTION && action === 'play') {
      PlaybackControlBridge.dispatch('play');
    } else if (want.action === PlaybackControlBridge.CONTROL_ACTION && action === 'pause') {
      PlaybackControlBridge.dispatch('pause');
    } else if (want.action === PlaybackControlBridge.CONTROL_ACTION && action === 'favorite') {
      PlaybackControlBridge.dispatch('favorite');
    } else if (want.action === PlaybackControlBridge.CONTROL_ACTION && action === 'desktopLyrics') {
      PlaybackControlBridge.dispatch('desktopLyrics');
    } else if (want.action === PlaybackControlBridge.CONTROL_ACTION && action === 'mode') {
      PlaybackControlBridge.dispatch('mode');
    }
  }

  /** 桌面图标长按快捷方式：把动作写进 AppStorage，等首页绑定播放控制器后再执行。 */
  private handleShortcutWant(want: Want): void {
    const raw = want.parameters?.[ShortcutBridge.ACTION_KEY];
    if (typeof raw !== 'string') { return; }
    ShortcutBridge.publish(raw);
  }

  private handleMusicCardWant(want: Want): void {
    const action = want.parameters?.musicCardAction;
    const songId = want.parameters?.musicCardSongId;
    if (typeof action === 'string') {
      MusicCardActionBridge.publish(action, typeof songId === 'string' ? songId : '');
    }
  }

  /** 应用被系统的「打开方式 / FileOpen」拉起时，把音频 URI 交给界面层播放。 */
  private handleOpenAudioWant(want: Want): void {
    // 文件管理器既可能只给 action，也可能只给 linkFeature 或 UTD type，
    // 三种都要认，否则注册成功也收不到文件。
    const params = want.parameters;
    const feature = params ? params['linkFeature'] : undefined;
    const isFileOpen = want.action === 'ohos.want.action.viewData' ||
      (typeof feature === 'string' && feature === 'FileOpen') ||
      (typeof want.type === 'string' && want.type.indexOf('audio') >= 0);
    if (!isFileOpen) { return; }
    let uri: string = want.uri || '';
    if (!uri && params) {
      const alt = params['uri'];
      if (typeof alt === 'string') { uri = alt; }
    }
    if (!uri || uri.length === 0) { return; }
    AppStorage.setOrCreate<string>('openAudioUri', uri);
    const seq = AppStorage.get<number>('openAudioSeq') ?? 0;
    AppStorage.setOrCreate<number>('openAudioSeq', seq + 1);
    hilog.info(DOMAIN, 'testTag', 'Open audio request: %{public}s', uri);
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 读取持久化的深浅色偏好与皮肤覆盖，并在首帧前生效，避免启动闪屏
    ThemeService.init(this.context);
    SkinService.init(this.context);
    // 读取装扮（皮肤颜色会覆盖到 SkinService，其余发布到 AppStorage），首帧即生效
    DecorationStore.init(this.context);
    AppSettings.context = this.context;
    SystemShareService.bindAbility(this.context);
    this.registerCardControls();
    this.handlePlaybackWant(want);
    this.handleOpenAudioWant(want);
    this.handleShortcutWant(want);
    this.handleMusicCardWant(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    MusicCardActionBridge.unbind();
    this.callee.off(MusicCardProtocol.METHOD);
    if (this.cardSubscriber) { commonEventManager.unsubscribe(this.cardSubscriber, () => {}); }
    SystemShareService.unbindAbility();
    playerController.release().catch((error: Error) => console.error(error.message));
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    try {
      await AppSettings.load(this.context);
    } catch (err) {
      hilog.warn(DOMAIN, 'settings', 'Failed to load settings. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', async (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      
      try {
        const mainWindow: window.Window = windowStage.getMainWindowSync();  // 获取应用主窗口
        this.mainWindow = mainWindow;
        await mainWindow.setWindowLayoutFullScreen(true); // 进入窗口沉浸式布局（非自由窗口状态）
        mainWindow.setWindowDecorVisible(false);  // 隐藏窗口标题栏，进入沉浸式布局（自由窗口状态）
        this.updateSystemBar(ThemeService.isDark());      // 首帧同步一次
        ThemeService.addModeListener((isDark: boolean) => this.updateSystemBar(isDark));
      } catch (e) {
        console.error(`Failed to set status bar to invisible`);
      }
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handlePlaybackWant(want);
    this.handleOpenAudioWant(want);
    this.handleShortcutWant(want);
    this.handleMusicCardWant(want);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统深浅色变化：仅在「跟随系统」时同步 UI，手动模式下忽略
    ThemeService.onSystemColorModeChange(newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    NearbyShareSession.setForeground(true);
    playerController.onAppForeground();
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    NearbyShareSession.setForeground(false);
    playerController.onAppBackground();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
