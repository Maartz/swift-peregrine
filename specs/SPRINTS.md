# Peregrine — Sprint Plan

## Sprint 0: Foundation

**Goal:** Package compiles, re-exports work, `PeregrineApp` protocol exists.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 0.1 | Create `Package.swift` with all dependencies | 01 §2.2 | Package resolves and builds |
| 0.2 | `Exports.swift` — `@_exported import` for all sub-frameworks | 01 §2.3 | `import Peregrine` gives access to Nexus, Spectro, ESW, HTTPTypes |
| 0.3 | `PeregrineApp` protocol with `routes` requirement | 01 §2.4 | Protocol compiles, default extensions compile |
| 0.4 | `ServerConfig` struct with env var reading | 01 §2.6 | `PEREGRINE_HOST` / `PEREGRINE_PORT` or defaults |
| 0.5 | `Environment` enum + `Peregrine.env` | 04 §2.1 | Reads `PEREGRINE_ENV`, defaults to `.dev` |

**Exit criteria:** `swift build` passes. A minimal app conforming to `PeregrineApp` compiles.

---

## Sprint 1: Application Bootstrap

**Goal:** `PeregrineApp` boots a real server. Zero manual Hummingbird wiring.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 1.1 | `Database` config struct with env var defaults | 01 §2.5 | `Database.postgres()` reads `DB_HOST` etc. |
| 1.2 | Database name suffix convention (dev/test/prod) | 04 §2.4 | `_dev`/`_test` suffix in non-prod |
| 1.3 | Default `static func main()` implementation | 01 §2.7 | Creates SpectroClient, builds pipeline, boots Hummingbird |
| 1.4 | SpectroClient injection into pipeline via assign | 01 §2.9 | `SpectroKey` typed assign key |
| 1.5 | `conn.spectro` and `conn.repo()` accessors | 01 §2.9 | Route handlers access DB without parameter threading |
| 1.6 | `willStart(spectro:)` lifecycle hook | 01 §2.4 | Called after DB connect, before server accepts |
| 1.7 | `configure(for:)` environment hook | 04 §2.3 | Called during startup |
| 1.8 | Startup banner: `Peregrine running on http://...` | 01 §2.7 | Prints on boot, suppressed in test |
| 1.9 | Clean shutdown of SpectroClient on exit | 01 §2.7 | `defer` or structured concurrency |

**Exit criteria:** A `PeregrineApp` conformance with `database` and `routes` starts a working HTTP server.

---

## Sprint 2: Built-in Plugs & Environment Behavior

**Goal:** Ship the plugs and environment-aware defaults that eliminate common boilerplate.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 2.1 | `responseTimer()` built-in plug | 01 §2.8 | Sets `X-Response-Time` header |
| 2.2 | Environment-aware JSON pretty-printing | 04 §2.2 | Pretty in dev, compact in prod |
| 2.3 | Environment-aware error detail | 04 §2.2, 05 §2.1 | Full detail in dev, generic in prod |
| 2.4 | Default error rescue with content negotiation | 05 §2.1 | JSON errors for JSON requests, HTML for HTML requests |
| 2.5 | Dev error page (styled HTML) | 05 §2.3 | Error type, message, request info, pipeline trace, assigns |
| 2.6 | Prod error page (clean minimal) | 05 §2.1 | Status + generic message only |
| 2.7 | Custom error page support (`Views/errors/404.esw`) | 05 §2.2 | Override default pages with templates |
| 2.8 | Infrastructure error logging (server-side) | 05 §2.4 | Always log full error, regardless of env |

**Exit criteria:** App handles errors gracefully across all environments. Dev shows debug info, prod shows clean pages.

---

## Sprint 3: Testing

**Goal:** `PeregrineTest` library lets you test an app without starting a server.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 3.1 | `PeregrineTest` target in Package.swift | 03 §2.6 | New library product |
| 3.2 | `TestApp` harness — runs pipeline without server | 03 §2.1 | Instantiate from any `PeregrineApp` |
| 3.3 | `get`, `post`, `put`, `delete` request methods | 03 §2.2 | Convenience methods returning `TestResponse` |
| 3.4 | `TestResponse` struct | 03 §2.3 | `status`, `headers`, `body`, `text`, `json`, `decode(as:)`, `cookies` |
| 3.5 | Database override in TestApp | 03 §2.4 | `.postgres(database: "test_db")` or `nil` |
| 3.6 | Assign/session injection in test requests | 03 §2.5 | Pre-populate assigns for authenticated routes |
| 3.7 | Self-tests for PeregrineTest | 03 §3 | Test the test framework with a minimal fixture app |

