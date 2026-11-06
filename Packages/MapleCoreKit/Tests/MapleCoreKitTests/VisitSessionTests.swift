import XCTest
@testable import MapleCoreKit

final class VisitSessionTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func makeSession() -> VisitSession {
        VisitSession(routeID: "r", stopID: "s", propertyID: "p", propertyName: "Islington Medical Centre", stopNumber: 6, stopCount: 9, serviceName: "Leaf removal", estimateMinutes: 45, tasks: [VisitTask(id: "t1", title: "Front beds")])
    }

    func testFullLifecycle() throws {
        var s = makeSession()
        try s.startTravel(at: t0)
        XCTAssertEqual(s.state, .travelling)
        try s.arrive(at: t0.addingTimeInterval(480))
        XCTAssertEqual(s.state, .arrived)

        XCTAssertThrowsError(try s.startWork(at: t0)) { error in
            XCTAssertEqual(error as? VisitError, .needsBeforePhotos(have: 0, need: 3))
        }
        for _ in 0..<3 { s.addPhoto(kind: .before, at: t0) }
        XCTAssertEqual(s.photos(.before).map(\.angle), ["Front beds", "Parking lot", "Side gate"])
        XCTAssertNil(s.nextAngle(for: .before))

        let start = t0.addingTimeInterval(600)
        try s.startWork(at: start)
        try s.pause(at: start.addingTimeInterval(600), reason: .weather)
        XCTAssertEqual(s.state, .paused)
        // Time does not advance while paused.
        XCTAssertEqual(s.workingElapsed(at: start.addingTimeInterval(800)), 600)
        try s.resume(at: start.addingTimeInterval(840))
        XCTAssertEqual(s.workingElapsed(at: start.addingTimeInterval(1000)), 760)
        XCTAssertEqual(s.pausedDuration(at: start.addingTimeInterval(1000)), 240)

        XCTAssertThrowsError(try s.complete(at: start.addingTimeInterval(2000)))
        for _ in 0..<3 { s.addPhoto(kind: .after, at: start) }
        XCTAssertNotNil(s.beforePhoto(forAngle: s.photos(.after)[0].angle))
        try s.complete(at: start.addingTimeInterval(2880))
        XCTAssertEqual(s.state, .completed)
        // Frozen after completion.
        XCTAssertEqual(s.workingElapsed(at: start.addingTimeInterval(99999)), 2640)
        try s.markReviewed()
        XCTAssertEqual(s.state, .reviewed)
    }

    func testInvalidTransitions() {
        var s = makeSession()
        XCTAssertThrowsError(try s.pause(at: t0))
        XCTAssertThrowsError(try s.resume(at: t0))
        XCTAssertThrowsError(try s.markReviewed())
    }

    func testCompleteWhilePausedClosesPause() throws {
        var s = makeSession()
        try s.arrive(at: t0)
        for _ in 0..<3 { s.addPhoto(kind: .before, at: t0) }
        try s.startWork(at: t0)
        for _ in 0..<3 { s.addPhoto(kind: .after, at: t0) }
        try s.pause(at: t0.addingTimeInterval(100))
        try s.complete(at: t0.addingTimeInterval(400))
        XCTAssertNil(s.currentPause)
        XCTAssertEqual(s.workingElapsed(at: t0.addingTimeInterval(5000)), 100)
    }

    func testCodableRoundTripPreservesTimer() throws {
        var s = makeSession()
        try s.arrive(at: t0)
        for _ in 0..<3 { s.addPhoto(kind: .before, at: t0) }
        try s.startWork(at: t0)
        let data = try JSONEncoder().encode(s)
        let restored = try JSONDecoder().decode(VisitSession.self, from: data)
        XCTAssertEqual(restored.workingElapsed(at: t0.addingTimeInterval(2538)), 2538)
        XCTAssertEqual(restored.state, .working)
    }

    func testTaskToggleAndCaption() {
        var s = makeSession()
        s.toggleTask(id: "t1")
        XCTAssertEqual(s.completedTaskCount, 1)
        let p = s.addPhoto(kind: .before, at: t0)
        s.setCaption("Heavy leaf cover", forPhoto: p.id)
        XCTAssertEqual(s.photos.first?.caption, "Heavy leaf cover")
        s.removePhoto(id: p.id)
        XCTAssertTrue(s.photos.isEmpty)
    }
}
