import { MusicComment, playlistType, SongArtist, songItemType } from './music'

export interface ApiParam {
  key: string
  value: string
}

export interface ApiArtist {
  name: string
  id?: number
  picUrl?: string
  img1v1Url?: string
  cover?: string
  avatar?: string
  alias?: string[]
  identities?: string[]
  albumSize?: number
  musicSize?: number
  mvSize?: number
  fansSize?: number
  fansCount?: number
  briefDesc?: string
  followed?: boolean
}

export interface ApiAlbum {
  name: string
  picUrl: string
  id?: number
  size?: number
  artists?: ApiArtist[]
  artist?: ApiArtist
  publishTime?: number
  company?: string
  type?: string
}

export interface ArtistPageParam {
  id: string
  name?: string
  picUrl?: string
}

export interface ArtistTopSongsResponse {
  code: number
  songs?: ApiSong[]
  more?: boolean
}

export interface ArtistAlbumResponse {
  code: number
  artist?: ApiArtist
  hotAlbums?: ApiAlbum[]
  more?: boolean
}

export interface ArtistMvItem {
  id: number
  name: string
  status?: number
  imgurl?: string
  imgurl16v9?: string
  artistName?: string
  duration?: number
  playCount?: number
  publishTime?: string
  subed?: boolean
}

export interface ArtistMvResponse {
  code: number
  mvs?: ArtistMvItem[]
  hasMore?: boolean
}

export interface MvPlayerPageParam {
  id: string
  name: string
  cover?: string
  artistName?: string
  duration?: number
  playCount?: number
  publishTime?: string
}

export interface MvUrlData {
  id?: number
  url?: string
  r?: number
  size?: number
  md5?: string
  code?: number
  expi?: number
}

export interface MvUrlResponse {
  code: number
  data?: MvUrlData
  message?: string
}

export interface MvDetailInfoData {
  likedCount?: number
  shareCount?: number
  commentCount?: number
  liked?: boolean
}

export interface MvDetailInfoResponse {
  code: number
  likedCount?: number
  shareCount?: number
  commentCount?: number
  liked?: boolean
  data?: MvDetailInfoData
}

export interface MvDetailArtist {
  id?: number
  name?: string
  img1v1Url?: string
  followed?: boolean
}

export interface MvDetailData {
  id?: number
  name?: string
  artistId?: number
  artistName?: string
  briefDesc?: string
  desc?: string
  cover?: string
  playCount?: number
  subCount?: number
  shareCount?: number
  commentCount?: number
  duration?: number
  publishTime?: string
  artists?: MvDetailArtist[]
  commentThreadId?: string
}

export interface MvDetailResponse {
  code: number
  subed?: boolean
  data?: MvDetailData
  message?: string
}

export interface ArtistIdentifyInfo {
  imageUrl?: string
  imageDesc?: string
  actionUrl?: string
}

export interface ArtistRankInfo {
  rank?: number
  type?: number
}

export interface ArtistDetailArtist extends ApiArtist {
  transNames?: string[]
  identifyTag?: string
  rank?: ArtistRankInfo
}

export interface ArtistExpertIdentity {
  expertIdentiyId?: number
  expertIdentiyName: string
  expertIdentiyCount?: number
}

export interface ArtistDetailData {
  videoCount?: number
  identify?: ArtistIdentifyInfo
  artist?: ArtistDetailArtist
  secondaryExpertIdentiy?: ArtistExpertIdentity[]
}

export interface ArtistDetailResponse {
  code: number
  message?: string
  data?: ArtistDetailData
}

export interface SimilarArtistResponse {
  code: number
  artists?: ApiArtist[]
}

export interface ApiSong {
  id: number
  name: string
  picUrl?: string
  duration?: number
  dt?: number
  fee?: number
  artists?: ApiArtist[]
  ar?: ApiArtist[]
  album?: ApiAlbum
  al?: ApiAlbum
  lyrics?: SearchLyricInfo
  reason?: string
  recommendReason?: string
}

export interface PersonalizedSongItem {
  id: number
  name: string
  picUrl: string
  song: ApiSong
}

