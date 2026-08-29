import AppKit

/// Six-digit sRGB color codes ("1A2B3C", optional leading "#") used by the
/// custom-color preference path. Parsing keeps only hex digits and requires
/// exactly six of them, so a truncated code never decodes into a near-black
/// surprise.
enum ColorCode {
    static func unpack(_ raw: String) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        let digits = raw.lowercased().filter(\.isHexDigit)
        guard digits.count == 6, let packed = UInt32(digits, radix: 16) else {
            return nil
        }
        return (
            red: UInt8((packed >> 16) & 0xFF),
            green: UInt8((packed >> 8) & 0xFF),
            blue: UInt8(packed & 0xFF)
        )
    }

    static func pack(_ color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        func channel(_ fraction: CGFloat) -> Int {
            Int((fraction * 255).rounded())
        }
        return String(
            format: "%02X%02X%02X",
            channel(srgb.redComponent),
            channel(srgb.greenComponent),
            channel(srgb.blueComponent)
        )
    }
}

extension NSColor {
    /// Decodes a six-digit sRGB code. Nil unless exactly six hex digits remain
    /// after stripping separators.
    convenience init?(decodingColorCode raw: String) {
        guard let parts = ColorCode.unpack(raw) else { return nil }
        let red = CGFloat(parts.red) / CGFloat(255)
        let green = CGFloat(parts.green) / CGFloat(255)
        let blue = CGFloat(parts.blue) / CGFloat(255)
        self.init(srgbRed: red, green: green, blue: blue, alpha: CGFloat(1))
    }

    /// The six-digit sRGB code of this color, or nil when it cannot be
    /// converted into the sRGB space.
    var encodedColorCode: String? {
        ColorCode.pack(self)
    }
}
