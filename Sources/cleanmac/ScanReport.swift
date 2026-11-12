import Foundation

/// 无界面扫描报告，用于验证引擎（不修改任何文件）
enum ScanReport {
    static func run() {
        print("ID\t名称\t体积\t项目数\t路径")
        var grand: Int64 = 0
        for rule in Rule.all {
            let urls = rule.resolve()
            var total: Int64 = 0
            for u in urls { total += FileSizer.size(of: u) }
            grand += total
            let detail: String
            switch rule.target {
            case .contents(let p), .directory(let p): detail = p
            case .files(let p, _): detail = p
            }
            print("\(rule.id)\t\(rule.title)\t\(formatBytes(total))\t\(urls.count)\t\(detail)")
        }
        print("TOTAL\t\t\(formatBytes(grand))\t\t")
    }
}
