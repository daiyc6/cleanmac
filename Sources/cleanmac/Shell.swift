import SwiftUI
import AppKit

// MARK: - App 入口

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--scan-report") {
            ScanReport.run()
            exit(0)
        }
        let argv = CommandLine.arguments
        if let i = argv.firstIndex(of: "--who"), i + 1 < argv.count {
            let url = URL(fileURLWithPath: (argv[i + 1] as NSString).expandingTildeInPath)
            let owners = ProcessAttribution.owners(of: url)
            let app = ProcessAttribution.runningApp(for: url.path)
            print("owners=\(owners)")
            print("runningApp=\(app?.name ?? "none") bundleID=\(app?.bundleID ?? "none")")
            exit(0)
        }
        if let i = argv.firstIndex(of: "--diagnose"), i + 1 < argv.count {
            let url = URL(fileURLWithPath: (argv[i + 1] as NSString).expandingTildeInPath)
            let flags = FileFlags.read(url)
            let d = FailureAnalyzer.analyze(
                url: url,
                error: NSError(domain: "probe", code: 0),
                owners: [],
                app: nil
            )
            print("flags=0x\(String(flags, radix: 16))")
            print("protection=\(Protection.reason(for: url) ?? "可删除")")
            print("cause=\(d.cause)")
            print("remedies=\(d.remedies.map(\.label))")
            exit(0)
        }
        if let i = argv.firstIndex(of: "--clear-uchg"), i + 1 < argv.count {
            let url = URL(fileURLWithPath: (argv[i + 1] as NSString).expandingTildeInPath)
            let ok = RemedyRunner.clearImmutable(url)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let immutable = (attrs?[.immutable] as? Bool) ?? false
            print("cleared=\(ok) stillImmutable=\(immutable)")
            exit(0)
        }
        if let i = argv.firstIndex(of: "--purge-days"), i + 1 < argv.count, let d = Int(argv[i + 1]) {
            let r = Quarantine.purge(olderThanDays: d)
            print("purged=\(r.removed) bytes=\(r.bytes)")
            exit(0)
        }
        if CommandLine.arguments.contains("--apps-report") {
            let list = Uninstaller.scan()
            print("名称\t应用体积\t残留\t最近使用\tBundleID")
            for a in list.prefix(15) {
                print("\(a.name)\t\(formatBytes(a.size))\t可移除=\(a.removable)\t路径=\(a.path.path)")
            }
            print("TOTAL\t\(list.count) 个应用\t\(formatBytes(list.reduce(0) { $0 + $1.size }))\t\t")
            exit(0)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 菜单栏常驻，关窗不退出
        false
    }
}

@main
struct CleanMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("cleanmac", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarPanel().environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                Text(formatBytes(model.disk.free))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - 菜单栏面板

struct MenuBarPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatBytes(model.disk.free))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text("可用")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
                Spacer()
            }

            Text("已用 \(Int(model.disk.usedRatio * 100))% · 共 \(formatBytes(model.disk.total))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.sub)

            Divider()

            HStack {
                Text("可以安全清理")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.sub)
                Spacer()
                Text(formatBytes(model.safeBytes))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }

            Button("立即清理") { model.cleanSafe() }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .disabled(model.safeBytes == 0)
                .frame(maxWidth: .infinity)

            Divider()

            HStack(spacing: 8) {
                Button("打开 cleanmac") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(GhostButtonStyle(compact: true))

                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(GhostButtonStyle(compact: true))
            }
        }
        .padding(18)
        .frame(width: 250)
    }
}

// MARK: - 路由

enum Route: String, CaseIterable, Identifiable {
    case overview = "概览"
    case cleanup  = "清理"
    case apps     = "应用程序"
    case files    = "大文件"
    case space    = "空间地图"
    case hidden   = "隐形空间"
    case settings = "设置"

    var id: String { rawValue }

