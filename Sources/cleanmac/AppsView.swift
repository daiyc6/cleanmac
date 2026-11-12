import SwiftUI
import AppKit

// MARK: - 行内动作按钮

private struct RowActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(tint.opacity(0.13))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
            )
            .fixedSize()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - 应用程序

struct AppsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showConfirm = false
    @State private var pendingRemoval: AppInfo?

    var body: some View {
        VStack(spacing: 0) {
            if model.apps.isEmpty {
                emptyState
            } else {
                listPanel
            }
            bottomBar
        }
        .onAppear {
            if model.apps.isEmpty && !model.scanningApps {
                model.scanApps()
            }
        }
        .alert("清理所选应用？", isPresented: $showConfirm) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) { model.cleanSelectedApps() }
        } message: {
            Text("将移除 \(model.selectedApps.count) 个应用及其数据，共约 \(formatBytes(model.selectedAppsBytes))。全部移入隔离区，可还原。")
        }
        .alert(item: $pendingRemoval) { app in
            Alert(
                title: Text("移除 \(app.name)？"),
                message: Text("只删除应用本体（\(formatBytes(app.size))），数据会保留，重新安装后可继续使用。会先移入隔离区。"),
                primaryButton: .destructive(Text("移除应用")) { model.removeApp(for: app) },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.scanningApps {
                ProgressView().controlSize(.small)
                Text("正在扫描应用与数据…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text("按 Bundle ID 与目录名反查每一项应用的数据")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.sub)
            } else {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.faint)
                Text("还没有扫描应用")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Button("开始扫描") { model.scanApps() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 列表

    private var listPanel: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.black.opacity(0.06))

            HStack(spacing: 10) {
                Spacer().frame(width: 18)
                Text("应用").frame(maxWidth: .infinity, alignment: .leading)
                Text("数据").frame(width: 78, alignment: .trailing)
                Text("占用").frame(width: 68, alignment: .trailing)
                Text("操作").frame(width: 172, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.faint)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.apps) { app in
                        row(app)
                        Divider().overlay(Color.black.opacity(0.04)).padding(.leading, 18)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
        .padding(18)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("应用程序")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("共 \(model.apps.count) 个 · 按占用排序")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
            }
            Spacer()
            Button("重新扫描") { model.scanApps() }
                .buttonStyle(GhostButtonStyle(compact: true))
                .disabled(model.scanningApps)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func row(_ app: AppInfo) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: binding(app))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 18)

            Image(nsImage: IconCache.shared.icon(for: app.path.path))
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("v\(app.version)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.faint)
                    if !app.removable {
                        Pill(text: "需管理员", color: Theme.warn)
                    }
                }
                HStack(spacing: 6) {
                    Text(app.bundleID.isEmpty ? app.path.path : app.bundleID)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                    Text("· \(app.lastUsedText)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(app.isStale ? Theme.danger : Theme.faint.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(app.exactDataSize > 0 ? formatBytes(app.exactDataSize) : "—")
                .font(.system(size: 11))
                .foregroundStyle(app.exactDataSize > 0 ? Theme.warn : Theme.faint)
                .monospacedDigit()
                .frame(width: 78, alignment: .trailing)

            Text(formatBytes(app.totalSize))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .frame(width: 68, alignment: .trailing)

            HStack(spacing: 6) {
                RowActionButton(
                    title: "删数据",
                    icon: "internaldrive",
                    tint: Theme.warn
                ) {
                    model.cleanData(for: app)
                }
                RowActionButton(
                    title: "删 App",
                    icon: "trash",
                    tint: Theme.danger
                ) {
                    pendingRemoval = app
                }
            }
            .frame(width: 172, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(app.selected ? Theme.accent.opacity(0.05) : Color.clear)
    }

    private func binding(_ app: AppInfo) -> Binding<Bool> {
        Binding(
            get: { model.apps.first(where: { $0.id == app.id })?.selected ?? false },
            set: { model.toggleApp(app.id, on: $0) }
        )
    }

    // MARK: 底栏

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(model.selectedApps.count) 个 · \(formatBytes(model.selectedAppsBytes))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.sub)

            if model.selectedApps.contains(where: { $0.likelyCount > 0 }) {
                Toggle("含疑似数据", isOn: $model.includeLikely)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
            }

            Spacer()

            Button("清理所选") { showConfirm = true }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.selectedApps.isEmpty || model.selectedAppsBytes == 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
