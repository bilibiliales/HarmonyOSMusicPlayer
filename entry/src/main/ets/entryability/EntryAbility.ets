import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppSettings } from '../services/AppSettings';
import { playerController } from '../services/PlayerController';
import { PlaybackControlBridge } from '../services/PlaybackControlBridge';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private handlePlaybackWant(want: Want): void {
    const action = want.parameters?.playbackAction;
    if (want.action === PlaybackControlBridge.CONTROL_ACTION && action === 'play') {
      PlaybackControlBridge.dispatch('play');
    } else if (want.action === PlaybackControlBridge.CONTROL_ACTION && action === 'pause') {
      PlaybackControlBridge.dispatch('pause');
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    AppSettings.context = this.context;
    this.handlePlaybackWant(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
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
        await mainWindow.setWindowLayoutFullScreen(true); // 进入窗口沉浸式布局（非自由窗口状态）
        mainWindow.setWindowDecorVisible(false);  // 隐藏窗口标题栏，进入沉浸式布局（自由窗口状态）
      } catch (e) {
        console.error(`Failed to set status bar to invisible`);
      }
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handlePlaybackWant(want);
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    playerController.onAppBackground();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
