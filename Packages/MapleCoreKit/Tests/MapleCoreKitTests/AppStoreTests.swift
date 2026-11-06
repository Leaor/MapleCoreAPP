import XCTest
@testable import MapleCoreKit

@MainActor
final class AppStoreTests: XCTestCase {
    final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    var clock: Clock!
    var store: AppStore!

    override func setUp() async throws {
        clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let c = clock!
        store = AppStore(fixtures: Fixtures(now: c.now), persistence: MemorySnapshotStore(), syncMode: .disabled, clock: { c.now })
        store.signIn(Fixtures.accounts[1]) // Daniel, field only
    }

    func advance(_ seconds: TimeInterval) { clock.now = clock.now.addingTimeInterval(seconds) }

    func testFieldUserLandsInFieldRoleAndRoute() async {
        XCTAssertEqual(store.activeRole, .field)
        XCTAssertEqual(store.fieldRoute?.id, Fixtures.ID.routeNorth)
        XCTAssertTrue(store.capabilities.isEmpty)
    }

    func testDualRoleAccountMustChoose() async {
        store.signIn(Fixtures.accounts[0])
        XCTAssertNil(store.activeRole)
        store.choose(role: .admin)
        XCTAssertEqual(store.activeRole, .admin)
        XCTAssertTrue(store.capabilities.contains(.finance))
    }

    func testCompleteVisitFlowQueuesOutboxWhenOffline() async throws {
        let route = store.fieldRoute!
        let stop = route.nextStop!
        store.isOnline = false
        store.beginTravel(routeID: route.id, stopID: stop.id)
        advance(480)
        let session = store.arrive(routeID: route.id, stopID: stop.id)
        XCTAssertEqual(session?.state, .arrived)
        XCTAssertEqual(store.stop(routeID: route.id, stopID: stop.id)?.status, .inProgress)

        XCTAssertThrowsError(try store.updateVisit { s, now in try s.startWork(at: now) })
        try store.updateVisit { s, now in for _ in 0..<3 { s.addPhoto(kind: .before, at: now) } }
        try store.updateVisit { s, now in try s.startWork(at: now) }
        advance(1200)
        try store.updateVisit { s, now in try s.pause(at: now) }
        advance(240)
        try store.updateVisit { s, now in try s.resume(at: now) }
        advance(1440)
        try store.updateVisit { s, now in
            for _ in 0..<3 { s.addPhoto(kind: .after, at: now) }
            s.notes = "Bagged 14 bags."
        }
        let result = try store.submitVisit()
        XCTAssertEqual(result?.workMinutes, 44)
        XCTAssertEqual(result?.photoCount, 6)
        XCTAssertEqual(result?.queuedOffline, true)
        XCTAssertNil(store.activeVisit)
        XCTAssertEqual(store.stop(routeID: route.id, stopID: stop.id)?.status, .done)
        XCTAssertEqual(store.route(route.id)?.nextStop?.propertyID, Fixtures.ID.riverwood)

        let record = store.visit(session!.id)!
        XCTAssertEqual(record.review, .awaiting)
        XCTAssertNil(record.receivedAt, "offline submissions have no server time yet")
        XCTAssertTrue(store.pendingOutbox.contains { $0.kind == .photoUpload && $0.totalUnits == 6 })
    }

    func testDemoSyncDeliversWhenOnline() async {
        store.syncMode = .demo
        store.syncStepDelay = .zero
        store.isOnline = false
        store.send("On our way", to: Fixtures.ID.threadCrewA, visibility: .internal)
        XCTAssertEqual(store.thread(Fixtures.ID.threadCrewA)?.messages.last?.delivery, .queued)
        XCTAssertFalse(store.pendingOutbox.isEmpty)
        store.isOnline = true
        await store.syncPending()
        XCTAssertTrue(store.pendingOutbox.isEmpty)
        XCTAssertEqual(store.thread(Fixtures.ID.threadCrewA)?.messages.last?.delivery, .sent)
    }

