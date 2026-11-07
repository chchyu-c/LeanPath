// FeatureFlags.swift
enum FeatureFlag: String {
    case checkoutNewUi = "checkout_new_ui_enabled"
}
struct FeatureFlags {
    static func isEnabled(_ f: FeatureFlag) -> Bool {
        // RemoteConfig 覆盖本地默认
        return RemoteConfig.shared.bool(forKey: f.rawValue)
    }
}
