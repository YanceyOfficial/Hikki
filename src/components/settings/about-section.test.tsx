import { render, screen, waitFor } from '@testing-library/react'
import { test, expect, vi } from 'vitest'

vi.mock('@tauri-apps/api/app', () => ({
  getVersion: vi.fn().mockResolvedValue('0.1.0')
}))

import { AboutSection } from '#components/settings/about-section'

test('shows the app version', async () => {
  render(<AboutSection />)
  await waitFor(() =>
    expect(screen.getByTestId('app-version')).toHaveTextContent('0.1.0')
  )
})
