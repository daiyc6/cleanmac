import SwiftUI
import AppKit

// MARK: - 空间地图

struct SpaceView: View {
    @EnvironmentObject var model: AppModel
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)

            if model.spaceLoading {
                loading
            } else if model.spaceEntries.isEmpty {
                emptyFolder
            } else {
                treemapSection
                listSection
            }

            bottomBar
        }
        .onAppear {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--path"), i + 1 < args.count {
                model.openSpace(URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath), push: false)
            } else if model.spaceStack.isEmpty {
                model.openSpace(FileManager.default.homeDirectoryForCurrentUser, push: false)
            }
        }
        .alert("删除所选项目？", isPresented: $showConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) { model.deleteSpaceSelection() }
        } message: {
            Text("将删除 \(model.spaceSelected.count) 项，约 \(formatBytes(model.spaceSelectedSize))。文件会移入隔离区，7 天内可还原。")
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                model.goUpSpace()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(model.canGoUp ? Color(red: 0.933, green: 0.941, blue: 0.965) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canGoUp ? Theme.ink : Theme.faint.opacity(0.4))
            .disabled(!model.canGoUp)

            breadcrumb

            Spacer()

            if model.spaceLoading {
                ProgressView().controlSize(.small)
            } else {
                Text("\(model.spaceEntries.count) 项 · \(formatBytes(model.spaceTotal))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.sub)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(Color.white.opacity(0.7))
    }

    private func breadcrumbLabel(index: Int, url: URL) -> String {
        if index == 0, url.path == NSHomeDirectory() { return "~" }
        return url.lastPathComponent
    }

    private var breadcrumb: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.spaceStack.enumerated()), id: \.offset) { index, url in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.faint)
                }
                Button {
                    model.jumpSpace(to: index)
                } label: {
                    Text(breadcrumbLabel(index: index, url: url))
                        .font(.system(size: 12,
                                      weight: index == model.spaceStack.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == model.spaceStack.count - 1 ? Theme.ink : Theme.accent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 状态

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("正在计算体积…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.sub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFolder: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 30))
                .foregroundStyle(Theme.faint)
            Text("这个文件夹是空的")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
            if model.canGoUp {
                Button("返回上一级") { model.goUpSpace() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 色块图

    /// 条目过多时，把尾部小项合并成「其他」，避免树图退化成噪点
    private func displayEntries(_ entries: [SpaceEntry]) -> [SpaceEntry] {
        let limit = 36
        guard entries.count > limit else { return entries }
        let head = Array(entries.prefix(limit))
        let tail = entries.dropFirst(limit)
        let tailSize = tail.reduce(Int64(0)) { $0 + $1.size }
        guard tailSize > 0 else { return head }
        var out = head
        out.append(SpaceEntry(
            url: URL(fileURLWithPath: "/__others__"),
            name: "其他 \(tail.count) 项",
            isDirectory: false,
            size: tailSize
        ))
        return out
    }

    private var treemapSection: some View {
        GeometryReader { geo in
            let tiles = treemapTiles(displayEntries(model.spaceEntries),
                                     in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    tileView(tile)
                }
            }
        }
        .frame(height: 232)
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private func tileView(_ tile: SpaceTile) -> some View {
        let isSelected = model.spaceSelected.contains(tile.entry.url)
        let color = tile.entry.isDirectory ? Theme.accent : Theme.accent2

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color.opacity(isSelected ? 1.0 : 0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
            .frame(width: max(0, tile.rect.width - 4),
                   height: max(0, tile.rect.height - 4))
            .overlay(alignment: .topLeading) {
                if tile.rect.width > 72 && tile.rect.height > 32 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.entry.name)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Text(formatBytes(tile.entry.size))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if Protection.isProtected(tile.entry.url), tile.rect.width > 50, tile.rect.height > 40 {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(5)
                }
            }
            .offset(x: tile.rect.minX + 2, y: tile.rect.minY + 2)
            .onTapGesture { model.enter(tile.entry) }
            .help(tile.entry.isDirectory ? "点击进入 \(tile.entry.name)" : "点击选择 \(tile.entry.name)")
    }

    // MARK: 文件列表

    private var listSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("文件列表")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if model.spaceEntries.contains(where: { Protection.isProtected($0.url) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 8))
                        Text("资料库受保护，内部项目不可删除")
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(Theme.warn)
                } else {
                    Text("点击文件夹色块可进入")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.faint)
                }
                Spacer()
                Button(model.spaceSelected.count == model.spaceEntries.count ? "取消全选" : "全选") {
                    model.selectAllSpace(model.spaceSelected.count != model.spaceEntries.count)
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)

            Divider().overlay(Theme.line)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.spaceEntries) { entry in
                        row(entry)
                        Divider().overlay(Theme.line.opacity(0.45))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ entry: SpaceEntry) -> some View {
        let lockReason = Protection.reason(for: entry.url)
        return HStack(spacing: 10) {
            Toggle("", isOn: spaceBinding(entry))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(lockReason != nil)

            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(entry.isDirectory ? Theme.accent : Theme.faint)
                .frame(width: 14)

            Text(entry.name)
                .font(.system(size: 12))
                .foregroundStyle(lockReason == nil ? Theme.ink : Theme.sub)
                .lineLimit(1)

            if let reason = lockReason {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warn)
                    .help(reason)
            }

            Spacer(minLength: 8)

            if entry.isDirectory {
                Button("进入 ›") { model.enter(entry) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
            }

            Text(entry.size > 0 ? formatBytes(entry.size) : "无法读取")
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(entry.size > 0 ? Theme.ink : Theme.warn)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(model.spaceSelected.contains(entry.url)
                    ? Theme.accent.opacity(0.06)
                    : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.enter(entry) }
    }

    private func spaceBinding(_ entry: SpaceEntry) -> Binding<Bool> {
        Binding(
            get: { model.spaceSelected.contains(entry.url) },
            set: { on in
                if on {
                    model.spaceSelected.insert(entry.url)
                } else {
                    model.spaceSelected.remove(entry.url)
                }
            }
        )
    }

    // MARK: 底栏

    private var bottomBar: some View {
        HStack {
            Text(model.spaceSelected.isEmpty
                 ? "勾选项目后可删除"
                 : "已选 \(model.spaceSelected.count) 项 · \(formatBytes(model.spaceSelectedSize))")
                .font(.system(size: 12))
                .foregroundStyle(model.spaceSelected.isEmpty ? Theme.faint : Theme.sub)

            Spacer()

            Button("删除所选") { showConfirm = true }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.spaceSelected.isEmpty || model.spaceDeleting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.85))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }
}

// MARK: - 矩形树图布局

struct SpaceTile: Identifiable {
    let id = UUID()
    let entry: SpaceEntry
    let rect: CGRect
}

func treemapTiles(_ entries: [SpaceEntry], in rect: CGRect) -> [SpaceTile] {
    if entries.isEmpty { return [] }
    if entries.count == 1 { return [SpaceTile(entry: entries[0], rect: rect)] }

    let total = Double(entries.reduce(Int64(0)) { $0 + $1.size })
    guard total > 0 else { return [SpaceTile(entry: entries[0], rect: rect)] }

    var acc: Double = 0
    var splitIndex = 1
    for (i, e) in entries.enumerated() {
        acc += Double(e.size)
        if acc >= total / 2 {
            splitIndex = i + 1
            break
        }
    }
    splitIndex = max(1, min(splitIndex, entries.count - 1))

    let a = Array(entries[0..<splitIndex])
    let b = Array(entries[splitIndex...])
    let sumA = Double(a.reduce(Int64(0)) { $0 + $1.size })
    let ratio = CGFloat(sumA / total)

    if rect.width >= rect.height {
        let w = rect.width * ratio
        return treemapTiles(a, in: CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height))
             + treemapTiles(b, in: CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height))
    } else {
        let h = rect.height * ratio
        return treemapTiles(a, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h))
             + treemapTiles(b, in: CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h))
    }
}
