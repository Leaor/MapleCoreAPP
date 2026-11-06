// Re-export the domain package so `@testable import MapleCore` also exposes MapleCoreKit to the unit
// tests without linking a second copy of the static library into the test bundle.
@_exported import MapleCoreKit