export interface PersonalizedNewSongResponse {
  code: number
  result: PersonalizedSongItem[]
}

export interface SearchResultData {
  songs?: ApiSong[]
  songCount?: number
  albums?: ApiAlbum[]
  albumCount?: number
  artists?: ApiArtist[]
  artistCount?: number
  playlists?: ApiPlaylist[]
  playlistCount?: number
  userprofiles?: ApiUser[]
  userprofileCount?: number
  mvs?: SearchMvItem[]
  mvCount?: number
  djRadios?: DjRadioItem[]
  djRadiosCount?: number
  videos?: SearchVideoItem[]
  videoCount?: number
  resources?: SearchVoiceItem[]
  voices?: SearchVoiceItem[]
  song?: SearchCompositeSong
  album?: SearchCompositeAlbum
  artist?: SearchCompositeArtist
  playList?: SearchCompositePlaylist
  user?: SearchCompositeUser
  new_mlog?: SearchCompositeVideo
  voice?: SearchCompositeVoice
}

export interface SearchLyricInfo {
  txt?: string
}

export interface SearchMvItem {
  id: number
  name: string
  cover: string
  artistName?: string
  playCount?: number
  duration?: number
}

export interface SearchVideoCreator {
  userId?: number
  userName?: string
}

export interface SearchVideoItem {
  vid?: string
  title: string
  coverUrl: string
  durationms?: number
  playTime?: number
  creator?: SearchVideoCreator[]
}

export interface SearchVoiceItem {
  id?: number
  name?: string
  title?: string
  coverUrl?: string
  picUrl?: string
  description?: string
  creator?: ApiUser
}

export interface SearchCompositeSong {
  songs?: ApiSong[]
}

export interface SearchCompositeAlbum {
  albums?: ApiAlbum[]
}

export interface SearchCompositeArtist {
  artists?: ApiArtist[]
}

export interface SearchCompositePlaylist {
  playLists?: ApiPlaylist[]
}

export interface SearchCompositeUser {
  users?: ApiUser[]
}

export interface SearchCompositeVideo {
  resources?: SearchVideoItem[]
}

export interface SearchCompositeVoice {
  resources?: SearchVoiceItem[]
}

export interface SearchResponse {
  code: number
  result?: SearchResultData
}

export interface SearchDefaultData {
  showKeyword?: string
  realkeyword?: string
  searchType?: number
}

export interface SearchDefaultResponse {
  code: number
  message?: string
  data?: SearchDefaultData
}

export interface HotSearchItem {
  searchWord: string
  score?: number
  iconType?: number
  iconUrl?: string
  content?: string
  url?: string
}

export interface HotSearchResponse {
  code: number
  message?: string
  data?: HotSearchItem[]
}

export interface SearchSuggestResult {
  songs?: ApiSong[]
  albums?: ApiAlbum[]
  artists?: ApiArtist[]
  playlists?: ApiPlaylist[]
  order?: string[]
}

export interface SearchSuggestResponse {
  code: number
  result?: SearchSuggestResult
}

export interface ApiPlaylist {
  id: number
  name: string
  picUrl?: string
  coverImgUrl?: string
  playCount?: number
  trackCount?: number
  creator?: ApiUser
  subscribed?: boolean
  subscribedCount?: number
  commentCount?: number
  shareCount?: number
  privacy?: number
  specialType?: number
  userId?: number
  description?: string
  tags?: string[]
}

export interface PersonalizedPlaylistResponse {
  code: number
  result: ApiPlaylist[]
}

export interface BannerItem {
  bannerId?: string
  pic: string
  typeTitle: string
  targetId: number
  targetType: number
  titleColor?: string
  url?: string
  showAdTag?: boolean
}

export interface BannerResponse {
  code: number
  banners: BannerItem[]
}

export interface ToplistTrackPreview {
  first: string
  second: string
}

export interface ToplistItem extends ApiPlaylist {
  coverImgUrl: string
  updateFrequency?: string
  description?: string
  tracks?: ToplistTrackPreview[]
  ToplistType?: string
  specialType?: number
}

