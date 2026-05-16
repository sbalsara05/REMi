# REMi Design System

## Overview

REMi is a **dark-first**, glass-native chat shell with a consistent **ASCII animal-mouse** identity (not SVG silhouettes, not pointer/cursor icons). LibreChat upstream naming is removed from user-visible surfaces, static HTML, PWA install, auth, and locale copy.

**Key characteristics:**
- Default theme: dark (`#0a0a0f` canvas); light mode remains supported.
- Glass layer: `glass-panel`, `glass-bar`, `glass-composer`, `glass-card`, `glass-modal`, `glass-sheet`.
- ASCII marks in nav, stream carets, thinking idle, history, and landing hero.
- Whisker-stripe divider (violet → teal → blue) for brand moments only.
- `RemiAmbient` on main, auth, and share shells.

## Colors (dark default)

| Token | Value | Use |
|-------|--------|-----|
| Canvas | `#0a0a0f` | Page background, `theme-color`, PWA |
| Elevated glass | `#1a1a1a` / `#262626` | Panels, modals |
| Pearl text | `#f5f0eb` | Primary on dark |
| Body | `#bbbbbb` | Secondary copy |
| Muted | `#7e7e7e` | Captions |
| Brand purple | `#ab68ff` | Focus, badges, composer glow |
| Nose tint | `#e8b4b4` | Rare highlights only |
| Orbs | violet → teal → blue | Ambient mesh + stripe |

Light mode keeps LibreChat surface tokens with glass alphas tuned in `style.css`.

## Typography

**UI:** Inter (existing stack).

**ASCII tier:** `font-mono` / `ui-monospace` at 8–11px for nav icons and stream carets.

Sentence-case labels; uppercase only on small status badges.

## ASCII catalog

Source of truth: `librechat/client/src/components/Icons/asciiMouseCatalog.ts`  
Component: `AsciiMouse.tsx` (`data-testid="remi-ascii-mouse"`).

| Key | Example | Use |
|-----|---------|-----|
| `micro` | `()-()` | Nav icons, inline marks |
| `caret` | `(_)_">` | Stream / preview `::after` |
| `thinking` | `(o.o)` | Pre-token idle |
| `peek` | 2-line peek | History header, empty hero accent |
| `logoCompact` | 3-line mouse | Auth header |
| `logoHero` | 5-line mouse | Landing empty state |
| Shell keys | `(o.o)`, `(^.^)`, … | Side nav + chat chrome |

Stream CSS uses CSS variables `--remi-stream-caret`, `--remi-thinking-caret`, `--remi-stream-preview-caret` (no SVG mask).

## Static assets & meta

| Asset | Path |
|-------|------|
| Logo SVG | `public/assets/remi-logo.svg` |
| Favicons / PWA | `favicon-16x16.png`, `favicon-32x32.png`, `apple-touch-icon-180x180.png`, `icon-192x192.png`, `maskable-icon.png` |
| OG | `public/assets/og-image.png` (+ `og-image.svg` source) |

`index.html`: title/description **REMi**, `theme-color` `#0a0a0f`, Open Graph + Twitter tags.  
`vite.config.ts` PWA: `name` / `short_name` **REMi**, `theme_color` `#0a0a0f`.

Env: `APP_TITLE=REMi` in `env.local.example`.

## Motion

| Pattern | Duration | Use |
|---------|----------|-----|
| `remi-stream-pulse` | 1.4s | ASCII stream caret |
| `remi-thinking-pulse` | 1.8s | Thinking caret |
| `remi-preview-highlight` | 0.6s | Mouse History preview growth |
| `remi-fade-in` | 400ms | Main outlet enter |
| `glass-enter` + stagger | 45ms × index | History cards |
| `remi-mouse-icon-breathe` | 4s | Empty-state icon well |

Respect `prefers-reduced-motion` (animations disabled in `style.css`).

## Components

- **Auth:** `AuthLayout` — `RemiAmbient`, `AsciiMouse logoCompact`, `glass-modal` card.
- **Landing:** `logoHero` + whisker stripe above greeting.
- **Mouse History:** `glass-card` rows, `peek` header, ASCII card marks.
- **Chat chrome:** `ShellIcons` in header controls (sidebar, presets, bookmarks, temp chat).
- **Side nav:** ASCII attach / MCP when REMi enabled.

## File map

| Area | Path |
|------|------|
| Catalog | `librechat/client/src/components/Icons/asciiMouseCatalog.ts` |
| Renderer | `librechat/client/src/components/Icons/AsciiMouse.tsx` |
| Shell icons | `librechat/client/src/components/Icons/shellIcons.tsx` |
| Glass / stream CSS | `librechat/client/src/style.css` |
| Ambient | `librechat/client/src/components/Glass/RemiAmbient.tsx` |
| Dark theme RGB | `librechat/packages/client/src/theme/themes/dark.ts` |
| Config | `config/librechat.yaml` → `interface.remi` |

## Out of scope (v1)

- Provider logos in model picker
- Animated ASCII frame sequences
- Upstream package / API renames
