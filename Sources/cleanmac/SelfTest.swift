import Foundation

/// 隔离区往返自测：不接触任何真实用户文件
enum SelfTest {

    static func run() -> Bool {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("cleanmac-selftest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }

        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)

            var urls: [URL] = []
            for i in 0..<3 {
                let u = base.appendingPathComponent("file\(i).txt")
                try Data("hello-cleanmac".utf8).write(to: u)
                urls.append(u)
            }

            let item = ScanItem(
                ruleID: "SELFTEST",
                title: "自测项",
                detail: base.path,
                category: .cache,
                risk: .safe,
                size: 45,
                urls: urls,
                selected: true
            )

            let result = Quarantine.move([item])
            guard result.success, let batch = result.batch else {
                print("SELFTEST FAIL: move 失败 \(result.failures.map(\.reason))")
                return false
            }
            if result.moved != 3 {
                print("SELFTEST FAIL: 移动数量 \(result.moved) != 3")
                return false
            }

            let remaining = urls.filter { fm.fileExists(atPath: $0.path) }
            if !remaining.isEmpty {
                print("SELFTEST FAIL: 原位置仍有 \(remaining.count) 个文件")
                return false
            }

            let restored = Quarantine.restore(batch: batch)
            if restored != 3 {
                print("SELFTEST FAIL: 还原数量 \(restored) != 3")
                return false
            }

            let back = urls.filter { fm.fileExists(atPath: $0.path) }
            if back.count != 3 {
                print("SELFTEST FAIL: 还原后只剩 \(back.count) 个文件")
                return false
            }

            print("SELFTEST OK: move=\(result.moved) restore=\(restored)")
            return true
        } catch {
            print("SELFTEST ERROR: \(error)")
            return false
        }
    }
}
