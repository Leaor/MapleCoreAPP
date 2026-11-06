import XCTest
@testable import MapleCoreKit

final class BusinessAndFormattingTests: XCTestCase {
    let fixtures = Fixtures(now: Date(timeIntervalSince1970: 1_800_000_000))

    func testQuoteTotalsMatchDesign() {
        let q214 = fixtures.quotes.first { $0.number == "Q-214" }!
        XCTAssertEqual(q214.totals.subtotal, 14800)
        XCTAssertEqual(q214.totals.tax, 1924)
        XCTAssertEqual(q214.totals.total, 16724)
        let awaiting = fixtures.quotes.filter { $0.status.isOpen }.reduce(Decimal(0)) { $0 + $1.totals.total }
        XCTAssertEqual(awaiting, 18294)
        let approved = fixtures.quotes.filter { $0.status == .approved }.reduce(Decimal(0)) { $0 + $1.totals.total }
        XCTAssertEqual(approved, 9940)
    }

    func testInvoiceTotalsMatchDesign() {
        let invoices = fixtures.invoices
        let inv1048 = invoices.first { $0.number == "INV-1048" }!
        XCTAssertEqual(inv1048.totals.subtotal, 1600)
        XCTAssertEqual(inv1048.totals.tax, 208)
        XCTAssertEqual(inv1048.totals.total, 1808)

        let now = fixtures.now
        let outstanding = invoices.filter { !$0.isPaid && $0.number != "INV-1019" }
        XCTAssertEqual(outstanding.reduce(Decimal(0)) { $0 + $1.balance }, Decimal(string: "7271.50")!)
        let overdue = invoices.filter { $0.isOverdue(asOf: now) }
        XCTAssertEqual(overdue.map(\.number), ["INV-1047"])
        XCTAssertEqual(overdue.first?.balance, Decimal(string: "2412.50")!)
        XCTAssertEqual(overdue.first?.daysOverdue(asOf: now), 6)
        XCTAssertTrue(invoices.first { $0.number == "INV-1019" }!.isPaid)
    }

    func testOptionalLineItemsExcludedFromTotal() {
        let items = [LineItem(id: "a", title: "A", unitPrice: 100), LineItem(id: "b", title: "B", unitPrice: 50, isOptional: true)]
        XCTAssertEqual(Totals(items: items).subtotal, 100)
    }

    func testMoneyFormatting() {
        XCTAssertEqual(Fmt.money(Decimal(string: "1808")!), "$1,808.00")
        XCTAssertEqual(Fmt.moneyWhole(18294), "$18,294")
    }

    func testDurations() {
        XCTAssertEqual(Fmt.duration(minutes: 45), "45 min")
        XCTAssertEqual(Fmt.duration(minutes: 70), "1 h 10 min")
        XCTAssertEqual(Fmt.duration(minutes: 120), "2 h")
        XCTAssertEqual(Fmt.compactDuration(minutes: 121), "2 h 01 m")
        XCTAssertEqual(Fmt.timer(2538), "42:18")
        XCTAssertEqual(Fmt.timer(5047), "1:24:07")
        XCTAssertEqual(Fmt.timerLong(2538), "00:42:18")
        XCTAssertEqual(Fmt.spokenDuration(2538), "42 minutes 18 seconds")
    }

    func testConflictKeepBothAddsOnlyNewLines() {
        let c = fixtures.conflicts[0]
        let merged = c.resolvedText(.keepBoth)
        XCTAssertTrue(merged.hasPrefix(c.office.text))
        XCTAssertTrue(merged.contains("Leaves bagged, not mulched."))
        XCTAssertTrue(merged.contains("Park on Riverwood Cres."))
        XCTAssertEqual(merged.components(separatedBy: "Gate code changed").count, 2, "shared line must not repeat")
    }

    func testCapabilitiesByRole() {
        XCTAssertTrue(AppRole.admin.capabilities.contains(.finance))
        XCTAssertFalse(AppRole.supervisor.capabilities.contains(.finance))
        XCTAssertTrue(AppRole.supervisor.capabilities.contains(.visitReview))
        XCTAssertTrue(AppRole.field.capabilities.isEmpty)
    }

    func testFixtureIntegrity() {
        let ids = Set(fixtures.properties.map(\.id))
        for route in fixtures.routes {
            for stop in route.stops { XCTAssertTrue(ids.contains(stop.propertyID), "\(route.name) references unknown property") }
        }
        let crewIDs = Set(fixtures.crews.map(\.id))
        for member in fixtures.staff { if let c = member.crewID { XCTAssertTrue(crewIDs.contains(c)) } }
        for thread in fixtures.threads { if let p = thread.propertyID { XCTAssertTrue(ids.contains(p)) } }
        let north = fixtures.routes.first { $0.id == Fixtures.ID.routeNorth }!
        XCTAssertEqual(north.completedCount, 5)
        XCTAssertEqual(north.nextStop?.propertyID, Fixtures.ID.islington)
    }
}