export interface ToplistResponse {
  code: number
  list: ToplistItem[]
}

export interface ArtistToplistArtist extends ApiArtist {
  id: number
  lastRank?: number
  score?: number
}

export interface ArtistToplistData {
  artists: ArtistToplistArtist[]
  updateTime?: number
  type?: number
}

export interface ArtistToplistResponse {
  code: number
  list?: ArtistToplistData
}

export interface ApiUser {
  userId?: number
  nickname: string
  avatarUrl: string
  follows?: number
  followeds?: number
  signature?: string
  userType?: number
  authStatus?: number
  followed?: boolean
  mutual?: boolean
  backgroundUrl?: string
  eventCount?: number
  artistId?: number
  city?: number
}

export interface LikeListResponse {
  code: number
  ids: number[]
}

export interface IntelligencePlayItem {
  id: number
  alg?: string
  recommended?: boolean
  songInfo?: ApiSong | null
}

export interface IntelligencePlayResponse {
  code: number
  message?: string
  data?: IntelligencePlayItem[]
}

export interface LoginResponse {
  code: number
  message?: string
  msg?: string
  cookie?: string
  profile?: ApiUser
  account?: ApiAccount
}

export interface CellphoneExistenceResponse {
  code: number
  exist: number
  nickname?: string
  hasPassword?: boolean
  message?: string
}

export interface SocialUser {
  userId: number
  nickname: string
  avatarUrl: string
  signature?: string
  followed: boolean
  mutual: boolean
  follows?: number
  followeds?: number
  userType?: number
  authStatus?: number
}

export interface UserFollowsResponse {
  code: number
  follow: SocialUser[]
  more: boolean
}

export interface UserFollowedsResponse {
  code: number
  followeds: SocialUser[]
  more: boolean
  size?: number
}

export interface OperationResponse {
  code: number
  message?: string
}

export interface UserLevelData {
  userId: number
  level: number
  progress: number
  nowPlayCount: number
  nextPlayCount: number
  nowLoginCount: number
  nextLoginCount: number
  info?: string
}

export interface UserLevelResponse {
  code: number
  message?: string
  full?: boolean
  data?: UserLevelData
}

export interface VipPackageInfo {
  vipCode: number
  expireTime: number
  vipLevel: number
  iconUrl?: string | null
  dynamicIconUrl?: string | null
}

export interface VipInfoData {
  userId?: number
  redVipLevel: number
  now?: number
  musicPackage?: VipPackageInfo
  associator?: VipPackageInfo
  redplus?: VipPackageInfo
}

export interface VipInfoResponse {
  code: number
  message?: string
  data?: VipInfoData
}

export interface ListenDataValue {
  totalTime?: number
  totalDuration?: number
  duration?: number
  listenTime?: number
  songCount?: number
  count?: number
  days?: number
  type?: string
}

export interface ListenDataResponse {
  code: number
  message?: string
  data?: ListenDataValue
}

export interface ListenReportSection {
  type?: string
  field?: string
  valueA?: string
  textB?: string
  value?: string
}

export interface ListenTimePeriodDuration {
  period: string
  duration: number
}

export interface ListenTimeBlock {
  playDuration?: number
  playDurationText?: string
  circleTimePeriodDurations?: ListenTimePeriodDuration[]
  sections?: ListenReportSection[]
}

export interface ListenDurationDetail {
  period: string
  duration: number
  podcastDuration?: number
  audiobookDuration?: number
  reachLimit?: boolean
}

export interface ListenTimeDistributionBlock {
  playDuration?: number
  listenDays?: number
  durationDetails?: ListenDurationDetail[]
  sections?: ListenReportSection[]
}

export interface ListenReportTopSongSection {
  type?: string
  field?: string
  songId?: number
  picUrl?: string
  songName?: string
  text?: string
}

export interface ListenReportTopSongBlock {
  sections?: ListenReportTopSongSection[]
}

export interface ListenReportTopArtistSection {
  type?: string
  field?: string
  artistId?: number
  artistName?: string
  picUrl?: string
  text?: string
}

