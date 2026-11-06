import SwiftUI
import MapleCoreKit

// MARK: - Splash

/// Brief brand moment. Advances on its own (or on tap) to Sign in.
struct OnboardingSplashView: View {
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer(minLength: Space.xxxl)
            OnboardingBrandMark(size: 96)
            VStack(spacing: Space.s) {
                Text("MAPLE CORE")
                    .font(.title.weight(.bold))
                    .tracking(4)
                    .foregroundStyle(Palette.ink)
                Rectangle()
                    .fill(Palette.red)
                    .frame(width: 40, height: 2)
                    .accessibilityHidden(true)
                Text("OPERATIONS")
                    .font(.subheadline.weight(.semibold))
                    .tracking(6)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: Space.xxxl)
            Text("MapleCore Construction · MapleCore LawnCare")
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.xxl)
        .padding(.bottom, Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Continues to sign in")
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }
}

// MARK: - Sign in

/// Sign in by work email or mobile, then the 6-digit code. Uses a NavigationStack so Verify gets the
/// system back button.
struct OnboardingSignInFlow: View {
    var onSignedIn: (Account) -> Void

    @Environment(AppModel.self) private var model
    @Environment(AppStore.self) private var store

    @State private var login = ""
    @State private var challenge: CodeChallenge?
    @State private var showVerify = false
    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var showAccessHelp = false
    @FocusState private var loginFocused: Bool

    private var canContinue: Bool {
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRequesting
    }

    var body: some View {
        NavigationStack {
            form
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showVerify) {
                    if let challenge {
                        OnboardingVerifyView(login: login, challenge: challenge, onSignedIn: onSignedIn)
                    }
                }
        }
        .tint(Palette.red)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                OnboardingBrandMark(size: 44)
                OnboardingHeading(title: "Sign in", message: "For MapleCore staff. Use the work email or mobile number your manager added to your account.")
                loginField
                Button(action: requestCode) {
                    HStack(spacing: Space.s) {
                        if isRequesting { ProgressView().tint(.white) }
                        Text(isRequesting ? "Sending Code…" : "Continue")
                    }
                }
                .buttonStyle(.mc(.primary))
                .disabled(!canContinue)
                .accessibilityIdentifier("signin-continue")

                OnboardingDemoAccounts { account in
                    login = account.login
                    errorMessage = nil
                }

                NoticeCard(symbol: "info.circle", text: "Looking to book service or pay an invoice? This app is for staff only — customers use the MapleCore customer app.", tone: .neutral)

                Button("Need access? Contact your manager") { showAccessHelp = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.redText)
                    .frame(minHeight: Hit.min)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
        .alert("Need access?", isPresented: $showAccessHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ask your manager to add your work email or mobile number to your MapleCore staff account. Once they have, sign in here with that email or number.")
        }
    }

    private var loginField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Work email or mobile")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink2)
            TextField("name@maplecorelawncare.com", text: $login)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($loginFocused)
                .onSubmit(requestCode)
                .font(.body)
                .padding(.horizontal, Space.l)
                .frame(minHeight: 52)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous)
                        .strokeBorder(errorMessage == nil ? Palette.separator : Palette.redText, lineWidth: errorMessage == nil ? 1 : 1.5)
                }
                .accessibilityLabel("Work email or mobile")
                .accessibilityIdentifier("signin-login")
                .onChange(of: login) { _, _ in errorMessage = nil }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.redText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestCode() {
        guard canContinue else { return }
        errorMessage = nil
        isRequesting = true
        loginFocused = false
        let auth = model.auth
        let value = login
        let now = store.now
        Task {
            do {
                challenge = try await auth.requestCode(for: value, now: now)
                showVerify = true
            } catch let error as AuthError {
                errorMessage = error.message
                Haptics.error()
            } catch {
                errorMessage = "Couldn't start sign-in. Check your connection and try again."
                Haptics.error()
            }
            isRequesting = false
        }
    }
}

