import { WantAgent, wantAgent } from '@kit.AbilityKit'

export type PlaybackAction = 'play' | 'pause'

export class PlaybackControlBridge {
  private static readonly BUNDLE_NAME: string = 'com.harmonyos.cloudmusic'
  static readonly CONTROL_ACTION: string = 'com.harmonyos.cloudmusic.event.PLAYBACK_CONTROL'
  private static handler?: (action: PlaybackAction) => void
  private static playAgent?: WantAgent
  private static pauseAgent?: WantAgent
  private static pendingAction?: PlaybackAction

  static subscribe(handler: (action: PlaybackAction) => void): Promise<void> {
    PlaybackControlBridge.handler = handler
    if (PlaybackControlBridge.pendingAction) {
      const action = PlaybackControlBridge.pendingAction
      PlaybackControlBridge.pendingAction = undefined
      handler(action)
    }
    return Promise.resolve()
  }

  static dispatch(action: PlaybackAction): void {
    if (PlaybackControlBridge.handler) {
      PlaybackControlBridge.handler(action)
    } else {
      PlaybackControlBridge.pendingAction = action
    }
  }

  static async getPlaybackWantAgent(action: PlaybackAction): Promise<WantAgent> {
    if (action === 'play' && PlaybackControlBridge.playAgent) {
      return PlaybackControlBridge.playAgent
    }
    if (action === 'pause' && PlaybackControlBridge.pauseAgent) {
      return PlaybackControlBridge.pauseAgent
    }
    const agent = await wantAgent.getWantAgent({
      wants: [{
        bundleName: PlaybackControlBridge.BUNDLE_NAME,
        abilityName: 'EntryAbility',
        action: PlaybackControlBridge.CONTROL_ACTION,
        parameters: {
          playbackAction: action
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: action === 'play' ? 10002 : 10003,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    })
    if (action === 'play') {
      PlaybackControlBridge.playAgent = agent
    } else {
      PlaybackControlBridge.pauseAgent = agent
    }
    return agent
  }
}
