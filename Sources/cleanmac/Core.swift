import Foundation
import AppKit

// MARK: - 风险等级

enum Risk: String, Sendable {
    case safe    = "安全"
    case careful = "注意"
    case risky   = "谨慎"
}

// MARK: - 分类

enum CategoryKind: String, Identifiable, Sendable {
    case cache     = "系统缓存"
    case logs      = "日志"
    case developer = "开发者"
    case trash     = "废纸篓"
    case wallpaper = "壁纸缓存"
    case downloads = "下载残留"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cache:     return "internaldrive"
        case .logs:      return "doc.text"
        case .developer: return "hammer"
        case .trash:     return "trash"
        case .wallpaper: return "photo.on.rectangle"
        case .downloads: return "arrow.down.circle"
        }
    }
}

// MARK: - 规则目标

enum Target: Sendable {
    /// 删除目录下的所有子项，保留目录本身
    case contents(String)
    /// 删除目录本身
    case directory(String)
    /// 按扩展名筛选目录下的文件
    case files(String, [String])
}

// MARK: - 规则

struct Rule: Identifiable, Sendable {
    let id: String
    let category: CategoryKind
    let title: String
    let detail: String
    let target: Target
    let risk: Risk

    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    func resolve() -> [URL] {
        let fm = FileManager.default
        switch target {
        case .contents(let p):
            let dir = Rule.url(p)
            guard let kids = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: []
            ) else { return [] }
            return kids

        case .directory(let p):
            let dir = Rule.url(p)
            return fm.fileExists(atPath: dir.path) ? [dir] : []

        case .files(let p, let exts):
            let dir = Rule.url(p)
            guard let kids = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: []
            ) else { return [] }
            if exts.isEmpty { return kids }
            return kids.filter { exts.contains($0.pathExtension.lowercased()) }
        }
    }
}

// MARK: - 内置规则库 v0.1

extension Rule {

    /// App Store 下载缓存位于临时目录的同级 C 目录
    static var appStoreCachePath: String {
        let tmp = FileManager.default.temporaryDirectory
        let base = tmp.deletingLastPathComponent()
        return base.appendingPathComponent("C/com.apple.appstoreagent").path
    }

    static let all: [Rule] = RulePack.all + [
        Rule(id: "CACHE-02", category: .cache, title: "App Store 下载缓存",
             detail: "var/folders · appstoreagent",
             target: .directory(appStoreCachePath), risk: .safe),
    ]
}

// MARK: - 扫描项

struct ScanItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let ruleID: String
    let title: String
    let detail: String
    let category: CategoryKind
    let risk: Risk
    let size: Int64
    let urls: [URL]
    var selected: Bool

    static func == (lhs: ScanItem, rhs: ScanItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 文件体积统计

enum FileSizer {

    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .isRegularFileKey
    ]

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: keys)
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }

        var total: Int64 = 0
        guard let e = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let child as URL in e {
            if Task.isCancelled { break }
            guard let v = try? child.resourceValues(forKeys: keys) else { continue }
            if v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

// MARK: - 磁盘信息

struct DiskStats: Sendable {
    var total: Int64 = 0
    var free: Int64 = 0
    var used: Int64 { max(0, total - free) }
    var usedRatio: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskStats {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) else {
            return DiskStats()
        }
        let total = Int64(v.volumeTotalCapacity ?? 0)
        var free = Int64(v.volumeAvailableCapacityForImportantUsage ?? 0)
        if free == 0 {
            free = Int64(v.volumeAvailableCapacity ?? 0)
        }
        return DiskStats(total: total, free: free)
    }
}

// MARK: - 体积格式化

