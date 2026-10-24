import type { Transport } from './bridge-types'

/** Raw bytes per upload message (base64 adds a third). */
const UPLOAD_CHUNK = 768 * 1024

const MIME_EXTENSIONS: Record<string, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a'
}

/** The file's extension (from its name, else its type; "bin" when neither says). */
export function extensionOf(file: { name?: string; type: string }): string {
  const fromName = file.name?.includes('.') ? file.name.split('.').pop()?.toLowerCase() : undefined
  if (fromName && /^[a-z0-9]{1,10}$/u.test(fromName)) return fromName
  return MIME_EXTENSIONS[file.type] ?? 'bin'
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.addEventListener('load', () =>
      resolve(String(reader.result).replace(/^data:[^,]*,/u, ''))
    )
    reader.addEventListener('error', () => reject(reader.error))
    reader.readAsDataURL(blob)
  })
}

/**
 * Sends a file to the native side in chunks (one base64 message per chunk instead of one huge one) and
 * resolves to its asset URL. A failure cancels the upload, so no partial file is kept.
 */
export async function uploadFile(
  transport: Transport,
  file: Blob & { name?: string },
  onProgress: (fraction: number) => void = () => {}
): Promise<string> {
  const fileExtension = extensionOf(file)
  const id = await transport.post({ type: 'beginUpload', fileExtension, size: file.size })
  if (typeof id !== 'string') throw new Error('beginUpload: native side returned no id')
  try {
    for (let offset = 0; offset < file.size; offset += UPLOAD_CHUNK) {
      const dataBase64 = await blobToBase64(file.slice(offset, offset + UPLOAD_CHUNK))
      await transport.post({ type: 'uploadChunk', id, dataBase64 })
      onProgress(Math.min(1, (offset + UPLOAD_CHUNK) / file.size))
    }
    const url = await transport.post({ type: 'finishUpload', id })
    if (typeof url !== 'string') throw new Error('finishUpload: native side returned no URL')
    return url
  } catch (error) {
    transport.post({ type: 'cancelUpload', id }).catch((cancelError: unknown) => {
      // Can't route through the transport that just failed.
      console.error('[hikki] bridge post failed', 'cancelUpload', cancelError)
    })
    throw error
  }
}

/** Hands an image to the native side for storage; resolves to the URL to reference it by. */
export async function saveAsset(
  transport: Transport,
  file: Blob,
  fileExtension: string
): Promise<string> {
  const dataBase64 = await blobToBase64(file)
  const url = await transport.post({ type: 'saveAsset', fileExtension, dataBase64 })
  if (typeof url !== 'string') throw new Error('saveAsset: native side returned no URL')
  return url
}
