# MapleCore Operations — Architecture

Native SwiftUI app for iPhone, **iOS 17+**, built with **Xcode 16+** (the project uses folder-synchronized
groups: any `.swift` file added under `MapleCore/`, `Shared/`, `MapleCoreWidgets/`, `MapleCoreTests/` or
`MapleCoreUITests/` is compiled automatically — never edit `project.pbxproj` to add files).

```
MapleCoreAPP/
├── MapleCore.xcodeproj           App, widget extension, unit + UI test targets; shared scheme "MapleCore"
├── Packages/MapleCoreKit/        Domain package (Foundation + Observation only, Swift 6 mode, builds on Linux)
│   ├── Sources/MapleCoreKit/
│   │   ├── Models/               Roles, Operations (properties, routes, stops, visits, photos), Messaging, Business, System
│   │   ├── Visit/VisitSession    Visit state machine (dates, pauses, photos) — timer derived from stored dates
│   │   ├── Store/AppStore        @MainActor @Observable single source of truth + local-first outbox
│   │   ├── Store/Persistence     JSON snapshot in Application Support (atomic writes)
│   │   ├── Services/AuthService  Mock code sign-in (demo code 123456), lockout, expiry
│   │   ├── Fixtures/             Preview data from the design canvas, anchored to "now"
│   │   └── Formatting/Fmt        Money (CAD), times, durations, spoken durations
│   └── Tests/                    33 unit tests (`swift test`)
├── MapleCore/                    App target
│   ├── App/                      MapleCoreApp, RootView, AppModel (tabs, paths, covers), Shells
│   ├── Core/DesignSystem/        Tokens (Palette, Space, Radius, Hit, Tone), Typography helpers
│   ├── Core/Components/          MCButton, Pill/StatusPill/SyncBadge, rows, state views, photo views
│   ├── Core/Navigation/          AppDestination + DestinationView
│   ├── Core/Persistence/         KeychainStore (session token), PhotoStorage (+ thumbnail cache)
│   ├── Core/Utilities/           Environment values (gloveMode, isRolePreview), Haptics, motion helpers
│   ├── Features/<Feature>/       Views (+ small view-local models where needed)
│   ├── PreviewSupport/           previewEnvironment()
│   └── Resources/                Assets, Info.plist (URL scheme)
├── Shared/                       Compiled into app + widget (Live Activity attributes, intents)
├── MapleCoreWidgets/             Widget extension: Live Activity / Dynamic Island
├── MapleCoreTests/               App-level unit tests
└── MapleCoreUITests/             UI tests for critical workflows
```

## State & data flow

- `AppStore` (MapleCoreKit) holds **all** domain data and exposes intent-named mutations
  (`send(_:to:visibility:)`, `arrive(routeID:stopID:)`, `submitVisit()`, `approveVisit(_:)`, `recordPayment…`).
  Views read it via `@Environment(AppStore.self) private var store` and never mutate arrays directly.
- **Local-first**: every mutation updates state, appends an `OutboxItem`, and saves a snapshot.
  `syncPending()` is a **demo transport** (no backend in Phase 1); the Sync & Uploads screen says so.
- `AppModel` (app) holds UI state: tab selection, one `[AppDestination]` path per tab, the visit cover,
  Admin "Preview Field Mode", the network monitor and `ToastCenter`.
- **Role preview**: `store.isReadOnly` is true while an admin previews Field Mode; mutations become no-ops.
  Views also get `@Environment(\.isRolePreview)` to explain disabled actions.
- Capabilities (not role names) gate admin features: `store.capabilities.contains(.finance)`.

## Navigation

- `TabView`; every tab owns a `NavigationStack(path:)` bound to `AppModel` → tabs keep their own stack.
- Push with `NavigationLink(value: AppDestination.x)` or `model.push(.x)`. Switch tabs with `model.open(.inbox, then: .thread(id))`.
- Create/edit flows are `.sheet` with `.presentationDetents` and `.interactiveDismissDisabled(hasEdits)`.
- The active visit is one `.fullScreenCover` (`VisitFlowView`). Minimizing never stops the timer.
- Deep links: `maplecore://visit` (Live Activity), `maplecore://inbox`.

## Design rules

- Colours only from `Palette`; spacing `Space`; radii `Radius`; hit targets `Hit` (44 min, 60 glove).
- Type uses Dynamic Type text styles only (`.largeTitle … .caption`). Timer uses `TimerText`.
- Red is for the primary action, selected tab, urgent items and the brand — never large fills.
- Status is always colour + icon + label (`StatusPill`, `Pill`).
- Cards are flat on the grouped background (`.cardStyle()`); shadows only over maps/cameras (`.floatingShadow()`).
- Animations communicate change: `.motionAnimation(value:)` / `withMotion { }` respect Reduce Motion.
- Haptics: `.sensoryFeedback(.selection/.success/.impact…, trigger:)`, or `Haptics.success()` from actions.
- Glove Mode (`@Environment(\.gloveMode)`): field primary buttons use `.buttonStyle(.mc(.primary, glove: true))`.
- Accessibility: label icon-only buttons, combine row elements, spoken timer values, no colour-only meaning.

## Swift settings

The domain package compiles in **Swift 6 language mode** (strict concurrency, verified on Linux with
Swift 6.0.3). The app target uses Swift 5 mode with `SWIFT_STRICT_CONCURRENCY = complete`, so any
concurrency diagnostics surface as warnings on the first Xcode build instead of blocking it; switch the
target to Swift 6 once those are clean.