func formatBytes(_ bytes: Int64) -> String {
    if bytes <= 0 { return "0 B" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var idx = 0
    while value >= 1024 && idx < units.count - 1 {
        value /= 1024
        idx += 1
    }
    if idx <= 1 {
        return String(format: "%.0f %@", value, units[idx])
    }
    return String(format: "%.1f %@", value, units[idx])
}

// MARK: - 删除失败与占用进程

struct MoveResult: Sendable {
    let batch: URL?
    let moved: Int
    let failures: [MoveFailure]
    var success: Bool { moved > 0 }
}

struct ProcessOwner: Identifiable, Hashable, Sendable {
    let id = UUID()
    let pid: Int32
    let name: String

    var display: String { "\(name)（\(pid)）" }
}

enum Remedy: String, Sendable, Identifiable {
    case quitAndRetry
    case clearImmutable
    case adminDelete
    case openFullDiskAccess
    case refreshList

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quitAndRetry:      return "结束应用并重试"
        case .clearImmutable:    return "解除锁定并重试"
        case .adminDelete:       return "以管理员删除"
        case .openFullDiskAccess: return "打开权限设置"
        case .refreshList:       return "刷新列表"
        }
    }

    var isDestructive: Bool { self == .adminDelete }

    /// 会改变系统状态的手段，执行前需要用户确认
    var needsConfirm: Bool { self == .adminDelete || self == .quitAndRetry }
}

struct MoveFailure: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let reason: String
    let cause: String
    let remedies: [Remedy]
    let owners: [ProcessOwner]
    let appName: String?
    let bundleID: String?

    var canTerminate: Bool {
        (appName != nil && bundleID != nil) || !owners.isEmpty
    }
}

// MARK: - 不可删除的数据

enum Protection {

    /// 这些是资料库包，里面是原始数据，删掉无法恢复
    static let libraryExtensions: Set<String> = [
        "photoslibrary", "photolibrary",
        "musiclibrary", "tvlibrary", "imovielibrary",
        "aplibrary", "fcpbundle"
    ]

    private static var home: String { NSHomeDirectory() }

    static func reason(for url: URL) -> String? {
        let path = url.standardizedFileURL.path

        if libraryExtensions.contains(url.pathExtension.lowercased()) {
            return "这是资料库，包含你的原始照片或媒体，删除后无法恢复"
        }

        // 没有扩展名的媒体图库（例如 Photo Booth图库）
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            let name = url.lastPathComponent
            if name.hasSuffix("图库") || name.lowercased().hasSuffix("library") && name.lowercased().contains("photo") {
                return "这是媒体图库，包含原始照片，删除后无法恢复"
            }
        }

        // 位于资料库内部的任何文件
        for comp in url.pathComponents where libraryExtensions.contains((comp as NSString).pathExtension.lowercased()) {
            return "位于资料库内部，删除会破坏整个资料库"
        }

        let blocked: [String: String] = [
            home:                              "这是你的主目录",
            home + "/Library":                 "系统与应用数据",
            home + "/Documents":               "个人文档",
            home + "/Desktop":                 "桌面文件",
            home + "/Pictures":                "图片目录",
            home + "/Movies":                  "影片目录",
            home + "/Music":                   "音乐目录",
            home + "/Applications":            "应用程序目录",
            "/Applications":                   "应用程序目录",
            "/Library":                        "系统库",
            "/System":                         "系统文件",
            "/Users":                          "用户目录",
            "/private/etc":                    "系统配置",
            "/private/var":                    "系统数据",
        ]
        if let r = blocked[path] { return r }

        let prefixes: [(String, String)] = [
            (home + "/Library/Mobile Documents", "iCloud 云盘，删除会同步到所有设备"),
            (home + "/Library/CloudStorage",     "网盘同步目录，删除可能影响云端"),
            (home + "/Library/Keychains",        "钥匙串，保存着密码"),
            (home + "/Library/Application Support/MobileSync", "iPhone 备份"),
            (home + "/Library/Mail",             "邮件数据"),
            (home + "/Library/Messages",         "信息记录"),
            ("/System",                          "系统文件"),
            ("/usr",                             "系统文件"),
            ("/bin",                             "系统文件"),
        ]
        for (prefix, r) in prefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return r
        }
        return nil
    }

    static func isProtected(_ url: URL) -> Bool { reason(for: url) != nil }
}

// MARK: - 文件标志位

enum FileFlags {
    static let userImmutable: UInt32   = 0x0000_0002   // uchg
    static let systemImmutable: UInt32 = 0x0002_0000   // schg
    static let restricted: UInt32      = 0x0008_0000   // SIP

    static func read(_ url: URL) -> UInt32 {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return 0 }
        return UInt32(truncatingIfNeeded: st.st_flags)
    }
}

// MARK: - 失败原因分析

enum FailureAnalyzer {