    /// 调试用：CLEANMAC_ROUTE=apps 可直接启动到指定页
    static var initial: Route {
        // 支持两种写法：open --args --route apps / 环境变量 CLEANMAC_ROUTE
        var key = ProcessInfo.processInfo.environment["CLEANMAC_ROUTE"] ?? ""
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--route"), i + 1 < args.count {
            key = args[i + 1]
        }
        switch key {
        case "cleanup":  return .cleanup
        case "apps":     return .apps
        case "files":    return .files
        case "space":    return .space
        case "hidden":   return .hidden
        case "settings": return .settings
        default:         return .overview
        }
    }

    var icon: String {
        switch self {
        case .overview: return "circle.dashed"
        case .cleanup:  return "line.3.horizontal.decrease"
        case .apps:     return "square.stack.3d.up"
        case .files:    return "doc.text.magnifyingglass"
        case .space:    return "square.grid.2x2"
        case .hidden:   return "eye"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - 主容器

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var route: Route = .initial

    var body: some View {
        ZStack {
            VisualEffectBackground()
            // 中性白纱：压住壁纸的明暗，保证文字稳定；不做成彩色，避免又变成色块
            Color.white.opacity(model.scrimOpacity)
            AppBackground().opacity(0.10)
            HStack(spacing: 0) {
                Sidebar(route: $route)

            VStack(spacing: 0) {
                TopBar(route: route)
                Divider().overlay(Theme.line)

                Group {
                    switch route {
                    case .overview: OverviewView(route: $route)
                    case .cleanup:  CleanupView()
                    case .apps:     AppsView()
                    case .files:    BigFilesView()
                    case .space:    SpaceView()
                    case .hidden:   HiddenView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            }
        }
        .background(WindowConfigurator())
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            if CommandLine.arguments.contains("--autoscan"), model.items.isEmpty {
                model.startScan()
            }
            guard CommandLine.arguments.contains("--demo-failures"), model.moveReport == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                model.moveReport = AppModel.MoveReport(failures: [
                    MoveFailure(
                        name: "com.google.Chrome",
                        path: "~/Library/Caches/com.google.Chrome",
                        reason: "没有写入权限（可能需要管理员或完全磁盘访问）",
                        cause: "正被 Google Chrome 使用，被 Google Chrome 占用",
                        remedies: [.quitAndRetry],
                        owners: [ProcessOwner(pid: 1204, name: "Google Chrome")],
                        appName: "Google Chrome",
                        bundleID: "com.google.Chrome"
                    ),
                    MoveFailure(
                        name: "video.mp4",
                        path: "~/Movies/video.mp4",
                        reason: "操作不被允许（系统保护或文件不可变）",
                        cause: "文件被标记为不可变（uchg），系统拒绝移动",
                        remedies: [.clearImmutable],
                        owners: [],
                        appName: nil,
                        bundleID: nil
                    ),
                    MoveFailure(
                        name: "Mail",
                        path: "~/Library/Mail/V10",
                        reason: "没有写入权限",
                        cause: "文件位于受 macOS 隐私保护的目录，未授权时任何程序都无法读取",
                        remedies: [.openFullDiskAccess],
                        owners: [],
                        appName: nil,
                        bundleID: nil
                    )
                ])
            }
        }
        .sheet(item: $model.moveReport) { _ in
            MoveFailureSheet().environmentObject(model)
        }
        .animation(.easeInOut(duration: 0.18), value: model.toast)
        .onAppear {
            if ProcessInfo.processInfo.environment["CLEANMAC_AUTOSCAN"] == "1", model.items.isEmpty {
                model.startScan()
            }
        }
    }
}

// MARK: - 侧边栏

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @Binding var route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text("cleanmac")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 18)
            .padding(.top, 38)
            .padding(.bottom, 18)

            VStack(spacing: 1) {
                ForEach(Route.allCases) { item in
                    Button {
                        route = item
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12))
                                .frame(width: 18)
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: route == item ? .medium : .regular))
                            Spacer(minLength: 0)
                            if item == .cleanup, model.safeBytes > 0 {
                                Text(formatBytes(model.safeBytes))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundStyle(route == item ? Theme.ink : Theme.sub)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(route == item ? Color.white : Color.clear)
                                .shadow(color: .black.opacity(route == item ? 0.07 : 0), radius: 3, y: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Macintosh HD")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.faint)
                    Spacer()
                    Text("\(Int(model.disk.usedRatio * 100))%")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.faint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.07))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(3, geo.size.width * min(1, model.disk.usedRatio)))
                    }
                }
                .frame(height: 4)
                Text("可用 \(formatBytes(model.disk.free))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.sub)
            }
            .padding(16)
        }
        .frame(width: 216)
        .background { Rectangle().fill(.ultraThinMaterial) }
    }
}

