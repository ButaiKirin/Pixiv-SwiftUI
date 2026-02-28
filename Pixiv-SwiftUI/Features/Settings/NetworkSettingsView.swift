import SwiftUI

struct NetworkSettingsView: View {
    @Environment(AccountStore.self) private var accountStore
    @State private var networkModeStore = NetworkModeStore.shared
    @State private var showAuthView = false

    var body: some View {
        Form {
            networkSection
            ajaxSessionSection
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

    private var ajaxSessionSection: some View {
        Section {
            if !accountStore.isLoggedIn {
                Text(String(localized: "请先完成 OAuth 登录后再配置 Ajax API 登录。"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                LabeledContent(String(localized: "Ajax API 状态")) {
                    Text(accountStore.hasAjaxSession ? String(localized: "已登录") : String(localized: "未登录"))
                        .foregroundColor(accountStore.hasAjaxSession ? .green : .secondary)
                }

                if !accountStore.hasAjaxSession {
                    Button(String(localized: "登录 Ajax API")) {
                        showAuthView = true
                    }
                } else {
                    Button(role: .destructive) {
                        accountStore.clearCurrentAccountPHPSESSID()
                    } label: {
                        Text(String(localized: "登出"))
                    }
                }
            }
        } header: {
            Text(String(localized: "Ajax API"))
        }
    }
}

#Preview {
    NavigationStack {
        NetworkSettingsView()
    }
}