**Exit criteria:** A test suite using `TestApp` runs without ports, without a real server, and exercises the full pipeline.

---

## Sprint 4: CLI — Project Scaffolding

**Goal:** `peregrine new MyApp` generates a buildable, runnable project.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 4.1 | `PeregrineCLI` executable target with ArgumentParser | 02 §3 | Top-level command group |
| 4.2 | `peregrine new <AppName>` command | 02 §2.1 | Generates project directory with all files |
| 4.3 | Project template: `Package.swift` | 02 §2.1 | Correct Peregrine dependency |
| 4.4 | Project template: `App.swift` | 02 §2.1 | Minimal `PeregrineApp` conformance |
| 4.5 | Project template: `layout.esw` | 02 §2.1 | Default HTML layout |
| 4.6 | Project template: `.gitignore`, `.swift-format` | 02 §2.1 | Standard Swift ignores + formatting |
| 4.7 | `--no-db` flag | 02 §2.1 | Omits database config |
| 4.8 | `--no-esw` flag | 02 §2.1 | Omits Views directory and plugin |
| 4.9 | File creation logging | 02 §4 | Prints `create path/to/file` for each file |
| 4.10 | "Next steps" output | 02 §2.1 | `cd AppName && swift run` |

**Exit criteria:** `peregrine new TestApp && cd TestApp && swift run` works first try.

---

## Sprint 5: CLI — Code Generators

**Goal:** `gen.schema`, `gen.json`, `gen.html` produce correct, buildable code.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 5.1 | `peregrine gen.schema <Name> <fields...>` | 02 §2.2 | Generates `@Schema` model + SQL migration |
| 5.2 | Field type mapping (string, int, double, bool, uuid, date) | 02 §2.2 | All types produce correct Swift + Postgres |
| 5.3 | `:references` modifier | 02 §2.2 | FK constraint + `@ForeignKey` wrapper |
| 5.4 | `:optional` modifier | 02 §2.2 | `T?` + drops `NOT NULL` |
| 5.5 | `peregrine gen.json <Name> <fields...>` | 02 §2.3 | Model + migration + CRUD route file |
| 5.6 | `peregrine gen.html <Name> <fields...>` | 02 §2.4 | Model + migration + routes + `.esw` templates |
| 5.7 | `peregrine migrate up/down/status` | 02 §2.5 | Delegates to Spectro migration system |
| 5.8 | `peregrine server` | 02 §2.6 | `swift run` wrapper |
| 5.9 | Project structure discovery from `Package.swift` | 02 §4 | CLI finds correct source directories |

**Exit criteria:** `peregrine new Blog && cd Blog && peregrine gen.json Post title:string body:string && swift run` produces a working CRUD API.

---

## Sprint 6: DonutShop Migration

**Goal:** Migrate DonutShop to Peregrine. Prove the framework works.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 6.1 | Update `Package.swift` to depend on Peregrine only | 06 §2.1 | 1 dependency instead of 4 |
| 6.2 | Rewrite `App.swift` using `PeregrineApp` | 06 §2.2 | < 30 lines |
| 6.3 | Remove `db: DB` from all route functions | 06 §2.3 | Use `conn.repo()` instead |
| 6.4 | Replace `import Spectro` / `import Nexus` with `import Peregrine` | 06 §2.4 | Single import everywhere |
| 6.5 | Delete `DB` struct, `Helpers.swift`, `setupDatabase()` | 06 §2.5 | Dead code removal |
| 6.6 | Update tests to use `PeregrineTest` | 06 §2.6 | `TestApp`-based tests |
| 6.7 | Run `test.sh` — all endpoints return same responses | 06 §4 | Behavioral equivalence |
| 6.8 | Measure before/after metrics | 06 §3 | Lines, imports, dependencies |

**Exit criteria:** DonutShop works identically with less code. All tests pass. `test.sh` passes unchanged.

---

## Sprint 7: Flash Messages

**Goal:** Write-once, read-once messages that survive exactly one redirect.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 7.1 | `flashPlug()` — reads from session, clears after read | 07 §2.1 | Plug function |
| 7.2 | `conn.putFlash(.info, "msg")` helper | 07 §2.2 | Connection extension |
| 7.3 | `conn.flash` accessor with `.info`, `.error`, `.warning` | 07 §2.2 | `Flash` struct |
| 7.4 | Session storage as JSON under `_flash` key | 07 §2.3 | Serialize/deserialize |
| 7.5 | Template integration — flash available in assigns | 07 §2.4 | Auto-injected |
| 7.6 | Tests: survives redirect, displays once, multiple levels | 07 §3 | Test suite |

**Exit criteria:** `putFlash(.info, "Created!")` in a POST handler displays the message once after redirect, then it's gone.