// MARK: - 顶栏

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    let route: Route

    var body: some View {
        HStack(spacing: 10) {
            Text(route.rawValue)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            if model.scanning {
                ProgressView().controlSize(.small)
            }
            Button {
                model.startScan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.sub)
            .disabled(model.scanning)
        }
        .padding(.horizontal, 24)
        .frame(height: 50)
        .padding(.top, 16)
    }
}

// MARK: - 删除失败报告

struct MoveFailureSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pending: PendingAction?

    private struct PendingAction: Identifiable {
        let id = UUID()
        let remedy: Remedy
        let failure: MoveFailure
    }

    private var failures: [MoveFailure] { model.moveReport?.failures ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warn)
                Text("\(failures.count) 项无法删除")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(20)

            Divider().overlay(Theme.line)

            if failures.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.ok)
                    Text("已全部处理")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(failures) { f in
                            row(f)
                            Divider().overlay(Theme.line.opacity(0.5))
                        }
                    }
                }
            }

            Divider().overlay(Theme.line)

            HStack {
                Text("每项都给出了对应的解决办法，可直接执行")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
        }
        .frame(width: 620, height: 500)
        .background(Theme.bg)
        .alert(item: $pending) { p in
            Alert(
                title: Text(p.remedy == .adminDelete ? "以管理员永久删除？" : "结束 \(p.failure.appName ?? "占用进程")？"),
                message: Text(confirmMessage(p)),
                primaryButton: .destructive(Text(p.remedy == .adminDelete ? "永久删除" : "结束并删除")) {
                    model.apply(p.remedy, to: p.failure)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private func confirmMessage(_ p: PendingAction) -> String {
        switch p.remedy {
        case .adminDelete:
            return "「\(p.failure.name)」会被直接删除，不进入隔离区，无法还原。需要输入管理员密码。"
        case .quitAndRetry:
            return "未保存的修改会丢失。结束后会自动重试删除这一项。"
        default:
            return ""
        }
    }

    private func row(_ f: MoveFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(f.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text(f.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)

            // 诊断结论
            HStack(spacing: 5) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 9))
                Text(f.cause)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Theme.danger)

            if !f.owners.isEmpty {
                Text("占用进程：" + f.owners.map(\.display).joined(separator: "、"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.danger.opacity(0.85))
            }

            // 解决办法
            HStack(spacing: 8) {
                if model.quittingIDs.contains(f.id) {
                    ProgressView().controlSize(.small)
                    Text("正在处理…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.sub)
                } else {
                    ForEach(f.remedies) { remedy in
                        Button(remedy.label) { request(remedy, f) }
                            .buttonStyle(GhostButtonStyle())
                    }
                    Spacer()
                    Text(f.reason)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func request(_ remedy: Remedy, _ failure: MoveFailure) {
        if remedy.needsConfirm {
            pending = PendingAction(remedy: remedy, failure: failure)
        } else {
            model.apply(remedy, to: failure)
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.204, green: 0.827, blue: 0.600))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.114, green: 0.125, blue: 0.149))
        )
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
    }
}
