import { songItemType, TabClass, playlistType } from '../models'
import { tabsData } from '../constants'
import Find from './Find'
import Mine from './Mine'
import Moment from './Moment'
import Recommend from './Recommend'
import { Play } from './Play'
import { PlaylistDetail } from './PlaylistDetail'
import { Login } from './Login'
import { SongWiki } from './SongWiki'
import { SearchPage } from './Search'
import { SettingsPage } from './SettingsV2'
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
import { AuthStore } from '../stores/AuthStore'
import { PlayerStore } from '../stores/PlayerStore'
import { playerController } from '../services/PlayerController'
import { AppSettings } from '../services/AppSettings'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'

@Entry
@Component
struct HomeIndex {
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack()
  @Provide('authStore') authStore: AuthStore = new AuthStore()
  @Provide('playerStore') playerStore: PlayerStore = new PlayerStore()
  @Provide('topAvoidHeight') topAvoidHeight: number = 0
  @State currentName: string = 'recommend'
  @State currentIndex: number = 0
  @State sidebarVisible: boolean = false
  @State sidebarMounted: boolean = false

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
    }
  }

  @Builder
  getTabBar(item: TabClass) {
    Column({ space: 4 }) {
      Stack() {
        if (item.name === this.currentName) {
          Column()
            .width(30)
            .height(30)
            .backgroundColor('#ef233c')
            .borderRadius(15)
            .shadow({ radius: 10, color: 'rgba(239,35,60,0.28)', offsetY: 4 })
        }
        Image(item.icon)
          .width(21)
          .height(21)
          .fillColor(item.name === this.currentName ? Color.White : '#77777f')
      }
      .width(36)
      .height(30)
      .alignContent(Alignment.Center)

      Text(item.title)
        .fontSize(10)
        .fontColor(item.name === this.currentName ? '#ffffff' : '#77777f')
        .fontWeight(item.name === this.currentName ? FontWeight.Medium : FontWeight.Regular)
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
        Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
          ForEach(tabsData, (item: TabClass) => {
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
            .tabBar(this.getTabBar(item))
            .backgroundColor('#121215')
          })
        }
        .barHeight(60)
        .padding({ top: this.topAvoidHeight })
        .barMode(BarMode.Fixed)
        .barBackgroundColor('#17171c')
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#121215')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.PageMap)
  }
}
