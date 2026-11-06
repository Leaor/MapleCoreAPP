import SwiftUI
import UIKit
import MapleCoreKit

// Tokens mirror the "Design Tokens" board. Colours are defined in code with light/dark pairs so
// they stay in one reviewable place; every text pair passes 4.5:1 on its surface.

enum Palette {
    /// Brand red. Primary action, selected tab, urgent, brand mark. Never large fills.
    static let red = Color(hex: 0xD62828)
    /// Red text and links on surfaces.
    static let redText = Color(light: 0xC21F1F, dark: 0xFF7B72)
    static let redSoft = Color(light: 0xFBE8E6, dark: 0xD62828, darkOpacity: 0.22)

    static let background = Color(light: 0xF4F3F1, dark: 0x000000)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surface2 = Color(light: 0xEFEDEA, dark: 0x2C2C2E)

    static let ink = Color(light: 0x171717, dark: 0xF5F5F4)
    static let ink2 = Color(light: 0x56544F, dark: 0xB4B2AD)
    static let ink3 = Color(light: 0x6B6964, dark: 0x9A9893)
    static let separator = Color(light: 0x171717, lightOpacity: 0.09, dark: 0xFFFFFF, darkOpacity: 0.12)

    /// In progress, en route, live location.
    static let blue = Color(light: 0x0B63CE, dark: 0x5AA8FF)
    static let blueSoft = Color(light: 0xE5EFFB, dark: 0x5AA8FF, darkOpacity: 0.16)
    /// Completed, uploaded, available.
    static let green = Color(light: 0x1D7A44, dark: 0x4CCB80)
    static let greenSoft = Color(light: 0xE3F1E8, dark: 0x4CCB80, darkOpacity: 0.16)
    /// Delayed, paused, internal-only, offline.
    static let amber = Color(light: 0xA35200, dark: 0xFFB04D)
    static let amberSoft = Color(light: 0xFCEEDC, dark: 0xFFB04D, darkOpacity: 0.16)

    /// Floating bars over content.
    static let bar = Color(light: 0xFFFFFF, lightOpacity: 0.9, dark: 0x161618, darkOpacity: 0.9)

    /// Photo placeholder tints (fixtures have no real images).
    static let swatches: [Color] = [
        Color(hex: 0x6E7F4F), Color(hex: 0x8C6A3F), Color(hex: 0x5D7C6B),
        Color(hex: 0x7A6E58), Color(hex: 0x4F6B57), Color(hex: 0x8A7A4A)
    ]
}

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    /// Screen margin.
    static let l: CGFloat = 16
    /// Card padding.
    static let xl: CGFloat = 20
    /// Section gap.
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum Radius {
    static let control: CGFloat = 10
    static let card: CGFloat = 16
    static let sheet: CGFloat = 22
}

enum Hit {
    static let min: CGFloat = 44
    /// Field primary actions and Glove Mode.
    static let glove: CGFloat = 60
    static let shutter: CGFloat = 84
}

// MARK: - Semantic tones

enum Tone: Sendable, Hashable {
    case neutral, red, blue, green, amber

    var foreground: Color {
        switch self {
        case .neutral: Palette.ink2
        case .red: Palette.redText
        case .blue: Palette.blue
        case .green: Palette.green
        case .amber: Palette.amber
        }
    }

    var background: Color {
        switch self {
        case .neutral: Palette.surface2
        case .red: Palette.redSoft
        case .blue: Palette.blueSoft
        case .green: Palette.greenSoft
        case .amber: Palette.amberSoft
        }
    }
}

extension StopStatus {
    var tone: Tone {
        switch self {
        case .pending, .skipped: .neutral
        case .enRoute, .inProgress: .blue
        case .done: .green
        case .delayed: .amber
        case .urgent: .red
        }
    }
}

extension UploadState {
    var tone: Tone {
        switch self {
        case .savedOnDevice: .amber
        case .uploading: .blue
        case .uploaded: .green
        case .failed: .red
        }
    }
}

// MARK: - Colour helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    init(light: UInt32, lightOpacity: Double = 1, dark: UInt32, darkOpacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkOpacity)
                : UIColor(hex: light, alpha: lightOpacity)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
