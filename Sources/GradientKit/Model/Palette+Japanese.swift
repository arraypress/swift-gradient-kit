//
//  Palette+Japanese.swift
//  GradientKit
//
//  Palettes built from traditional Japanese colour names (和色). The hex
//  values are the conventional digital approximations these names are
//  published with (Nippon Colors and the usual 和色大辞典 tables) — the
//  historical dyes they name are pigments, not sRGB, so treat them as the
//  agreed modern rendering rather than a measurement.
//
//  Each set is grouped so the six roles land sensibly: two grounds, two
//  saturated hues, a near-white and a near-black.
//

import Foundation

public extension Palette {
    private static func jp(_ s: String) -> RGBA { RGBA(hex: s)! }

    /// 藍 — indigo dye, from the pale first dip to the near-black last.
    static let ai = Palette(
        name: "Ai",
        base: jp("#2B3A55"),        // 藍鉄 aitetsu
        baseAlt: jp("#3E5C76"),     // 納戸色 nandoiro
        accent: jp("#165E83"),      // 藍色 ai-iro
        secondary: jp("#6E7F80"),   // 水浅葱 mizuasagi
        highlight: jp("#EAF4F4"),   // 白藍 shiraai
        deep: jp("#0F1C2E"),        // 濃藍 koiai
        mood: .dark)

    /// 茜 — madder red, the colour of a Japanese sunset sky.
    static let akane = Palette(
        name: "Akane",
        base: jp("#F6E5D8"),        // 生成色 kinari
        baseAlt: jp("#E8C4B8"),     // 珊瑚色 sangoiro
        accent: jp("#B7282E"),      // 茜色 akane-iro
        secondary: jp("#E17B64"),   // 曙色 akebonoiro
        highlight: jp("#FFF9F4"),   // 卯の花色 unohanairo
        deep: jp("#4A1F28"),        // 葡萄色 ebiiro
        mood: .light)

    /// 苔 — moss, bamboo and the greens of a temple garden.
    static let koke = Palette(
        name: "Koke",
        base: jp("#DDE3D5"),        // 白緑 byakuroku
        baseAlt: jp("#A8BBA2"),     // 柳色 yanagiiro
        accent: jp("#5B7B54"),      // 苔色 kokeiro
        secondary: jp("#8C9A5B"),   // 鶯色 uguisuiro
        highlight: jp("#F5F8F0"),   // 月白 geppaku
        deep: jp("#1F2A1C"),        // 藍海松茶 aimirucha
        mood: .light)

    /// 桜 — cherry blossom, the pale pinks of early spring.
    static let sakura = Palette(
        name: "Sakura",
        base: jp("#FDEFF2"),        // 桜色 sakurairo
        baseAlt: jp("#F5D1D8"),     // 鴇色 tokiiro
        accent: jp("#E0A0B0"),      // 撫子色 nadeshikoiro
        secondary: jp("#C48B9F"),   // 梅紫 umemurasaki
        highlight: jp("#FFFBFC"),   // 白練 shironeri
        deep: jp("#56303F"),        // 紫鳶 murasakitobi
        mood: .light)

    /// 紫 — the imperial purples, deep and dusky.
    static let murasaki = Palette(
        name: "Murasaki",
        base: jp("#4A3A55"),        // 紫紺 shikon
        baseAlt: jp("#6B5B7B"),     // 藤鼠 fujinezumi
        accent: jp("#8F5A9E"),      // 菖蒲色 ayameiro
        secondary: jp("#B88FCF"),   // 藤色 fujiiro
        highlight: jp("#F0E9F5"),   // 白藤色 shirofujiiro
        deep: jp("#1C1424"),        // 黒紫 kurimurasaki
        mood: .dark)

    /// 墨 — sumi ink on paper: the quiet, near-neutral set.
    static let sumi = Palette(
        name: "Sumi",
        base: jp("#D6D3CB"),        // 灰白色 kaihakushoku
        baseAlt: jp("#9C9A93"),     // 利休鼠 rikyunezumi
        accent: jp("#4F4B45"),      // 墨 sumi
        secondary: jp("#7A7267"),   // 橡 tsurubami
        highlight: jp("#FAF8F3"),   // 胡粉色 gofuniro
        deep: jp("#14120F"),        // 呂色 roiro
        mood: .light)

    /// 柿 — persimmon and safflower: the warm, high-chroma set.
    static let kaki = Palette(
        name: "Kaki",
        base: jp("#F7E3C6"),        // 練色 neriiro
        baseAlt: jp("#E8B98A"),     // 洗柿 araigaki
        accent: jp("#ED6D3D"),      // 柿色 kakiiro
        secondary: jp("#D9A62E"),   // 黄金 kogane
        highlight: jp("#FFF7E8"),   // 鳥の子色 torinokoiro
        deep: jp("#4C2A1E"),        // 焦茶 kogecha
        mood: .light)

    /// Traditional Japanese sets, in a stable order.
    static let japanese: [Palette] = [.ai, .akane, .koke, .sakura, .murasaki, .sumi, .kaki]
}
