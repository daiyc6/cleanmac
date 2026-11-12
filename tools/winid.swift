import CoreGraphics
import Foundation

let opts: CGWindowListOption = [.optionAll]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
var best: (Int, Double) = (0, 0)
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.lowercased().contains("cleanmac") else { continue }
    let num = w[kCGWindowNumber as String] as? Int ?? 0
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    guard layer == 0 else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = (b["Width"] as? Double) ?? 0
    let height = (b["Height"] as? Double) ?? 0
    let area = width * height
    print("window=\(num) \(Int(width))x\(Int(height))")
    if area > best.1 { best = (num, area) }
}
print("BEST=\(best.0)")