    func testInternalThreadsForceInternalVisibility() async {
        store.send("Note", to: Fixtures.ID.threadCrewA, visibility: .customer)
        XCTAssertEqual(store.thread(Fixtures.ID.threadCrewA)?.messages.last?.visibility, .internal)
    }

    func testRolePreviewMakesWritesNoOps() async {
        store.signIn(Fixtures.accounts[0])
        store.choose(role: .admin)
        store.beginRolePreview()
        let before = store.outbox.count
        store.send("Should not send", to: Fixtures.ID.threadCrewA, visibility: .internal)
        store.arrive(routeID: Fixtures.ID.routeNorth, stopID: "north-6")
        XCTAssertEqual(store.outbox.count, before)
        XCTAssertNil(store.activeVisit)
        XCTAssertEqual(store.fieldRoute?.id, Fixtures.ID.routeNorth, "preview shows Daniel's route")
        store.endRolePreview()
        XCTAssertNil(store.fieldRoute, "Michael has no crew")
    }

    func testOptimizeKeepsHighPriorityFirstAndFinishedInPlace() async {
        let proposal = store.proposedOrder(for: Fixtures.ID.routeNorth)!
        let route = store.route(Fixtures.ID.routeNorth)!
        XCTAssertEqual(Array(proposal.stops.prefix(5)).map(\.id), Array(route.stops.prefix(5)).map(\.id))
        XCTAssertEqual(proposal.stops[5].priority, .high)
        XCTAssertEqual(Set(proposal.stops.map(\.id)), Set(route.stops.map(\.id)))
        XCTAssertGreaterThanOrEqual(proposal.savedMinutes, 0)
    }

    func testCrewAvailability() async {
        let sweep = store.route(Fixtures.ID.routeSweep)!
        let kingsway = store.route(Fixtures.ID.routeKingsway)!
        var sameDay = sweep
        sameDay.date = kingsway.date
        sameDay.startTime = kingsway.startTime
        if case .overlaps = store.availability(of: Fixtures.ID.crewC, for: sameDay) {} else { XCTFail("Crew C should overlap with Kingsway Residential") }
        XCTAssertEqual(store.availability(of: Fixtures.ID.crewB, for: sweep), .available)
    }

    func testAssignCrewPublishesDraft() async {
        var draft = store.newRouteDraft(on: clock.now)
        draft.name = "Test"
        store.saveRoute(draft)
        store.assignCrew(Fixtures.ID.crewB, to: draft.id)
        XCTAssertEqual(store.route(draft.id)?.state, .scheduled)
        XCTAssertEqual(store.route(draft.id)?.crewID, Fixtures.ID.crewB)
    }

    func testReviewQueueApproval() async {
        store.signIn(Fixtures.accounts[0])
        store.choose(role: .admin)
        XCTAssertEqual(store.reviewQueue.count, 3)
        store.approveVisit(store.reviewQueue[0].id)
        XCTAssertEqual(store.reviewQueue.count, 2)
    }

    func testRecordPaymentPaysInvoice() async {
        store.recordPayment(invoiceID: "inv-1048", amount: 1808, method: "e-Transfer")
        XCTAssertTrue(store.invoice("inv-1048")!.isPaid)
    }

    func testResolveConflictUpdatesNotesAndKeepsHistory() async {
        store.resolveConflict("sc-riverwood", with: .office)
        XCTAssertTrue(store.conflicts.isEmpty)
        XCTAssertEqual(store.property(Fixtures.ID.riverwood)?.accessNotes, "Gate code changed — ask board. Visitor parking only, not the fire lane.")
        XCTAssertTrue(store.history(for: Fixtures.ID.riverwood).contains { $0.detail.contains("Park on Riverwood Cres.") })
        XCTAssertFalse(store.outbox.contains { $0.conflictID != nil })
    }

    func testSnowDispatchSkipsBelowTriggerRoutes() async {
        store.dispatchSnow(routeIDs: ["sr-3", "sr-5"], startAt: nil, message: "")
        XCTAssertTrue(store.snowEvent!.routes.first { $0.id == "sr-3" }!.isDispatched)
        XCTAssertFalse(store.snowEvent!.routes.first { $0.id == "sr-5" }!.isDispatched)
    }

