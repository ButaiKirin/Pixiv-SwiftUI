import SwiftUI

struct NetworkSettingsView: View {
    @Environment(AccountStore.self) private var accountStore
    @State private var networkModeStore = NetworkModeStore.shared
    @State private var showAuthView = false

    var body: some View {
        Form {
            networkSection
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "网络"))
        .sheet(isPresented: $showAuthView) {
            AuthView(accountStore: accountStore, onGuestMode: nil)
        }
    }

    private var networkSection: some View {
        Section {
            LabeledContent(String(localized: "网络模式")) {
                Picker("", selection: $networkModeStore.currentMode) {
                    ForEach(NetworkMode.allCases) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #endif
            }
        } header: {
            Text(String(localized: "网络"))
        } footer: {
            Text(networkModeStore.currentMode.description)
        }
    }
}

#Preview {
    NavigationStack {
        NetworkSettingsView()
    }
}