---

## Sprint 8: CSRF Protection

**Goal:** State-changing requests are protected from cross-site forgery by default.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 8.1 | `csrfProtection()` plug with token generation | 08 §2.1 | Plug function |
| 8.2 | Token validation on POST/PUT/PATCH/DELETE | 08 §2.1 | 403 on mismatch |
| 8.3 | Skip validation for JSON requests | 08 §2.1 | Content-Type check |
| 8.4 | `csrfToken` injected into assigns for templates | 08 §2.2 | Template helper |
| 8.5 | `except:` parameter to skip specific paths | 08 §2.1 | Webhook support |
| 8.6 | Token read from `_csrf_token` param or `x-csrf-token` header | 08 §2.1 | Dual source |
| 8.7 | Tests: valid token passes, missing rejects, JSON skips | 08 §3 | Test suite |

**Exit criteria:** HTML form submissions without a valid CSRF token get 403. JSON API requests are unaffected.

---

## Sprint 9: Static File Serving

**Goal:** Drop files in `Public/`, they're served. No configuration.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 9.1 | `staticFiles()` plug serving from `Public/` | 09 §2.1 | Plug function |
| 9.2 | MIME type detection from file extension | 09 §2.3 | Content-Type mapping |
| 9.3 | Path traversal prevention (`..` rejection) | 09 §2.4 | Security check |
| 9.4 | Hidden file protection (no `.env` serving) | 09 §2.4 | Dot-file skip |
| 9.5 | Environment-aware cache headers | 09 §2.5 | `no-cache` in dev, `max-age` in prod |
| 9.6 | Update `peregrine new` to create `Public/` directory | 09 §2.6 | CLI update |
| 9.7 | Tests: serves files, rejects traversal, correct MIME types | 09 §3 | Test suite |

**Exit criteria:** CSS/JS/images in `Public/` are served with correct content types and cache headers.

---

## Sprint 10: Authentication Generator

**Goal:** `peregrine gen.auth` generates a complete, working auth system.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 10.1 | User and UserToken model templates | 10 §2.1-2.2 | Generated Swift models |
| 10.2 | SQL migrations with indexes | 10 §2.3 | Generated SQL |
| 10.3 | Password hashing with bcrypt | 10 §2.5 | `Auth.hashPassword` / `verifyPassword` |
| 10.4 | Auth routes: register, login, logout | 10 §2.4 | Generated route file |
| 10.5 | `requireAuth()` plug | 10 §2.6 | Middleware plug |
| 10.6 | Session token flow (create, verify, delete) | 10 §2.7 | Token lifecycle |
| 10.7 | Login and register ESW templates | 10 §2.8 | Generated templates |
| 10.8 | Validation: email uniqueness, password length | 10 §2.9 | Input validation |
| 10.9 | `peregrine gen.auth` CLI command wiring | 10 §2 | CLI integration |
| 10.10 | Tests: register, login, logout, requireAuth | 10 §3 | Test suite |

**Exit criteria:** `peregrine gen.auth && swift build` produces a working registration and login system.

---

## Sprint 11: Deployment Tooling & Token Signing

**Goal:** Production-ready with `peregrine gen.dockerfile` and `PeregrineToken` for signed URLs.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 11.1 | `peregrine gen.dockerfile` command | 11 §2.1 | Generates Dockerfile + .dockerignore |
| 11.2 | Multi-stage Dockerfile with layer caching | 11 §2.2 | Optimized build |
| 11.3 | `.dockerignore` generation | 11 §2.3 | Exclude build artifacts |
| 11.4 | `PeregrineToken.sign` with HMAC-SHA256 | 11 §2.5 | Token creation |
| 11.5 | `PeregrineToken.verify` with expiry support | 11 §2.5 | Token validation |
| 11.6 | URL-safe token format (base64url) | 11 §2.6 | Compact tokens |
| 11.7 | `PEREGRINE_SECRET` convention | 11 §2.8 | Env var convention |
| 11.8 | Tests: sign/verify, expiry, tamper detection | 11 §3 | Test suite |

**Exit criteria:** `docker build -t myapp . && docker run -p 8080:8080 myapp` works. Tokens can be signed, verified, and expire correctly.

---

## Sprint 12: Asset Pipeline & Default Styling

