import Foundation

/// Preference property observers fire while `Preferences` hydrates from disk.
/// Those observers must not post notifications or write the store: launch
/// observers already registered on `Preferences.shared` would re-enter the
/// still-running `dispatch_once`.
public enum PreferencePublicationPolicy {
    public static func shouldPublishSideEffects(isHydrating: Bool) -> Bool {
        !isHydrating
    }
}
