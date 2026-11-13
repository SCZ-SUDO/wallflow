import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var layoutManager: DesktopLayoutManager

    var chooseVideo: () -> Void

    @State private var isDropTarget = false

    private let accent = Color(red: 0.56, green: 0.34, blue: 0.97)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hero
            fillCard
            optionsGrid
            desktopLayoutSection
            recentSection
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 720)
        .background(background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wallflow")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("壁纸、桌面布局与桌面整理")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let reason = engine.autoPauseReason {
                Label(reason, systemImage: "pause.circle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关于 Wallflow")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)

            if let url = engine.currentURL {
                VideoThumbnail(url: url)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.02),
                        Color.black.opacity(0.12),
                        Color.black.opacity(0.86)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                emptyState
            }

            if isDropTarget {
                dropOverlay
            }
        }
        .frame(height: 248)
        .overlay(alignment: .bottomLeading) {
            if engine.currentURL != nil {
                heroDetails.padding(18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDropTarget ? accent : Color.white.opacity(0.12),
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: handleDrop)
        .animation(.easeOut(duration: 0.15), value: isDropTarget)
    }

    private var heroDetails: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(engine.displayTitle)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(engine.metadataText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.72))
                if let reason = engine.autoPauseReason {
                    Label(reason, systemImage: "pause.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.95))
                }
            }

            Spacer(minLength: 8)

            playButton

            Button {
                chooseVideo()
            } label: {
                Label("更换视频", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }

    private var playButton: some View {
        Button {
            engine.togglePlayback()
        } label: {
            Image(systemName: settings.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(engine.isBatteryPaused)
        .opacity(engine.isBatteryPaused ? 0.45 : 1)
        .help(settings.isPaused ? "继续播放" : "暂停播放")
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "film.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("拖入一段视频，让桌面动起来")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text("支持 MP4 / MOV / M4V · 建议使用可无缝循环的视频")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Button("选择视频…") {
                chooseVideo()
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropOverlay: some View {
        ZStack {
            accent.opacity(0.28)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34))
                Text("松开即可设为壁纸")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
    }

    // MARK: - Fill mode

    private var fillCard: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "arrow.up.left.and.arrow.down.right", tint: accent, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("画面填充")
                    .font(.system(size: 12.5, weight: .medium))
                Text(settings.fillMode.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("画面填充", selection: $settings.fillMode) {
                ForEach(FillMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(cardBackground)
    }

    // MARK: - Options

    private var optionsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            OptionCard(
                symbol: "speaker.slash.fill",
                tint: .blue,
                title: "静音播放",
                subtitle: "关闭视频原声",
                isOn: $settings.isMuted
            )
            OptionCard(
                symbol: "moon.zzz.fill",
                tint: .indigo,
                title: "锁屏时暂停",
                subtitle: "锁屏或休眠时停止渲染",
                isOn: $settings.pauseOnLock
            )
            OptionCard(
                symbol: "battery.50",
                tint: .green,
                title: "省电模式",
                subtitle: "使用电池时自动暂停",
                isOn: $settings.batterySaver
            )
            OptionCard(
                symbol: "power",
                tint: .orange,
                title: "开机启动",
                subtitle: "登录后自动恢复壁纸",
                isOn: launchAtLoginBinding
            )
        }
    }

    // MARK: - Desktop layout

    private var desktopLayoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconBadge(symbol: "rectangle.on.rectangle.angled", tint: .teal, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("桌面布局")
                        .font(.system(size: 12.5, weight: .medium))
                    Text(layoutManager.currentSummary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let profile = layoutManager.currentProfile {
                    Text("已保存 · \(profile.iconCount) 个图标")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.10)))
                } else {
                    Text("未保存")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("保存当前布局") {
                    let result = layoutManager.saveCurrentLayout()
                    Alerts.show(
                        title: result.success ? "已保存桌面布局" : "保存失败",
                        message: result.message
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)

                Button("恢复布局") {
                    layoutManager.restoreCurrentLayout { message in
                        Alerts.show(title: "桌面布局", message: message)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(layoutManager.currentProfile == nil)

                Spacer()

                Toggle("自动恢复", isOn: $layoutManager.autoRestore)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
            }

            Text("保存每套显示器组合的排列和桌面图标；自动恢复默认关闭。主屏不静默改，主屏不一致时会提示你先去系统设置切换。首次保存图标需允许 Wallflow 控制 Finder。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(cardBackground)
    }

    // MARK: - Recents

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("最近使用")
                    .font(.system(size: 13, weight: .semibold))

                if !settings.recents.isEmpty {
                    Text("\(settings.recents.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }

                Spacer()

                if !settings.recents.isEmpty {
                    Button("清除") {
                        settings.clearRecents()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }

            if settings.recents.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("应用过的视频会出现在这里")
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(height: 44)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(settings.recents) { recent in
                            RecentCard(
                                recent: recent,
                                isCurrent: recent.path == engine.currentURL?.path,
                                action: { _ = engine.apply(video: recent.url) },
                                remove: { settings.removeRecent(recent) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 1)
                }
                .frame(height: 78)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "menubar.rectangle")
            Text("关闭窗口后，点按菜单栏图标可重新打开")
            Spacer()
            Text("v1.1")
                .foregroundStyle(.tertiary)
            Text("·")
                .foregroundStyle(.tertiary)
            Button("退出 Wallflow") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.31, blue: 0.95).opacity(0.12),
                    Color.clear,
                    Color(red: 0.93, green: 0.36, blue: 0.55).opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                if let error = settings.setLaunchAtLogin(newValue) {
                    Alerts.show(
                        title: "无法设置开机启动",
                        message: "\(error)\n\n如果 Wallflow 还不在「应用程序」文件夹中，请先把它拖进去再试。"
                    )
                }
            }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var droppedURL: URL?
            if let data = item as? Data {
                droppedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                droppedURL = url
            }
            guard let droppedURL else { return }
            DispatchQueue.main.async {
                _ = engine.apply(video: droppedURL)
            }
        }
        return true
    }
}

// MARK: - Components

private struct VideoThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.9))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            image = await ThumbnailStore.shared.thumbnail(for: url)
        }
    }
}

private struct RecentCard: View {
    let recent: RecentVideo
    let isCurrent: Bool
    let action: () -> Void
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VideoThumbnail(url: recent.url)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    Spacer()
                    HStack {
                        Text(recent.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                }

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(5)
                }
            }
            .frame(width: 132, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isCurrent ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button("重新应用") { action() }
            Button("在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([recent.url])
            }
            Divider()
            Button("移除记录") { remove() }
        }
    }
}

private struct OptionCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, tint: tint, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}
