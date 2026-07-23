export interface DigitalAlbumProduct {
  newAlbum?: boolean
  albumId: number
  albumName: string
  artistName: string
  artistNames?: string[]
  price: number
  coverUrl: string
  pubTime?: number
  productId?: number
  saleNum?: number
  sales?: number
  rank?: number
  rankIncr?: number
  newest?: boolean
  albumType?: number
  saleType?: number
  area?: number
  status?: number
  bought?: boolean
  salesCertificationSystemLevelCode?: string
}

export interface DigitalAlbumNewResponse {
  code: number
  products?: DigitalAlbumProduct[]
}

export interface DigitalAlbumSalesResponse {
  code: number
  products?: DigitalAlbumProduct[]
  hasMore?: boolean
}

export interface DigitalAlbumStyleResponse {
  code: number
  albumProducts?: DigitalAlbumProduct[]
  hasNextPage?: boolean
}

export interface DigitalAlbumDescription {
  type?: number
  resource?: string
}

export interface DigitalAlbumDetailProduct {
  saleNum?: number
  donateMsg?: string
  price?: number
  pubTime?: number
  buysingle?: boolean
  status?: number
  descr?: DigitalAlbumDescription[]
  mvCoverUrl?: string
  mvPlayUrl?: string
  mvTitle?: string
  showMv?: boolean
  tags?: string[]
  buynotes?: string[]
  isFree?: boolean
  albumfee?: number
}

export interface DigitalAlbumDetailAlbum {
  albumId: number
  coverUrl?: string
  blurImgUrl?: string
  albumName?: string
  artistId?: number
  artistName?: string
  artistNames?: string
  artistAvatarUrl?: string
}

export interface DigitalAlbumDetailResponse {
  code: number
  product?: DigitalAlbumDetailProduct
  album?: DigitalAlbumDetailAlbum
  canBuy?: boolean
  boughtCnt?: number
  hasAlbum?: boolean
  singleSongProductId?: number
}

export interface DigitalAlbumDetailPageParam {
  albumId: number
  albumName?: string
  artistName?: string
  coverUrl?: string
}
