import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppSettings } from '../services/AppSettings';
import { ThemeService } from '../services/ThemeService';
import { SkinService } from '../services/SkinService';
import { playerController } from '../services/PlayerController';
import { PlaybackControlBridge } from '../services/PlaybackControlBridge';
import { NearbyShareSession, SystemShareService } from '../services/SystemShareService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;

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
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 读取持久化的深浅色偏好与皮肤覆盖，并在首帧前生效，避免启动闪屏
    ThemeService.init(this.context);
    SkinService.init(this.context);
    AppSettings.context = this.context;
    SystemShareService.bindAbility(this.context);
    this.handlePlaybackWant(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
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