export interface ListenReportTopArtistBlock {
  sections?: ListenReportTopArtistSection[]
}

export interface ListenReportStyleSection {
  genreId?: number
  genreName?: string
  percent?: string
}

export interface ListenReportTopStyleBlock {
  genreId?: number
  genreName?: string
  sections?: ListenReportStyleSection[]
}

export interface ListenReportAgeSection {
  age?: string
  playSongNum?: number
}

export interface ListenReportTopAgeBlock {
  sections?: ListenReportAgeSection[]
}

export interface ListenReportLanguageSection {
  language?: string
  percent?: string
  playSongNum?: number
  songName?: string
}

export interface ListenReportTopLanguageBlock {
  sections?: ListenReportLanguageSection[]
}

export interface ListenReportData {
  type?: string
  startTime?: number
  endTime?: number
  listenTimeBlock?: ListenTimeBlock
  listenTimeDistributionBlock?: ListenTimeDistributionBlock
  topSongBlock?: ListenReportTopSongBlock
  topArtistBlock?: ListenReportTopArtistBlock
  topStyleBlock?: ListenReportTopStyleBlock
  topAgeBlock?: ListenReportTopAgeBlock
  topLanguageBlock?: ListenReportTopLanguageBlock
}

export interface ListenReportResponse {
  code: number
  message?: string
  data?: ListenReportData
}

export interface UserDetailProfile extends ApiUser {
  userId: number
  follows: number
  followeds: number
  playlistCount?: number
  allSubscribedCount?: number
  description?: string
  gender?: number
  birthday?: number
  province?: number
}

export interface UserDetailResponse {
  code: number
  level: number
  listenSongs: number
  profile: UserDetailProfile
}

export interface UserProfilePageParam {
  uid: string
  followsTarget?: boolean
  followedByTarget?: boolean
}

export interface EventJsonData {
  msg?: string
  title?: string
  song?: ApiSong
  playlist?: ApiPlaylist
  album?: EventJsonAlbum
  mv?: EventJsonMv
  video?: EventJsonVideo
  program?: EventJsonResource
  djRadio?: EventJsonResource
  resource?: EventJsonResource
  event?: EventForwardData
}

export interface EventForwardData {
  id?: number
  user?: SocialUser
  json?: string
  pics?: EventPicture[]
  info?: EventInfo
  actName?: string
  eventTime?: number
  showTime?: number
  type?: number
  forwardCount?: number
  insiteForwardCount?: number
}

export interface EventJsonAlbum {
  id?: number
  name?: string
  picUrl?: string
  artists?: ApiArtist[]
  artist?: ApiArtist
}

export interface EventJsonVideo {
  title?: string
  coverUrl?: string
  durationms?: number
  creator?: ApiUser
}

export interface EventJsonMv {
  id?: number
  name?: string
  imgurl?: string
  imgurl16v9?: string
  artistName?: string
  duration?: number
  playCount?: number
}

export interface EventJsonResource {
  id?: number
  name?: string
  title?: string
  picUrl?: string
  coverUrl?: string
  description?: string
  artists?: ApiArtist[]
}

export interface EventInfo {
  commentCount: number
  likedCount: number
  shareCount: number
  threadId?: string
  liked?: boolean
}

export interface EventPicture {
  originUrl?: string
  squareUrl?: string
  rectangleUrl?: string
  pcSquareUrl?: string
  width?: number
  height?: number
}

export interface UserEventItem {
  id: number
  type?: number
  eventTime?: number
  showTime?: number
  json: string
  user: SocialUser
  info: EventInfo
  pics?: EventPicture[]
  actName?: string
}

export interface EventDetailPageParam {
  event: UserEventItem
  canDelete?: boolean
}

export interface UserEventResponse {
  code: number
  events: UserEventItem[]
  more: boolean
  lasttime: number
  size?: number
}

export interface EventFeedResponse {
  code: number
  event: UserEventItem[]
  more: boolean
  lasttime?: number
}

export interface HotTopicItem {
  actId: number
  title: string
  text?: string[]
  participateCount?: number
  sharePicUrl?: string
  reason?: string
}

