import Foundation
import AppKit

// MARK: - 数据可信度

enum LeftoverConfidence: String, Sendable {
    case exact      = "精确"
    case likely     = "疑似"
    case restricted = "受保护"
}

struct LeftoverPath: Identifiable, Sendable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let confidence: LeftoverConfidence

    var name: String { url.lastPathComponent }

    static func == (l: LeftoverPath, r: LeftoverPath) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - 应用信息

struct AppInfo: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let bundleID: String
    let version: String
    let path: URL
    let size: Int64
    let lastUsed: Date?
    let removable: Bool
    var leftovers: [LeftoverPath]
    var selected: Bool

    var exactDataSize: Int64 {
        leftovers.filter { $0.confidence == .exact }.reduce(0) { $0 + $1.size }
    }
    var likelyDataSize: Int64 {
        leftovers.filter { $0.confidence == .likely }.reduce(0) { $0 + $1.size }
    }
    var dataSize: Int64 { exactDataSize + likelyDataSize }
    var exactCount: Int { leftovers.filter { $0.confidence == .exact }.count }
    var likelyCount: Int { leftovers.filter { $0.confidence == .likely }.count }
    var restrictedCount: Int { leftovers.filter { $0.confidence == .restricted }.count }
    var totalSize: Int64 { size + dataSize }

    var lastUsedText: String {
        guard let d = lastUsed, d.timeIntervalSince1970 > 0 else { return "未知" }
        let days = Int(Date().timeIntervalSince(d) / 86_400)
        if days <= 0 { return "今天" }
        if days < 30 { return "\(days) 天前" }
        if days < 365 { return "\(days / 30) 个月前" }
        return "\(days / 365) 年前"
    }

    var isStale: Bool {
        guard let d = lastUsed else { return false }
        return Date().timeIntervalSince(d) > 180 * 86_400
    }
}

// MARK: - 卸载 / 清数据

enum Uninstaller {

    static let selfBundleID = "com.cleanmac.app"

    /// 精确模板：按 Bundle ID 拼出的固定位置
    static func exactCandidates(for bundleID: String) -> [URL] {
        guard !bundleID.isEmpty, bundleID != selfBundleID else { return [] }
        let fm = FileManager.default
        let lib = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")

        var urls: [URL] = [
            lib.appendingPathComponent("Application Support/\(bundleID)"),
            lib.appendingPathComponent("Caches/\(bundleID)"),
            lib.appendingPathComponent("Containers/\(bundleID)"),
            lib.appendingPathComponent("Group Containers/\(bundleID)"),
            lib.appendingPathComponent("Logs/\(bundleID)"),
            lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
            lib.appendingPathComponent("WebKit/\(bundleID)"),
            lib.appendingPathComponent("Application Scripts/\(bundleID)"),
            lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            lib.appendingPathComponent("Preferences/\(bundleID).plist"),
            lib.appendingPathComponent("Cookies/\(bundleID).binarycookies"),
            lib.appendingPathComponent("LaunchAgents/\(bundleID).plist"),
        ]

        let byHost = lib.appendingPathComponent("Preferences/ByHost")
        if let files = try? fm.contentsOfDirectory(at: byHost, includingPropertiesForKeys: nil, options: []) {
            for f in files where f.lastPathComponent.hasPrefix(bundleID + ".") {
                urls.append(f)
            }
        }
        return urls.filter { fm.fileExists(atPath: $0.path) }
    }

    /// 名称匹配的键：完整 Bundle ID、末段、应用名
    static func matchKeys(name: String, bundleID: String) -> [String] {
        var keys = Set<String>()
        let bid = bundleID.lowercased()
        if !bid.isEmpty { keys.insert(bid) }
        if let last = bid.split(separator: ".").last, last.count >= 4 {
            keys.insert(String(last))
        }
        let n = name.lowercased().replacingOccurrences(of: " ", with: "")
        if n.count >= 4 { keys.insert(n) }
        return Array(keys)
    }

    /// 短键只允许全等；长键才允许前缀/包含，避免 "Code" 误伤 "CodeBuddy"
    static func matches(child: String, key: String) -> Bool {
        let c = child.lowercased()
        if c == key { return true }
        guard key.count >= 8 else { return false }
        return c.hasPrefix(key) || c.contains(key)
    }

