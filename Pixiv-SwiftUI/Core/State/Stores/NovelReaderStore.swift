import Foundation
import SwiftUI
import TranslationKit

extension Notification.Name {
    static let novelReaderShouldRestorePosition = Notification.Name("novelReaderShouldRestorePosition")
    static let novelReaderProgressDidSave = Notification.Name("novelReaderProgressDidSave")
}

@Observable
@MainActor
final class NovelReaderStore {
    let novelId: Int

    var content: NovelReaderContent?
    var spans: [NovelSpan] = []
    var isLoading = false
    var errorMessage: String?
    var translationError: String?

    var translatedParagraphs: [Int: String] = [:]
    var isTranslationEnabled = false
    var isTranslatingAll = false
    var translatingIndices: Set<Int> = []

    var isBookmarked: Bool = false

    @ObservationIgnored
    var savedIndex: Int?

    @ObservationIgnored
    var hasRestoredPosition = false

    var savedTotalSpans: Int?

    var settings: NovelReaderSettings = NovelReaderSettings()

    @ObservationIgnored
    var visibleParagraphIndices: Set<Int> = []

    @ObservationIgnored
    private var debounceTask: Task<Void, Never>?

    private let cacheStore = NovelTranslationCacheStore.shared
    private let progressKey = "novel_reader_progress_"
    private let settingsKey = "novel_reader_settings"

    private struct NovelTranslationBatchPlan: Sendable {
        let paragraphIndices: [Int]
        let inputs: [NovelBatchInput]
        let context: [String]
    }

    private enum NovelBatchTaskResult: Sendable {
        case success(indices: [Int], translations: [Int: String])
        case failed(indices: [Int], message: String)
    }

    var novel: NovelReaderContent? {
        content
    }

    var seriesNavigation: SeriesNavigation? {
        content?.seriesNavigation
    }

    init(novelId: Int) {
        self.novelId = novelId
        loadSettings()
        loadProgress()
    }

    private func loadProgress() {
        let key = "\(progressKey)\(novelId)"
        if let data = UserDefaults.standard.dictionary(forKey: key),
           let index = data["index"] as? Int,
           let total = data["total"] as? Int {
            savedIndex = index
            savedTotalSpans = total
        } else if let progress = UserDefaults.standard.object(forKey: key) as? Int {
            // 向后兼容：旧格式只有索引
            savedIndex = progress
            savedTotalSpans = nil
        } else {
            savedIndex = nil
            savedTotalSpans = nil
        }
    }

    func paragraphAppeared(index: Int) {
        visibleParagraphIndices.insert(index)
        triggerDebouncedUpdate()
    }

    func paragraphDisappeared(index: Int) {
        visibleParagraphIndices.remove(index)
        triggerDebouncedUpdate()
    }

