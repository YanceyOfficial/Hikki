import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import {
  searchUnsplash,
  trackUnsplashDownload,
  UNSPLASH_HOME,
  UnsplashError,
  type UnsplashPhoto
} from '../src/lib/unsplash'
import { CoverPicker, PhotoCredit } from '../src/page/cover-picker'

const photo: UnsplashPhoto = {
  id: 'abc',
  thumb: 'https://images.unsplash.com/t',
  regular: 'https://images.unsplash.com/r',
  full: 'https://images.unsplash.com/f',
  color: '#000',
  alt: 'storm',
  author: 'Jeremy Bishop',
  authorUrl: 'https://unsplash.com/@jb?utm_source=hikki&utm_medium=referral',
  photoUrl: 'https://unsplash.com/photos/abc?utm_source=hikki&utm_medium=referral',
  downloadLocation: 'https://api.unsplash.com/photos/abc/download'
}

describe('unsplash client', () => {
  it('queries the BFF, never Unsplash directly', async () => {
    const fetcher = vi.fn<typeof fetch>(
      async () => new Response(JSON.stringify({ photos: [photo], totalPages: 1 }))
    )
    const page = await searchUnsplash(' sea ', 2, 'https://bff.example', fetcher)
    expect(String(fetcher.mock.calls[0]?.[0])).toBe(
      'https://bff.example/api/unsplash/photos?query=sea&page=2'
    )
    expect(page.photos).toEqual([photo])
  })

  it('maps 403 to a rate-limit error and fails clearly when unconfigured', async () => {
    const fetcher = vi.fn(async () => new Response('{}', { status: 403 }))
    await expect(
      searchUnsplash('x', 1, 'https://bff.example', fetcher as unknown as typeof fetch)
    ).rejects.toMatchObject({
      message: 'rate_limited',
      status: 403
    })
    await expect(searchUnsplash('x', 1, null)).rejects.toBeInstanceOf(UnsplashError)
  })

  it('reports a pick to the download endpoint', () => {
    const fetcher = vi.fn<typeof fetch>(async () => new Response(null, { status: 204 }))
    trackUnsplashDownload(photo, 'https://bff.example', fetcher)
    expect(fetcher).toHaveBeenCalledWith(
      'https://bff.example/api/unsplash/download',
      expect.objectContaining({ method: 'POST' })
    )
    const init = fetcher.mock.calls[0]?.[1]
    expect(JSON.parse(String(init?.body))).toEqual({ downloadLocation: photo.downloadLocation })
  })
})

function renderPicker(onSelect = vi.fn()) {
  render(
    <CoverPicker
      current={null}
      onSelect={onSelect}
      onRemove={vi.fn()}
      onUpload={vi.fn(async () => {})}
    />
  )
  return onSelect
}

describe('CoverPicker tabs', () => {
  afterEach(cleanup)

  it('Link accepts only https image links', () => {
    const onSelect = renderPicker()
    fireEvent.click(screen.getByRole('tab', { name: 'Link' }))
    const input = screen.getByLabelText('Image link')
    const submit = screen.getByRole('button', { name: 'Submit' })
    fireEvent.change(input, { target: { value: 'javascript:alert(1)' } })
    expect((submit as HTMLButtonElement).disabled).toBe(true)
    fireEvent.change(input, { target: { value: 'https://example.com/a.jpg' } })
    fireEvent.click(submit)
    expect(onSelect).toHaveBeenCalledWith('https://example.com/a.jpg')
  })

  it('Unsplash shows skeletons while a search is on its way, then the photos', async () => {
    vi.stubEnv('VITE_HIKKI_BFF_URL', 'https://bff.example')
    // Held until the test answers.
    const answers: Array<(r: Response) => void> = []
    const pending = new Promise<Response>((resolve) => answers.push(resolve))
    vi.stubGlobal(
      'fetch',
      vi.fn(() => pending)
    )
    try {
      renderPicker()
      fireEvent.click(screen.getByRole('tab', { name: 'Unsplash' }))
      expect(screen.getAllByTestId('unsplash-skeleton')).toHaveLength(9)
      await act(async () => {
        await new Promise((r) => setTimeout(r, 350))
        answers[0]?.(new Response(JSON.stringify({ photos: [photo], totalPages: 1 })))
        await new Promise((r) => setTimeout(r, 0))
      })
      expect(screen.queryAllByTestId('unsplash-skeleton')).toHaveLength(0)
      expect(screen.getByRole('link', { name: 'Jeremy Bishop' })).toBeTruthy()
    } finally {
      vi.unstubAllGlobals()
      vi.unstubAllEnvs()
    }
  })

  it('Unsplash explains when the build has no BFF configured', () => {
    renderPicker()
    fireEvent.click(screen.getByRole('tab', { name: 'Unsplash' }))
    expect(screen.getByText("Unsplash isn't configured for this build.")).toBeTruthy()
  })
})

describe('PhotoCredit', () => {
  afterEach(cleanup)

  it('credits the photographer and Unsplash, both linked with utm params', () => {
    render(<PhotoCredit photo={photo} />)
    const author = screen.getByRole('link', { name: 'Jeremy Bishop' })
    const unsplash = screen.getByRole('link', { name: 'Unsplash' })
    expect(author.getAttribute('href')).toBe(photo.authorUrl)
    expect(unsplash.getAttribute('href')).toBe(UNSPLASH_HOME)
    expect(UNSPLASH_HOME).toContain('utm_source=hikki&utm_medium=referral')
    expect(author.parentElement?.textContent).toBe('Photo by Jeremy Bishop on Unsplash')
  })
})