/// Quick-fill buttons for the preview build's demo accounts. Clearly labelled as demo data.
private struct OnboardingDemoAccounts: View {
    var onPick: (Account) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Demo accounts · preview build")
                .captionStyle()
            VStack(spacing: 0) {
                ForEach(Array(Fixtures.accounts.enumerated()), id: \.element.staffID) { index, account in
                    Button { onPick(account) } label: {
                        HStack(spacing: Space.m) {
                            Avatar(initials: account.initials, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.ink)
                                Text(account.roles.map(\.title).joined(separator: " + "))
                                    .font(.caption)
                                    .foregroundStyle(Palette.ink2)
                            }
                            Spacer(minLength: Space.s)
                            Text("Fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.redText)
                        }
                        .frame(minHeight: Hit.min + 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Fill demo account \(account.displayName), \(account.roles.map(\.title).joined(separator: " and "))")
                    if index < Fixtures.accounts.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

// MARK: - Verify

/// 6-digit code entry. One real text field (so iOS can offer the code from Mail or Messages)
/// drawn as six boxes. Submits automatically when six digits are entered.
struct OnboardingVerifyView: View {
    let login: String
    var onSignedIn: (Account) -> Void

    @Environment(AppModel.self) private var model
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var challenge: CodeChallenge
    @State private var code = ""
    @State private var error: AuthError?
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var shakes: CGFloat = 0
    @FocusState private var focused: Bool

    init(login: String, challenge: CodeChallenge, onSignedIn: @escaping (Account) -> Void) {
        self.login = login
        self.onSignedIn = onSignedIn
        _challenge = State(initialValue: challenge)
    }

    private var isLocked: Bool {
        if case .lockedOut = error { return true }
        return false
    }

    private var isExpired: Bool { error == .expired }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                OnboardingHeading(title: "Enter code", message: "We sent a 6-digit code to \(challenge.login). It expires in 10 minutes.")
                codeField
                errorArea
                resendRow
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("The code fills in automatically from Mail or Messages when available.")
                    Text("After 5 tries, sign-in pauses for 15 minutes to protect the account.")
                    Label("Demo build · no code is sent. Use 123456.", systemImage: "info.circle")
                        .foregroundStyle(Palette.ink2)
                }
                .font(.footnote)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    // MARK: Code field

    private var codeField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Verification code")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink2)
            ZStack {
                HStack(spacing: Space.s) {
                    ForEach(0..<6, id: \.self) { index in
                        digitBox(index)
                    }
                }
                .accessibilityHidden(true)

                TextField("", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .foregroundStyle(Color.clear)
                    .tint(Color.clear)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .disabled(isLocked || isVerifying)
                    .accessibilityLabel("Verification code, 6 digits")
                    .accessibilityValue(code.isEmpty ? "Empty" : code.map(String.init).joined(separator: " "))
                    .accessibilityIdentifier("verify-code")
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .modifier(OnboardingShakeEffect(animatableData: shakes))
            .onChange(of: code) { _, newValue in handleInput(newValue) }

            if isVerifying {
                HStack(spacing: Space.s) {
                    ProgressView()
                    Text("Checking code…").font(.footnote).foregroundStyle(Palette.ink2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func digitBox(_ index: Int) -> some View {
        let digits = Array(code)
        let character: String = index < digits.count ? String(digits[index]) : ""
        let isActive = focused && index == min(digits.count, 5) && !isLocked
        let borderColor: Color = error != nil && code.isEmpty ? Palette.redText : (isActive ? Palette.red : Palette.separator)
        return Text(character)
            .font(.title.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isActive || error != nil ? 2 : 1)
            }
    }

    // MARK: Errors & resend

    @ViewBuilder
    private var errorArea: some View {
        if let error {
            VStack(alignment: .leading, spacing: Space.m) {
                Label(error.message, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.redText)
                    .fixedSize(horizontal: false, vertical: true)
                if case let .lockedOut(until) = error {
                    Text("You can try again at \(Fmt.time(until)).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                if isExpired {
                    Button(action: resend) {
                        Text(isResending ? "Sending…" : "Send a New Code")
                    }
                    .buttonStyle(.mc(.ink))
                    .disabled(isResending)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var resendRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(challenge.resendAvailableAt.timeIntervalSince(context.date).rounded(.up))
            HStack(spacing: Space.xs) {
                Text("Didn't get it?")
                    .foregroundStyle(Palette.ink2)
                if remaining > 0 {
                    Text("Resend in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                        .foregroundStyle(Palette.ink3)
                        .monospacedDigit()
                } else {
                    Button(isResending ? "Sending…" : "Resend Code", action: resend)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.redText)
                        .disabled(isResending || isLocked)
                        .frame(minHeight: Hit.min)
                }
            }
            .font(.subheadline)
            .frame(minHeight: Hit.min)
        }
    }

    // MARK: Actions

    private func handleInput(_ newValue: String) {
        let digits = String(newValue.filter(\.isNumber).prefix(6))
        if digits != newValue {
            code = digits
            return
        }
        if !digits.isEmpty, case .wrongCode = error { error = nil }
        if digits.count == 6 { verify() }
    }

    private func verify() {
        guard code.count == 6, !isVerifying, !isLocked else { return }
        isVerifying = true
        let entered = code
        let auth = model.auth
        let now = store.now
        Task {
            do {
                let result = try await auth.verify(code: entered, now: now)
                KeychainStore.set(result.token, for: KeychainStore.sessionTokenKey)
                Haptics.success()
                focused = false
                isVerifying = false
                onSignedIn(result.account)
            } catch let authError as AuthError {
                isVerifying = false
                fail(authError)
            } catch {
                isVerifying = false
                fail(.expired)
            }
        }
    }

    private func fail(_ authError: AuthError) {
        error = authError
        code = ""
        Haptics.error()
        if !reduceMotion {
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        }
        if case .lockedOut = authError { focused = false }
    }

    private func resend() {
        guard !isResending else { return }
        isResending = true
        let auth = model.auth
        let now = store.now
        let value = login
        Task {
            do {
                challenge = try await auth.requestCode(for: value, now: now)
                error = nil
                code = ""
                focused = true
                toasts.show("New demo code ready · use 123456", symbol: "envelope", tone: .blue)
            } catch let authError as AuthError {
                error = authError
                Haptics.error()
            } catch {
                Haptics.error()
            }
            isResending = false
        }
    }
}

#Preview("Sign in") {
    OnboardingSignInFlow(onSignedIn: { _ in })
        .previewEnvironment()
}
