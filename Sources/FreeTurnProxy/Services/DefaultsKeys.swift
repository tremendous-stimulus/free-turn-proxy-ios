import Foundation

enum DefaultsKeys {
    static let manualLink = "manualLink"       // legacy — одна ссылка, мигрируется в manualLinks
    static let manualLinks = "manualLinks.v1"
    static let telemetryEnabled = "telemetry_enabled"
    static let persistLogs = "persist_logs"
    static let errorLoggerClientId = "error_logger_client_id"
    static let keychainBoundToInstall = "keychainBoundToInstall.v1"
    static let shakeHintPending = "shakeHintPending"
    static let savedConfigs = "savedConfigs.v1"
    static let savedConfigsSelected = "savedConfigs.selected"
    static let telemetryOnboarded = "telemetry_onboarded"
    static let coreClientId = "core_client_id"
    static let refreshBannerAnchorAt = "refresh_banner_anchor_at"
}
