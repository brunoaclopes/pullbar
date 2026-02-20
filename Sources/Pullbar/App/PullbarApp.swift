import SwiftUI
import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppContext {
    static let shared = AppContext()

    let settings = SettingsStore()
    let store = PullRequestStore()

    private init() {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private enum Layout {
        static let popoverSize = NSSize(width: 560, height: 640)
    }

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var hasDeferredStatusUpdate = false
    private var lastSeenNotificationCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let context = AppContext.shared

        let hosting = NSHostingController(
            rootView: ContentView()
                .environmentObject(context.settings)
                .environmentObject(context.store)
                .frame(width: Layout.popoverSize.width, height: Layout.popoverSize.height)
        )

        hosting.preferredContentSize = Layout.popoverSize

        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "Pull Requests")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
        }

        syncLaunchAtLoginSetting(context: context)

        bindStatusItem(context: context)

        Task { @MainActor in
            await context.store.configure(settings: context.settings)
            await context.store.loadCachedIfNeeded()
            await context.store.refreshAll(force: false, settings: context.settings)
        }
    }

    private func bindStatusItem(context: AppContext) {
        let forceRefresh: () -> Void = {
            Task { @MainActor in
                await context.store.refreshAll(force: true, settings: context.settings)
            }
        }

        context.store.$notificationHintCount
            .sink { [weak self] _ in
                self?.updateStatusButton(context: context)
            }
            .store(in: &cancellables)

        context.settings.$showNotificationCount
            .sink { [weak self] _ in
                self?.updateStatusButton(context: context)
            }
            .store(in: &cancellables)

        context.settings.$notifyReviewRequests
            .sink { _ in
                context.store.updateNotificationHints(settings: context.settings)
            }
            .store(in: &cancellables)

        context.settings.$notifyOpenComments
            .sink { _ in
                context.store.updateNotificationHints(settings: context.settings)
            }
            .store(in: &cancellables)

        context.settings.$refreshIntervalSeconds
            .sink { _ in
                context.store.restartAutoRefresh(settings: context.settings)
            }
            .store(in: &cancellables)

        context.settings.$prSortOrder
            .sink { _ in
                context.store.applySort(settings: context.settings)
            }
            .store(in: &cancellables)

        context.settings.$launchAtLogin
            .dropFirst()
            .sink { [weak self] enabled in
                self?.setLaunchAtLogin(enabled, context: context)
            }
            .store(in: &cancellables)

        context.settings.$enterpriseHostURL
            .sink { _ in
                forceRefresh()
            }
            .store(in: &cancellables)

        context.settings.$enterpriseAPIURL
            .sink { _ in
                forceRefresh()
            }
            .store(in: &cancellables)

        updateStatusButton(context: context)
    }

    private func updateStatusButton(context: AppContext) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            hasDeferredStatusUpdate = true
            return
        }

        let count = context.store.notificationHintCount
        if count > 0 {
            let indicatorText = context.settings.showNotificationCount ? " \(count)" : " •"
            let hasIncreasedSinceLastOpen = count > lastSeenNotificationCount

            button.title = ""
            button.attributedTitle = NSAttributedString(
                string: indicatorText,
                attributes: [
                    .foregroundColor: hasIncreasedSinceLastOpen ? NSColor.systemOrange : NSColor.labelColor
                ]
            )
        } else {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        }

        hasDeferredStatusUpdate = false
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            lastSeenNotificationCount = AppContext.shared.store.notificationHintCount
            updateStatusButton(context: AppContext.shared)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard hasDeferredStatusUpdate else { return }
        updateStatusButton(context: AppContext.shared)
    }

    private func syncLaunchAtLoginSetting(context: AppContext) {
        context.settings.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool, context: AppContext) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            context.settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

@main
struct PullbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let context = AppContext.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(context.settings)
                .environmentObject(context.store)
                .frame(width: 620, height: 540)
        }
    }
}