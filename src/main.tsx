import React from 'react'
import ReactDOM from 'react-dom/client'
import { createHashRouter, RouterProvider } from 'react-router'

import { AppShell } from '#components/app-shell'
import { ThemeProvider } from '#components/theme-provider'
import DashboardPage from '#pages/dashboard-page'
import DocumentPage from '#pages/document-page'

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
