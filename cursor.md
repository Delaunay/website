# Okaasan website — project context for AI assistants

Read this file before changing the frontend, backend, static build, or deployment.

## Repository layout

| Path | Role |
|------|------|
| `database.db`, `uploads/` | **Data** (SQLite + media). Set `OKAASAN_DATA` or `FLASK_STATIC` to this repo root in dev/build. |
| `recipes/okaasan/` | **Application package** (FastAPI server, React UI, CLI). Installed with `pip install -e recipes`. |
| `recipes/okaasan/ui/` | React + Vite + TypeScript frontend |
| `recipes/okaasan/server/` | FastAPI API and static file serving |
| `recipes/okaasan/cli/staticwebsite.py` | Static site generator (`okaasan static`) |
| `static_build/` | Output of static generation (deployed to GitHub Pages) |
| `static/` | **Legacy** pre-built UI only — no `api/` JSON; do not use for Pages deploy |

## Three ways the site runs

### 1. Local development (dynamic, two processes)

**Use when:** editing features, writing to the DB, uploads, health sync, tasks, etc.

| Process | Command | Port / URL |
|---------|---------|------------|
| API | `make back-dev` → `uvicorn okaasan.server.run:entry` with `FLASK_STATIC=$(pwd)` | `http://localhost:5001` |
| UI | `make front-dev` → `npm run dev` in `recipes/okaasan/ui` | `http://localhost:3000` |

**How API calls work:**

- Frontend uses `API_BASE_URL` default `/api` (`recipes/okaasan/ui/src/services/api.ts`).
- Vite proxies `/api/*` → `localhost:5001` and **strips** the `/api` prefix (`vite.config.ts`).
- FastAPI routes are registered **without** `/api` (e.g. `GET /recipes`, not `/api/recipes`).

**Env:**

- `FLASK_STATIC` or `OKAASAN_DATA` → repo root so `database.db` and `uploads/` resolve correctly.

**Static mode is off:** `VITE_USE_STATIC_MODE` is unset; all HTTP methods work; WebSocket `/api/ws` works.

---

### 2. Production server (dynamic, single process)

**Use when:** running the app on a machine with live data (NAS, VPS, systemd).

- `make back-prod` or uvicorn on port 8081.
- UI is the **bundled** build in `recipes/okaasan/server/static/` (built with `VITE_API_URL=` empty and `VITE_BASE_PATH=/` — see `recipes/Makefile`).
- FastAPI serves assets and SPA; `_StripApiPrefix` middleware rewrites incoming `/api/…` to `/…` (same as Vite proxy in dev).
- Still uses live SQLite + uploads under `OKAASAN_DATA` / `FLASK_STATIC`.

---

### 3. GitHub Pages (static, no backend)

**Use when:** public read-only site from this data repo.

**Build** (CI: `.github/workflows/deploy.yml` or locally):

```bash
export OKAASAN_DATA=/path/to/this/repo   # must contain database.db
okaasan static \
  --output ./static_build \
  --base_path "/website/" \
  --api_url "/website/api"
```

**Important:** CI must install okaasan from **git** (`pip install -e`), not PyPI, unless you know the published wheel matches this tree.

**Build steps:**

1. Crawl all GET routes marked with `@expose()` → write `static_build/api/<path>.json` (e.g. `/recipes` → `api/recipes.json`, `/recipes/18` → `api/recipes/18.json`).
2. Generate recipe slug files (`/recipes/fresh-berries-tart.json`) for name-based URLs.
3. Build React with `VITE_USE_STATIC_MODE=true`, `VITE_BASE_PATH`, `VITE_API_URL`.
4. Copy `ui/dist` into `static_build/`, copy `uploads/` to `uploads/` and `api/uploads/`.

**How API calls work in the browser:**

- `isStaticMode()` is true when `VITE_USE_STATIC_MODE === 'true'`.
- `recipeAPI.request()` only allows **GET**; it fetches pre-generated JSON:
  - `GET /recipes` → fetch `/website/api/recipes.json`
  - `GET /recipes/18` → fetch `/website/api/recipes/18.json`
- No server: POST/PUT/DELETE throw or are gated with `isStaticMode()` checks in UI.
- Articles in static build use `X-Public-Only: true` and `public_articles_only()` so private articles are excluded.

**Routing:** `HashRouter` in `App.tsx` — paths are `https://user.github.io/website/#/recipes`, etc.

**Images:** `imagePath()` prepends `SITE_BASE` (`VITE_BASE_PATH`) and `/api` for `/uploads/…` paths.

---

## Frontend configuration (Vite env)

| Variable | Dev (default) | Static Pages build |
|----------|---------------|---------------------|
| `VITE_USE_STATIC_MODE` | unset / `false` | `true` |
| `VITE_API_URL` | `/api` | `/website/api` (or `/{repo}/api`) |
| `VITE_BASE_PATH` | `/` | `/website/` (must match Pages project path) |

