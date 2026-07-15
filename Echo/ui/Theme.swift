import SwiftUI

// Design tokens — single source of truth for colors, spacing, radii, and type.
// ponytail: enums (not structs) so there's no accidental instantiation.

enum AppColor {
    // Fix: was Color.accentColor (system), now explicitly our #FF3366.
    static let accent     = Color("ColorAccent")
    static let background = Color("ColorBackground")   // dark: navy #011627, light: #F5F5F7
    static let surface    = Color("ColorSurface")      // dark: #1D1D1F,      light: #F2E9E4
    static let tealDark   = Color("ColorTealDark")     // #0E7C7B — data viz primary
    static let tealLight  = Color("ColorTealLight")    // #17BEBB — data viz secondary / stat labels
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum AppRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

// Number of adaptive grid columns that fit `width` given an item's min width and spacing.
func gridColumnCount(width: CGFloat, minItemWidth: CGFloat, spacing: CGFloat) -> Int {
    max(1, Int((width + spacing) / (minItemWidth + spacing)))
}

extension Font {
    // Rounded numerals read as the "data face" — gives stats a distinct personality.
    static let appTitle    = Font.system(.title2,   design: .rounded).weight(.bold)
    static let appHeadline = Font.system(.headline, design: .rounded)
    static let appStat     = Font.system(.caption,  design: .rounded).weight(.semibold).monospacedDigit()
    static let appTime     = Font.system(size: 11).monospacedDigit()
}