**Goal:** Generated pages look professional by default. Pico CSS out of the box, Tailwind opt-in.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 12.1 | Download Pico CSS on `peregrine new` | 12 §2.2 | `Public/css/pico.min.css` |
| 12.2 | `--color` flag with all 19 Pico themes | 12 §2.1 | `pico.{color}.min.css` |
| 12.3 | Generate styled `layout.esw` with Pico link | 12 §2.2 | Semantic HTML layout |
| 12.4 | `Public/css/app.css` for custom overrides | 12 §2.2 | Override file |
| 12.5 | Update `gen.html` to produce Pico-compatible HTML | 12 §2.3 | Semantic templates |
| 12.6 | Update `gen.auth` templates for Pico styling | 12 §2.3 | Styled forms |
| 12.7 | `--tailwind` flag: download CLI binary | 12 §2.5-2.6 | Standalone binary |
| 12.8 | `--tailwind`: generate config + input.css | 12 §2.7 | Tailwind setup |
| 12.9 | `peregrine build` command (assets + Swift) | 12 §2.8 | Build pipeline |
| 12.10 | Tests: color validation, file download, mutual exclusion | 12 §3 | Test suite |

**Exit criteria:** `peregrine new MyApp && swift run` serves styled pages. `peregrine new MyApp --tailwind` sets up Tailwind with no Node dependency.

---

## Sprint 13: Development Server with Watch Mode

**Goal:** `peregrine build --watch` gives you edit-save-see in seconds.

| # | Task | Spec | Deliverable |
|---|------|------|-------------|
| 13.1 | `peregrine build` command (assets + Swift) | 13 §2.1 | Unified build |
| 13.2 | File watcher for `.swift` and `.esw` changes | 13 §2.3 | OS-native or polling |
| 13.3 | `--watch` mode: rebuild + restart on change | 13 §2.2 | Watch loop |
| 13.4 | Debouncing (300ms) for rapid saves | 13 §2.2 | Debounce logic |
| 13.5 | Process management: start, SIGTERM, restart | 13 §2.4 | Child process lifecycle |
| 13.6 | Build failure handling (keep old server alive) | 13 §2.5 | Error resilience |
| 13.7 | Tailwind watch integration (parallel process) | 13 §2.6 | CSS live rebuild |
| 13.8 | `peregrine server` as alias for `build --watch` | 13 §2.7 | Alias command |
| 13.9 | Ignore temp files (`.swp`, `~`, `.tmp`) | 13 §3 | Editor compatibility |
| 13.10 | Clean `Ctrl+C` shutdown of all child processes | 13 §2.4 | Signal handling |

**Exit criteria:** `peregrine build --watch` starts the server and automatically rebuilds + restarts when source files change. Build errors don't kill the running server.

---

## Dependency Graph

```
Sprint 0 (foundation)
    │
Sprint 1 (bootstrap)
    │
    ├── Sprint 2 (plugs + env)
    │       │
    │       └── Sprint 3 (testing)
    │
    └── Sprint 4 (CLI scaffolding)
            │
            └── Sprint 5 (CLI generators)
                    │
                    All ──→ Sprint 6 (DonutShop migration)
                              │
              ┌───────────────┼───────────────┐
              │               │               │
        Sprint 7        Sprint 8        Sprint 9
       (flash msgs)    (CSRF)         (static files)
              │               │               │
              └───────┬───────┘               │
                      │                       │
                Sprint 12 ◄───────────────────┘
              (asset pipeline)
                      │
              ┌───────┴───────┐
              │               │
        Sprint 10       Sprint 13
        (gen.auth)      (dev server)
              │
        Sprint 11
    (deploy + tokens)
```

Sprints 7–9 can run in parallel. Sprint 12 depends on 9 (static files).
Sprint 10 depends on 8 (CSRF) and 12 (styled templates).
Sprint 13 depends on 12 (build command).
Sprint 11 can start after 10 or in parallel.

---

## Summary

| Sprint | Focus | Key Deliverable |
|--------|-------|-----------------|
| 0 | Foundation | Package compiles, protocol exists |
| 1 | Bootstrap | App boots a server with one protocol conformance |
| 2 | DX polish | Error pages, env-aware defaults, response timer |
| 3 | Testing | `TestApp` — test without a server |
| 4 | CLI: new | `peregrine new` generates runnable project |
| 5 | CLI: gen | `gen.schema`, `gen.json`, `gen.html`, `migrate` |
| 6 | Proof | DonutShop migrated, framework validated |
| 7 | Flash messages | Write-once read-once messages across redirects |
| 8 | CSRF protection | Automatic form token validation |
| 9 | Static files | Serve CSS/JS/images from `Public/` |
| 10 | Auth generator | `peregrine gen.auth` — register, login, logout |
| 11 | Production | Dockerfile generation, signed tokens |
| 12 | Asset pipeline | Pico CSS default, Tailwind opt-in, `peregrine build` |
| 13 | Dev server | `peregrine build --watch` with auto-rebuild |
