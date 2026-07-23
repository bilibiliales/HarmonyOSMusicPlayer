import { fileIo } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { OperationResponse } from '../models/api'
import { ApiClient } from '../services/ApiClient'
import { AuthStore } from '../stores/AuthStore'

interface CityInfo {
  id: string
  name: string
  cities: CityInfo[] | null
}

interface ProvinceInfo {
  id: string
  name: string
  cities: CityInfo[] | null
}

export interface ProfileEditorPageParam {
  nickname: string
  avatarUrl: string
  signature: string
  gender: number
  birthday: number
  province: number
  city: number
  onSaved?: () => void
}

interface LocationDataResponseData {
  provinces: ProvinceInfo[]
}

interface LocationDataResponse {
  code: number
  message: string
  data: LocationDataResponseData
}

@Component
export struct ProfileEditorPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @Consume('authStore') authStore: AuthStore
  pageParam: ProfileEditorPageParam = {
    nickname: '', avatarUrl: '', signature: '', gender: 0, birthday: 0, province: 0, city: 0
  }

  @State nickname: string = ''
  @State signature: string = ''
  @State gender: number = -1
  @State birthdayText: string = ''
  @State avatarUri: string = ''
  @State saving: boolean = false
  @State message: string = ''
  @State provinces: ProvinceInfo[] = []
  @State selectedProvince: ProvinceInfo | null = null
  @State selectedCity: CityInfo | null = null
  @State showProvinceSelector: boolean = false
  @State showCitySelector: boolean = false
  private initialized: boolean = false

  aboutToAppear(): void {
    if (!this.authStore.loggedIn) {
      this.pageStack.replacePathByName('LoginPage', null)
      return
    }
    if (!this.initialized) {
      this.nickname = this.pageParam.nickname
      this.signature = this.pageParam.signature
      // 将性别值转换为新的两选项格式 (0=男, 1=女)，如果是原来的'保密'(2)则设为-1表示未选择
      this.gender = this.pageParam.gender === 2 ? -1 : this.pageParam.gender
      this.birthdayText = this.formatBirthday(this.pageParam.birthday)
      this.loadLocationData()
      this.initialized = true
    }
  }

  private formatBirthday(value: number): string {
    if (!value || value <= 0) {
      return ''
    }
    const date = new Date(value)
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${date.getFullYear()}-${month}-${day}`
  }

  private birthdayTimestamp(): number {
    const value = this.birthdayText.trim()
    if (!value) {
      return 0
    }
    const timestamp = new Date(`${value}T00:00:00`).getTime()
    return Number.isNaN(timestamp) ? 0 : timestamp
  }

  private async selectAvatar(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const result = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      })
      if (result.photoUris.length > 0) {
        this.avatarUri = result.photoUris[0]
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '头像选择失败'
    }
  }

  private async uploadAvatar(): Promise<void> {
    if (!this.avatarUri) {
      return
    }
    const file = fileIo.openSync(this.avatarUri, fileIo.OpenMode.READ_ONLY)
    try {
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      const lower = this.avatarUri.toLowerCase()
      const isPng = lower.includes('.png')
      const response = await ApiClient.upload<OperationResponse>('/avatar/upload', [
        { key: 'imgSize', value: '500' },
        { key: 'imgX', value: '0' },
        { key: 'imgY', value: '0' }
      ], 'imgFile', isPng ? 'avatar.png' : 'avatar.jpg', buffer, isPng ? 'image/png' : 'image/jpeg')
      if (response.code !== 200) {
        throw new Error(response.message || '头像上传失败')
      }
    } finally {
      fileIo.closeSync(file)
    }
  }

  private async loadLocationData(): Promise<void> {
    try {
      const response = await ApiClient.get<LocationDataResponse>('/lbs/city/code', [
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code === 200) {
        this.provinces = response.data.provinces
        // 尝试找到用户当前设置的省市区
        if (this.pageParam.province > 0) {
          const provinceId = this.pageParam.province.toString()
          this.selectedProvince = this.provinces.find(p => p.id === provinceId) || null
          if (this.selectedProvince && this.pageParam.city > 0) {
            const cityId = this.pageParam.city.toString()
            this.selectedCity = this.findCityById(this.selectedProvince.cities, cityId)
          }
        }
      }
    } catch (error) {
      console.error('加载省市数据失败:', error)
      this.message = '省市数据加载失败'
    }
  }

  private findCityById(cities: CityInfo[] | null, cityId: string): CityInfo | null {
    if (!cities) return null
    for (const city of cities) {
      if (city.id === cityId) {
        return city
      }
      if (city.cities && city.cities.length > 0) {
        const found = this.findCityById(city.cities, cityId)
        if (found) return found
      }
    }
    return null
  }

  private async save(): Promise<void> {
    if (!this.nickname.trim() || this.saving) {
      return
    }
    const birthday = this.birthdayTimestamp()
    if (this.birthdayText.trim() && birthday <= 0) {
      this.message = '生日格式应为 YYYY-MM-DD'
      return
    }
    this.saving = true
    this.message = ''
    try {
      const response = await ApiClient.get<OperationResponse>('/user/update', [
        { key: 'nickname', value: this.nickname.trim() },
        { key: 'signature', value: this.signature.trim() },
        { key: 'gender', value: this.gender.toString() },
        { key: 'birthday', value: birthday.toString() },
        { key: 'province', value: this.selectedProvince ? this.selectedProvince.id : '0' },
        { key: 'city', value: this.selectedCity ? this.selectedCity.id : '0' },
        { key: 'timestamp', value: Date.now().toString() }
      ])
      if (response.code !== 200) {
        throw new Error(response.message || '个人资料更新失败')
      }
      await this.uploadAvatar()
      await this.authStore.refreshAccount()
      this.pageParam.onSaved?.()
      this.pageStack.pop()
    } catch (error) {
      this.message = error instanceof Error ? error.message : '个人资料保存失败'
    } finally {
      this.saving = false
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor(['#ffffff'])
            .onClick(() => this.pageStack.pop())
          Text('编辑个人资料').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor('#ffffff').textAlign(TextAlign.Center)
          Button(this.saving ? '保存中' : '保存').height(36).fontSize(12).fontColor('#ffffff')
            .backgroundColor(this.nickname.trim() && !this.saving ? '#ef233c' : '#38383f').borderRadius(18)
            .enabled(this.nickname.trim().length > 0 && !this.saving).onClick(() => this.save())
        }.width('100%').height(58).padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 19 }) {
            Stack({ alignContent: Alignment.BottomEnd }) {
              Image(this.avatarUri || this.pageParam.avatarUrl).width(112).height(112).borderRadius(56)
                .objectFit(ImageFit.Cover).backgroundColor('#29292f')
              Stack() {
                SymbolGlyph($r('sys.symbol.camera_fill')).fontSize(18).fontColor(['#ffffff'])
              }.width(38).height(38).borderRadius(19).backgroundColor('#ef233c')
            }.width(112).height(112).onClick(() => this.selectAvatar())

            Column({ space: 8 }) {
              Text('昵称').width('100%').fontSize(12).fontColor('#85858e')
              TextInput({ text: this.nickname, placeholder: '输入昵称' }).width('100%').height(48)
                .fontColor('#ffffff').placeholderColor('#5f5f67').backgroundColor('#1f1f24').borderRadius(14)
                .onChange((value: string) => this.nickname = value.substring(0, 30))
            }.width('100%')

            Column({ space: 8 }) {
              Text('个人介绍').width('100%').fontSize(12).fontColor('#85858e')
              TextArea({ text: this.signature, placeholder: '介绍一下自己' }).width('100%').height(120)
                .fontColor('#ffffff').placeholderColor('#5f5f67').backgroundColor('#1f1f24').borderRadius(14)
                .onChange((value: string) => this.signature = value.substring(0, 300))
            }.width('100%')

            Column({ space: 9 }) {
              Text('性别').width('100%').fontSize(12).fontColor('#85858e')
              Row({ space: 9 }) {
                ForEach(['男', '女'], (label: string, index: number) => {
                  Text(label).layoutWeight(1).height(42).fontSize(13).textAlign(TextAlign.Center)
                    .fontColor(this.gender === index ? '#ffffff' : '#85858e')
                    .backgroundColor(this.gender === index ? '#ef233c' : '#24242a').borderRadius(13)
                    .onClick(() => this.gender = index)
                })
              }.width('100%')
            }.width('100%')

            Column({ space: 8 }) {
              Text('生日').width('100%').fontSize(12).fontColor('#85858e')
              TextInput({ text: this.birthdayText, placeholder: 'YYYY-MM-DD' }).width('100%').height(48)
                .fontColor('#ffffff').placeholderColor('#5f5f67').backgroundColor('#1f1f24').borderRadius(14)
                .inputFilter('[0-9-]*').onChange((value: string) => this.birthdayText = value.substring(0, 10))
            }.width('100%')

            Row({ space: 10 }) {
              Column({ space: 8 }) {
                Text('省份').width('100%').fontSize(12).fontColor('#85858e')
                Row() {
                  Text(this.selectedProvince ? this.selectedProvince.name : '请选择省份')
                    .fontSize(13)
                    .fontColor(this.selectedProvince ? '#ffffff' : '#5f5f67')
                }
                .width('100%').height(48)
                .padding({ left: 12 }).backgroundColor('#24242a')
                .borderRadius(14).onClick(() => this.showProvinceSelector = true)
              }.layoutWeight(1)

              Column({ space: 8 }) {
                Text('城市').width('100%').fontSize(12).fontColor('#85858e')
                Row() {
                  Text(this.selectedCity ? this.selectedCity.name : '请选择城市')
                    .fontSize(13)
                    .fontColor(this.selectedCity ? '#ffffff' : '#5f5f67')
                }
                .width('100%').height(48)
                .padding({ left: 12 }).backgroundColor('#24242a')
                .borderRadius(14).onClick(() => {
                  if (this.selectedProvince) {
                    this.showCitySelector = true
                  } else {
                    this.message = '请先选择省份'
                  }
                })
              }.layoutWeight(1)
            }.width('100%')

            // 省份选择弹窗
            if (this.showProvinceSelector) {
              Blank().width('100%').height('100%').position({ x: 0, y: 0 })
                .zIndex(100).onClick(() => this.showProvinceSelector = false)
              Column() {
                Row({ space: 12 }) {
                  Text('选择省份').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                  Text('取消').fontSize(14).fontColor('#ef233c')
                    .onClick(() => this.showProvinceSelector = false)
                }.width('100%').padding({ left: 20, right: 20, top: 20, bottom: 10 })
                List({ space: 2 }) {
                  ForEach(this.provinces, (province: ProvinceInfo) => {
                    ListItem() {
                      Text(province.name).width('100%').height(48).padding({ left: 20 })
                        .fontSize(14).fontColor('#ffffff').textAlign(TextAlign.Start)
                        .backgroundColor(province.id === this.selectedProvince?.id ? '#2d2d35' : '#1f1f24')
                        .borderRadius(8)
                        .onClick(() => {
                          this.selectedProvince = province
                          this.selectedCity = null // 切换省份时清空城市选择
                          this.showProvinceSelector = false
                        })
                    }
                  })
                }.width('100%').height(300).padding({ left: 20, right: 20 })
                  .edgeEffect(EdgeEffect.Spring).friction(0.8)
              }.width('90%').backgroundColor('#24242a').borderRadius(16)
                .position({ x: '5%', y: 100 }).zIndex(101)
            }

            // 城市选择弹窗
            if (this.showCitySelector) {
              Blank().width('100%').height('100%').position({ x: 0, y: 0 })
                .zIndex(100).onClick(() => this.showCitySelector = false)
              Column() {
                Row({ space: 12 }) {
                  Text('选择城市').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#ffffff')
                  Text('取消').fontSize(14).fontColor('#ef233c')
                    .onClick(() => this.showCitySelector = false)
                }.width('100%').padding({ left: 20, right: 20, top: 20, bottom: 10 })
                List({ space: 2 }) {
                  ForEach(this.selectedProvince?.cities || [], (city: CityInfo) => {
                    ListItem() {
                      Text(city.name).width('100%').height(48).padding({ left: 20 })
                        .fontSize(14).fontColor('#ffffff').textAlign(TextAlign.Start)
                        .backgroundColor(city.id === this.selectedCity?.id ? '#2d2d35' : '#1f1f24')
                        .borderRadius(8)
                        .onClick(() => {
                          this.selectedCity = city
                          this.showCitySelector = false
                        })
                    }
                  })
                }.width('100%').height(300).padding({ left: 20, right: 20 })
                  .edgeEffect(EdgeEffect.Spring).friction(0.8)
              }.width('90%').backgroundColor('#24242a').borderRadius(16)
                .position({ x: '5%', y: 100 }).zIndex(101)
            }

            if (this.message) {
              Text(this.message).width('100%').padding(12).fontSize(11).lineHeight(18).fontColor('#ff8b78')
                .textAlign(TextAlign.Center).backgroundColor('#2b211f').borderRadius(13)
            }
          }.width('100%').alignItems(HorizontalAlign.Center)
            .padding({ left: 18, right: 18, top: 18, bottom: 40 })
        }.layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').backgroundColor('#121215')
    }.hideTitleBar(true)
  }
}