export interface HotTopicResponse {
  code: number
  hot: HotTopicItem[]
}

export interface TopicHotEventResponse {
  code: number
  events: UserEventItem[]
}

export interface SubscribedAlbumArtist {
  name: string
}

export interface SubscribedAlbum {
  id: number
  name: string
  picUrl: string
  size: number
  artists: SubscribedAlbumArtist[]
}

export interface AlbumSublistResponse {
  code: number
  data?: SubscribedAlbum[]
  hasMore?: boolean
  count?: number
}

export interface PlaylistDynamicResponse {
  code: number
  commentCount: number
  shareCount: number
  playCount: number
  bookedCount: number
  subscribed: boolean
}

export interface ApiAccount {
  id: number
}

export interface QrKeyResponse {
  code: number
  data: QrKeyData
}

export interface QrKeyData {
  code: number
  unikey: string
}

export interface QrCheckResponse extends LoginResponse {
  nickname?: string
  avatarUrl?: string
}

export interface UserAccountResponse {
  code: number
  account: ApiAccount
  profile: ApiUser
}

export interface LoginStatusData {
  profile?: ApiUser
  account?: ApiAccount
}

export interface LoginStatusResponse {
  code: number
  data?: LoginStatusData
  profile?: ApiUser
  account?: ApiAccount
}

export interface UserPlaylistData {
  playlist?: ApiPlaylist[]
  more?: boolean
  count?: number
}

export interface UserPlaylistResponse {
  code: number
  playlist?: ApiPlaylist[]
  data?: UserPlaylistData
}

export interface PlaylistDetailData {
  id: number
  name: string
  coverImgUrl: string
  trackCount: number
  creator: ApiUser
  tracks: ApiSong[]
  playCount?: number
  subscribedCount?: number
  commentThreadId?: string
  tags?: string[]
  description?: string
  privacy?: number
}

export interface PlaylistDetailResponse {
  code: number
  playlist: PlaylistDetailData
}

export interface SongUrlData {
  id: number
  url: string
  level: string
  type: string
  size?: number
}

export interface SongUrlResponse {
  code: number
  data: SongUrlData[]
}

export interface SongDownloadUrlData {
  id: number
  url: string
  br: number
  size: number
  md5: string
  code: number
  expi: number
  type: string
  gain: number
  peak: number
  fee: number
  uf: string | null
  payed: number
  flag: number
  canExtend: boolean
  freeTrialInfo: string | null
  level: string
  encodeType: string
  channelLayout: string | null
  urlSource: number
  rightSource: number
  time: number
  message: string | null
  levelConfuse: string | null
  musicId: string
  sr: number
}

export interface SongDownloadUrlResponse {
  code: number
  data: SongDownloadUrlData
}

export interface SongDetailResponse {
  code: number
  songs: ApiSong[]
}

export interface CommentApiUser {
  nickname: string
  avatarUrl: string
}

export interface CommentApiItem {
  commentId: number
  content: string
  likedCount: number
  liked?: boolean
  timeStr: string
  user: CommentApiUser
}

export interface SongMusicQualityInfo {
  br: number
  size: number
  sr: number
}

export interface SongMusicDetailData {
  songId: number
  l?: SongMusicQualityInfo
  m?: SongMusicQualityInfo
  h?: SongMusicQualityInfo
  sq?: SongMusicQualityInfo
  hr?: SongMusicQualityInfo
}

export interface SongMusicDetailResponse {
  code: number
  data?: SongMusicDetailData
  message?: string
}

export interface CommentResponse {
  code: number
  total: number
  hotComments?: CommentApiItem[]
  comments: CommentApiItem[]
}

export interface LyricPart {
  version: number
  lyric: string
}

export interface LyricResponse {
  code: number
  lrc?: LyricPart
  yrc?: LyricPart
  tlyric?: LyricPart
  romalrc?: LyricPart
  nolyric?: boolean
  uncollected?: boolean
}

export interface SongWikiResponse {
  code: number
  data?: SongWikiData
  message?: string
}

export interface SongWikiData {
  blocks?: SongWikiRawBlock[]
}

