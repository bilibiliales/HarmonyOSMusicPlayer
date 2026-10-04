import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'

export interface WeApiEnvelope {
  params: string
  encSecKey: string
}

export class WeApiCrypto {
  private static readonly PRESET_KEY: string = '0CoJUm6Qyw8W8jud'
  private static readonly IV: string = '0102030405060708'
  private static readonly MODULUS: string =
    'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7'

  private static bytes(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text)
  }

  private static unhex(text: string): Uint8Array {
    const bytes = new Uint8Array(text.length / 2)
    for (let i = 0; i < bytes.length; i++) { bytes[i] = parseInt(text.substring(i * 2, i * 2 + 2), 16) }
    return bytes
  }

  private static async secret(): Promise<string> {
    const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    const random = cryptoFramework.createRandom()
    let key = ''
    while (key.length < 16) {
      const bytes = (await random.generateRandom(32)).data
      for (let i = 0; i < bytes.length && key.length < 16; i++) {
        // Reject the final eight byte values to avoid bias when choosing from 62 characters.
        if (bytes[i] < 248) { key += alphabet.charAt(bytes[i] % alphabet.length) }
      }
    }
    return key
  }

  private static async aes(text: string, key: string): Promise<string> {
    const generator = cryptoFramework.createSymKeyGenerator('AES128')
    const symKey = await generator.convertKey({ data: WeApiCrypto.bytes(key) })
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7')
    const iv: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: WeApiCrypto.bytes(WeApiCrypto.IV) } }
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, iv)
    const output = await cipher.doFinal({ data: WeApiCrypto.bytes(text) })
    return new util.Base64Helper().encodeToStringSync(output.data)
  }

  private static async rsa(secret: string): Promise<string> {
    // DER SubjectPublicKeyInfo: 1024-bit modulus (with unsigned leading zero) and exponent 0x010001.
    const der = WeApiCrypto.unhex('30819f300d06092a864886f70d010101050003818d0030818902818100' +
      WeApiCrypto.MODULUS + '0203010001')
    const pair = await cryptoFramework.createAsyKeyGenerator('RSA1024').convertKey({ data: der }, null)
    const cipher = cryptoFramework.createCipher('RSA1024|NoPadding')
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, pair.pubKey, null)
    // WeAPI treats the reversed ASCII key as a big-endian integer, zero-padded to the RSA block size.
    const block = new Uint8Array(128)
    for (let i = 0; i < 16; i++) { block[112 + i] = secret.charCodeAt(15 - i) }
    const output = await cipher.doFinal({ data: block })
    let hex = ''
    for (let i = 0; i < output.data.length; i++) { hex += output.data[i].toString(16).padStart(2, '0') }
    return hex.padStart(256, '0')
  }

  static async encrypt(text: string): Promise<WeApiEnvelope> {
    const key = await WeApiCrypto.secret()
    const first = await WeApiCrypto.aes(text, WeApiCrypto.PRESET_KEY)
    return { params: await WeApiCrypto.aes(first, key), encSecKey: await WeApiCrypto.rsa(key) }
  }
}
