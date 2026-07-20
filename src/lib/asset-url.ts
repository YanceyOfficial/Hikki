export function protocolAssetUrl(docId: string, fileName: string): string {
  const path = `${encodeURIComponent(docId)}/${encodeURIComponent(fileName)}`
  return navigator.userAgent.includes('Windows')
    ? `http://hikki-asset.localhost/${path}`
    : `hikki-asset://localhost/${path}`
}