    func testPersistenceRoundTrip() async throws {
        let memory = MemorySnapshotStore()
        let c = clock!
        let a = AppStore(fixtures: Fixtures(now: c.now), persistence: memory, syncMode: .disabled, clock: { c.now })
        a.signIn(Fixtures.accounts[1])
        a.arrive(routeID: Fixtures.ID.routeNorth, stopID: "north-6")
        try memory.save(a.snapshot())
        let b = AppStore(fixtures: Fixtures(now: c.now), persistence: memory, syncMode: .disabled, clock: { c.now })
        XCTAssertEqual(b.account?.staffID, Fixtures.ID.daniel)
        XCTAssertEqual(b.activeVisit?.stopID, "north-6")
        XCTAssertEqual(b.activeVisit?.state, .arrived)
    }

    func testFileSnapshotStore() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("s.json")
        let file = FileSnapshotStore(url: url)
        XCTAssertNil(try file.load())
        try file.save(store.snapshot())
        XCTAssertEqual(try file.load()?.properties.count, store.properties.count)
        try file.clear()
        XCTAssertNil(try file.load())
    }

    func testTodayStatusLine() async {
        XCTAssertEqual(store.todayStatus(for: Fixtures.ID.kingsway)?.status, .done)
        XCTAssertEqual(store.todayStatus(for: Fixtures.ID.islington)?.status, .enRoute)
    }

    func testSkipStopNeedsReason() async {
        store.skipStop(routeID: Fixtures.ID.routeNorth, stopID: "north-8", reason: "  ")
        XCTAssertEqual(store.stop(routeID: Fixtures.ID.routeNorth, stopID: "north-8")?.status, .pending)
        store.skipStop(routeID: Fixtures.ID.routeNorth, stopID: "north-8", reason: "Gate locked")
        XCTAssertEqual(store.stop(routeID: Fixtures.ID.routeNorth, stopID: "north-8")?.status, .skipped)
    }
}

final class AuthServiceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSignInWithEmailAndPhone() async throws {
        let auth = MockAuthService(latency: .zero)
        _ = try await auth.requestCode(for: " Daniel@MapleCoreLawnCare.com ", now: now)
        let result = try await auth.verify(code: MockAuthService.demoCode, now: now)
        XCTAssertEqual(result.account.staffID, Fixtures.ID.daniel)
        _ = try await auth.requestCode(for: "(416) 555-0100", now: now)
        let michael = try await auth.verify(code: MockAuthService.demoCode, now: now)
        XCTAssertTrue(michael.account.hasMultipleRoles)
    }

    func testUnknownAndInvalidLogin() async {
        let auth = MockAuthService(latency: .zero)
        await XCTAssertThrowsAsync(try await auth.requestCode(for: "nobody@example.com", now: now), .unknownAccount)
        await XCTAssertThrowsAsync(try await auth.requestCode(for: "abc", now: now), .invalidLogin)
    }

    func testExpiryAndLockout() async throws {
        let auth = MockAuthService(latency: .zero)
        _ = try await auth.requestCode(for: "daniel@maplecorelawncare.com", now: now)
        await XCTAssertThrowsAsync(try await auth.verify(code: "123456", now: now.addingTimeInterval(601)), .expired)
        _ = try await auth.requestCode(for: "daniel@maplecorelawncare.com", now: now)
        for left in stride(from: 4, through: 1, by: -1) {
            await XCTAssertThrowsAsync(try await auth.verify(code: "000000", now: now), .wrongCode(attemptsLeft: left))
        }
        do {
            _ = try await auth.verify(code: "000000", now: now)
            XCTFail("expected lockout")
        } catch let error as AuthError {
            if case .lockedOut = error {} else { XCTFail("got \(error)") }
        }
    }
}

func XCTAssertThrowsAsync<T>(_ expression: @autoclosure () async throws -> T, _ expected: AuthError, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? AuthError, expected, file: file, line: line)
    }
}
