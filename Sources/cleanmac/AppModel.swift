import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {

    @Published var items: [ScanItem] = []
    @Published var scanning = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var disk = DiskStats.current()

    @Published var hidden: [HiddenEntry] = []
    @Published var probingHidden = false

    @Published var apps: [AppInfo] = []
    @Published var scanningApps = false

    @Published var analyzingSpace = false
    @Published var spaceStatus = ""

    @Published var toast: String?
    @Published var moveReport: MoveReport?
    @Published var quittingIDs = Set<UUID>()

    struct MoveReport: Identifiable {
        let id = UUID()
        let failures: [MoveFailure]
    }
    @Published var quarantineSize: Int64 = 0
    @Published var quarantineCount = 0
    @Published var batches: [Quarantine.Batch] = []

    // MARK: - 首启引导

    @Published var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "didOnboard")

    func finishOnboarding() {
        showOnboarding = false
        UserDefaults.standard.set(true, forKey: "didOnboard")
    }

    /// 用户点了「已授权」之后验证一次：读得到 Downloads 才算通过
    func checkAccessAndFinish() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        let ok = (try? FileManager.default.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: nil,
            options: []
        )) != nil

        if ok {
            finishOnboarding()
            toast = "已获得访问权限，正在重新扫描"
            startScan()
            scanBigFiles()
        } else {
            toast = "仍未获得权限，请确认已在系统设置中勾选 cleanmac"
        }
        scheduleToastClear()
    }

    func reopenOnboarding() {
        showOnboarding = true
        UserDefaults.standard.set(false, forKey: "didOnboard")
    }

    /// 背景白纱浓度：越低越透，越高越稳
    @Published var scrimOpacity: Double = {
        let saved = UserDefaults.standard.object(forKey: "scrimOpacity") as? Double
        return saved ?? 0.45
    }()

    func setScrim(_ value: Double) {
        scrimOpacity = value
        UserDefaults.standard.set(value, forKey: "scrimOpacity")
    }

    /// 隔离区保留天数，0 表示永不自动清理
    @Published var retentionDays: Int = {
        let saved = UserDefaults.standard.object(forKey: "quarantineRetentionDays") as? Int
        return saved ?? 1
    }()

    init() {
        refreshQuarantine()
        purgeExpired()
        startPurgeLoop()
    }

    // MARK: - 自动清理

    func setRetention(_ days: Int) {
        retentionDays = days
        UserDefaults.standard.set(days, forKey: "quarantineRetentionDays")
        purgeExpired(manual: false)
    }

    func purgeExpired(manual: Bool = false) {
        let days = retentionDays
        guard days > 0 else {
            if manual {
                toast = "已设为永不自动清理"
                scheduleToastClear()
            }
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            let result = Quarantine.purge(olderThanDays: days)
            await MainActor.run {
                guard let self else { return }
                if result.removed > 0 {
                    self.refreshQuarantine()
                    self.disk = DiskStats.current()
                    self.toast = "已清理 \(result.removed) 个过期批次，释放 \(formatBytes(result.bytes))"
                    self.scheduleToastClear()
                } else if manual {
                    self.toast = "没有超过 \(days) 天的批次"
                    self.scheduleToastClear()
                }
            }
        }
    }

    private func startPurgeLoop() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                self?.purgeExpired()
            }
        }
    }

    // MARK: - 派生值

    var selectedBytes: Int64 {
        items.filter { $0.selected }.reduce(0) { $0 + $1.size }
    }

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int {
        items.filter { $0.selected }.count
    }

    func items(in category: CategoryKind) -> [ScanItem] {
        items.filter { $0.category == category }
    }

    // MARK: - 扫描

    func startScan() {
        guard !scanning else { return }
        scanning = true
        progress = 0
        statusText = "准备扫描…"
        items = []
        disk = DiskStats.current()

        let rules = Rule.all

        Task.detached(priority: .userInitiated) { [weak self] in
            var collected: [ScanItem] = []

            for (index, rule) in rules.enumerated() {
                if Task.isCancelled { break }
                await MainActor.run { self?.statusText = "正在扫描：\(rule.title)" }

                let urls = rule.resolve()
                var size: Int64 = 0
                for url in urls {
                    if Task.isCancelled { break }
                    size += FileSizer.size(of: url)
                }

                if size > 0 && !urls.isEmpty {
                    collected.append(ScanItem(
                        ruleID: rule.id,
                        title: rule.title,
                        detail: rule.detail,
                        category: rule.category,
                        risk: rule.risk,
                        size: size,
                        urls: urls,
                        selected: rule.risk == .safe
                    ))
                }

                let p = Double(index + 1) / Double(rules.count)
                await MainActor.run { self?.progress = p }
            }

            await MainActor.run {
                guard let self else { return }
                self.items = collected.sorted { $0.size > $1.size }
                self.scanning = false
                self.progress = 1
                self.statusText = ""
                self.disk = DiskStats.current()
            }
        }
    }

    // MARK: - 清理

    func toggle(_ id: UUID, on: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].selected = on
    }

    /// 分类统计：可安全清理的（系统可重建数据）
    var safeItems: [ScanItem] { items.filter { $0.risk == .safe } }
    var safeBytes: Int64 { safeItems.reduce(0) { $0 + $1.size } }

    /// 需要用户亲自决定的（个人文件）
    var personalItems: [ScanItem] { items.filter { $0.risk != .safe } }
    var personalBytes: Int64 { personalItems.reduce(0) { $0 + $1.size } }

    var selectedPersonalItems: [ScanItem] { personalItems.filter { $0.selected } }
    var selectedPersonalBytes: Int64 { selectedPersonalItems.reduce(0) { $0 + $1.size } }
    var selectedPersonalCount: Int { selectedPersonalItems.count }

    /// 一步到位：只清理系统可重建数据，不弹任何确认
    func cleanSafe() {
        performClean(safeItems, verb: "已清理")
    }

    /// 只处理用户自己勾选的个人文件，系统数据走 cleanSafe()
    func cleanPersonalSelected() {
        performClean(selectedPersonalItems, verb: "已删除")
    }

    private func performClean(_ chosen: [ScanItem], verb: String) {
        guard !chosen.isEmpty else { return }

        let bytes = chosen.reduce(0) { $0 + $1.size }

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Quarantine.move(chosen)
            await MainActor.run {
                guard let self else { return }
                self.reportFailures(result.failures)
                if result.success {
                    self.model_cleanFinish(bytes: bytes, count: result.moved, chosen: chosen, verb: verb)
                } else {
                    self.toast = result.failures.isEmpty
                        ? "清理失败：没有可移动的项目"
                        : "清理失败：\(result.failures.count) 项无法删除"
                    self.scheduleToastClear()
                }
            }
        }
    }

    private func model_cleanFinish(bytes: Int64, count: Int, chosen: [ScanItem], verb: String) {
        let ids = Set(chosen.map { $0.id })
        items.removeAll { ids.contains($0.id) }
        disk = DiskStats.current()
        refreshQuarantine()
        toast = "\(verb) \(formatBytes(bytes)) · \(count) 项"
        scheduleToastClear()
    }

    // MARK: - 隔离区

    func refreshQuarantine() {
        let info = Quarantine.batchesInfo()
        batches = info
        quarantineSize = info.reduce(0) { $0 + $1.size }
        quarantineCount = info.reduce(0) { $0 + $1.count }
    }

    func restoreLatest() {
        guard let latest = Quarantine.batches().first else { return }
        let n = Quarantine.restore(batch: latest)
        disk = DiskStats.current()
        refreshQuarantine()
        toast = "已还原 \(n) 项到原位置"
        scheduleToastClear()
    }

    func clearQuarantine() {
        Quarantine.clearAll()
        refreshQuarantine()
        toast = "隔离区已清空"
        scheduleToastClear()
    }

    func revealQuarantine() {
        Quarantine.ensureRoot()
        NSWorkspace.shared.activateFileViewerSelecting([Quarantine.root])
    }

    // MARK: - 隐形空间

    func probeHidden() {
        guard !probingHidden else { return }
        probingHidden = true
        Task.detached(priority: .utility) { [weak self] in
            let entries = HiddenProbe.probe()
            await MainActor.run {
                self?.hidden = entries
                self?.probingHidden = false
            }
        }
    }

    // MARK: - 空间地图

    @Published var spaceStack: [URL] = []
    @Published var spaceEntries: [SpaceEntry] = []
    @Published var spaceLoading = false
    @Published var spaceSelected = Set<URL>()
    @Published var spaceDeleting = false

    private var spaceCache: [String: [SpaceEntry]] = [:]

    var spaceTotal: Int64 { spaceEntries.reduce(0) { $0 + $1.size } }
    var spaceSelectedSize: Int64 {
        spaceEntries.filter { spaceSelected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }
    var canGoUp: Bool { spaceStack.count > 1 }

    func openSpace(_ url: URL, push: Bool) {
        if push {
            spaceStack.append(url)
        } else {
            spaceStack = [url]
        }
        reloadSpace()
    }

    func enter(_ entry: SpaceEntry) {
        if entry.url.path.hasPrefix("/__") { return }
        if entry.isDirectory {
            openSpace(entry.url, push: true)
        } else if let reason = Protection.reason(for: entry.url) {
            toast = "受保护：\(reason)"
            scheduleToastClear()
        } else {
            toggleSpace(entry.url)
        }
    }

    func goUpSpace() {
        guard spaceStack.count > 1 else { return }
        spaceStack.removeLast()
        reloadSpace()
    }

    func jumpSpace(to index: Int) {
        guard index >= 0, index < spaceStack.count else { return }
        spaceStack = Array(spaceStack.prefix(index + 1))
        reloadSpace()
    }

    func toggleSpace(_ url: URL) {
        if spaceSelected.contains(url) {
            spaceSelected.remove(url)
        } else {
            spaceSelected.insert(url)
        }
    }

    func selectAllSpace(_ on: Bool) {
        if on {
            spaceSelected = Set(spaceEntries.map { $0.url })
        } else {
            spaceSelected.removeAll()
        }
    }

    private func reloadSpace() {
        guard let target = spaceStack.last else { return }
        spaceSelected.removeAll()

        if let cached = spaceCache[target.path] {
            spaceEntries = cached
            spaceLoading = false
            return
        }

        spaceLoading = true
        spaceEntries = []

        Task.detached(priority: .userInitiated) { [weak self] in
            let entries = await AppModel.readDirectory(target)
            await MainActor.run {
                guard let self else { return }
                self.spaceCache[target.path] = entries
                self.spaceEntries = entries
                self.spaceLoading = false
            }
        }
    }

    nonisolated static func readDirectory(_ url: URL) async -> [SpaceEntry] {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [SpaceEntry] = []
        var index = 0
        while index < kids.count {
            let batch = Array(kids[index..<min(index + 8, kids.count)])
            index += 8

            await withTaskGroup(of: SpaceEntry?.self) { group in
                for k in batch {
                    group.addTask {
                        let isDir = (try? k.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        let size = FileSizer.size(of: k)
                        // 目录即使读到 0 也要显示（可能是 TCC 受限），否则会凭空消失
                        guard size > 0 || isDir else { return nil }
                        return SpaceEntry(url: k, name: k.lastPathComponent, isDirectory: isDir, size: size)
                    }
                }
                for await item in group {
                    if let item { out.append(item) }
                }
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// 关键目录：即使被勾选也拒绝删除，避免把系统弄坏
    nonisolated static func isProtected(_ url: URL) -> Bool {
        let home = NSHomeDirectory()
        let path = url.standardizedFileURL.path
        let blocked: Set<String> = [
            home,
            home + "/Library",
            home + "/Documents",
            home + "/Desktop",
            home + "/Pictures",
            home + "/Movies",
            home + "/Music",
            "/Applications",
            "/Library",
            "/System",
            "/Users",
            "/private/etc",
        ]
        return blocked.contains(path)
    }

    func deleteSpaceSelection() {
        let all = Array(spaceSelected)
        let urls = all.filter { !Protection.isProtected($0) }
        let skipped = all.count - urls.count
        if skipped > 0 {
            for u in all where Protection.isProtected(u) {
                spaceSelected.remove(u)
            }
        }
        guard !urls.isEmpty else {
            toast = skipped > 0 ? "所选是系统关键目录，已阻止删除" : "没有选中项目"
            scheduleToastClear()
            return
        }
        let bytes = spaceSelectedSize
        let count = urls.count
        spaceDeleting = true

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Quarantine.moveRaw([(title: "空间地图", urls: urls)])
            await MainActor.run {
                guard let self else { return }
                self.spaceDeleting = false
                self.reportFailures(result.failures)
                if result.success {
                    self.spaceCache.removeAll()
                    self.disk = DiskStats.current()
                    self.refreshQuarantine()
                    self.spaceSelected.removeAll()
                    self.reloadSpace()
                    var msg = "已删除 \(count) 项，释放约 \(formatBytes(bytes))（可还原）"
                    if skipped > 0 { msg += " · 跳过 \(skipped) 个关键目录" }
                    self.toast = msg
                } else {
                    self.toast = result.failures.isEmpty
                        ? "删除失败"
                        : "删除失败：\(result.failures.count) 项无法删除"
                }
                self.scheduleToastClear()
            }
        }
    }

    // MARK: - 大文件与旧文件

    enum FileFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case big = "大文件"
        case old = "一年未用"
        var id: String { rawValue }
    }

    @Published var bigFiles: [BigFile] = []
    @Published var scanningFiles = false
    @Published var fileScanStatus = ""
    @Published var selectedFileIDs = Set<UUID>()
    @Published var fileFilter: FileFilter = .all
    @Published var blockedDirs: [String] = []

    var filteredFiles: [BigFile] {
        switch fileFilter {
        case .all: return bigFiles
        case .big: return bigFiles.filter { $0.isBig }
        case .old: return bigFiles.filter { $0.isOld }
        }
    }

    var selectedFiles: [BigFile] { bigFiles.filter { selectedFileIDs.contains($0.id) } }
    var selectedFilesBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }
    var bigFilesBytes: Int64 { bigFiles.reduce(0) { $0 + $1.size } }

    func scanBigFiles() {
        guard !scanningFiles else { return }
        scanningFiles = true
        bigFiles = []
        selectedFileIDs.removeAll()
        fileScanStatus = "正在遍历你的主目录…"

        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = BigFileScanner.scan { count, name in
                Task { @MainActor in
                    self?.fileScanStatus = "已检查 \(count) 个文件 · \(name)"
                }
            }
            await MainActor.run {
                self?.bigFiles = outcome.files
                self?.blockedDirs = outcome.blocked
                self?.scanningFiles = false
                self?.fileScanStatus = ""
            }
        }
    }

    func setFileSelected(_ id: UUID, _ on: Bool) {
        if on {
            selectedFileIDs.insert(id)
        } else {
            selectedFileIDs.remove(id)
        }
    }

    func deleteSelectedFiles() {
        let all = Array(selectedFileIDs)
        let chosen = bigFiles.filter { all.contains($0.id) }
        guard !chosen.isEmpty else { return }

        let protected = chosen.filter { Protection.isProtected($0.url) }
        let allowed = chosen.filter { !Protection.isProtected($0.url) }

        guard !allowed.isEmpty else {
            toast = "所选位于受保护位置，已阻止删除"
            scheduleToastClear()
            return
        }

        let bytes = allowed.reduce(Int64(0)) { $0 + $1.size }
        let groups = allowed.map { (title: $0.name, urls: [$0.url]) }
        let ids = Set(allowed.map { $0.id })
        let skipped = protected.count

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Quarantine.moveRaw(groups)
            await MainActor.run {
                guard let self else { return }
                self.reportFailures(result.failures)
                guard result.success else {
                    self.toast = "删除失败：文件可能正在使用中"
                    self.scheduleToastClear()
                    return
                }
                self.bigFiles.removeAll { ids.contains($0.id) }
                self.selectedFileIDs.subtract(ids)
                self.disk = DiskStats.current()
                self.refreshQuarantine()
                var msg = "已删除 \(allowed.count) 项，释放 \(formatBytes(bytes))"
                if skipped > 0 { msg += " · 跳过 \(skipped) 个受保护项" }
                self.toast = msg
                self.scheduleToastClear()
            }
        }
    }

    // MARK: - 应用 / 数据

    enum AppAction: String, CaseIterable, Identifiable {
        case appAndData = "应用 + 数据"
        case dataOnly   = "仅清数据"
        case appOnly    = "仅删应用"
        var id: String { rawValue }
    }

    @Published var includeLikely = false

    var selectedApps: [AppInfo] { apps.filter { $0.selected } }

    var selectedAppsBytes: Int64 {
        selectedApps.reduce(Int64(0)) { sum, app in
            var s = sum + app.size + app.exactDataSize
            if includeLikely { s += app.likelyDataSize }
            return s
        }
    }

    func scanApps() {
        guard !scanningApps else { return }
        scanningApps = true

        Task.detached(priority: .userInitiated) { [weak self] in
            let list = Uninstaller.scan()
            await MainActor.run {
                self?.apps = list
                self?.scanningApps = false
            }
        }
    }

    func toggleApp(_ id: UUID, on: Bool) {
        guard let idx = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[idx].selected = on
    }

    // 三个入口，语义各自独立

    /// 底部按钮：清理所选（应用 + 数据）
    func cleanSelectedApps() {
        execute(.appAndData, apps: selectedApps)
    }

    /// 行内按钮：只删这个 App 产生的数据，保留应用本体
    func cleanData(for app: AppInfo) {
        execute(.dataOnly, apps: [app])
    }

    /// 行内按钮：只删应用本体，保留数据以便重装后衔接
    func removeApp(for app: AppInfo) {
        execute(.appOnly, apps: [app])
    }

    private func execute(_ mode: AppAction, apps chosen: [AppInfo]) {
        guard !chosen.isEmpty else { return }

        var groups: [(title: String, urls: [URL])] = []
        var moved = Set<URL>()
        var plannedBytes: Int64 = 0

        for app in chosen {
            var urls: [URL] = []
            if mode != .dataOnly && app.removable {
                urls.append(app.path)
                plannedBytes += app.size
            }
            if mode != .appOnly {
                for l in app.leftovers where l.confidence != .restricted {
                    if l.confidence == .likely && !includeLikely { continue }
                    urls.append(l.url)
                    plannedBytes += l.size
                }
            }
            if !urls.isEmpty {
                groups.append((app.name, urls))
                moved.formUnion(urls)
            }
        }

        guard !groups.isEmpty else {
            toast = mode == .appOnly ? "这个应用需要管理员权限才能移除" : "没有可清理的数据"
            scheduleToastClear()
            return
        }

        let ids = Set(chosen.map { $0.id })
        let bytes = plannedBytes
        let count = chosen.count

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Quarantine.moveRaw(groups)
            await MainActor.run {
                guard let self else { return }
                self.reportFailures(result.failures)
                guard result.success else {
                    self.toast = "操作失败：项目正在使用中"
                    self.scheduleToastClear()
                    return
                }

                for i in self.apps.indices {
                    self.apps[i].leftovers.removeAll { moved.contains($0.url) }
                }
                if mode == .dataOnly {
                    for i in self.apps.indices where ids.contains(self.apps[i].id) {
                        self.apps[i].selected = false
                    }
                } else {
                    self.apps.removeAll { ids.contains($0.id) }
                }

                self.disk = DiskStats.current()
                self.refreshQuarantine()

                let verb: String
                switch mode {
                case .appAndData: verb = "已清理"
                case .dataOnly:   verb = "已删除数据，应用已保留"
                case .appOnly:    verb = "已移除应用，数据已保留"
                }
                self.toast = "\(verb) · \(count) 个 · \(formatBytes(bytes))"
                self.scheduleToastClear()
            }
        }
    }

    // MARK: - 修复动作

    func apply(_ remedy: Remedy, to failure: MoveFailure) {
        switch remedy {
        case .quitAndRetry:       quitAndRetry(failure)
        case .clearImmutable:     resolveImmutable(failure)
        case .adminDelete:        adminDelete(failure)
        case .openFullDiskAccess: openPrivacySettings()
        case .refreshList:
            removeFailure(failure.id)
            refreshSpaceIfNeeded()
            toast = "已刷新列表"
            scheduleToastClear()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func quitAndRetry(_ failure: MoveFailure) {
        guard !quittingIDs.contains(failure.id) else { return }
        quittingIDs.insert(failure.id)

        Task { [weak self] in
            guard let self else { return }
            let acted = ProcessController.terminate(
                appName: failure.appName,
                bundleID: failure.bundleID,
                owners: failure.owners
            )
            guard acted else {
                self.quittingIDs.remove(failure.id)
                self.toast = "没有找到正在运行的进程"
                self.scheduleToastClear()
                return
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            await self.retryMove(failure)
        }
    }

    private func resolveImmutable(_ failure: MoveFailure) {
        guard !quittingIDs.contains(failure.id) else { return }
        quittingIDs.insert(failure.id)

        Task { [weak self] in
            guard let self else { return }
            let url = URL(fileURLWithPath: failure.path)
            let ok = await Task.detached { RemedyRunner.clearImmutable(url) }.value
            guard ok else {
                self.quittingIDs.remove(failure.id)
                self.toast = "解除锁定失败"
                self.scheduleToastClear()
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self.retryMove(failure)
        }
    }

    private func adminDelete(_ failure: MoveFailure) {
        guard !quittingIDs.contains(failure.id) else { return }
        quittingIDs.insert(failure.id)

        Task { [weak self] in
            guard let self else { return }
            let url = URL(fileURLWithPath: failure.path)
            let ok = await Task.detached { RemedyRunner.adminDelete(url) }.value
            self.quittingIDs.remove(failure.id)

            if ok {
                self.removeFailure(failure.id)
                self.disk = DiskStats.current()
                self.refreshQuarantine()
                self.refreshSpaceIfNeeded()
                self.toast = "已永久删除 \(failure.name)"
            } else {
                self.toast = "已取消或删除失败"
            }
            self.scheduleToastClear()
        }
    }

    private func retryMove(_ failure: MoveFailure) async {
        let url = URL(fileURLWithPath: failure.path)
        let result = await Task.detached(priority: .userInitiated) {
            Quarantine.moveRaw([(title: "重试", urls: [url])])
        }.value

        quittingIDs.remove(failure.id)

        if result.success {
            removeFailure(failure.id)
            disk = DiskStats.current()
            refreshQuarantine()
            refreshSpaceIfNeeded()
            toast = "已删除 \(failure.name)"
        } else {
            if let updated = result.failures.first {
                replaceFailure(failure.id, with: updated)
            }
            toast = "仍然无法删除 \(failure.name)"
        }
        scheduleToastClear()
    }

    private func removeFailure(_ id: UUID) {
        guard let current = moveReport else { return }
        let remaining = current.failures.filter { $0.id != id }
        moveReport = remaining.isEmpty ? nil : MoveReport(failures: remaining)
    }

    private func replaceFailure(_ id: UUID, with new: MoveFailure) {
        guard let current = moveReport else { return }
        let updated = current.failures.map { $0.id == id ? new : $0 }
        moveReport = MoveReport(failures: updated)
    }

    func refreshSpaceIfNeeded() {
        guard !spaceStack.isEmpty else { return }
        spaceCache.removeAll()
        reloadSpace()
    }

    func reportFailures(_ failures: [MoveFailure]) {
        guard !failures.isEmpty else { return }
        moveReport = MoveReport(failures: failures)
    }

    private var toastTask: Task<Void, Never>?

    private func scheduleToastClear() {
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}
