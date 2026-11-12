// 由 tools/gen_rules.py 从 resources/rules.json 生成，请勿手改
import Foundation

enum RulePack {
    /// 清单来源：docs/清理清单.md

    static let all: [Rule] = [
        Rule(id: "CACHE-01", category: .cache, title: "应用缓存", detail: "~/Library/Caches", target: .contents("~/Library/Caches"), risk: .safe),
        Rule(id: "LOG-01", category: .logs, title: "应用日志", detail: "~/Library/Logs", target: .contents("~/Library/Logs"), risk: .safe),
        Rule(id: "WALL-01", category: .wallpaper, title: "动态壁纸视频", detail: "~/Library/Application Support/com.apple.wallpaper/aerials", target: .contents("~/Library/Application Support/com.apple.wallpaper/aerials/videos"), risk: .safe),
        Rule(id: "TRASH-01", category: .trash, title: "废纸篓", detail: "~/.Trash", target: .contents("~/.Trash"), risk: .safe),
        Rule(id: "DEV-01", category: .developer, title: "Xcode DerivedData", detail: "~/Library/Developer/Xcode/DerivedData", target: .contents("~/Library/Developer/Xcode/DerivedData"), risk: .safe),
        Rule(id: "DEV-02", category: .developer, title: "模拟器缓存", detail: "~/Library/Developer/CoreSimulator/Caches", target: .contents("~/Library/Developer/CoreSimulator/Caches"), risk: .safe),
        Rule(id: "DEV-03", category: .developer, title: "npm 缓存", detail: "~/.npm/_cacache", target: .directory("~/.npm/_cacache"), risk: .safe),
        Rule(id: "DEV-04", category: .developer, title: "pnpm store", detail: "~/Library/pnpm/store", target: .contents("~/Library/pnpm/store"), risk: .safe),
        Rule(id: "DEV-05", category: .developer, title: "uv 缓存", detail: "~/.cache/uv", target: .directory("~/.cache/uv"), risk: .safe),
        Rule(id: "DEV-06", category: .developer, title: "Cargo 缓存", detail: "~/.cargo/registry/cache", target: .contents("~/.cargo/registry/cache"), risk: .safe),
        Rule(id: "HTTP-01", category: .cache, title: "App 会话缓存", detail: "~/Library/HTTPStorages", target: .contents("~/Library/HTTPStorages"), risk: .careful),
        Rule(id: "SAVED-01", category: .cache, title: "窗口恢复状态", detail: "~/Library/Saved Application State", target: .contents("~/Library/Saved Application State"), risk: .careful),
        Rule(id: "DL-01", category: .downloads, title: "安装包与压缩包", detail: "~/Downloads · dmg / pkg / zip", target: .files("~/Downloads", ["dmg", "pkg", "zip", "iso"]), risk: .risky),
    ]
}
