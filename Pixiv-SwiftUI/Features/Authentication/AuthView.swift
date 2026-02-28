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
    @State private var phpSessIdInput: String = ""
    @State private var showAjaxWebLogin = false
    @State private var codeVerifier: String = ""
    @State private var loginMode: LoginMode = .main
    @State private var authStep: AuthStep = .oauth
    @Bindable var accountStore: AccountStore
    var onGuestMode: (() -> Void)?

    enum LoginMode {
        case main
        case token
    }

    enum AuthStep {
        case oauth
        case ajaxOptional
    }

    struct CapturedAjaxCookies {
        let phpSessId: String
        let yuidB: String?
        let pAbDId: String?
        let pAbId: String?
        let pAbId2: String?
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

                ZStack {
                    if authStep == .oauth {
                        if loginMode == .main {
                            mainLoginView
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .leading)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                        } else {
                            tokenLoginView
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .trailing))
                                ))
                        }
                    } else {
                        ajaxOptionalView
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .trailing))
                            ))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: loginMode)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: authStep)

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
        .onAppear {
            if accountStore.isLoggedIn {
                authStep = .ajaxOptional
                phpSessIdInput = accountStore.currentAccount?.webPHPSESSID ?? ""
            }
        }
        .onChange(of: accountStore.isLoggedIn) { _, isLoggedIn in
            guard isLoggedIn else { return }
            authStep = .ajaxOptional
            if let webPHPSESSID = accountStore.currentAccount?.webPHPSESSID {
                phpSessIdInput = webPHPSESSID
            }
        }
        .sheet(isPresented: $showAjaxWebLogin) {
            AjaxSessionWebLoginSheet { cookies in
                phpSessIdInput = cookies.phpSessId
                Task {
                    await saveAjaxSession(cookies)
                }
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 600)
        #endif
    }

    var mainLoginView: some View {
        VStack(spacing: 20) {
            Button(action: startWebLogin) {
                Text(String(localized: "登录（OAuth）"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(color: themeManager.currentColor))

            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    loginMode = .token
                }
            }) {
                Text(String(localized: "使用 refresh_token 登录"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(color: nil))

        }
    }

    var tokenLoginView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
Label(String(localized: "刷新令牌"), systemImage: "key.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                SecureField(String(localized: "输入您的 refresh_token"), text: $refreshToken)
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

            Button(action: loginWithToken) {
                ZStack {
                    if accountStore.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(String(localized: "登录"))
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(color: themeManager.currentColor))
            .disabled(refreshToken.isEmpty || accountStore.isLoading)

            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    loginMode = .main
                }
            }) {
                Text(String(localized: "返回"))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(color: nil))
        }
    }

    var ajaxOptionalView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "OAuth 登录已完成"))
                    .font(.headline)
                Text(String(localized: "Ajax API 登录是可选项，可通过 WebView 自动获取或手动输入 PHPSESSID。"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                showAjaxWebLogin = true
            }) {
                Text(String(localized: "通过 WebView 登录 Ajax API（可选）"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(color: themeManager.currentColor))

            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "手动输入 PHPSESSID"), systemImage: "key.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                SecureField("PHPSESSID", text: $phpSessIdInput)
                    .onSubmit {
                        Task {
                            await saveAjaxSession(phpSessIdInput)
                        }
                    }
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

            Button(action: finishAndEnterHome) {
                Text(String(localized: "进入主页"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(color: themeManager.currentColor))
        }
    }

    func startWebLogin() {
        codeVerifier = PKCEHelper.generateCodeVerifier()
        let codeChallenge = PKCEHelper.generateCodeChallenge(codeVerifier: codeVerifier)
        let urlString = "https://app-api.pixiv.net/web/v1/login?code_challenge=\(codeChallenge)&code_challenge_method=S256&client=pixiv-android"
        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let callbackURL = try await AuthenticationManager.shared.startLogin(url: url, callbackScheme: "pixiv")
                if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    await accountStore.loginWithCode(code, codeVerifier: codeVerifier)
                    if accountStore.isLoggedIn {
                        authStep = .ajaxOptional
                        phpSessIdInput = accountStore.currentAccount?.webPHPSESSID ?? ""
                    }
                }
            } catch is CancellationError {
                // 用户取消，无需处理
            } catch {
                // 处理其他错误
                print("登录失败: \(error)")
            }
        }
    }

    func loginWithToken() {
        Task {
            await accountStore.loginWithRefreshToken(refreshToken)
            if accountStore.isLoggedIn {
                authStep = .ajaxOptional
                phpSessIdInput = accountStore.currentAccount?.webPHPSESSID ?? ""
            }
        }
    }

    func saveAjaxSession(_ phpsessidRaw: String) async {
        let phpsessid = phpsessidRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phpsessid.isEmpty else { return }

        accountStore.updateCurrentAccountAjaxCookies(
            phpSessId: phpsessid,
            yuidB: nil,
            pAbDId: nil,
            pAbId: nil,
            pAbId2: nil
        )
        await updateAjaxSessionValidationResult(isFromWebView: false)
    }

    func saveAjaxSession(_ cookies: CapturedAjaxCookies) async {
        accountStore.updateCurrentAccountAjaxCookies(
            phpSessId: cookies.phpSessId,
            yuidB: cookies.yuidB,
            pAbDId: cookies.pAbDId,
            pAbId: cookies.pAbId,
            pAbId2: cookies.pAbId2
        )
        await updateAjaxSessionValidationResult(isFromWebView: true)
    }

    private func updateAjaxSessionValidationResult(isFromWebView: Bool) async {
        let isValid = await PixivAPI.shared.validateAjaxSession()

        if isValid {
            accountStore.error = nil
            return
        }

        accountStore.clearCurrentAccountPHPSESSID()
        phpSessIdInput = ""
        accountStore.error = .authenticationError("Ajax 会话校验失败：当前 PHPSESSID 不是登录态，请在 WebView 中先完成 Pixiv 网页登录")
    }

    func finishAndEnterHome() {
        accountStore.markLoginAttempted()
        dismiss()
    }
}

