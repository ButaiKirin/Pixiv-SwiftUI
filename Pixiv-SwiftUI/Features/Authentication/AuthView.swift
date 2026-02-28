import SwiftUI
import WebKit

#if os(macOS)
private typealias AuthWebViewRepresentable = NSViewRepresentable
#else
private typealias AuthWebViewRepresentable = UIViewRepresentable
#endif

/// 登录页面
struct AuthView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(ThemeManager.self) var themeManager
    @State private var refreshToken: String = ""
    @State private var codeVerifier: String = ""
    @State private var phpSessId: String = ""
    @State private var showLoginWebView = false
    @State private var loginURL: URL?
    @Bindable var accountStore: AccountStore
    var onGuestMode: (() -> Void)?

    enum LoginMode {
        case main
        case token
    }

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                gradient: Gradient(colors: [
                    themeManager.currentColor.opacity(0.1),
                    Color.purple.opacity(0.1),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                // 标题
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(themeManager.currentColor)

                    Text(String(localized: "Pixiv-SwiftUI"))
                        .font(.system(size: 36, weight: .bold))

                    Text(String(localized: "优雅的插画社区客户端"))
                        .font(.callout)
                        .foregroundColor(.gray)
                }

                Spacer()

                unifiedLoginView

                Spacer()

                // 错误提示
                if let error = accountStore.error {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(error.localizedDescription)
                    }
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

            }
            .padding(32)
        }
        #if os(macOS)
        .frame(width: 450, height: 660)
        #endif
        .sheet(isPresented: $showLoginWebView) {
            if let url = loginURL {
                #if os(macOS)
                LoginWebView(url: url) { code, cookies in
                    showLoginWebView = false
                    handleLoginCallback(code: code, cookies: cookies)
                }
                .frame(width: 800, height: 600)
                #else
                NavigationStack {
                    LoginWebView(url: url) { code, cookies in
                        showLoginWebView = false
                        handleLoginCallback(code: code, cookies: cookies)
                    }
                    .navigationTitle(String(localized: "登录 Pixiv"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "取消")) {
                                showLoginWebView = false
                            }
                        }
                    }
                }
                #endif
            }
        }
    }

    var unifiedLoginView: some View {
        VStack(spacing: 24) {
            Button(action: startWebLogin) {
                Text(String(localized: "在新窗口中登录（推荐）"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(color: themeManager.currentColor))

            HStack {
                VStack { Divider().background(Color.gray) }
                Text("OR")
                    .font(.caption)
                    .foregroundColor(.gray)
                VStack { Divider().background(Color.gray) }
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "刷新令牌"), systemImage: "key.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    SecureField(String(localized: "输入您的 refresh_token（必填）"), text: $refreshToken)
                        .padding(12)
                        .background {
                            if #available(iOS 26.0, macOS 26.0, *) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.clear)
                                    .glassEffect(in: .rect(cornerRadius: 12))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "网页凭证"), systemImage: "safari.fill")
                        .fontWeight(.semibold)

                    SecureField(String(localized: "输入您的 PHPSESSID（可选）"), text: $phpSessId)
                        .padding(12)
                        .background {
                            if #available(iOS 26.0, macOS 26.0, *) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.clear)
                                    .glassEffect(in: .rect(cornerRadius: 12))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            }
                        }

                    Text(String(localized: "通过 refresh_token 登录将无法访问 Ajax API（部分功能不可用）。如果需要完整功能，请选填 PHPSESSID，或使用上方的新窗口登录。"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: loginWithToken) {
                ZStack {
                    if accountStore.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(String(localized: "进入应用"))
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(color: themeManager.currentColor))
            .disabled(refreshToken.isEmpty || accountStore.isLoading)
        }
    }

    func startWebLogin() {
        codeVerifier = PKCEHelper.generateCodeVerifier()
        let codeChallenge = PKCEHelper.generateCodeChallenge(codeVerifier: codeVerifier)
        let urlString = "https://app-api.pixiv.net/web/v1/login?code_challenge=\(codeChallenge)&code_challenge_method=S256&client=pixiv-android"
        guard let url = URL(string: urlString) else { return }

        self.loginURL = url
        self.showLoginWebView = true
    }

    func handleLoginCallback(code: String, cookies: [HTTPCookie]) {
        Task {
            // 登录 OAuth
            await accountStore.loginWithCode(code, codeVerifier: codeVerifier)

            if accountStore.isLoggedIn {
                // 提取 .pixiv.net 下的 Cookie
                var phpSessId: String?
                var yuidB: String?
                var pAbDId: String?
                var pAbId: String?
                var pAbId2: String?

                for cookie in cookies where cookie.domain.contains("pixiv.net") {
                    switch cookie.name {
                    case "PHPSESSID":
                        // 取出包含 _ 的 PHPSESSID
                        if cookie.value.contains("_") {
                            phpSessId = cookie.value
                        }
                    case "yuid_b":
                        yuidB = cookie.value
                    case "p_ab_d_id":
                        pAbDId = cookie.value
                    case "p_ab_id":
                        pAbId = cookie.value
                    case "p_ab_id_2":
                        pAbId2 = cookie.value
                    default:
                        break
                    }
                }

                accountStore.updateCurrentAccountAjaxCookies(
                    phpSessId: phpSessId,
                    yuidB: yuidB,
                    pAbDId: pAbDId,
                    pAbId: pAbId,
                    pAbId2: pAbId2
                )

                dismiss()
            }
        }
    }

    func loginWithToken() {
        Task {
            await accountStore.loginWithRefreshToken(refreshToken)
            if accountStore.isLoggedIn {
                if !phpSessId.isEmpty {
                    accountStore.updateCurrentAccountAjaxCookies(
                        phpSessId: phpSessId,
                        yuidB: nil,
                        pAbDId: nil,
                        pAbId: nil,
                        pAbId2: nil
                    )
                }
                dismiss()
            }
        }
    }

    func finishAndEnterHome() {
        accountStore.markLoginAttempted()
        dismiss()
    }
}

#Preview {
    AuthView(accountStore: .shared)
}
