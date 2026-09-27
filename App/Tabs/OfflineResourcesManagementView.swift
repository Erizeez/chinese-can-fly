import SwiftUI
import CCFlyCore

/// 离线航电资源管理中心视图 (模块化按需下载与存储空间管理)
public struct OfflineResourcesManagementView: View {
    @State private var resourceManager = OfflineResourceManager.shared
    @State private var selectedCategory: ResourceCategory? = nil
    @State private var isDownloadingDict: [String: Double] = [:]
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false
    @State private var showConfirmDeleteAll: Bool = false

    public init() {}

    public var body: some View {
        List {
            // 1. 顶部存储空间使用摘要卡片
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("离线资源已占用空间")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(resourceManager.totalDiskUsageString())
                                .font(.system(size: 28, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue.opacity(0.8))
                    }

                    Text("提示：推荐在地面 WiFi 环境下按需下载所需空域及机场跑道包。脱网登机后，系统将自动优先调度本地已下载资源包。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack {
                        Button {
                            refreshAll()
                        } label: {
                            Label("检查更新", systemImage: "arrow.clockwise")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(role: .destructive) {
                            showConfirmDeleteAll = true
                        } label: {
                            Label("清空所有离线包", systemImage: "trash")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.vertical, 4)
            }

            // 2. 类别筛选选择器
            Section {
                Picker("资源分类", selection: $selectedCategory) {
                    Text("全部分类").tag(nil as ResourceCategory?)
                    ForEach(ResourceCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat as ResourceCategory?)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            // 3. 资源包列表
            let filteredPackages = selectedCategory == nil
                ? resourceManager.predefinedPackages
                : resourceManager.predefinedPackages.filter { $0.category == selectedCategory }

            ForEach(filteredPackages) { pkg in
                Section {
                    resourcePackageCard(pkg: pkg)
                }
            }
        }
        .navigationTitle("离线资源管理")
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertMessage ?? "通知", isPresented: $showAlert) {
            Button("好的", role: .cancel) {}
        }
        .confirmationDialog("确定清空所有已下载的离线资源包？", isPresented: $showConfirmDeleteAll, titleVisibility: .visible) {
            Button("确认清空并释放空间", role: .destructive) {
                resourceManager.deleteAllPackages()
                refreshAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将回退至内置基础常量。如需完整全国机场跑道与矢量航图，可随时重新下载。")
        }
        .onAppear {
            refreshAll()
        }
    }

    @ViewBuilder
    private func resourcePackageCard(pkg: OfflineResourcePackage) -> some View {
        let status = resourceManager.getStatus(for: pkg.id)
        let isDownloading = isDownloadingDict[pkg.id] != nil
        let progress = isDownloadingDict[pkg.id] ?? 0.0

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pkg.name)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(pkg.category.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())

                        Text("版本 \(pkg.version)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                // 状态指示
                switch status {
                case .installed(let size):
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("已就绪", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                case .downloading:
                    Text("下载中")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                case .notDownloaded:
                    Text("未下载 (\(pkg.formattedExpectedSize))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(pkg.packageDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            // 下载进度条
            if isDownloading {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }

            // 操作控制栏
            HStack {
                Text(pkg.localFileName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)

                Spacer()

                switch status {
                case .installed:
                    Button(role: .destructive) {
                        deletePackage(pkg: pkg)
                    } label: {
                        Label("删除", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)

                case .notDownloaded:
                    Button {
                        startDownload(pkg: pkg)
                    } label: {
                        if isDownloading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("下载 (\(pkg.formattedExpectedSize))", systemImage: "arrow.down.circle.fill")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading)

                case .downloading:
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 2)
    }

    private func startDownload(pkg: OfflineResourcePackage) {
        isDownloadingDict[pkg.id] = 0.1

        Task {
            do {
                try await resourceManager.downloadPackage(packageId: pkg.id) { prog in
                    Task { @MainActor in
                        self.isDownloadingDict[pkg.id] = prog
                    }
                }
                await MainActor.run {
                    self.isDownloadingDict.removeValue(forKey: pkg.id)
                    self.resourceManager.refreshAllPackageStatuses()
                    self.alertMessage = "“\(pkg.name)”已成功安装并生效！"
                    self.showAlert = true
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingDict.removeValue(forKey: pkg.id)
                    self.resourceManager.refreshAllPackageStatuses()
                    self.alertMessage = "下载失败: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }

    private func deletePackage(pkg: OfflineResourcePackage) {
        do {
            try resourceManager.deletePackage(packageId: pkg.id)
            refreshAll()
        } catch {
            alertMessage = "删除失败: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func refreshAll() {
        resourceManager.refreshAllPackageStatuses()
    }
}