    static func analyze(
        url: URL,
        error: Error,
        owners: [ProcessOwner],
        app: (name: String, bundleID: String)?
    ) -> (cause: String, remedies: [Remedy]) {
        let fm = FileManager.default
        let path = url.path

        guard fm.fileExists(atPath: path) else {
            return ("文件已不存在，可能已被其他程序移走", [.refreshList])
        }

        let flags = FileFlags.read(url)

        if flags & FileFlags.restricted != 0 {
            return ("文件受系统完整性保护（SIP），任何程序都无法删除", [])
        }
        if flags & FileFlags.systemImmutable != 0 {
            return ("文件被设为系统级不可变（schg），需要管理员先解除再删除", [.adminDelete])
        }
        if flags & FileFlags.userImmutable != 0 {
            return ("文件被锁定（uchg），通常是「显示简介」里勾了「已锁定」", [.clearImmutable])
        }

        let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        if values?.volumeIsReadOnly == true {
            return ("所在磁盘是只读的（可能是挂载的磁盘镜像），只能先推出该卷", [])
        }

        let home = NSHomeDirectory()
        let tccPrefixes = [
            "/Pictures/Photos Library",
            "/Library/Mail",
            "/Library/Messages",
            "/Library/Safari",
            "/Library/Application Support/MobileSync",
        ]
        if tccPrefixes.contains(where: { path.hasPrefix(home + $0) }) {
            return ("文件位于受 macOS 隐私保护的目录，未授权时任何程序都无法读取", [.openFullDiskAccess])
        }

        if !owners.isEmpty || app != nil {
            var parts: [String] = []
            if let app { parts.append("正被 \(app.name) 使用") }
            if !owners.isEmpty {
                parts.append("被 \(owners.map(\.name).joined(separator: "、")) 占用")
            }
            return (parts.joined(separator: "，"), [.quitAndRetry])
        }

        let parent = url.deletingLastPathComponent()
        if !fm.isWritableFile(atPath: parent.path) {
            return ("没有 \(parent.lastPathComponent) 的写入权限，需要管理员", [.adminDelete])
        }

        return (error.localizedDescription, [.adminDelete, .refreshList])
    }
}

enum ProcessAttribution {

    /// 用 lsof 查谁打开了这个文件
    static func owners(of url: URL) -> [ProcessOwner] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-n", "-P", "-F", "pc", "--", url.path]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return []
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcessOwner] = []
        var pid: Int32 = 0
        for line in text.split(separator: "\n") {
            if line.hasPrefix("p") {
                pid = Int32(String(line.dropFirst())) ?? 0
            } else if line.hasPrefix("c") {
                let name = String(line.dropFirst())
                let owner = ProcessOwner(pid: pid, name: name)
                if !result.contains(where: { $0.pid == owner.pid && $0.name == owner.name }) {
                    result.append(owner)
                }
            }
        }
        return result
    }

    /// 从路径里猜出正在运行的相关应用
    static func runningApp(for path: String) -> (name: String, bundleID: String)? {
        let comps = path.split(separator: "/").map(String.init)
        for comp in comps where comp.contains(".") && !comp.hasPrefix(".") {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: comp).first,
               let name = app.localizedName {
                return (name, comp)
            }
        }
        return nil
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case 513: return "没有写入权限（可能需要管理员或完全磁盘访问）"
        case 516: return "目标位置已存在同名项目"
        case 4, 260: return "文件不存在，可能已被移动"
        case 640: return "编码或属性不兼容"
        default: break
        }
        if ns.code == 1 { return "操作不被允许（系统保护或文件不可变）" }
        return ns.localizedDescription
    }
}

// MARK: - 结束占用进程

enum ProcessController {

    /// 先优雅退出，超时再强制结束；返回是否发出过信号
    @MainActor
    static func terminate(appName: String?, bundleID: String?, owners: [ProcessOwner]) -> Bool {
        var acted = false

        if let bundleID, !bundleID.isEmpty, bundleID != "com.cleanmac.app" {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            for app in apps {
                if app.terminate() { acted = true }
            }
            if !apps.isEmpty {
                var waited = 0
                while apps.contains(where: { !$0.isTerminated }) && waited < 25 {
                    usleep(100_000)
                    waited += 1
                }
            }
            for app in apps where !app.isTerminated {
                if app.forceTerminate() { acted = true }
            }
        }

        for owner in owners where owner.pid > 0 {
            if kill(owner.pid, SIGTERM) == 0 { acted = true }
        }
        return acted
    }
}

