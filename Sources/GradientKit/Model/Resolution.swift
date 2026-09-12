//
//  Resolution.swift
//  GradientKit
//
//  Output sizes. Device presets are native panel pixels, so a wallpaper
//  exported for a display is pixel-exact for it.
//

import Foundation

public struct Resolution: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var name: String
    public var width: Int
    public var height: Int

    public var id: String { "\(name)-\(width)x\(height)" }

    public init(_ name: String, _ width: Int, _ height: Int) {
        self.name = name; self.width = width; self.height = height
    }

    /// Any pixel size. Presets below are conveniences; the renderer takes
    /// whatever you pass (up to the GPU's texture limit per side).
    public static func custom(_ width: Int, _ height: Int) -> Resolution {
        Resolution("Custom", max(1, width), max(1, height))
    }

    public var isCustom: Bool { name == "Custom" }

    public var aspect: Double { Double(width) / Double(height) }
    public var isPortrait: Bool { height > width }
    public var label: String { "\(width) × \(height)" }

    // MARK: Presets

    public static let iMac24 = Resolution("iMac 24″", 4480, 2520)
    public static let macBookAir13 = Resolution("MacBook Air 13″", 2560, 1664)
    public static let macBookAir15 = Resolution("MacBook Air 15″", 2880, 1864)
    public static let macBookPro14 = Resolution("MacBook Pro 14″", 3024, 1964)
    public static let macBookPro16 = Resolution("MacBook Pro 16″", 3456, 2234)
    public static let studioDisplay = Resolution("Studio Display 5K", 5120, 2880)
    public static let proDisplayXDR = Resolution("Pro Display XDR 6K", 6016, 3384)
    public static let uhd4K = Resolution("4K UHD", 3840, 2160)
    public static let qhd = Resolution("QHD", 2560, 1440)
    public static let fullHD = Resolution("Full HD", 1920, 1080)
    public static let ultrawide = Resolution("Ultrawide 21:9", 3440, 1440)

    public static let iPhonePro = Resolution("iPhone Pro", 1206, 2622)
    public static let iPhoneProMax = Resolution("iPhone Pro Max", 1320, 2868)
    public static let iPhone = Resolution("iPhone", 1179, 2556)
    public static let iPadPro13 = Resolution("iPad Pro 13″", 2752, 2064)
    public static let iPadPro11 = Resolution("iPad Pro 11″", 2420, 1668)
    public static let iPadPro13Portrait = Resolution("iPad Pro 13″ portrait", 2064, 2752)
    public static let appleWatch = Resolution("Apple Watch", 416, 496)

    public static let story = Resolution("Story 9:16", 1080, 1920)
    public static let square = Resolution("Square", 2048, 2048)
    public static let post = Resolution("Post 1:1", 1080, 1080)
    public static let portrait45 = Resolution("Portrait 4:5", 1080, 1350)
    public static let landscape = Resolution("Landscape 16:9", 1920, 1080)
    public static let banner = Resolution("Banner 3:1", 1500, 500)
    public static let openGraph = Resolution("Open Graph", 1200, 630)
    public static let pin = Resolution("Pin 2:3", 1000, 1500)
    public static let preview = Resolution("Preview", 960, 540)

    public static let mac: [Resolution] = [
        .iMac24, .macBookAir13, .macBookAir15, .macBookPro14, .macBookPro16,
        .studioDisplay, .proDisplayXDR, .uhd4K, .qhd, .fullHD, .ultrawide,
    ]
    public static let mobile: [Resolution] = [
        .iPhone, .iPhonePro, .iPhoneProMax, .iPadPro11, .iPadPro13, .iPadPro13Portrait, .appleWatch,
    ]
    public static let social: [Resolution] = [
        .post, .portrait45, .story, .landscape, .banner, .openGraph, .pin, .square,
    ]
    public static let all: [Resolution] = mac + mobile + social
}