    static func sizeOrRestricted(_ url: URL) -> (Int64, Bool) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, false) }
        if isDir.boolValue {
            do {
                _ = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            } catch {
                return (0, true)
            }
        }
        return (FileSizer.size(of: url), false)
    }

    /// 模糊匹配池：这些目录下的子项名参与比对
    static func fuzzyPool() -> [(name: String, url: URL)] {
        let fm = FileManager.default
        let lib = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let dirs = [
            "Application Support", "Caches", "Logs",
            "Containers", "Group Containers",
            "HTTPStorages", "WebKit", "Application Scripts"
        ]
        var pool: [(String, URL)] = []
        for d in dirs {
            let base = lib.appendingPathComponent(d)
            guard let kids = try? fm.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for k in kids { pool.append((k.lastPathComponent, k)) }
        }
        return pool
    }

    /// 扫描 /Applications 与 ~/Applications
    static func scan() -> [AppInfo] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dirs = ["/Applications", home.appendingPathComponent("Applications").path]

        // 先收集应用本体
        var raw: [(name: String, bid: String, version: String, path: URL, size: Int64, lastUsed: Date?, removable: Bool)] = []

        for dirPath in dirs {
            let dir = URL(fileURLWithPath: dirPath)
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentAccessDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            var candidates: [URL] = []
            for item in items {
                let ext = item.pathExtension.lowercased()
                if ext == "app" {
                    candidates.append(item)
                } else if ext == "localized" {
                    // macOS 会把应用包在 Foo.localized/Foo.app 里
                    if let inner = try? fm.contentsOfDirectory(
                        at: item, includingPropertiesForKeys: nil, options: []),
                       let app = inner.first(where: { $0.pathExtension.lowercased() == "app" }) {
                        candidates.append(app)
                    }
                }
            }

            for item in candidates {
                let plistURL = item.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plistURL),
                      let dict = (try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil)) as? [String: Any]
                else { continue }

                let bid = (dict["CFBundleIdentifier"] as? String) ?? ""
                if bid == selfBundleID { continue }

                let name = (dict["CFBundleDisplayName"] as? String)
                    ?? (dict["CFBundleName"] as? String)
                    ?? item.deletingPathExtension().lastPathComponent
                let version = (dict["CFBundleShortVersionString"] as? String) ?? "—"
                let lastUsed = (try? item.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
                let size = FileSizer.size(of: item)
                let parentWritable = fm.isWritableFile(atPath: item.deletingLastPathComponent().path)

                raw.append((name, bid, version, item, size, lastUsed, parentWritable))
            }
        }

        let pool = fuzzyPool()
        var result: [AppInfo] = []

        for app in raw {
            var leftovers: [LeftoverPath] = []
            var seen = Set<String>()

            // 1) 精确模板
            for url in exactCandidates(for: app.bid) {
                let (size, restricted) = sizeOrRestricted(url)
                leftovers.append(LeftoverPath(
                    url: url,
                    size: size,
                    confidence: restricted ? .restricted : .exact
                ))
                seen.insert(url.path)
            }

            // 2) 名称模糊匹配
            let keys = matchKeys(name: app.name, bundleID: app.bid)
            for (childName, url) in pool {
                if seen.contains(url.path) { continue }
                let hitKeys = keys.filter { matches(child: childName, key: $0) }
                guard !hitKeys.isEmpty else { continue }
                // 名称与键完全相等视为精确；前缀/包含命中的才是疑似
                let isExact = hitKeys.contains { childName.lowercased() == $0 }
                let (size, restricted) = sizeOrRestricted(url)
                leftovers.append(LeftoverPath(
                    url: url,
                    size: size,
                    confidence: restricted ? .restricted : (isExact ? .exact : .likely)
                ))
                seen.insert(url.path)
            }

            result.append(AppInfo(
                name: app.name,
                bundleID: app.bid,
                version: app.version,
                path: app.path,
                size: app.size,
                lastUsed: app.lastUsed,
                removable: app.removable,
                leftovers: leftovers.sorted { $0.size > $1.size },
                selected: false
            ))
        }

        return result.sorted { $0.size > $1.size }
    }
}

// MARK: - 图标缓存

final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let img = cache[path] { return img }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 36, height: 36)
        cache[path] = img
        return img
    }
}
