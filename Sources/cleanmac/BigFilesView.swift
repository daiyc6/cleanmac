import SwiftUI

struct BigFilesView: View {
    @EnvironmentObject var model: AppModel
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if model.bigFiles.isEmpty && !model.scanningFiles {
                emptyState
            } else {
                listPanel
            }
            bottomBar
        }
        .onAppear {
            if model.bigFiles.isEmpty && !model.scanningFiles {
                model.scanBigFiles()
            }
        }
        .alert("删除选中的文件？", isPresented: $showConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) { model.deleteSelectedFiles() }
        } message: {
            Text("共 \(model.selectedFiles.count) 项 · \(formatBytes(model.selectedFilesBytes))。会移入隔离区，可还原。")
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.scanningFiles {
                ProgressView().controlSize(.small)
                Text("正在查找大文件…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(model.fileScanStatus)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.faint)
                Text("还没有扫描")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("找出大于 200 MB，或一年没打开过的文件")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.sub)
                Button("开始扫描") { model.scanBigFiles() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 列表

    private var listPanel: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.black.opacity(0.06))

            if !model.blockedDirs.isEmpty { blockedBanner }

            HStack(spacing: 10) {
                Spacer().frame(width: 18)
                Text("文件").frame(maxWidth: .infinity, alignment: .leading)
                Text("最近访问").frame(width: 76, alignment: .trailing)
                Text("大小").frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.faint)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.filteredFiles) { file in
                        row(file)
                        Divider().overlay(Color.black.opacity(0.04)).padding(.leading, 18)
                    }
                    if model.filteredFiles.isEmpty {
                        Text("这个筛选条件下没有内容")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                            .padding(.vertical, 40)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
        .padding(18)
    }

    private var blockedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warn)
            Text("\(model.blockedDirs.count) 个目录无法读取（macOS 隐私保护），其中的大文件不会被列出")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.sub)
            Spacer()
            Button("去授权") { model.openPrivacySettings() }
                .buttonStyle(GhostButtonStyle(compact: true))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(Theme.warn.opacity(0.08))
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("大文件与旧文件")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(model.bigFiles.count) 个 · 共 \(formatBytes(model.bigFilesBytes)) · 大于 200 MB 或一年未打开")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
            }

            Spacer()

            Picker("", selection: $model.fileFilter) {
                ForEach(AppModel.FileFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 232)

            Button(model.scanningFiles ? "扫描中…" : "重新扫描") { model.scanBigFiles() }
                .buttonStyle(GhostButtonStyle(compact: true))
                .disabled(model.scanningFiles)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func row(_ file: BigFile) -> some View {
        let lockReason = Protection.reason(for: file.url)
        return HStack(spacing: 10) {
            Toggle("", isOn: binding(file))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(lockReason != nil)
                .frame(width: 18)

            Image(systemName: file.symbol)
                .font(.system(size: 12))
                .foregroundStyle(lockReason == nil ? Theme.accent : Theme.faint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if file.isOld && !file.isBig {
                        Pill(text: "一年未用", color: Theme.warn)
                    }
                    if let reason = lockReason {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.warn)
                            .help(reason)
                    }
                }
                Text(file.displayPath)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(file.lastAccessText)
                .font(.system(size: 10.5))
                .foregroundStyle(file.isOld ? Theme.warn : Theme.sub)
                .frame(width: 76, alignment: .trailing)

            Text(formatBytes(file.size))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(model.selectedFileIDs.contains(file.id) ? Theme.accent.opacity(0.05) : Color.clear)
    }

    private func binding(_ file: BigFile) -> Binding<Bool> {
        Binding(
            get: { model.selectedFileIDs.contains(file.id) },
            set: { model.setFileSelected(file.id, $0) }
        )
    }

    // MARK: 底栏

    private var bottomBar: some View {
        HStack {
            Text(model.selectedFiles.isEmpty
                 ? "勾选后可删除"
                 : "已选 \(model.selectedFiles.count) 项 · \(formatBytes(model.selectedFilesBytes))")
                .font(.system(size: 12))
                .foregroundStyle(model.selectedFiles.isEmpty ? Theme.faint : Theme.sub)

            Spacer()

            Button("删除所选") { showConfirm = true }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.selectedFiles.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
