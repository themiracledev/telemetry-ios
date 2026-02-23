//
//  ConfigSettingsView.swift
//  tmTrackerExample
//
//  Set API URLs and keys here. Values are saved to the device (UserDefaults) and persist
//  when you run the app without the cable. Restart the app after saving for tracker config to apply.
//

import SwiftUI

struct ConfigSettingsView: View {
    @State private var analyticsBaseUrl: String = ""
    @State private var analyticsSdkId: String = ""
    @State private var analyticsDistributor: String = ""
    @State private var benefitsApiBaseUrl: String = ""
    @State private var benefitsApiKey: String = ""
    @State private var savedMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Values are stored on the device and persist when you run without the cable. Restart the app after saving for tracker changes to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Analytics (Tracker)") {
                TextField("ANALYTICS_BASE_URL (optional)", text: $analyticsBaseUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("ANALYTICS_SDK_ID *", text: $analyticsSdkId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("ANALYTICS_DISTRIBUTOR (optional)", text: $analyticsDistributor)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Benefits API") {
                TextField("BENEFITS_API_BASE_URL (optional)", text: $benefitsApiBaseUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("BENEFITS_API_KEY *", text: $benefitsApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Text("* Required - no defaults in code for security")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save to device") {
                    saveToDevice()
                }
                .frame(maxWidth: .infinity)

                if let msg = savedMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Config")
        .onAppear { loadCurrent() }
    }

    private func loadCurrent() {
        // URLs can have defaults (they're endpoints, not secrets)
        analyticsBaseUrl = AppConfig.string(key: "ANALYTICS_BASE_URL", default: "")
        benefitsApiBaseUrl = AppConfig.string(key: "BENEFITS_API_BASE_URL", default: "")
        // Secrets must be explicitly set (no defaults in code)
        analyticsSdkId = AppConfig.requiredString(key: "ANALYTICS_SDK_ID")
        analyticsDistributor = AppConfig.string(key: "ANALYTICS_DISTRIBUTOR", default: "")
        benefitsApiKey = AppConfig.requiredString(key: "BENEFITS_API_KEY")
    }

    private func saveToDevice() {
        AppConfig.set(key: "ANALYTICS_BASE_URL", value: analyticsBaseUrl)
        AppConfig.set(key: "ANALYTICS_SDK_ID", value: analyticsSdkId)
        AppConfig.set(key: "ANALYTICS_DISTRIBUTOR", value: analyticsDistributor)
        AppConfig.set(key: "BENEFITS_API_BASE_URL", value: benefitsApiBaseUrl)
        AppConfig.set(key: "BENEFITS_API_KEY", value: benefitsApiKey)
        savedMessage = "Saved. Restart the app for tracker config to apply."
    }
}

#Preview {
    NavigationStack {
        ConfigSettingsView()
    }
}