Defined in: `recipes/okaasan/ui/src/services/api.ts`, `jsonstore.ts`, `vite.config.ts` (`base`).

---

## Backend: exposing data for static crawl

Static JSON is generated only for routes decorated with `@expose()` in `recipes/okaasan/server/decorators.py`.

- List/collection: `@expose()` with no args → one JSON file for the route.
- Parameterized: `@expose(recipe_id=select(Recipe._id))` → one file per ID.
- Implementations live in route modules (`recipe/routes.py`, `articles/routes.py`, etc.).

When adding a **new read-only GET endpoint** needed on GitHub Pages:

1. Add `@expose(...)` on the handler.
2. Re-run `okaasan static`.
3. Ensure the UI uses `recipeAPI.request()` (or `requestStatic` path) so static mode picks up `*.json`.

---

## Key files to touch by task

| Task | Files |
|------|--------|
| API behavior | `recipes/okaasan/server/**/routes.py`, `server.py` |
| Static crawl / deploy | `cli/staticwebsite.py`, `.github/workflows/deploy.yml` |
| Client API / static detection | `ui/src/services/api.ts`, `ui/src/services/jsonstore.ts` |
| Dev proxy / build base | `ui/vite.config.ts` |
| Sidebar / static visibility | `ui/src/layout/Layout.tsx`, `server.py` (`/sidebar`) |

---

## Frontend theming

The app supports **light and dark mode** via CSS custom properties defined in `recipes/okaasan/ui/src/theme.css`. The `.dark` class on `<html>` activates the dark palette (toggled by `next-themes`).

**Rule:** Never hardcode colors like `bg="blue.50"` or `borderColor="gray.200"` in components. Always use the CSS variables so both modes work.

### Core tokens (use these in components)

| Token | Purpose |
|-------|---------|
| `var(--card-bg)` | Card / elevated surface background |
| `var(--card-bg-raised)` | Higher-contrast card (modals, popovers) |
| `var(--surface-muted)` | Subtle background (empty states, placeholders) |
| `var(--input-bg)` | Input field background |
| `var(--border-color)` | Default border for cards, inputs, dividers |
| `var(--panel-border)` | Slightly stronger border for panels |
| `var(--muted-text)` | Secondary / helper text |
| `var(--empty-text)` | Placeholder / empty state text |
| `var(--heading-color)` | Section headings |
| `var(--hover-bg)` | Hover state background |
| `var(--selected-bg)` | Active/selected item background |
| `var(--icon-color)` | Icon accent color (links, actions) |

### Colored panels (semantic variants)

For colored highlight boxes, use the `--panel-{color}-*` family (`blue`, `orange`, `purple`, `teal`, `red`, `green`):

```
bg="var(--panel-blue-bg)"
borderColor="var(--panel-blue-border)"
color="var(--panel-blue-text)"
```

### Exceptions

- Chakra `colorPalette` on `<Badge>`, `<Button>` is fine — these adapt automatically.
- Semantic colors for data viz (rating bars, status indicators) can use Chakra palette tokens like `green.400` since they're intentionally vivid in both modes.
- The `VegaPlot` component auto-applies dark theme from `vega-themes` when `colorMode === 'dark'`.

### Pattern in components

```tsx
const cardBg = 'var(--card-bg)';
const border = 'var(--border-color)';
const mutedText = 'var(--muted-text)';
```

Or inline: `<Box bg="var(--card-bg)" borderColor="var(--border-color)">`.

---

## Common pitfalls

1. **404 on GitHub Pages for recipes** — Static JSON missing: rebuild with `OKAASAN_DATA` pointing at repo with `database.db`; verify `static_build/api/recipes.json` exists; CI must not install stale PyPI `okaasan`.
2. **`isStaticMode()` false in production build** — Forgot `VITE_USE_STATIC_MODE=true` during `vite build`.
3. **Wrong API URL** — `VITE_API_URL` must match where JSON files are hosted (e.g. `/website/api`, no trailing slash).
4. **Confusing `static/` vs `static_build/`** — Only `static_build/` from `okaasan static` has `api/*.json`.
5. **Dev 404 on `/api/...`** — Backend not running or `FLASK_STATIC` not set to data directory.
6. **Writes in static UI** — Guard with `isStaticMode()`; static site is read-only.

---

## Quick commands (from repo root)

```bash
# Dev
make install          # pip install -e recipes
make back-dev         # API :5001
make front-dev        # UI :3000

# Static site (local test)
OKAASAN_DATA=$(pwd) okaasan static --output ./static_build --base_path /website/ --api_url /website/api

# DB migrations
make update-db
```
