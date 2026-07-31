import { fetch as tauriFetch } from '@tauri-apps/plugin-http'
import React from 'react'
import ReactDOM from 'react-dom/client'
import { createHashRouter, RouterProvider } from 'react-router'

import { AppShell } from '#components/app-shell'
import { ThemeProvider } from '#components/theme-provider'
import { isTauri } from '#lib/backend/index'
import { createScopedFetch } from '#lib/scoped-fetch'
import DashboardPage from '#pages/dashboard-page'
import DocumentPage from '#pages/document-page'

if (isTauri()) {
  const nativeFetch = window.fetch.bind(window)
  window.fetch = createScopedFetch(
    nativeFetch,
    tauriFetch as unknown as typeof fetch
  )
}

const router = createHashRouter([
  {
    path: '/',
    Component: AppShell,
    children: [
      { index: true, Component: DashboardPage },
      { path: 'doc/:id', Component: DocumentPage }
    ]
  }
])

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <ThemeProvider>
      <RouterProvider router={router} />
    </ThemeProvider>
  </React.StrictMode>
)
