import SwiftUI
import AppKit

// MARK: - 概览

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    @Binding var route: Route

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if model.showOnboarding { onboarding }
                hero
                HStack(spacing: 14) {
                    statCard(title: "可用空间", value: formatBytes(model.disk.free), icon: "internaldrive", color: Theme.accent)
                    statCard(title: "隔离区", value: formatBytes(model.quarantineSize), icon: "archivebox", color: Theme.ok)
                    statCard(title: "个人文件待确认", value: formatBytes(model.personalBytes), icon: "hand.raised", color: Theme.warn)
                }
                if !model.safeItems.isEmpty { detailCard }
                if !model.personalItems.isEmpty { personalNotice }
            }
            .padding(24)
        }
    }

    private var sizeParts: (number: String, unit: String) {
        let s = formatBytes(model.safeBytes)
        let parts = s.split(separator: " ")
        if parts.count == 2 { return (String(parts[0]), String(parts[1])) }
        return (s, "")
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("两分钟，让它看得见更多")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("macOS 默认不允许读取「下载、桌面、文稿」。没有授权时，这些位置的文件扫不到，能清理的量会明显偏小。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("以后再说") { model.finishOnboarding() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
            }

            HStack(spacing: 8) {
                stepBadge(1, "打开系统设置")
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.faint)
                stepBadge(2, "勾选 cleanmac")
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.faint)
                stepBadge(3, "回来点「已授权」")
            }

            HStack(spacing: 10) {
                Button("去系统设置") {
                    model.openPrivacySettings()
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))

                Button("已授权，开始扫描") {
                    model.checkAccessAndFinish()
                }
                .buttonStyle(GhostButtonStyle(compact: true))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stepBadge(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text("\(n)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.sub)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.04)))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("可以安全清理")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.sub)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(sizeParts.number)
                    .font(.system(size: 62, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(sizeParts.unit)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.top, 2)

            Text(model.items.isEmpty ? "还没有扫描" : "来自缓存、日志与可重建的开发者数据")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.sub)
                .padding(.top, 2)

            HStack(spacing: 10) {
                Button(model.scanning ? "扫描中…" : "立即清理") {
                    model.cleanSafe()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.scanning || model.safeBytes == 0)

                Button("重新扫描") { model.startScan() }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.scanning)
            }
            .padding(.top, 18)

            Text("不会触碰你的照片、文档与聊天记录")
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(30)
        .card()
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.sub)
            }
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(radius: 14)
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("系统数据明细")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(formatBytes(model.safeBytes))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.sub)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider().overlay(Color.black.opacity(0.06))

            ForEach(model.safeItems) { item in
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.ink)
                    Text(item.detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.faint.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text(formatBytes(item.size))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 9)

                if item.id != model.safeItems.last?.id {
                    Divider().overlay(Color.black.opacity(0.05)).padding(.leading, 20)
                }
            }
        }
        .padding(.bottom, 6)
        .card()
    }

    private var personalNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("另有 \(formatBytes(model.personalBytes)) 属于你自己")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("安装包、下载文件等，需要你逐项确认才会删除")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.sub)
            }
            Spacer()
            Button("去确认") { route = .cleanup }
                .buttonStyle(GhostButtonStyle(compact: true))
        }
        .padding(16)
        .card(radius: 14)
    }
}

// MARK: - 清理

struct CleanupView: View {
    @EnvironmentObject var model: AppModel
    @State private var showConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                safeSection
                if !model.personalItems.isEmpty { personalSection }
            }
            .padding(24)
        }
        .alert("删除你选中的个人文件？", isPresented: $showConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) { model.cleanPersonalSelected() }
        } message: {
            Text("共 \(model.selectedPersonalCount) 项 · \(formatBytes(model.selectedPersonalBytes))。会先移入隔离区，可还原。")
        }
    }

    // MARK: 系统数据

    private var safeSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("系统数据")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("缓存、日志等可重建内容，清理后系统会自动生成")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.sub)
                }
                Spacer()
                Text(formatBytes(model.safeBytes))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Button("全部清理") { model.cleanSafe() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .disabled(model.safeBytes == 0)
            }
            .padding(20)

            Divider().overlay(Theme.line.opacity(0.6))

            if model.safeItems.isEmpty {
                Text(model.scanning ? "正在扫描…" : "没有可清理的系统数据")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
            } else {
                ForEach(model.safeItems) { item in
                    safeRow(item)
                    Divider().overlay(Theme.line.opacity(0.4)).padding(.leading, 20)
                }
            }
        }
        .card()
    }

    private func safeRow(_ item: ScanItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(item.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            Spacer()
            Text(formatBytes(item.size))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.sub)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: 个人文件

    private var personalSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("你的文件")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("这些内容由你创建，只有你确认后才会删除")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.sub)
                }
                Spacer()
                Text(formatBytes(model.personalBytes))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
            .padding(20)

            Divider().overlay(Theme.line.opacity(0.6))

            ForEach(model.personalItems) { item in
                personalRow(item)
                Divider().overlay(Theme.line.opacity(0.4)).padding(.leading, 20)
            }

            HStack {
                Text("已选 \(model.selectedPersonalCount) 项 · \(formatBytes(model.selectedPersonalBytes))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.sub)
                Spacer()
                Button("删除所选") { showConfirm = true }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .disabled(model.selectedPersonalCount == 0)
            }
            .padding(16)
        }
        .card()
    }

    private func personalRow(_ item: ScanItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: binding(item))
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(item.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            Spacer()
            Pill(text: item.risk.rawValue, color: riskColor(item.risk))
            Text(formatBytes(item.size))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func binding(_ item: ScanItem) -> Binding<Bool> {
        Binding(
            get: { model.items.first(where: { $0.id == item.id })?.selected ?? false },
            set: { model.toggle(item.id, on: $0) }
        )
    }
}