    private func triggerDebouncedUpdate() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            if isTranslationEnabled {
                await startTranslationForVisibleParagraphs()
            }
        }
    }

    func updateVisibleParagraphs(_ indices: Set<Int>) {
        visibleParagraphIndices = indices
        triggerDebouncedUpdate()
    }

    func isParagraphVisible(_ index: Int) -> Bool {
        visibleParagraphIndices.contains(index)
    }

    func fetch() async {
        guard !isLoading else { return }
        print("[NovelReaderStore] Fetching content for novelId=\(novelId)")
        isLoading = true
        errorMessage = nil

        do {
            let fetchedContent = try await PixivAPI.shared.getNovelContent(novelId: novelId)
            print("[NovelReaderStore] Fetched content, text length=\(fetchedContent.text.count)")
            content = fetchedContent
            isBookmarked = fetchedContent.isBookmarked ?? false

            let cleanedText = NovelTextParser.shared.cleanHTML(fetchedContent.text)
            spans = NovelTextParser.shared.parse(cleanedText, illusts: fetchedContent.illusts, images: fetchedContent.images)
            print("[NovelReaderStore] Parsed into \(spans.count) spans")

            isLoading = false

            await cacheStore.preloadCache(for: novelId)

            loadProgress()
            if let index = savedIndex {
                print("[NovelReaderStore] Restoring progress to index \(index)")
                NotificationCenter.default.post(name: .novelReaderShouldRestorePosition, object: nil)
            }
        } catch {
            print("[NovelReaderStore] Fetch failed: \(error)")
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func translateParagraph(_ index: Int, text: String) async {
        guard !translatingIndices.contains(index) else { return }

        translatingIndices.insert(index)

        let serviceId = UserSettingStore.shared.userSetting.translatePrimaryServiceId
        let targetLang = UserSettingStore.shared.userSetting.translateTargetLanguage.isEmpty
            ? "zh-CN"
            : UserSettingStore.shared.userSetting.translateTargetLanguage

        if let cached = await cacheStore.get(
            novelId: novelId,
            paragraphIndex: index,
            originalText: text,
            serviceId: serviceId,
            targetLanguage: targetLang
        ) {
            translatedParagraphs[index] = cached
            translatingIndices.remove(index)
            return
        }

        do {
            let translated = try await performTranslation(text: text, serviceId: serviceId, targetLanguage: targetLang)
            translatedParagraphs[index] = translated
            await cacheStore.save(
                novelId: novelId,
                paragraphIndex: index,
                originalText: text,
                translatedText: translated,
                serviceId: serviceId,
                targetLanguage: targetLang
            )
        } catch {
            translationError = "翻译失败，请检查服务配置"
            print("Translation failed for paragraph \(index): \(error)")
        }

        translatingIndices.remove(index)
    }

    func toggleTranslation() async {
        isTranslationEnabled.toggle()
        if isTranslationEnabled {
            translationError = nil
            await startTranslationForVisibleParagraphs()
        }
    }

    func toggleTranslationForTranslationOnly() async {
        isTranslationEnabled.toggle()
        if isTranslationEnabled {
            translationError = nil
            await startTranslationForVisibleParagraphs()
        } else {
            translatedParagraphs.removeAll()
        }
    }

    private func startTranslationForVisibleParagraphs() async {
        let setting = UserSettingStore.shared.userSetting
        let serviceId = setting.translatePrimaryServiceId
        let targetLanguage = setting.translateTargetLanguage.isEmpty ? "zh-CN" : setting.translateTargetLanguage
        let sortedIndices = visibleParagraphIndices.sorted()
        let pendingIndices = await collectPendingParagraphIndices(
            from: sortedIndices,
            serviceId: serviceId,
            targetLanguage: targetLanguage
        )

        guard !pendingIndices.isEmpty else { return }

        if shouldUseOpenAIBatchTranslation(serviceId: serviceId, setting: setting) {
            let plans = buildBatchPlans(indices: pendingIndices, setting: setting)
            if plans.isEmpty {
                return
            }
            await executeBatchPlans(
                plans,
                setting: setting,
                serviceId: serviceId,
                targetLanguage: targetLanguage
            )
        } else {
            for index in pendingIndices {
                await translateParagraph(index, text: spans[index].content)
            }
        }
    }

    private func shouldUseOpenAIBatchTranslation(serviceId: String, setting: UserSetting) -> Bool {
        serviceId == "openai" && setting.translateNovelBatchEnabled
    }

    private func collectPendingParagraphIndices(
        from indices: [Int],
        serviceId: String,
        targetLanguage: String
    ) async -> [Int] {
        var pending: [Int] = []

        for index in indices where index < spans.count {
            let span = spans[index]
            let text = span.content
            if span.type != .normal || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            if translatedParagraphs[index] != nil || translatingIndices.contains(index) {
                continue
            }

            if let cached = await cacheStore.get(
                novelId: novelId,
                paragraphIndex: index,
                originalText: text,
                serviceId: serviceId,
                targetLanguage: targetLanguage
            ) {
                translatedParagraphs[index] = cached
                continue
            }

            pending.append(index)
        }

        return pending
    }

    private func buildBatchPlans(indices: [Int], setting: UserSetting) -> [NovelTranslationBatchPlan] {
        let maxParagraphs = max(1, setting.translateNovelBatchMaxParagraphs)
        let maxCharacters = max(500, setting.translateNovelBatchMaxCharacters)
        let contextCount = max(0, setting.translateNovelContextParagraphs)

        var groups: [[Int]] = []
        var currentGroup: [Int] = []

        for index in indices {
            if let last = currentGroup.last, index != last + 1 {
                groups.append(currentGroup)
                currentGroup = [index]
            } else {
                currentGroup.append(index)
            }
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        var plans: [NovelTranslationBatchPlan] = []

        for group in groups {
            var currentIndices: [Int] = []
            var currentInputs: [NovelBatchInput] = []
            var currentCharacters = 0

            func flushCurrentBatch() {
                guard !currentIndices.isEmpty else { return }
                let context = contextParagraphs(before: currentIndices[0], count: contextCount)
                plans.append(
                    NovelTranslationBatchPlan(
                        paragraphIndices: currentIndices,
                        inputs: currentInputs,
                        context: context
                    )
                )
                currentIndices.removeAll(keepingCapacity: true)
                currentInputs.removeAll(keepingCapacity: true)
                currentCharacters = 0
            }

            for index in group {
                let text = spans[index].content
                let count = text.count

                if !currentIndices.isEmpty &&
                    (currentIndices.count >= maxParagraphs || currentCharacters + count > maxCharacters) {
                    flushCurrentBatch()
                }

                currentIndices.append(index)
                currentInputs.append(NovelBatchInput(id: index, text: text))
                currentCharacters += count
            }

            flushCurrentBatch()
        }

        return plans
    }

    private func contextParagraphs(before firstIndex: Int, count: Int) -> [String] {
        guard count > 0 else { return [] }

        var context: [String] = []
        var currentIndex = firstIndex - 1

        while currentIndex >= 0 && context.count < count {
            let span = spans[currentIndex]
            let text = span.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if span.type == .normal && !text.isEmpty {
                context.append(span.content)
            }
            currentIndex -= 1
        }

        return context.reversed()
    }

    private func executeBatchPlans(
        _ plans: [NovelTranslationBatchPlan],
        setting: UserSetting,
        serviceId: String,
        targetLanguage: String
    ) async {
        let maxConcurrent = min(max(1, setting.translateNovelMaxConcurrentBatches), 4)
        let baseURL = setting.translateOpenAIBaseURL.isEmpty ? "https://api.openai.com/v1" : setting.translateOpenAIBaseURL
        let model = setting.translateOpenAIModel.isEmpty ? "gpt-5.1-nano" : setting.translateOpenAIModel
        let apiKey = setting.translateOpenAIApiKey
        let temperature = setting.translateOpenAITemperature
        let novelSystemPrompt = setting.translateNovelSystemPrompt

        var iterator = plans.makeIterator()

        await withTaskGroup(of: NovelBatchTaskResult.self) { group in
            for _ in 0..<min(maxConcurrent, plans.count) {
                if let plan = iterator.next() {
                    for index in plan.paragraphIndices {
                        translatingIndices.insert(index)
                    }

                    group.addTask {
                        do {
                            let translations = try await NovelBatchTranslator.shared.translateBatch(
                                paragraphs: plan.inputs,
                                context: plan.context,
                                targetLanguage: targetLanguage,
                                baseURL: baseURL,
                                apiKey: apiKey,
                                model: model,
                                temperature: temperature,
                                baseSystemPrompt: novelSystemPrompt
                            )
                            return .success(indices: plan.paragraphIndices, translations: translations)
                        } catch {
                            return .failed(indices: plan.paragraphIndices, message: error.localizedDescription)
                        }
                    }
                }
            }

            while let result = await group.next() {
                switch result {
                case .success(let indices, let translations):
                    var missingIndices: [Int] = []

                    for index in indices {
                        if let translated = translations[index], !translated.isEmpty {
                            translatedParagraphs[index] = translated
                            await cacheStore.save(
                                novelId: novelId,
                                paragraphIndex: index,
                                originalText: spans[index].content,
                                translatedText: translated,
                                serviceId: serviceId,
                                targetLanguage: targetLanguage
                            )
                        } else {
                            missingIndices.append(index)
                        }
                        translatingIndices.remove(index)
                    }

                    for index in missingIndices {
                        await translateParagraph(index, text: spans[index].content)
                    }

                case .failed(let indices, let message):
                    translationError = "批量翻译失败，已回退单段翻译"
                    print("Batch translation failed: \(message)")

                    for index in indices {
                        translatingIndices.remove(index)
                    }

                    for index in indices {
                        await translateParagraph(index, text: spans[index].content)
                    }
                }

                if let next = iterator.next() {
                    for index in next.paragraphIndices {
                        translatingIndices.insert(index)
                    }

                    group.addTask {
                        do {
                            let translations = try await NovelBatchTranslator.shared.translateBatch(
                                paragraphs: next.inputs,
                                context: next.context,
                                targetLanguage: targetLanguage,
                                baseURL: baseURL,
                                apiKey: apiKey,
                                model: model,
                                temperature: temperature,
                                baseSystemPrompt: novelSystemPrompt
                            )
                            return .success(indices: next.paragraphIndices, translations: translations)
                        } catch {
                            return .failed(indices: next.paragraphIndices, message: error.localizedDescription)
                        }
                    }
                }
            }
        }
    }

    func translateAllParagraphs() async {
        guard !isTranslatingAll else { return }
        translationError = nil
        isTranslatingAll = true
        defer { isTranslatingAll = false }

        for (index, span) in spans.enumerated() {
            if span.type == .normal && !span.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await translateParagraph(index, text: span.content)
            }
        }
    }

private func performTranslation(text: String, serviceId: String, targetLanguage: String) async throws -> String {
        let service: any TranslateService

        switch serviceId {
        case "google":
            service = GoogleTranslateService()
        case "googleapi":
            service = GoogleAPITranslateService()
        case "openai":
            let setting = UserSettingStore.shared.userSetting
            service = OpenAITranslateService(
                baseURL: setting.translateOpenAIBaseURL.isEmpty ? "https://api.openai.com/v1" : setting.translateOpenAIBaseURL,
                apiKey: setting.translateOpenAIApiKey,
                model: setting.translateOpenAIModel.isEmpty ? "gpt-3.5-turbo" : setting.translateOpenAIModel,
                temperature: setting.translateOpenAITemperature,
                systemPrompt: setting.translateNovelSystemPrompt
            )
        case "baidu":
            let setting = UserSettingStore.shared.userSetting
            let config = BaiduTranslateConfig(
                appid: setting.translateBaiduAppid,
                key: setting.translateBaiduKey,
                action: "0"
            )
            service = BaiduTranslateService(config: config)
        case "bing":
            service = BingTranslateService()
        case "tencent":
            let setting = UserSettingStore.shared.userSetting
            let config = TencentTranslateConfig(
                secretId: setting.translateTencentSecretId,
                secretKey: setting.translateTencentSecretKey,
                region: setting.translateTencentRegion.isEmpty ? "ap-shanghai" : setting.translateTencentRegion,
                projectId: setting.translateTencentProjectId.isEmpty ? "0" : setting.translateTencentProjectId
            )
            service = TencentTranslateService(config: config)
        default:
            service = GoogleTranslateService()
        }

        var task = TranslateTask(
            raw: text,
            sourceLanguage: nil,
            targetLanguage: targetLanguage
        )
        try await service.translate(&task)
        return task.result
    }

    func updatePosition(_ offset: CGFloat) {
    }

    func saveProgress(index: Int) {
        guard hasRestoredPosition else { return }

        savedIndex = index
        savedTotalSpans = spans.count
        let progress: [String: Int] = [
            "index": index,
            "total": spans.count
        ]
        UserDefaults.standard.set(progress, forKey: "\(progressKey)\(novelId)")

        NotificationCenter.default.post(
            name: .novelReaderProgressDidSave,
            object: nil,
            userInfo: ["novelId": novelId]
        )
    }

    func savePositionOnDisappear(firstVisible: Int) {
        saveProgress(index: firstVisible)
    }

    func updateSettings(_ newSettings: NovelReaderSettings) {
        settings = newSettings
        saveSettings()
    }

    func toggleBookmark() async {
        do {
            if isBookmarked {
                try await PixivAPI.shared.novelAPI?.unbookmarkNovel(novelId: novelId)
            } else {
                try await PixivAPI.shared.novelAPI?.bookmarkNovel(novelId: novelId)
            }
            isBookmarked.toggle()
        } catch {
            print("Failed to toggle bookmark: \(error)")
        }
    }

    func updateFontSize(_ size: CGFloat) {
        settings.fontSize = size
        saveSettings()
    }

    func updateLineHeight(_ height: CGFloat) {
        settings.lineHeight = height
        saveSettings()
    }

    func updateTheme(_ theme: ReaderTheme) {
        settings.theme = theme
        saveSettings()
    }

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(NovelReaderSettings.self, from: data) {
            settings = saved
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func scrollToChapter(title: String) {
    }

    func scrollToParagraph(_ index: Int) {
    }
}