export interface SongWikiRawBlock {
  showType?: string
  title?: string
  content?: string
  text?: string
  code?: string
  uiElement?: WikiUiElement
  creatives?: WikiCreative[]
}

export interface WikiTitle {
  title?: string
  action?: WikiAction
}

export interface WikiDescription {
  text?: string
  title?: string
}

export interface WikiTextLink {
  text?: string
  url?: string
}

export interface WikiImage {
  title?: string
  imageUrl?: string
  imageWithoutTextUrl?: string
  action?: WikiAction
}

export interface WikiLabel {
  text?: string
}

export interface WikiButton {
  text?: string
  imageUrl?: string
  action?: WikiAction
}

export interface WikiClickAction {
  targetUrl?: string
}

export interface WikiAction {
  clickAction?: WikiClickAction
}

export interface WikiUiElement {
  mainTitle?: WikiTitle
  subTitles?: WikiTitle[]
  images?: WikiImage[]
  labels?: WikiLabel[]
  descriptions?: WikiDescription[]
  textLinks?: WikiTextLink[]
  buttons?: WikiButton[]
}

export interface WikiCreative {
  creativeType?: string
  uiElement?: WikiUiElement
  action?: WikiAction
  resources?: WikiResource[]
}

export interface WikiMusicFirstListenDto {
  timestamp?: string
  season?: string
  period?: string
  date?: string
  subTitle?: string
  desc?: string
}

export interface WikiMusicTotalPlayDto {
  playCount?: number
  duration?: number
  text?: string
  subTitle?: string
  desc?: string
}

export interface WikiResourceExt {
  playCount?: number
  specialType?: number
  musicMemoryTextType?: number
  musicFirstListenDto?: WikiMusicFirstListenDto
  musicTotalPlayDto?: WikiMusicTotalPlayDto
}

export interface WikiResource {
  resourceType?: string
  resourceId?: string
  resourceUrl?: string
  action?: WikiAction
  uiElement?: WikiUiElement
  resourceExt?: WikiResourceExt
}

export interface SheetInstrumentType {
  code: number
  name: string
  icon: string
}

export interface MusicSheetSimpleInfo {
  id: number
  sheetPackageId: number
  name: string
  type: SheetInstrumentType[]
  source: number
  sourceDesc: string
  sourceIcon?: string
  coverImageUrl: string
  totalPageSize: number
  difficulty: string
  musicKey: string
  playVersion: string
  chordName: string
  bpm: number
  commentNum: number
}

export interface SheetListData {
  sheetInstrumentTypeVOList: SheetInstrumentType[]
  musicSheetSimpleInfoVOS: MusicSheetSimpleInfo[]
  errorCode?: number
  findSheet: number
  uploadSheet: number
}

export interface SheetListResponse {
  code: number
  data?: SheetListData
  message?: string
}

export interface SheetPreviewPage {
  id: number
  sheetId: number
  url: string
  md5: string
  pageNumber: number
  size: number
}

export interface SheetPreviewResponse {
  code: number
  data?: SheetPreviewPage[]
  message?: string
}

export function mapApiSong(song: ApiSong): songItemType {
  const artists = song.ar || song.artists || []
  const album = song.al || song.album
  return {
    id: song.id.toString(),
    name: song.name,
    author: artists.map((item: ApiArtist) => item.name).join(' / '),
    img: album?.picUrl || song.picUrl || '',
    url: '',
    duration: song.dt || song.duration || 0,
    album: album?.name || '',
    albumId: album?.id?.toString() || '',
    fee: song.fee || 0,
    artists: artists.map((item: ApiArtist) => {
      const artist: SongArtist = {
        id: (item.id || 0).toString(),
        name: item.name,
        picUrl: item.picUrl || item.img1v1Url || ''
      }
      return artist
    })
  }
}

export function mapPlaylist(item: ApiPlaylist): playlistType {
  return {
    id: item.id.toString(),
    name: item.name,
    cover: item.coverImgUrl || item.picUrl || '',
    count: item.trackCount || 0,
    creator: item.creator?.nickname || '网易云音乐',
    creatorId: item.creator?.userId?.toString() || '',
    description: item.description || '',
    tags: item.tags || [],
    privacy: item.privacy || 0
  }
}

