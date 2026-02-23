//
//  AppConfig.swift
//  tmTrackerExample
//
//  Reads config in order: UserDefaults (persists on device) → env (Xcode Scheme) → Info.plist → default.
//  Use the Settings tab to save values to UserDefaults so they persist when running without cable.
//

import Foundation

enum AppConfig {
    private static let userDefaultsPrefix = "tm_config_"

    /// Resolution order: UserDefaults → ProcessInfo.environment → Bundle.main.infoDictionary → default
    static func string(key: String, default defaultValue: String) -> String {
        if let stored = UserDefaults.standard.string(forKey: userDefaultsPrefix + key), !stored.isEmpty {
            return stored
        }
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        if let bundle = Bundle.main.infoDictionary?[key] as? String, !bundle.isEmpty {
            return bundle
        }
        return defaultValue
    }

    /// Get value without default (for secrets). Returns empty string if not set.
    /// Resolution order: UserDefaults → ProcessInfo.environment → Bundle.main.infoDictionary
    static func requiredString(key: String) -> String {
        if let stored = UserDefaults.standard.string(forKey: userDefaultsPrefix + key), !stored.isEmpty {
            return stored
        }
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        if let bundle = Bundle.main.infoDictionary?[key] as? String, !bundle.isEmpty {
            return bundle
        }
        return ""
    }

    /// Save a value to UserDefaults so it persists on device (works when running without cable).
    static func set(key: String, value: String) {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsPrefix + key)
        } else {
            UserDefaults.standard.set(value, forKey: userDefaultsPrefix + key)
        }
    }

    /// Remove stored value so next read falls back to env / Info.plist / default.
    static func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: userDefaultsPrefix + key)
    }
}
