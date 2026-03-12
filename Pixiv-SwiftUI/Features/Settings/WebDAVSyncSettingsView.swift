import SwiftUI

struct WebDAVSyncSettingsView: View {
    @Environment(AccountStore.self) private var accountStore
    @State private var syncStore = WebDAVSyncStore.shared
    @State private var showRestoreConfirmation = false

    var body: some View {
        Form {
            serverSection
            scopeSection
            actionSection
            safetySection
        }
        .formStyle(.grouped)
        .navigationTitle("同步")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            syncStore.reloadConfiguration()
        }
        .alert("同步失败", isPresented: $syncStore.showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(syncStore.errorMessage)
        }
        .confirmationDialog("从 WebDAV 恢复", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
            Button("恢复并覆盖本地同步数据", role: .destructive) {
                Task {
                    await syncStore.restoreBackup()
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将恢复安全设置、屏蔽/过滤数据、搜索历史以及小说阅读进度。本地对应数据会被远端备份覆盖。")
        }
        .toast(isPresented: $syncStore.showSuccessToast, message: syncStore.successMessage)
    }

    private var serverSection: some View {
        Section {
            webDAVURLField

            usernameField

            passwordField

            remoteDirectoryField

            Button("保存配置") {
                syncStore.saveConfiguration()
            }
            .disabled(syncStore.isBusy)
        } header: {
            Text("WebDAV")
        } footer: {
            Text("密码会保存在系统钥匙串中。推荐使用 WebDAV 的 App Password。")
        }
    }

    private var scopeSection: some View {
        Section {
            LabeledContent("当前账号") {
                Text(accountStore.currentUserId)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("远端路径") {
                Text(syncStore.accountScopeDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Text(syncStore.lastOperationDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if syncStore.isBusy {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(syncStore.busyMessage)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("同步范围")
        } footer: {
            Text("当前实现按 Pixiv 账号分目录保存远端备份，避免不同账号互相覆盖。")
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task {
                    await syncStore.testConnection()
                }
            } label: {
                Label("测试连接", systemImage: "network")
            }
            .disabled(syncStore.isBusy)

            Button {
                Task {
                    await syncStore.uploadBackup()
                }
            } label: {
                Label("上传备份", systemImage: "arrow.up.circle")
            }
            .disabled(syncStore.isBusy || !syncStore.hasConfiguration)

            Button(role: .destructive) {
                showRestoreConfirmation = true
            } label: {
                Label("从远端恢复", systemImage: "arrow.down.circle")
            }
            .disabled(syncStore.isBusy || !syncStore.hasConfiguration)
        } header: {
            Text("操作")
        } footer: {
            Text("v1 为手动同步：测试连接会自动准备远端目录；上传和恢复不会同步 Pixiv 登录态。")
        }
    }

    private var safetySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("会同步：安全设置子集、屏蔽/过滤数据、搜索历史、小说阅读进度与阅读器设置", systemImage: "checkmark.circle")
                Label("不会同步：Pixiv token、Cookie、密码、翻译 API Key、下载路径、下载任务、图片缓存", systemImage: "lock.slash")
            }
            .font(.footnote)
        } header: {
            Text("已同步 / 不同步")
        }
    }

    @ViewBuilder
    private var webDAVURLField: some View {
        #if os(iOS)
        TextField("https://example.com/dav/", text: $syncStore.serverURLString)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
        #else
        TextField("https://example.com/dav/", text: $syncStore.serverURLString)
        #endif
    }

    @ViewBuilder
    private var usernameField: some View {
        #if os(iOS)
        TextField("用户名", text: $syncStore.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("用户名", text: $syncStore.username)
        #endif
    }

    @ViewBuilder
    private var passwordField: some View {
        #if os(iOS)
        SecureField("应用专用密码 / WebDAV 密码", text: $syncStore.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        SecureField("应用专用密码 / WebDAV 密码", text: $syncStore.password)
        #endif
    }

    @ViewBuilder
    private var remoteDirectoryField: some View {
        #if os(iOS)
        TextField("远端目录", text: $syncStore.remoteDirectory)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("远端目录", text: $syncStore.remoteDirectory)
        #endif
    }
}

#Preview {
    NavigationStack {
        WebDAVSyncSettingsView()
            .environment(AccountStore.shared)
    }
}
