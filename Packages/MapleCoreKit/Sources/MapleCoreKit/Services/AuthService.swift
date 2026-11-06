import Foundation

public enum AuthError: Error, Equatable, Sendable {
    case unknownAccount
    case invalidLogin
    case wrongCode(attemptsLeft: Int)
    case expired
    case lockedOut(until: Date)

    public var message: String {
        switch self {
        case .unknownAccount: "We couldn't find a MapleCore staff account for that email or number. Check with your manager."
        case .invalidLogin: "Enter a work email or a 10-digit mobile number."
        case let .wrongCode(left): "That code isn't right. \(left) \(left == 1 ? "try" : "tries") left."
        case .expired: "That code has expired. Codes last 10 minutes."
        case .lockedOut: "Too many tries. Sign-in pauses for 15 minutes to protect the account."
        }
    }
}

public struct CodeChallenge: Equatable, Sendable {
    public var login: String
    public var sentAt: Date
    public var expiresAt: Date
    public var resendAvailableAt: Date
}

/// Sign-in by work email or mobile with a one-time code.
public protocol AuthService: Sendable {
    func requestCode(for login: String, now: Date) async throws -> CodeChallenge
    func verify(code: String, now: Date) async throws -> (account: Account, token: String)
}

/// Demo sign-in. No code is actually sent anywhere; the demo code is `MockAuthService.demoCode`.
/// Replace with the real identity provider in Phase 2.
public actor MockAuthService: AuthService {
    public static let demoCode = "123456"
    public static let maxAttempts = 5
    public static let codeLifetime: TimeInterval = 10 * 60
    public static let lockout: TimeInterval = 15 * 60

    private let accounts: [Account]
    private var challenge: CodeChallenge?
    private var account: Account?
    private var failedAttempts = 0
    private var lockedUntil: Date?
    private let latency: Duration

    public init(accounts: [Account] = Fixtures.accounts, latency: Duration = .milliseconds(600)) {
        self.accounts = accounts
        self.latency = latency
    }

    public static func normalize(_ login: String) -> String? {
        let trimmed = login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.contains("@") {
            let parts = trimmed.split(separator: "@")
            guard parts.count == 2, parts[1].contains("."), !parts[0].isEmpty else { return nil }
            return trimmed
        }
        let digits = trimmed.filter(\.isNumber)
        return digits.count == 10 || (digits.count == 11 && digits.hasPrefix("1")) ? String(digits.suffix(10)) : nil
    }

    public func requestCode(for login: String, now: Date) async throws -> CodeChallenge {
        try await Task.sleep(for: latency)
        guard let normalized = Self.normalize(login) else { throw AuthError.invalidLogin }
        let phoneDirectory = ["4165550100": Fixtures.ID.michael, "4165550131": Fixtures.ID.daniel, "4165550141": Fixtures.ID.priya]
        let match = accounts.first { $0.login == normalized || phoneDirectory[normalized] == $0.staffID }
        guard let match else { throw AuthError.unknownAccount }
        if let lockedUntil, lockedUntil > now { throw AuthError.lockedOut(until: lockedUntil) }
        account = match
        failedAttempts = 0
        let c = CodeChallenge(login: login, sentAt: now, expiresAt: now.addingTimeInterval(Self.codeLifetime), resendAvailableAt: now.addingTimeInterval(30))
        challenge = c
        return c
    }

    public func verify(code: String, now: Date) async throws -> (account: Account, token: String) {
        try await Task.sleep(for: latency)
        if let lockedUntil, lockedUntil > now { throw AuthError.lockedOut(until: lockedUntil) }
        guard let challenge, let account else { throw AuthError.expired }
        guard now < challenge.expiresAt else { throw AuthError.expired }
        guard code == Self.demoCode else {
            failedAttempts += 1
            if failedAttempts >= Self.maxAttempts {
                let until = now.addingTimeInterval(Self.lockout)
                lockedUntil = until
                throw AuthError.lockedOut(until: until)
            }
            throw AuthError.wrongCode(attemptsLeft: Self.maxAttempts - failedAttempts)
        }
        self.challenge = nil
        failedAttempts = 0
        return (account, "demo-\(UUID().uuidString)")
    }
}
