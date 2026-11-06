# Screen implementation matrix

Source: Claude design canvas **MapleCore Operations** (`project/*.dc.html`, 70 artboards, inspected in full —
every artboard's copy, links and structure was extracted). "P" = pushed, "S" = sheet, "C" = full-screen cover,
"T" = tab root.

| # | Artboard | Swift view | Folder | Pres. | Notes |
|---|----------|-----------|--------|-------|-------|
| **Onboarding** |||||
| 1 | Onboarding · Splash | `OnboardingFlow` (splash step) | Onboarding | root | |
| 2 | Onboarding · Sign in | `OnboardingFlow` | Onboarding | root | Email or mobile; staff-only notice |
| 3 | Onboarding · Verification | `OnboardingFlow` | Onboarding | root | 6-digit code, one-time-code autofill, resend timer, error/lockout (StatesError board) |
| 4 | Onboarding · Account loading | `OnboardingFlow` | Onboarding | root | |
| 5 | Onboarding · Role selection | `OnboardingFlow` | Onboarding | root | Only for dual-role accounts |
| 6 | Onboarding · Notifications | `OnboardingFlow` | Onboarding | root | Pre-prompt, then system prompt |
| 7 | Onboarding · Location | `OnboardingFlow` | Onboarding | root | Field roles only, never forced |
| **Admin · Today & Snow & Review** |||||
| 8 | AdminToday | `AdminTodayView` | Today | T | |
| 9 | SnowOps | `SnowOpsView` | Today | P | |
| 10 | SnowDispatch | `SnowDispatchSheet` | Today | S | |
| 11 | SupervisorReview | `SupervisorReviewView` | Today | P | |
| **Admin · Routes** |||||
| 12 | RoutesList | `RoutesListView` | Routes | T | Today · Upcoming · History |
| 13 | RouteHistory | `RouteHistoryView` | Routes | P | |
| 14 | RoutePlanner / RouteBuilder prototype | `RoutePlannerView` | Routes | C | Select → order → optimize → crew → publish |
| 15 | RouteMap | `RouteMapView` | Routes | P | MapKit, muted style + brand overlays |
| 16 | StopDetail | `StopDetailView` | Routes | P | |
| 17 | CrewAssign | `CrewAssignSheet` | Routes | S | |
| 18 | RouteSummary | `RouteSummaryView` | Routes | P | |
| **Admin · Properties** |||||
| 19 | PropertyList | `PropertyListView` | Properties | T | List / map toggle |
| 20 | PropertyDetail | `PropertyDetailView` | Properties | P | |
| 21 | VisitHistory | `VisitHistoryView` | Properties | P | |
| 22 | PropertyGallery | `PropertyGalleryView` | Properties | P | |
| 23 | (Gallery → Compare) | `PhotoCompareView` | Properties | P | Admin before/after |
| 24 | AddProperty | `AddPropertySheet` | Properties | S | 3-step sheet |
| 25 | EditProperty | `EditPropertySheet` | Properties | S | |
| 26 | CustomerDetail | `CustomerDetailView` | Properties | P | |
| 27 | Documents | `DocumentsView` | Properties | P | |
| **Admin · Inbox** |||||
| 28 | Inbox | `InboxView` | Inbox | T | |
| 29 | CustomerChat | `ConversationView` | Inbox | P | Customer / Internal composer toggle |
| 30 | TeamChat | `ConversationView` | Inbox | P | Same view, internal-only thread |
| 31 | Attachments | `AttachmentsView` | Inbox | P | |
| 32 | PushNotifications | `PushNotificationsPreviewView` | Inbox | P | Template preview (More → Notifications) |
| — | (New message) | `NewMessageSheet` | Inbox | S | Inbox "compose" button |
| **Admin · Business & Team** |||||
| 33 | Quotes | `QuotesView` | Business | P | |
| 34 | QuoteBuilder | `QuoteBuilderView` | Business | C | |
| 35 | Invoices | `InvoicesView` | Business | P | |
| 36 | InvoiceDetail | `InvoiceDetailView` | Business | P | Record Payment only (no processor) |
| 37 | StaffDirectory | `StaffDirectoryView` | Business | P | |
| 38 | EmployeeProfile | `EmployeeProfileView` | Business | P | |
| 39 | CrewManagement | `CrewManagementView` | Business | P | |
| 40 | Analytics | `AnalyticsView` | Business | P | Swift Charts |
| **Admin · System** |||||
| 41 | More | `MoreView` | System | T | |
| 42 | Settings | `SettingsView` | System | P | Shared by Field Profile |
| 43 | NotificationPrefs | `NotificationPrefsView` | System | P | |
| 44 | OfflineQueue | `SyncQueueView` | System | P | Shared by Field Profile |
| 45 | SyncConflict | `SyncConflictSheet` | System | S | |
| 46 | FieldPreview | `FieldShell` + `RolePreviewBanner` | App | C | Writes are no-ops |
| **Field** |||||
| 47 | FieldToday | `FieldTodayView` | Field | T | Includes "no route" empty state |
| 48 | FieldRoute | `FieldRouteView` | Field | T | |
| 49 | FieldStop | `FieldStopView` | Field | P | |
| 50 | FieldMessages | `FieldMessagesView` | Field | T | Opens `ConversationView` |
| 51 | FieldProfile | `FieldProfileView` | Field | T | |
| — | (Profile → Shift history, Availability) | `ShiftHistoryView`, `AvailabilityView` | Field | P | Linked from FieldProfile |
| **Visit flow (one cover)** |||||
| 52 | ActiveVisit (Arrived) | `VisitFlowView` · arrived step | Visit | C | |
| 53 | CameraBefore | `VisitFlowView` · camera(before) | Visit | C | AVFoundation, 84pt shutter |
| 54 | PhotoReview | `VisitFlowView` · photo review | Visit | C | Caption, retake, keep |
| 55 | VisitTimer | `VisitFlowView` · timer | Visit | C | TimelineView, pause reasons |
| 56 | CameraAfter | `VisitFlowView` · camera(after) | Visit | C | Onion-skin overlay |
| 57 | BeforeAfter | `VisitFlowView` · compare | Visit | C | |
| 58 | VisitReview | `VisitFlowView` · review | Visit | C | |
| 59 | VisitSubmitted | `VisitFlowView` · submitted | Visit | C | |
| 60 | LiveActivity | `VisitLiveActivity` (widget) | Widgets | — | Lock Screen + Dynamic Island |
| 61 | FieldFlow prototype | `VisitFlowView` + offline toggle | Visit | C | Offline toggle in visit header |
| **System states (reference boards, applied in screens)** |||||
| 62 | OfflineQueue | `SyncQueueView`, `OfflineBanner` | — | — | |
| 63 | TimerStates | `VisitSession` state machine | MapleCoreKit | — | Unit tested |
| 64 | StatesEmpty | `EmptyStateView` usages | — | — | Routes, Inbox, Field Today |
| 65 | StatesLoading | `SkeletonBlock`, cached rows | — | — | |
| 66 | StatesError | `ErrorStateView`, sign-in errors, camera permission | — | — | |
| **Foundations (not screens)** |||||
| 67–70 | Sitemap, Design Tokens, Components, Developer Handoff | `Tokens.swift`, `Components/*`, `docs/ARCHITECTURE.md` | — | — | |
| — | Dark Mode page (6 boards) | Light/dark token pairs | — | — | Every screen supports dark |

## UX decisions that differ from the canvas

- **Field Camera tab** is a native tab item that opens the visit cover (native `TabView` can't render one item as a red capsule). The label switches to "Visit" while a visit is active.
- **Commercial Sweep** (no crew, dated tomorrow) appears under **Upcoming** rather than Today; Admin Today surfaces "1 route needs a crew" under Needs attention instead.
- **Route North fixture**: the canvas shows both "4 of 9 done" (admin) and "5 of 9 done" (field). The app uses 5 done / stop 6 next everywhere so admin and field views agree.
- **Map colours**: MapKit can't restyle land/water, so maps use `.standard(emphasis: .muted)` with brand-coloured pins and polylines (as the handoff's open questions recommend).
- **Snow event** fixture is shown as live (Event #7) regardless of today's weather card; both are labelled preview fixtures.