// MARK: - 修复动作

enum RemedyRunner {

    /// 解除 uchg 不可变标志
    static func clearImmutable(_ url: URL) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        proc.arguments = ["nouchg", url.path]
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    /// 以管理员身份永久删除（会弹出系统密码框）
    static func adminDelete(_ url: URL) -> Bool {
        let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
        // schg 标志会让 root 的 rm 也失败，先解除再删
        let script = "do shell script \"/usr/bin/chflags noschg '\(escaped)' 2>/dev/null; /bin/rm -rf '\(escaped)'\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}

// MARK: - 隔离区

struct QuarantineRecord: Codable, Sendable {
    let original: String
    let stored: String
    let size: Int64
    let title: String
    let date: Date
}

enum Quarantine {

    static var root: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/cleanmac/Quarantine")
        return base
    }

    static func ensureRoot() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 把一组扫描项移动到隔离区
    @discardableResult
    static func move(_ items: [ScanItem]) -> MoveResult {
        moveRaw(items.map { (title: $0.title, urls: $0.urls) })
    }

    /// 通用搬移：每组带一个标题，用于卸载器
    @discardableResult
    static func moveRaw(_ groups: [(title: String, urls: [URL])]) -> MoveResult {
        ensureRoot()
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let batch = root.appendingPathComponent(stamp)
        do {
            try fm.createDirectory(at: batch, withIntermediateDirectories: true)
        } catch {
            return MoveResult(batch: nil, moved: 0, failures: [])
        }

        var records: [QuarantineRecord] = []
        var failures: [MoveFailure] = []
        var counter = 0

        for group in groups {
            for url in group.urls {
                let safeName = "\(counter)-\(url.lastPathComponent)"
                counter += 1
                let dest = batch.appendingPathComponent(safeName)
                do {
                    try fm.moveItem(at: url, to: dest)
                    records.append(QuarantineRecord(
                        original: url.path,
                        stored: safeName,
                        size: 0,
                        title: group.title,
                        date: Date()
                    ))
                } catch {
                    let app = ProcessAttribution.runningApp(for: url.path)
                    let owners = ProcessAttribution.owners(of: url)
                    let diagnosis = FailureAnalyzer.analyze(
                        url: url,
                        error: error,
                        owners: owners,
                        app: app
                    )
                    failures.append(MoveFailure(
                        name: url.lastPathComponent,
                        path: url.path,
                        reason: ProcessAttribution.describe(error),
                        cause: diagnosis.cause,
                        remedies: diagnosis.remedies,
                        owners: owners,
                        appName: app?.name,
                        bundleID: app?.bundleID
                    ))
                    continue
                }
            }
        }

        if records.isEmpty {
            try? fm.removeItem(at: batch)
            return MoveResult(batch: nil, moved: 0, failures: failures)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            try? data.write(to: batch.appendingPathComponent("manifest.json"))
        }
        return MoveResult(batch: batch, moved: records.count, failures: failures)
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func batches() -> [URL] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return dirs.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    struct Batch: Identifiable, Sendable {
        let id: URL
        let date: Date
        let size: Int64
        let count: Int
    }

    static func batchesInfo() -> [Batch] {
        batches().compactMap { url in
            guard let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else {
                return nil
            }
            var count = 0
            if let data = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
               let records = try? decoder.decode([QuarantineRecord].self, from: data) {
                count = records.count
            }
            return Batch(id: url, date: created, size: FileSizer.size(of: url), count: count)
        }
    }

    /// 删除超过保留期的批次（不可还原）
    @discardableResult
    static func purge(olderThanDays days: Int) -> (removed: Int, bytes: Int64) {
        guard days > 0 else { return (0, 0) }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var removed = 0
        var bytes: Int64 = 0

        for batch in batches() {
            guard let created = (try? batch.resourceValues(forKeys: [.creationDateKey]))?.creationDate else {
                continue
            }
            guard created < cutoff else { continue }
            let size = FileSizer.size(of: batch)
            if (try? FileManager.default.removeItem(at: batch)) != nil {
                removed += 1
                bytes += size
            }
        }
        return (removed, bytes)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: root)
    }

    static func restore(batch: URL) -> Int {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: batch.appendingPathComponent("manifest.json")),
              let records = (try? decoder.decode([QuarantineRecord].self, from: data)) else { return 0 }
        var restored = 0
        for r in records {
            let dest = URL(fileURLWithPath: r.original)
            if fm.fileExists(atPath: dest.path) { continue }
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: batch.appendingPathComponent(r.stored), to: dest)) != nil {
                restored += 1
            }
        }
        if restored == records.count {
            try? fm.removeItem(at: batch)
        }
        return restored
    }
}

