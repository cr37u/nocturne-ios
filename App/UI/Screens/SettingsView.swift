import SwiftUI
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Setări: language (live), background / system integration status, storage, about.
struct SettingsView: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var library: Library
    @Environment(\.metrics) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var liveActivityOn = UserDefaults.standard.bool(forKey: "liveActivityEnabled")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    IconButton(icon: .chevronLeft, label: L10n.t("cd_back")) { dismiss() }
                    Text(L10n.t("settings"))
                        .font(.manrope(26, .extraBold, relativeTo: .title))
                        .foregroundStyle(NC.text)
                    Spacer()
                }

                section(L10n.t("settings_language_section")) {
                    VStack(spacing: 10) {
                        ForEach(AppLanguage.allCases) { language in
                            LanguageCard(language: language, selected: lang.selection == language) {
                                Haptics.soft()
                                withAnimation(.easeOut(duration: 0.2)) { lang.select(language) }
                            }
                        }
                        SettingsRow(icon: .globe, title: L10n.t("language_ios_settings"), subtitle: L10n.t("language_ios_settings_body"), chevron: true) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }

                section(L10n.t("settings_system_section")) {
                    VStack(spacing: 10) {
                        Toggle(isOn: $liveActivityOn) {
                            HStack(spacing: 14) {
                                IconView(icon: .activity, size: 19)
                                    .foregroundStyle(liveActivityOn ? NC.amber : NC.text)
                                    .frame(width: 40, height: 40)
                                    .background(NC.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.t("live_activity_toggle"))
                                        .font(.manrope(15, .bold, relativeTo: .body))
                                        .foregroundStyle(NC.text)
                                    Text(L10n.t("live_activity_toggle_body") + (liveActivitiesEnabled ? "" : "\n" + L10n.t("live_activities_off")))
                                        .font(.manrope(13, relativeTo: .footnote))
                                        .foregroundStyle(NC.text2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .tint(NC.brightStart)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .onChange(of: liveActivityOn) { on in
                            UserDefaults.standard.set(on, forKey: "liveActivityEnabled")
                            SystemSurfaces.shared.refreshAll()
                        }
                    }
                }

                section(L10n.t("storage_title")) {
                    VStack(spacing: 10) {
                        SettingsRow(icon: .storage, title: L10n.t("storage_title"),
                                    subtitle: L10n.f("storage_body", L10n.p("songs_count", library.tracks.count), Fmt.size(library.totalBytes)))
                        SettingsRow(icon: .folder, title: L10n.t("files_title"), subtitle: L10n.t("files_body"), chevron: true) {
                            // Opens the Files app at Nocturne's folder.
                            if let url = URL(string: "shareddocuments://" + Storage.musicDir.path) { UIApplication.shared.open(url) }
                        }
                    }
                }

                section(L10n.t("about_section")) {
                    VStack(spacing: 10) {
                        SettingsRow(icon: .info, title: L10n.t("app_version"), subtitle: appVersion)
                        SettingsRow(icon: .youtube, title: DownloadManager.shared.resolver.name,
                                    subtitle: DownloadManager.shared.resolver.version)
                        SettingsRow(icon: .info, title: "Device",
                                    subtitle: "\(DeviceProfile.modelIdentifier) · \(m.profile.label) · \(Int(m.width)) pt")
                    }
                }
            }
            .padding(.horizontal, m.hPad)
            .padding(.top, m.topPad)
            MiniPlayerSpacer()
        }
        .background(NC.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("settings")
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var liveActivitiesEnabled: Bool {
        if #available(iOS 16.1, *) { return ActivityAuthorizationInfo().areActivitiesEnabled }
        return false
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.manrope(12, .bold, relativeTo: .caption))
                .tracking(0.7)
                .foregroundStyle(NC.text2)
            content()
        }
    }
}

/// Radio card: language name in its own language + RO/EN/RU chip; selected = 1.5 pt #3B6CF6 border + amber check.
struct LanguageCard: View {
    let language: AppLanguage
    let selected: Bool
    let action: () -> Void
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.nativeName)
                        .font(.manrope(16, .bold, relativeTo: .body))
                        .foregroundStyle(NC.text)
                        .lineLimit(1)
                    if language == .system {
                        Text(L10n.t("language_system_body"))
                            .font(.manrope(12, relativeTo: .caption))
                            .foregroundStyle(NC.text2)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let chip = language.chip {
                    Text(verbatim: chip)
                        .font(.manropeFixed(11, .extraBold))
                        .tracking(0.6)
                        .foregroundStyle(selected ? NC.text : NC.text2)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(selected ? NC.brightStart.opacity(0.25) : NC.elevated, in: Capsule())
                }
                ZStack {
                    Circle().stroke(selected ? NC.amber : NC.text2.opacity(0.5), lineWidth: 1.5)
                    if selected {
                        Circle().fill(NC.amber)
                        IconView(icon: .check, size: 13, lineWidth: 3).foregroundStyle(NC.bg)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(selected ? NC.brightStart : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("lang-\(language.rawValue)")
    }
}

struct SettingsRow: View {
    let icon: Icon
    let title: String
    var subtitle: String?
    var accent = false
    var chevron = false
    var action: (() -> Void)?

    var body: some View {
        let row = HStack(spacing: 14) {
            IconView(icon: icon, size: 19)
                .foregroundStyle(accent ? NC.amber : NC.text)
                .frame(width: 40, height: 40)
                .background(NC.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.manrope(15, .bold, relativeTo: .body))
                    .foregroundStyle(NC.text)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.manrope(13, relativeTo: .footnote))
                        .foregroundStyle(NC.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                IconView(icon: .chevronRight, size: 16).foregroundStyle(NC.text2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

        if let action {
            Button(action: action) { row }.buttonStyle(PressScaleStyle(scale: 0.98))
        } else {
            row.accessibilityElement(children: .combine)
        }
    }
}
