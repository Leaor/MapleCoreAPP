# MapleCore Operations — iOS

Native SwiftUI iPhone app for MapleCore LawnCare staff, built from the **MapleCore Operations** design
canvas (70 artboards: Admin mode, Field mode, the proof-of-work visit flow, system states, dark mode and the
developer handoff). iOS 17+, Swift, SwiftUI, Observation, MapKit, Swift Charts, AVFoundation, ActivityKit.

## Open and run

1. Xcode **16 or later** (the project uses folder-synchronized groups).
2. Open `MapleCore.xcodeproj`, choose the **MapleCore** scheme and an iPhone simulator, Run.
3. Set your team under *Signing & Capabilities* for the app and the `MapleCoreWidgetsExtension` target to run on a device.

### Demo sign-in

No code is sent anywhere — this build uses a mock identity service. Enter any demo account, then code **123456**.

| Account | Roles | Lands in |
|---|---|---|
| `michael@maplecorelawncare.com` | Owner · Admin + Field | Role choice → Admin (Today · Routes · Properties · Inbox · More) |
| `daniel@maplecorelawncare.com` | Crew lead · Field | Field (Today · Route · Camera · Messages · Profile) |
| `priya@maplecorelawncare.com` | Supervisor | Admin shell without finance/analytics |

Wrong codes show the error state; five wrong tries lock sign-in for 15 minutes; codes expire after 10.
Settings → **Reset demo data** restores the fixtures. Admin → More → **Preview Field Mode** shows the crew app
as Daniel with every write disabled.

## What's in the app

| Area | Screens |
|---|---|
| Onboarding | Splash, sign in, verification, account loading, role choice, notification and location pre-prompts |
| Admin · Today | Operational home, Snow Operations + dispatch, supervisor visit review |
| Admin · Routes | Today / Upcoming / History, route map, stop detail (skip with reason), completion summary, route planner (reorder, optimize, assign crew, publish) |
| Admin · Properties | List + map, property profile, visit timeline, gallery, before/after compare, add (address search) & edit, customer, documents |
| Admin · Inbox | Filters & search, customer and team conversations (customer/internal composer, internal notes, photos), attachments, notification templates |
| Admin · More | Quotes + builder (HST 13%), invoices + Record Payment, team directory, employee profile, crews, analytics, sync queue, settings, notification preferences |
| Field | Today (shift, next stop), route map, stop detail, messages, profile (location sharing, availability, shift history) |
| Visit (one full-screen cover) | Arrive → before photos (camera, required angles) → photo review → work timer (pause reasons) → after photos (onion-skin overlay) → compare → review → submitted |
| System | Live Activity + Dynamic Island, offline banner, outbox & sync conflicts, empty/loading/error states, dark mode, Glove Mode, Dynamic Type, VoiceOver |

See `docs/SCREEN_MATRIX.md` for the artboard → view mapping and the UX decisions that differ from the canvas,
and `docs/ARCHITECTURE.md` for structure, state flow and design rules.

## Architecture in one paragraph

`Packages/MapleCoreKit` is a local Swift package (Foundation + Observation only, Swift 6 language mode) holding
the domain model, preview fixtures, the `VisitSession` state machine (timer derived from stored dates, so it
survives backgrounding and relaunch) and `AppStore`, a `@MainActor @Observable` single source of truth. Every
write is **local-first**: it updates state, appends an outbox item and saves an atomic JSON snapshot in
Application Support. The app target (`MapleCore/`) is SwiftUI only: two role shells (Admin, Field), each tab
with its own `NavigationStack` path, sheets with detents for create/edit flows, and one full-screen cover for
the active visit. The session token lives in the Keychain; proof-of-work photos are saved to the app container
before anything else.

## Mock vs. live — read before shipping

This is **Phase 1 (presentation + local behaviour)**, as the design handoff specifies. Nothing talks to a server.

| Works on device today | Mocked / needs a live integration |
|---|---|
| All navigation, forms, validation, search, filters, sorting, reordering | **Sign-in** — `MockAuthService` (demo code). Replace with the real identity provider |
| Local persistence of every change (survives relaunch) | **Sync** — the outbox "sends" through a demo transport; the Sync & Uploads screen says so. Needs the API + background `URLSession` uploads |
| Camera capture, on-device photo storage, captions, photo library import | **Server timestamps** — "Received" times are set by the demo transport, not a server |
| Visit timer, pause/resume, Live Activity with Pause/Resume intents | **Push notifications** — permission prompt only; dispatch/announcements post to in-app threads |
| Offline banner, outbox states, conflict resolution UI | **Documents** — metadata only; files sync in Phase 2 |
| Quotes/invoices maths (HST 13%), Record Payment bookkeeping | **Payments** — no processor; "Record Payment" is manual bookkeeping only |
| Location permission flow and sharing controls | **Live staff location** — fixture data; no location upload |
| Analytics charts | **Analytics figures** — fixtures |

All names, addresses, amounts and weather are preview fixtures from the canvas. The maple-leaf app icon and
splash mark are placeholders until the official logo is supplied.

## Tests

```bash
cd Packages/MapleCoreKit && swift test
```

37 unit tests cover the visit state machine, timer maths, totals/HST against the design's figures, the store's
workflows (submit visit offline, sync, role-preview read-only, optimize, crew availability, conflicts,
persistence round-trip) and the mock auth (expiry, lockout). They run on macOS or Linux.

```bash
xcodebuild test -project MapleCore.xcodeproj -scheme MapleCore -destination 'platform=iOS Simulator,name=iPhone 16'
```

Runs the app-level unit tests (`MapleCoreTests`: navigation model, camera-tab behaviour, deep links) and UI
tests (`MapleCoreUITests`: sign-in errors, admin tab navigation, tab state preservation, field arrive → visit).

`scripts/check-syntax.sh` parses every app/widget Swift file with `swiftc` (useful without Xcode).

## Verification status

This project was produced in a Linux environment **without Xcode or an iOS SDK**. What was verified:

- `MapleCoreKit` builds in Swift 6 mode and its 37 unit tests pass (Swift 6.0.3, Linux).
- Every app, widget and test Swift file parses (`swiftc -parse`).
- The Xcode project file parses and has no dangling object references; the scheme XML is valid.
- Every screen was reviewed line-by-line against the iOS 17 SDK APIs and the package's public API.

What has **not** been done yet: an Xcode build, running the app on a simulator, the `MapleCoreTests` and
UI tests, and visual comparison on device. Expect a short round of compiler fixes on the first Xcode build.
The app target is set to Swift 5 language mode with complete concurrency checking so concurrency diagnostics
appear as warnings; move it to Swift 6 once they're clean.

## Open questions carried over from the handoff

- Official logo vector (app icon, splash, documents).
- Tax rules per division (HST 13% assumed) and exemptions.
- Payment processor / customer pay links (out of scope).
- Customer messaging channel (customer app, SMS or email) — affects read receipts.
- Snow trigger thresholds per contract (2 cm / 5 cm shown as examples).
