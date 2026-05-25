import Foundation
@preconcurrency import Sparkle

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var automaticallyDownloadsUpdates: Bool
    @Published private(set) var canUseUpdates: Bool

    private let updaterController: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    private init() {
        let canUseUpdates = Self.canUseUpdatesFromCurrentLocation()
        self.canUseUpdates = canUseUpdates

        updaterController = SPUStandardUpdaterController(
            startingUpdater: canUseUpdates,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let updater = updaterController.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates

        if canUseUpdates {
            canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in
                    self?.canCheckForUpdates = updater.canCheckForUpdates
                }
            }
        } else {
            canCheckForUpdates = false
        }
    }

    func checkForUpdates() {
        guard canUseUpdates else { return }
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        guard canUseUpdates else { return }
        updaterController.updater.automaticallyChecksForUpdates = isEnabled
        automaticallyChecksForUpdates = isEnabled
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        guard canUseUpdates else { return }
        updaterController.updater.automaticallyDownloadsUpdates = isEnabled
        automaticallyDownloadsUpdates = isEnabled
    }

    private static func canUseUpdatesFromCurrentLocation(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        let standardizedPath = bundleURL.standardizedFileURL.path
        let applicationsPath = URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL.path + "/"
        let userApplicationsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path + "/"

        guard standardizedPath.hasPrefix(applicationsPath) || standardizedPath.hasPrefix(userApplicationsPath) else {
            return false
        }

        let resourceValues = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return resourceValues?.volumeIsReadOnly != true
    }
}