private struct AjaxSessionWebLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPHPSESSIDCaptured: (AuthView.CapturedAjaxCookies) -> Void
    @State private var capturedCookies: AuthView.CapturedAjaxCookies?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                AjaxSessionWebLoginView { cookies in
                    capturedCookies = cookies
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider()

                Text(String(localized: "登录成功后将自动捕获 PHPSESSID"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .navigationTitle(String(localized: "Ajax 登录"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) {
                        if let capturedCookies {
                            onPHPSESSIDCaptured(capturedCookies)
                        }
                        dismiss()
                    }
                    .disabled(capturedCookies == nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
        #endif
    }
}

private struct AjaxSessionWebLoginView: AuthWebViewRepresentable {
    let onPHPSESSIDCaptured: (AuthView.CapturedAjaxCookies) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPHPSESSIDCaptured: onPHPSESSIDCaptured)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: APIEndpoint.webBaseURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: APIEndpoint.webBaseURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
    #endif

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onPHPSESSIDCaptured: (AuthView.CapturedAjaxCookies) -> Void

        init(onPHPSESSIDCaptured: @escaping (AuthView.CapturedAjaxCookies) -> Void) {
            self.onPHPSESSIDCaptured = onPHPSESSIDCaptured
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                guard let sessionCookie = self.selectBestSessionCookie(from: cookies) else {
                    return
                }

                guard !sessionCookie.value.isEmpty else {
                    return
                }
                let cookieMap = cookies.reduce(into: [String: String]()) { partialResult, cookie in
                    guard self.isPixivWebDomain(cookie.domain) else { return }
                    partialResult[cookie.name] = cookie.value
                }

                let captured = AuthView.CapturedAjaxCookies(
                    phpSessId: sessionCookie.value,
                    yuidB: cookieMap["yuid_b"],
                    pAbDId: cookieMap["p_ab_d_id"],
                    pAbId: cookieMap["p_ab_id"],
                    pAbId2: cookieMap["p_ab_id_2"]
                )

                DispatchQueue.main.async {
                    self.onPHPSESSIDCaptured(captured)
                }
            }
        }

        private func selectBestSessionCookie(from cookies: [HTTPCookie]) -> HTTPCookie? {
            let candidates = cookies.filter { cookie in
                cookie.name == "PHPSESSID" && isPixivWebDomain(cookie.domain)
            }

            guard !candidates.isEmpty else { return nil }

            return candidates.max(by: { lhs, rhs in
                cookiePriority(lhs) < cookiePriority(rhs)
            })
        }

        private func isPixivWebDomain(_ domain: String) -> Bool {
            let normalized = domain.lowercased()
            if normalized.contains("accounts.pixiv.net") {
                return false
            }

            return normalized == "www.pixiv.net"
                || normalized == ".pixiv.net"
                || normalized.hasSuffix(".pixiv.net")
        }

        private func cookiePriority(_ cookie: HTTPCookie) -> Int {
            let domain = cookie.domain.lowercased()
            var score = 0

            switch domain {
            case "www.pixiv.net":
                score += 300
            case ".pixiv.net":
                score += 200
            default:
                if domain.hasSuffix(".pixiv.net") {
                    score += 100
                }
            }

            if cookie.path == "/" {
                score += 10
            }

            return score
        }
    }
}

#Preview {
    AuthView(accountStore: .shared)
}
