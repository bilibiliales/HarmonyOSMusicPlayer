import { LocalMusicPage } from './LocalMusic'
import { YunbeiPage } from './Yunbei'
import { songItemType, TabClass, playlistType } from '../models'
import { tabsData } from '../constants'
import Find from './Find'
import Mine from './Mine'
import Moment from './Moment'
import Recommend from './Recommend'
import { Play } from './Play'
import { CloudDrivePage } from './CloudDrive'
import { PlaylistDetail } from './PlaylistDetail'
import { RecentPlaybackPage, RecentPlaybackParam } from './RecentPlayback'
import { Login } from './Login'
import { SongWiki } from './SongWiki'
import { SearchPage } from './Search'
import { SettingsPage } from './Settings'
import { DeviceManagementPage } from './DeviceManagementPage'
import { FanClubListPage } from './FanClubListPage'
import { FanClubDetailPage } from './FanClubDetailPage'
import { FanClubDetailParam } from '../services/FanClubService'
import { RelationshipListPage, RelationshipPageParam } from './RelationshipList'
import { UserLevelPage } from './UserLevel'
import { ListeningStatsPage } from './ListeningStats'
import { UserProfilePage } from './UserProfile'
import { PrivateChatPage } from './PrivateChat'
import { MessageCenterPage } from './MessageCenter'
import { AiSongStudioPage } from './AiSongStudio'
import { ArtistPage } from './Artist'
import { EventDetailPage } from './EventDetail'
import { AlbumDetail } from './AlbumDetail'
import { NewSongListPage } from './NewSongList'
import { DailyRecommendPage } from './DailyRecommend'
import { MvPlayerPage } from './MvPlayer'
import { PublishEventPage, PublishEventPageParam } from './PublishEvent'
import { PlaylistEditorPage, PlaylistEditorPageParam } from './PlaylistEditor'
import { PlaylistSongManagerPage, PlaylistSongManagerPageParam } from './PlaylistSongManager'
import { ProfileEditorPage, ProfileEditorPageParam } from './ProfileEditor'
import { RankingPage } from './Ranking'
import { StylePage } from './Style'
import { StyleDetailPage } from './StyleDetail'
import { RadioPage } from './Radio'
import { RadioDetailPage, RadioProgramPage } from './RadioDetail'
import { DifmPage } from './Difm'
import { RadioPageParam } from '../models/radio'
import { DigitalAlbumPage } from './DigitalAlbum'
import { DigitalAlbumDetailPage } from './DigitalAlbumDetail'
import { SatiPage } from './Sati'
import { PlaylistCoverPreview, PlaylistCoverPreviewPageParam } from './PlaylistCoverPreview'
import {
  AlbumPageParam,
  ArtistPageParam,
  EventDetailPageParam,
  MvPlayerPageParam,
  PrivateChatPageParam,
  UserProfilePageParam
} from '../models/api'
import { NewSongPageParam } from '../models/home'
import { StyleDetailPageParam } from '../models/style'
import { DigitalAlbumDetailPageParam } from '../models/digitalAlbum'
import { FloatingMusicCard } from '../components/FloatingMusicCard'
import { Sidebar } from '../components/Sidebar'
import { AppBackdrop } from '../components/AppBackdrop'
import { StartupOverlay } from '../components/StartupOverlay'
import { DecoKeys } from '../services/DecorationRuntime'
import { DecorationCenterPage } from './DecorationCenter'
import { DecorationEditorPage, DecorationEditorParam } from './DecorationEditor'
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { playerController } from '../services/PlayerController'
import { AppSettings } from '../services/AppSettings'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { TC } from '../services/ThemeColors'

@Entry
@Component
struct HomeIndex {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack()
  @Provide('authStore') authStore: AuthStore = new AuthStore()
  @Provide('playerStore') playerStore: PlayerStore = new PlayerStore()
  @Provide('topAvoidHeight') topAvoidHeight: number = 0
  @State currentName: string = 'recommend'
  @State currentIndex: number = 0
  @State sidebarVisible: boolean = false
  @State sidebarMounted: boolean = false
  // 底部导航装扮
  @StorageProp(DecoKeys.DOCK_ICONS) dockIcons: string = ''
  @StorageProp(DecoKeys.DOCK_ICON_COLOR) dockIconColor: string = ''
  @StorageProp(DecoKeys.DOCK_ACTIVE_COLOR) dockActiveColor: string = ''
  @StorageProp(DecoKeys.DOCK_TEXT_COLOR) dockTextColor: string = ''
  @StorageProp(DecoKeys.DOCK_TEXT_SIZE) dockTextSize: number = 10
  @StorageProp(DecoKeys.DOCK_BG) dockBgColor: string = ''
  @StorageProp(DecoKeys.DOCK_INDICATOR) dockIndicator: string = ''
  @StorageProp(DecoKeys.DOCK_SHOW_TEXT) dockShowText: boolean = true