export function mapComment(item: CommentApiItem): MusicComment {
  return {
    commentId: item.commentId.toString(),
    content: item.content,
    likedCount: item.likedCount,
    liked: item.liked || false,
    timeStr: item.timeStr,
    user: {
      nickname: item.user.nickname,
      avatarUrl: item.user.avatarUrl
    }
  }
}

export interface DjCategory {
  id: number
  name: string
  pic56x56CategoryId: number
  pic84x84CategoryId: number
  picPCCategoryId: number
}

export interface DjCateListResponse {
  code: number
  categories: DjCategory[]
}

export interface DjRadioItem {
  id: number
  name: string
  picUrl: string
  desc: string
  subCount: number
  programCount: number
  playCount: number
  rcmdText?: string
  category: number
  secondCategory: number
  creator?: ApiUser
  dj?: ApiUser
}

export interface DjSublistResponse {
  code: number
  djRadios: DjRadioItem[]
  hasMore: boolean
  count?: number
}

export interface DjProgramItem {
  id: number
  name: string
  coverUrl: string
  duration: number
  serialNum: number
  listenerCount: number
  createTime: number
  description?: string
  djBrand?: DjRadioItem
}

export interface DjProgramResponse {
  code: number
  programs: DjProgramItem[]
  more: boolean
  count?: number
}

export interface DjDetailResponse {
  code: number
  djRadio?: DjRadioItem
}

export interface EventCommentResponse {
  code: number
  total: number
  comments: EventCommentItem[]
  hotComments?: EventCommentItem[]
  more: boolean
}

export interface EventCommentItem {
  commentId: number
  content: string
  time: number
  timeStr?: string
  likedCount: number
  liked?: boolean
  user: SocialUser
}

export interface ShareResourceResponse {
  code: number
  message?: string
  id?: number
}

export interface MsgPrivateItem {
  id: number
  fromUser: SocialUser
  toUser: SocialUser
  lastMsg: PrivateMsgContent
  lastMsgTime: number
  newMsgCount: number
  noticeAccountFlag: boolean
}

export interface PrivateMsgUser {
  userId: number
  nickname: string
  avatarUrl: string
  followed?: boolean
  mutual?: boolean
  vipType?: number
}

export interface PrivateMsgContent {
  fromUser: PrivateMsgUser
  toUser: PrivateMsgUser
  msg: string
  time?: number
  id?: number
}

export interface MsgPrivateResponse {
  code: number
  data: MsgPrivateItem[]
  more: boolean
  newMsgCount?: number
}

export interface MsgConversationMeta {
  id?: number
  toUserId?: number
  fromUserId?: number
  msgCount?: number
  newMsgCount?: number
  lastMsgTime?: number
}

export interface MsgPrivateConversation {
  user?: MsgConversationMeta
  fromUser: SocialUser
  toUser: SocialUser
  lastMsg: string
  lastMsgTime: number
  newMsgCount: number
  lastMsgId?: number
  noticeAccountFlag?: boolean
}

export interface MsgPrivateListResponse {
  code: number
  msgs: MsgPrivateConversation[]
  more?: boolean
  newMsgCount?: number
}

export interface MsgCommentNotification {
  user: SocialUser
  beRepliedUser?: SocialUser
  beRepliedContent?: string
  time: number
  content: string
  richContent?: string
  resourceJson?: string
  commentId: number
  threadId: string
  liked?: boolean
}

export interface MsgCommentsResponse {
  code: number
  total?: number
  comments: MsgCommentNotification[]
  more?: boolean
}

export interface MsgNoticeItem {
  id: number
  userId?: number
  time: number
  notice: string
  pushMsg?: string
  type?: number
}

export interface MsgNoticesResponse {
  code: number
  notices: MsgNoticeItem[]
  more?: boolean
  lasttime?: number
}

export interface MsgPrivateHistoryResponse {
  code: number
  msgs: PrivateMsgContent[]
  more: boolean
}

