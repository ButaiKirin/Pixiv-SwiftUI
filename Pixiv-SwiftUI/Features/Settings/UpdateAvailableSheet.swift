import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct UpdateAvailableSheet: View {
    let updateInfo: AppUpdateInfo
    @Binding var isPresented: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("发现新版本")
                .font(.title2)
                .fontWeight(.semibold)

            Text("v\(updateInfo.version)")
                .font(.headline)
                .foregroundColor(.secondary)

            ScrollView {
                Text(updateInfo.releaseNotes)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            .frame(maxHeight: 150)

            HStack(spacing: 20) {
                Button("关闭") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("查看更新") {
                    if let url = URL(string: updateInfo.releaseUrl) {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 400, height: 400)
    }
}

#Preview {
    UpdateAvailableSheet(
        updateInfo: AppUpdateInfo(
            version: "0.11.2",
            releaseName: "v0.11.2",
            releaseNotes: "修复了一些 bug\n新增了功能\n优化了性能",
            releaseUrl: "https://github.com/Eslzzyl/Pixiv-SwiftUI/releases",
            downloadUrl: nil
        ),
        isPresented: .constant(true)
    )
}