// MARK: - 隐形空间

struct HiddenView: View {
    @EnvironmentObject var model: AppModel

    private var blocked: [HiddenEntry] { model.hidden.filter { !$0.accessible } }
    private var allowed: [HiddenEntry] { model.hidden.filter { $0.accessible } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                intro
                listCard
            }
            .padding(22)
        }
        .onAppear { if model.hidden.isEmpty { model.probeHidden() } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("为什么有些空间读不到？")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("macOS 的隐私保护（TCC）只允许用户明确授权的程序读取照片、邮件、信息与备份目录。未授权时，这些文件真实占用磁盘，但任何清理工具都只能看到一个空壳。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("前往系统设置授权") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("重新检测") { model.probeHidden() }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.probingHidden)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("受保护位置")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(blocked.count) 个未授权 · \(allowed.count) 个可读")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().overlay(Theme.line)

            ForEach(model.hidden) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.accessible ? "lock.open" : "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(entry.accessible ? Theme.ok : Theme.warn)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text(entry.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(entry.accessible ? formatBytes(entry.size) : "未授权")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(entry.accessible ? Theme.ok : Theme.warn)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                Divider().overlay(Theme.line.opacity(0.6))
            }

            if model.hidden.isEmpty {
                Text(model.probingHidden ? "正在检测…" : "没有检测到受保护位置")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .padding(20)
            }
        }
        .card()
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                accessCard
                appearanceCard
                quarantineCard
                retentionCard
                aboutCard
            }
            .padding(22)
        }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("完全磁盘访问权限")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text("不授权时，「下载、桌面、文稿」里的文件不会被扫描。可以随时在这里补授权。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("打开系统设置") { model.openPrivacySettings() }
                    .buttonStyle(GhostButtonStyle(compact: true))
                Button("我已授权，检查一下") { model.checkAccessAndFinish() }
                    .buttonStyle(GhostButtonStyle(compact: true))
                Spacer()
                Button("重新显示引导") { model.reopenOnboarding() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("背景通透度")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 10) {
                Text("通透")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
                Slider(
                    value: Binding(get: { model.scrimOpacity }, set: { model.setScrim($0) }),
                    in: 0.15...0.70
                )
                .tint(Theme.accent)
                Text("厚实")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
            }

            Text("调低会更透出桌面壁纸，调高则文字更清晰。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.sub)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var quarantineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("隔离区")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(model.quarantineCount) 项 · \(formatBytes(model.quarantineSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
            }

            Text("清理的项目会先移动到这里。在保留期内可以还原，过期后会被自动删除。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("还原最近一次") { model.restoreLatest() }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.quarantineCount == 0)

                Button("在 Finder 中显示") { model.revealQuarantine() }
                    .buttonStyle(GhostButtonStyle())

                Button("清空隔离区") { model.clearQuarantine() }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.quarantineCount == 0)
            }

            if !model.batches.isEmpty {
                Divider().overlay(Theme.line)
                ForEach(model.batches) { batch in
                    HStack(spacing: 10) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faint)
                        Text(batch.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.ink)
                        Text("\(batch.count) 项")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.faint)
                        Spacer()
                        Text(remainingText(batch))
                            .font(.system(size: 10.5))
                            .foregroundStyle(remainingText(batch).contains("即将") ? Theme.danger : Theme.sub)
                        Text(formatBytes(batch.size))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var retentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("自动清理")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()

                Picker("", selection: Binding(
                    get: { model.retentionDays },
                    set: { model.setRetention($0) }
                )) {
                    Text("1 天后").tag(1)
                    Text("3 天后").tag(3)
                    Text("7 天后").tag(7)
                    Text("30 天后").tag(30)
                    Text("永不").tag(0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 104)
            }

            Text("超过保留期的批次会被彻底删除，无法还原。App 启动时与每小时各检查一次。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("立即清理过期项") { model.purgeExpired(manual: true) }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.retentionDays == 0)
                Spacer()
                Text(model.retentionDays == 0 ? "当前：不自动清理" : "当前：\(model.retentionDays) 天后清理")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func remainingText(_ batch: Quarantine.Batch) -> String {
        guard model.retentionDays > 0 else { return "不会自动清理" }
        let expire = batch.date.addingTimeInterval(Double(model.retentionDays) * 86_400)
        let left = expire.timeIntervalSinceNow
        if left <= 0 { return "即将清理" }
        let hours = Int(left / 3600)
        if hours >= 24 { return "\(hours / 24) 天后清理" }
        return "\(max(1, hours)) 小时后清理"
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accentGradient)
                    .frame(width: 34, height: 34)
                    .overlay(Text("✦").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text("cleanmac")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("版本 0.1 · 免费开源")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.sub)
                }
                Spacer()
            }

            Divider().overlay(Theme.line)

            row("网络请求", "0（完全不联网）")
            row("数据上传", "无")
            row("规则库", "内置 v0.1 · \(Rule.all.count) 条")
            row("剪贴板/键鼠监控", "无")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.sub)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
    }
}