  private dockIcon(index: number): string {
    if (!this.dockIcons) { return '' }
    const parts = this.dockIcons.split('\n')
    return index < parts.length ? parts[index] : ''
  }

  private dockIconTint(active: boolean): ResourceColor {
    if (active) {
      return this.dockActiveColor.length > 0 ? this.dockActiveColor : TC.textOnAccent()
    }
    return this.dockIconColor.length > 0 ? this.dockIconColor : TC.textTertiary()
  }

  private dockTextTint(active: boolean): ResourceColor {
    if (active) {
      return this.dockTextColor.length > 0 ? this.dockTextColor : TC.textPrimary()
    }
    return this.dockIconColor.length > 0 ? this.dockIconColor : TC.textTertiary()
  }


  async aboutToAppear(): Promise<void> {
    await this.loadWindowAvoidArea()
    await AppSettings.loadPlayerState(this.playerStore)
    playerController.bind(this.playerStore, this.getUIContext())
    await AppSettings.loadAuth(this.authStore)
    if (this.authStore.loggedIn) {
      this.authStore.refreshAccount()
    }
  }

  private async loadWindowAvoidArea(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const mainWindow = await window.getLastWindow(context)
      const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      this.topAvoidHeight = px2vp(avoidArea.topRect.height)
    } catch (error) {
      console.error(`[HomeIndex] Failed to obtain the top avoid area: ${JSON.stringify(error)}`)
      this.topAvoidHeight = 0
    }
  }

  private openSidebar(): void {
    this.sidebarMounted = true
    setTimeout(() => {
      this.sidebarVisible = true
    }, 16)
  }

  private closeSidebar(): void {
    this.sidebarVisible = false
    setTimeout(() => {
      if (!this.sidebarVisible) {
        this.sidebarMounted = false
      }
    }, 300)
  }

  private openMineFromSidebar(): void {
    const mineIndex = tabsData.findIndex((item: TabClass) => item.name === 'mine')
    if (mineIndex >= 0) {
      this.currentIndex = mineIndex
      this.currentName = 'mine'
    }
    this.closeSidebar()
  }

  @Builder
  PageMap(name: string, param: object) {
    if (name === 'PlayPage') {
      Play()
    } else if (name === 'LocalMusicPage') {
      LocalMusicPage()
    } else if (name === 'YunbeiPage') {
      YunbeiPage()
    } else if (name === 'CloudDrivePage') {
      CloudDrivePage()
    } else if (name === 'RecentPlaybackPage') {
      RecentPlaybackPage({ pageParam: (param || {}) as RecentPlaybackParam })
    } else if (name === 'PlaylistDetailPage') {
      PlaylistDetail({ initialPlaylist: param as playlistType })
    } else if (name === 'LoginPage') {
      Login()
    } else if (name === 'SongWikiPage') {
      SongWiki({ song: param as songItemType })
    } else if (name === 'SearchPage') {
      SearchPage()
    } else if (name === 'SettingsPage') {
      SettingsPage()
    } else if (name === 'DeviceManagementPage') {
      DeviceManagementPage()
    } else if (name === 'FanClubListPage') {
      FanClubListPage()
    } else if (name === 'FanClubDetailPage') {
      FanClubDetailPage({ pageParam: param as FanClubDetailParam })
    } else if (name === 'FollowingPage' || name === 'FollowersPage') {
      RelationshipListPage({ pageParam: param as RelationshipPageParam })
    } else if (name === 'UserLevelPage') {
      UserLevelPage()
    } else if (name === 'ListeningStatsPage') {
      ListeningStatsPage()
    } else if (name === 'UserProfilePage') {
      UserProfilePage({ pageParam: param as UserProfilePageParam })
    } else if (name === 'PrivateChatPage') {
      PrivateChatPage({ pageParam: param as PrivateChatPageParam })
    } else if (name === 'MessageCenterPage') {
      MessageCenterPage()
    } else if (name === 'AiSongStudioPage') {
      AiSongStudioPage()
    } else if (name === 'ArtistPage') {
      ArtistPage({ pageParam: param as ArtistPageParam })
    } else if (name === 'EventDetailPage') {
      EventDetailPage({ pageParam: param as EventDetailPageParam })
    } else if (name === 'AlbumDetailPage') {
      AlbumDetail({ pageParam: param as AlbumPageParam })
    } else if (name === 'NewSongListPage') {
      NewSongListPage({ pageParam: param as NewSongPageParam })
    } else if (name === 'DailyRecommendPage') {
      DailyRecommendPage()
    } else if (name === 'MvPlayerPage') {
      MvPlayerPage({ pageParam: param as MvPlayerPageParam })
    } else if (name === 'PublishEventPage') {
      PublishEventPage({ pageParam: param as PublishEventPageParam })
    } else if (name === 'PlaylistEditorPage') {
      PlaylistEditorPage({ pageParam: param as PlaylistEditorPageParam })
    } else if (name === 'PlaylistSongManagerPage') {
      PlaylistSongManagerPage({ pageParam: param as PlaylistSongManagerPageParam })
    } else if (name === 'ProfileEditorPage') {
      ProfileEditorPage({ pageParam: param as ProfileEditorPageParam })
    } else if (name === 'RankingPage') {
      RankingPage()
    } else if (name === 'StylePage') {
      StylePage()
    } else if (name === 'StyleDetailPage') {
      StyleDetailPage({ pageParam: param as StyleDetailPageParam })
    } else if (name === 'RadioDetailPage') {
      RadioDetailPage({ pageParam: param as RadioPageParam })
    } else if (name === 'RadioProgramPage') {
      RadioProgramPage({ pageParam: param as RadioPageParam })
    } else if (name === 'DifmPage') {
      DifmPage()
    } else if (name === 'RadioPage') {
      RadioPage()
    } else if (name === 'DigitalAlbumPage') {
      DigitalAlbumPage()
    } else if (name === 'DigitalAlbumDetailPage') {
      DigitalAlbumDetailPage({ pageParam: param as DigitalAlbumDetailPageParam })
    } else if (name === 'SatiPage') {
      SatiPage()
    } else if (name === 'PlaylistCoverPreviewPage') {
      PlaylistCoverPreview({ pageParam: param as PlaylistCoverPreviewPageParam })
    } else if (name === 'DecorationCenterPage') {
      DecorationCenterPage()
    } else if (name === 'DecorationEditorPage') {
      DecorationEditorPage({ pageParam: param as DecorationEditorParam })
    }
  }

  @Builder
  getTabBar(item: TabClass, index: number) {
    Column({ space: 4 }) {
      Stack() {
        if (item.name === this.currentName) {
          Column()
            .width(30)
            .height(30)
            .backgroundColor(this.dockIndicator ? this.dockIndicator : TC.accent())
            .borderRadius(15)
            .shadow({ radius: 10, color: 'rgba(239,35,60,0.28)', offsetY: 4 })
        }
        if (this.dockIcon(index)) {
          Image(this.dockIcon(index))
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
        } else {
          Image(item.icon)
            .width(21)
            .height(21)
            .fillColor(this.dockIconTint(item.name === this.currentName))
        }
      }
      .width(36)
      .height(30)
      .alignContent(Alignment.Center)

      if (this.dockShowText) {
        Text(item.title)
          .fontSize(this.dockTextSize)
          .fontColor(this.dockTextTint(item.name === this.currentName))
          .fontWeight(item.name === this.currentName ? FontWeight.Medium : FontWeight.Regular)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({ top: 6, bottom: 5 })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }

  build() {
    Navigation(this.pageStack) {
      Stack() {
        AppBackdrop()

        Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
          ForEach(tabsData, (item: TabClass, index: number) => {
            TabContent() {
              if (item.name === 'recommend') {
                Recommend({ onMenuClick: () => this.openSidebar() })
              } else if (item.name === 'find') {
                Find()
              } else if (item.name === 'moment') {
                Moment()
              } else if (item.name === 'mine') {
                Mine()
              }
            }
            .tabBar(this.getTabBar(item, index))
            .padding({ top: item.name === 'mine' ? 0 : this.topAvoidHeight })
            .backgroundColor(TC.pageBackground())
          })
        }
        .barHeight(60)
        .barMode(BarMode.Fixed)
        .barBackgroundColor(this.dockBgColor ? this.dockBgColor : TC.navBackground())
        .onChange((index: number) => {
          this.currentIndex = index
          this.currentName = tabsData[index].name
        })

        FloatingMusicCard({
          onOpen: () => this.pageStack.pushPathByName('PlayPage', null)
        })
          .position({ left: '4.26%', bottom: 70 })

        if (this.sidebarMounted) {
          Sidebar({
            visible: this.sidebarVisible,
            topAvoidHeight: this.topAvoidHeight,
            onClose: () => this.closeSidebar(),
            onOpenMine: () => this.openMineFromSidebar()
          })
        }

        StartupOverlay()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(Color.Transparent)
    .navDestination(this.PageMap)
  }
}