export interface SendMsgResponse {
  code: number
  message?: string
  msg?: string
}

export interface MutualFollowResponse {
  code: number
  data?: boolean | MutualFollowData
  follow?: boolean
  mutual?: boolean
}

export interface MutualFollowData {
  follow?: boolean
  followed?: boolean
  mutual?: boolean
}

export interface SongRedCountData {
  count: number
  countDesc?: string
}

export interface SongRedCountResponse {
  code: number
  data?: SongRedCountData
}

export interface PlaylistCreateResponse {
  code: number
  id?: number
  playlist?: ApiPlaylist
  message?: string
}

export interface PlaylistDeleteResponse {
  code: number
  message?: string
}

export interface EventLikeResponse {
  code: number
  message?: string
  msg?: string
}

export interface SharePageParam {
  type: 'song' | 'playlist' | 'album'
  id: string
  name: string
  img: string
  author?: string
}

export interface PrivateChatPageParam {
  uid: string
  nickname: string
  avatarUrl: string
  shareMsg?: string
  shareType?: string
  shareId?: string
}

export interface PlaylistCollectResponse {
  code: number
  playlist: ApiPlaylist[]
  hasMore?: boolean
  count?: number
}

export interface ListenRankSong {
  songId: number
  songName: string
  aliasName?: string
  picUrl?: string
  artists?: ApiArtist[]
  redStar?: boolean
  lastPlayTime?: number
  name?: string
  ar?: ApiArtist[]
  al?: ApiAlbum
  dt?: number
  fee?: number
}

export interface ListenRankItem {
  song?: ListenRankSong
  songId?: number
  songName?: string
  picUrl?: string
  artists?: ApiArtist[]
  playCount?: number
  score?: number
  redStar?: boolean
  lastPlayTime?: number
}

export interface ListenRankResponse {
  code: number
  data?: ListenRankData
  message?: string
}

export interface ListenRankData {
  songPlayRank?: ListenRankItem[]
  songDTOs?: ListenRankItem[]
}

export interface PlaylistImportTaskResponse {
  code: number
  id?: number
  message?: string
}

export interface PlaylistImportStatusResponse {
  code: number
  status?: number
  message?: string
  playlistId?: number
}

export interface AlbumDetailData {
  id?: number
  name?: string
  picUrl?: string
  artist?: ApiArtist
  artists?: ApiArtist[]
  publishTime?: number
  company?: string
  size?: number
  description?: string
  type?: string
  subType?: string
}

export interface AlbumDetailResponse {
  code: number
  album?: AlbumDetailData
  songs?: ApiSong[]
}

export interface AlbumDynamicResponse {
  code: number
  commentCount?: number
  shareCount?: number
  isSub?: boolean
  subCount?: number
  onSale?: boolean
}

export interface AlbumPageParam {
  id: string
  name?: string
  picUrl?: string
  artist?: string
}

export interface VipGrowthUserLevel {
  userId?: number
  level?: number
  growthPoint?: number
  levelName?: string
  vipType?: number
  expireTime?: number
  latestVipType?: number
  latestVipStatus?: number
}

export interface VipGrowthLevelCard {
  level?: number
  levelName?: string
  privilegeName?: string
  privilegeSubTitle?: string
  privilegeIconUrl?: string
  levelBackgroundCardImageUrl?: string
  backgroundImageUrl?: string
  levelMarkImageUrl?: string
}

export interface VipGrowthData {
  userLevel?: VipGrowthUserLevel
  levelCard?: VipGrowthLevelCard
}

export interface VipGrowthResponse {
  code: number
  message?: string
  data?: VipGrowthData
}

export interface VipGrowthClaimResponse {
  code: number
  message?: string
}

export interface MsgRecentContactUser {
  userId?: number
  nickname?: string
  avatarUrl?: string
  mutual?: boolean
  py?: string
  onlined?: boolean
}

export interface MsgRecentContactData {
  follow?: MsgRecentContactUser[]
}

export interface MsgRecentContactResponse {
  code: number
  data?: MsgRecentContactData
}