// MARK: - 受保护空间探测

struct HiddenEntry: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let accessible: Bool
    let size: Int64
}

enum HiddenProbe {

    static let targets: [(String, String)] = [
        ("照片图库",   "~/Pictures/Photos Library.photoslibrary"),
        ("邮件",       "~/Library/Mail"),
        ("信息",       "~/Library/Messages"),
        ("iPhone 备份", "~/Library/Application Support/MobileSync"),
        ("Chrome 配置", "~/Library/Application Support/Google/Chrome"),
    ]

    static func probe() -> [HiddenEntry] {
        targets.map { name, raw in
            let url = Rule.url(raw)
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path) else {
                return HiddenEntry(name: name, path: raw, accessible: false, size: 0)
            }
            let readable = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) != nil
            let size = readable ? FileSizer.size(of: url) : 0
            return HiddenEntry(name: name, path: raw, accessible: readable, size: size)
        }
    }
}

// MARK: - 空间条目

struct SpaceEntry: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
}

// MARK: - 大文件与旧文件

struct BigFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let size: Int64
    let lastAccess: Date
    let isBig: Bool
    let isOld: Bool

    var name: String { url.lastPathComponent }

    var displayPath: String {
        let home = NSHomeDirectory()
        var p = url.deletingLastPathComponent().path
        if p.hasPrefix(home) { p = "~" + p.dropFirst(home.count) }
        return p
    }

    var lastAccessText: String {
        let days = Int(Date().timeIntervalSince(lastAccess) / 86_400)
        if days <= 0 { return "今天" }
        if days < 30 { return "\(days) 天前" }
        if days < 365 { return "\(days / 30) 个月前" }
        return "\(days / 365) 年前"
    }

    var symbol: String {
        switch url.pathExtension.lowercased() {
        case "mov", "mp4", "avi", "mkv", "m4v": return "film"
        case "dmg", "pkg", "iso":              return "shippingbox"
        case "zip", "rar", "7z", "tar", "gz":  return "doc.zipper"
        case "pdf":                            return "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "nef", "raw": return "photo"
        case "app":                            return "app"
        default:                               return "doc"
        }
    }
}

enum BigFileScanner {

    static let bigThreshold: Int64 = 200 * 1024 * 1024        // 200 MB
    static let minSize: Int64 = 20 * 1024 * 1024              // 低于 20 MB 不看
    static let oldThreshold: TimeInterval = 365 * 24 * 3600   // 一年未访问
    static let oldMinSize: Int64 = 50 * 1024 * 1024           // 旧文件至少 50 MB

    struct Result: Sendable {
        let files: [BigFile]
        let blocked: [String]
    }

    static func scan(progress: @escaping @Sendable (Int, String) -> Void) -> Result {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .contentAccessDateKey,
            .contentModificationDateKey
        ]
        let keySet = Set(keys)

        var blocked: Set<String> = []

        guard let enumerator = fm.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { url, _ in
                blocked.insert(url.path)
                return true
            }
        ) else { return Result(files: [], blocked: []) }

        var result: [BigFile] = []
        var visited = 0
        let now = Date()

        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            visited += 1
            if visited % 500 == 0 {
                progress(visited, url.lastPathComponent)
            }

            guard let values = try? url.resourceValues(forKeys: keySet),
                  values.isRegularFile == true else { continue }

            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minSize else { continue }

            let access = values.contentAccessDate
                ?? values.contentModificationDate
                ?? Date.distantPast

            let isBig = size >= bigThreshold
            let isOld = size >= oldMinSize && now.timeIntervalSince(access) > oldThreshold
            guard isBig || isOld else { continue }

            result.append(BigFile(
                url: url,
                size: size,
                lastAccess: access,
                isBig: isBig,
                isOld: isOld
            ))
        }

        return Result(
            files: result.sorted { $0.size > $1.size },
            blocked: Array(blocked)
        )
    }
}

