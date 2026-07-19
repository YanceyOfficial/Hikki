# Hikki — Product & Engineering Specification

Build a Notion-like note-taking application called **Hikki**.

## Tech Stack

The frontend stack is already initialized with the following technologies:

- Tauri
- React
- React Router _(desktop applications should use `createHashRouter`)_
- Tailwind CSS
- shadcn/ui
- Lucide React
- Jotai
- Immer

A basic UI template has already been prepared, and you are free to refactor or redesign it extensively.

---

# Engineering Requirements

## 1. UI Components

- **Always prioritize shadcn/ui components. Do not reinvent existing UI components.** This is extremely important.
- Base UI components are located under `src/components/ui`.
- If a required component has not yet been installed, install it using the official shadcn CLI/workflow rather than implementing a custom version.

---

## 2. Testing (TDD)

Every new feature or bug fix **must** include tests.

Adopt a strict **Test-Driven Development (TDD)** workflow.

Testing stack:

- Unit tests: **Vitest**
- End-to-end tests: **Playwright**

Whenever generating React (`.tsx`) components, proactively add `data-testid="..."` attributes at critical interaction points to simplify Playwright selectors.

These attributes should:

- remain in the source code during development;
- be stripped from production builds.

---

## 3. macOS Window Experience

Provide a polished macOS-native experience.

Requirements:

- Proper handling of the macOS traffic-light window controls.
- Support both fullscreen and windowed modes.
- Ensure the traffic-light buttons never overlap with header UI elements.
- Consider abstracting this into a reusable layout component since multiple pages may require the same behavior in the future.
- Add `data-tauri-drag-region` to appropriate header areas to support window dragging.

---

## 4. Editor

The editor is the heart of the application.

Use **BlockNote**:

https://www.blocknotejs.org/docs/reference/editor/overview

Study the documentation thoroughly before implementation.

Focus especially on:

- multimedia support
- image insertion
- file attachments
- embeds
- extensibility

The required packages have already been installed.

---

## 5. AI Integration

BlockNote's built-in AI features are only available in its commercial package.

Instead, implement our own AI layer.

The interaction should resemble **Apple Intelligence Writing Tools** on iPhone.

A reference screenshot (`IMG_6065.jpeg`) has been placed in the project root. It may be deleted after implementation.

AI backend:

https://github.com/earendil-works/pi/tree/main

Initially support:

- OpenAI
- Anthropic

Use each provider's latest flagship and recommended models.

Allow users to switch models through a dropdown selector.

---

## 6. Experimental Voice Input

Experimentally support AI-powered voice input.

This includes:

- speech-to-text
- AI prompt dictation

Useful UI components may be taken from:

https://ui.elevenlabs.io/docs

For implementation ideas, refer to:

`~/code/exodus/exodus`

---

## 7. Settings

Design a comprehensive Settings experience.

Use:

`src/components/settings-dialog.tsx`

---

## 8. Toasts & Error Management

Implement a unified frontend notification system.

Requirements:

- global toast notifications
- centralized error management
- standardized error codes
- structured logging

Create a dedicated **Logs** section inside **Settings** to:

- collect logs
- inspect logs
- manage logs

---

## 9. Auto Update

Implement an application update system using:

- GitHub Releases
- GitHub Actions

Inside **Settings**, display:

- current version
- latest version
- update status

If an update is available, display an upgrade button in an appropriate location on the main interface (for example, the top-right corner).

---

## 10. Dashboard

Design a rich Dashboard experience.

Leverage:

- `src/components/ui/chart.tsx`
- `src/components/ui/calendar.tsx`

Be creative.

The dashboard should feel informative, modern, and visually impressive.

---

## 11. Additional Features

Brainstorm additional features inspired by Notion.

Examples include:

- page covers
- emojis
- icons
- templates
- favorites
- backlinks
- slash commands
- quick search
- recent pages
- keyboard shortcuts

Aim to build a feature-rich product rather than merely replicating the basics.

---

## 12. Leverage Tauri

Take full advantage of Tauri and Rust whenever appropriate.

Continuously think through:

- architecture
- performance
- security
- UX
- technical design
- documentation
- implementation strategy

Use your available capabilities proactively throughout development.

---

## 13. Documentation

As development progresses, continuously keep project documentation synchronized.

Examples include:

- `CLAUDE.md`
- `README.md`

The documentation should evolve alongside the implementation rather than being updated afterward.

---

# Data Storage Architecture Discussion

Each document should have a UUID.

A document consists of:

- BlockNote document structure
- multimedia assets
- nested child documents

The hierarchy should naturally support unlimited nesting.

---

## Option 1 — Local-first Storage

Adopt a local-first architecture similar to Obsidian.

Potentially integrate with iCloud if feasible.

Advantages:

- Simple architecture
- Native cloud synchronization through iCloud
- Easy migration between devices
- User retains ownership of data
- Excellent offline experience

---

## Option 2 — Database-backed Storage

Use a database architecture similar to:

`~/code/exodus/exodus`

Suggested stack:

- Drizzle ORM
- PGlite

Advantages:

- Easier future migration to cloud infrastructure
- Well-structured data model
- Better support for backend features
- Ideal for document sharing
- Better foundation for real-time collaboration

Future cloud architecture could look like:

- PostgreSQL
- Object Storage (S3-compatible)

One additional question worth investigating:

Can database files themselves be synchronized through iCloud while preserving data integrity and avoiding synchronization conflicts?
