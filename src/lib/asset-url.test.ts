import { protocolAssetUrl } from '#lib/asset-url'

test('builds custom-scheme URL on non-Windows', () => {
  expect(protocolAssetUrl('doc-1', 'img.png')).toBe(
    'hikki-asset://localhost/doc-1/img.png'
  )
})

test('encodes unusual characters', () => {
  expect(protocolAssetUrl('doc-1', 'a b.png')).toBe(
    'hikki-asset://localhost/doc-1/a%20b.png'
  )
})
