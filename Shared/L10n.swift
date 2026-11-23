import Foundation

/// UI language. `.system` follows iOS (Settings → Nocturne → Language, or the phone language),
/// falling back to Română. Track titles / artists / playlist names are data and never localized.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system, ro, en, ru

    var id: String { rawValue }

    /// Name of the language in that language (picker rows).
    var nativeName: String {
        switch self {
        case .system: return L10n.t("language_system")
        case .ro: return "Română"
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    var chip: String? {
        switch self {
        case .system: return nil
        case .ro: return "RO"
        case .en: return "EN"
        case .ru: return "RU"
        }
    }
}

/// Localized-bundle helper: resolves strings from `<code>.lproj` of the String Catalog so the
/// language can change live, without restarting, in the app and in every extension.
final class L10n {
    static let supported = ["ro", "en", "ru"]
    static let storageKey = "appLanguage"

    private static let lock = NSLock()
    private static var _current = L10n(code: "ro")

    static var current: L10n {
        lock.lock(); defer { lock.unlock() }
        return _current
    }

    let code: String
    let bundle: Bundle
    let locale: Locale

    private init(code: String) {
        self.code = code
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = .main
        }
        locale = Locale(identifier: code == "ro" ? "ro_RO" : code == "ru" ? "ru_RU" : "en_US")
    }

    /// Effective language code for a selection.
    static func resolve(_ language: AppLanguage) -> String {
        if language != .system { return language.rawValue }
        // preferredLocalizations honours the per-app language from iOS Settings.
        for pref in Bundle.main.preferredLocalizations + Locale.preferredLanguages {
            let code = String(pref.prefix(2)).lowercased()
            if supported.contains(code) { return code }
        }
        return "ro"
    }

    static let resolvedKey = "appLanguageResolved"

    static func apply(_ language: AppLanguage) {
        apply(code: resolve(language))
    }

    static func apply(code rawCode: String) {
        let code = supported.contains(rawCode) ? rawCode : "ro"
        lock.lock()
        if _current.code != code { _current = L10n(code: code) }
        lock.unlock()
    }

    /// Reads the stored selection (App Group first, so extensions follow the app).
    static func storedSelection() -> AppLanguage {
        let raw = AppGroup.defaults?.string(forKey: storageKey) ?? UserDefaults.standard.string(forKey: storageKey)
        return raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// For extensions: apply the language the app resolved (falls back to resolving locally).
    static func applyStored() {
        if let code = AppGroup.defaults?.string(forKey: resolvedKey) {
            apply(code: code)
        } else {
            apply(storedSelection())
        }
    }

    // MARK: lookup

    static func t(_ key: String) -> String {
        let c = current
        let value = c.bundle.localizedString(forKey: key, value: "\u{1}", table: nil)
        if value != "\u{1}" { return value }
        let fallback = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return fallback
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: current.locale, arguments: args)
    }

    /// Plural lookup through the String Catalog's plural variations (one / few / many / other).
    static func p(_ key: String, _ count: Int) -> String {
        let c = current
        let format = c.bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: c.locale, count)
    }
}

/// Locale-aware formatting (durations, sizes, speeds) in the selected UI language.
enum Fmt {
    /// "3:58" / "1:02:03"
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// "1 h 32 min" / "45 min"
    static func longDuration(_ seconds: Double) -> String {
        let total = Int((seconds / 60).rounded())
        let h = total / 60, m = total % 60
        if h > 0 && m > 0 { return L10n.f("fmt_hours_minutes", h, m) }
        if h > 0 { return L10n.f("fmt_hours", h) }
        return L10n.f("fmt_minutes", max(m, 0))
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        let nf = NumberFormatter()
        nf.locale = L10n.current.locale
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = digits
        nf.maximumFractionDigits = digits
        return nf.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
    }

    /// "4,2 MB" (RO/RU) / "4.2 MB" (EN)
    static func size(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return L10n.f("fmt_gb", decimal(mb / 1024)) }
        return L10n.f("fmt_mb", decimal(mb))
    }

    /// "4,2 MB/s" (RO/RU) / "4.2 MB/s" (EN)
    static func speed(_ bytesPerSecond: Double) -> String {
        let mb = bytesPerSecond / 1_048_576
        if mb >= 1 { return L10n.f("fmt_speed_mb", decimal(mb)) }
        return L10n.f("fmt_speed_kb", decimal(bytesPerSecond / 1024, digits: 0))
    }
}
