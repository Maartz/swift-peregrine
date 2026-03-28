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

                    All ──→ Sprint 6 (DonutShop migration)
```

Sprints 2–3 and 4–5 can run in parallel tracks once Sprint 1 is done.

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
