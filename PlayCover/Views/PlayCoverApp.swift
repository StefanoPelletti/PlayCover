//
//  PlayCoverApp.swift
//  PlayCover
//

import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("ShowLowPowerModeAlert") var showLowPowerModeAlert = true

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            URLHandler.shared.processURL(url: url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdateScheme.checkForUpdate()
        UpstreamCommitBadge.start()

        UserDefaults.standard.register(
            defaults: ["NSApplicationCrashOnExceptions": true]
        )

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(powerStateChanged),
                                               name: Notification.Name.NSProcessInfoPowerStateDidChange,
                                               object: nil)
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            powerModal()
        }
        URLCache.iconCache.removeAllCachedResponses()
        // Code that run once on first launch
        let launchedBefore = UserDefaults.standard.bool(forKey: "launchedBefore")
        if !launchedBefore {
            UserDefaults.standard.set(true, forKey: "launchedBefore")

            // Initialize KeyCover with an automatically generated key
            let keyCoverPassword = KeyCoverPassword.shared.generateVerySecurePassword()
            KeyCoverPassword.shared.setKeyCoverPassword(keyCoverPassword)
            KeyCoverPreferences.shared.keyCoverEnabled = .selfGeneratedPassword
        }

    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc func powerStateChanged(_ notification: Notification) {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            Task { @MainActor in
                self.powerModal()
            }
        }
    }

    func powerModal() {
        if showLowPowerModeAlert {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.power.title", comment: "")
            alert.informativeText = NSLocalizedString("alert.power.subtitle", comment: "")
            alert.addButton(withTitle: NSLocalizedString("button.OK", comment: ""))
            alert.showsSuppressionButton = true
            alert.alertStyle = .critical

            if alert.runModal() == .alertFirstButtonReturn {
                showLowPowerModeAlert = alert.suppressionButton?.state == .off
            }
        }
    }
}

/// Fork-only: badges the Dock icon with the number of upstream `develop` commits newer than
/// the one this build is based on (`PlayCoverUpstreamBase`, stamped into Info.plist by build.sh).
/// macOS only draws the badge for apps granted badge permission, hence the authorization request.
enum UpstreamCommitBadge {
    static func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { _, _ in
            refresh()
        }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in refresh() }
    }

    static func refresh() {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "PlayCoverUpstreamBase") as? String,
              let url = URL(string:
                "https://api.github.com/repos/PlayCover/PlayCover/compare/\(base)...develop?per_page=1")
        else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let aheadBy = json["ahead_by"] as? Int
            else { return }
            if #available(macOS 13.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(aheadBy)
            } else {
                DispatchQueue.main.async {
                    NSApp.dockTile.badgeLabel = aheadBy > 0 ? String(aheadBy) : nil
                }
            }
        }.resume()
    }
}

@main
struct PlayCoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var updaterViewModel = UpdaterViewModel()
    var storeVM = StoreVM.shared

    @State var isSigningSetupShown = false

    var body: some Scene {
        WindowGroup {
            MainView(isSigningSetupShown: $isSigningSetupShown)
                .environmentObject(InstallVM.shared)
                .environmentObject(DownloadVM.shared)
                .environmentObject(AppsVM.shared)
                .environmentObject(storeVM)
                .environmentObject(AppIntegrity())
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                    SoundDeviceService.shared.prepareSoundDevice()
                    NotifyService.shared.allowNotify()
                }
        }
        .handlesExternalEvents(matching: ["{same path of URL?}"]) // create new window if doesn't exist
        .commands {
            SidebarCommands()
            PlayCoverMenuView(isSigningSetupShown: $isSigningSetupShown)
            PlayCoverHelpMenuView(updaterViewModel: updaterViewModel)
            PlayCoverViewMenuView()
        }

        Settings {
            PlayCoverSettingsView(updaterViewModel: updaterViewModel)
                .environmentObject(storeVM)
        }
    }
}
