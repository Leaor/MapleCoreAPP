import XCTest
import MapleCoreKit
@testable import MapleCore

/// App-layer tests: navigation state, role routing and the visit cover. Domain logic is covered by
/// the MapleCoreKit package tests (`swift test` in Packages/MapleCoreKit).
@MainActor
final class AppModelTests: XCTestCase {
    private func makeModel(account: Account, role: AppRole) -> AppModel {
        let store = AppStore(persistence: MemorySnapshotStore(), syncMode: .disabled)
        store.signIn(account)
        store.choose(role: role)
        store.completePermissions()
        return AppModel(store: store, auth: MockAuthService(latency: .zero))
    }

    func testEachAdminTabKeepsItsOwnPath() {
        let model = makeModel(account: Fixtures.accounts[0], role: .admin)
        model.adminTab = .properties
        model.push(.property(Fixtures.ID.islington))
        model.adminTab = .routes
        model.push(.route(Fixtures.ID.routeNorth))

        XCTAssertEqual(model.adminPaths[.properties], [.property(Fixtures.ID.islington)])
        XCTAssertEqual(model.adminPaths[.routes], [.route(Fixtures.ID.routeNorth)])

        model.popToRoot()
        XCTAssertEqual(model.adminPaths[.routes], [])
        XCTAssertEqual(model.adminPaths[.properties]?.count, 1, "other tabs keep their place")
    }

    func testOpenSwitchesTabAndPushes() {
        let model = makeModel(account: Fixtures.accounts[0], role: .admin)
        model.open(.inbox, then: .thread(Fixtures.ID.threadSandra))
        XCTAssertEqual(model.adminTab, .inbox)
        XCTAssertEqual(model.adminPaths[.inbox], [.thread(Fixtures.ID.threadSandra)])
    }

    func testCameraTabStartsVisitAtNextStop() {
        let model = makeModel(account: Fixtures.accounts[1], role: .field)
        XCTAssertNil(model.store.activeVisit)
        model.open(FieldTab.camera)
        XCTAssertTrue(model.isVisitPresented)
        XCTAssertEqual(model.store.activeVisit?.propertyID, Fixtures.ID.islington)
        XCTAssertEqual(model.fieldTab, .today, "camera never becomes the selected tab")
    }

    func testCameraTabDoesNothingWithoutRoute() {
        // Michael holds the field role but has no crew, so there is no route.
        let model = makeModel(account: Fixtures.accounts[0], role: .field)
        model.open(FieldTab.camera)
        XCTAssertFalse(model.isVisitPresented)
        XCTAssertNil(model.store.activeVisit)
    }

    func testRolePreviewCannotStartVisit() {
        let model = makeModel(account: Fixtures.accounts[0], role: .admin)
        model.store.beginRolePreview()
        model.isFieldPreviewPresented = true
        model.presentVisit()
        XCTAssertNil(model.store.activeVisit)
        XCTAssertFalse(model.isVisitPresented)
    }

    func testVisitDeepLinkOnlyOpensActiveVisit() {
        let model = makeModel(account: Fixtures.accounts[1], role: .field)
        model.handle(url: URL(string: "maplecore://visit")!)
        XCTAssertFalse(model.isVisitPresented)
        model.store.arrive(routeID: Fixtures.ID.routeNorth, stopID: "north-6")
        model.handle(url: URL(string: "maplecore://visit")!)
        XCTAssertTrue(model.isVisitPresented)
    }

    func testSimulatedOfflineUpdatesStore() {
        let model = makeModel(account: Fixtures.accounts[1], role: .field)
        model.simulateOffline = true
        XCTAssertFalse(model.store.isOnline)
    }

    func testResetNavigation() {
        let model = makeModel(account: Fixtures.accounts[0], role: .admin)
        model.open(.more, then: .settings)
        model.resetNavigation()
        XCTAssertEqual(model.adminTab, .today)
        XCTAssertTrue(model.adminPaths.isEmpty)
    }
}
