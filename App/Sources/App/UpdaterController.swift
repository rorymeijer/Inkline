import AppKit
import Combine

#if canImport(Sparkle)
import Sparkle
#endif

/// Wraps Sparkle so the rest of the app never imports it.
///
/// Sparkle is optional at compile time: a build without the package still
/// compiles and simply reports that updates are unavailable, which keeps
/// `swift build` of the app sources possible without network access. The
/// feed URL and public key live in `Info.plist` (`SUFeedURL`, `SUPublicEDKey`);
/// see the README for how to generate them.
@MainActor
final class UpdaterController: ObservableObject {

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var statusDescription = ""

    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController
    private let isUpdaterConfigured: Bool
    private var cancellable: AnyCancellable?
    #endif

    init() {
        #if canImport(Sparkle)
        isUpdaterConfigured = Self.shouldStartUpdater
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        if isUpdaterConfigured {
            controller.startUpdater()
            canCheckForUpdates = controller.updater.canCheckForUpdates
            cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] value in self?.canCheckForUpdates = value }
            statusDescription = Self.describe(lastCheck: controller.updater.lastUpdateCheckDate)
        } else {
            statusDescription = NSLocalizedString("Automatische updates zijn niet geconfigureerd.",
                                                  comment: "Updatestatus bij ontbrekende Sparkle-sleutel")
        }
        #else
        statusDescription = NSLocalizedString("Deze build bevat geen automatische updates.",
                                              comment: "Updatestatus zonder Sparkle")
        #endif
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            #if canImport(Sparkle)
            controller.updater.automaticallyChecksForUpdates
            #else
            false
            #endif
        }
        set {
            #if canImport(Sparkle)
            if isUpdaterConfigured {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
            #endif
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get {
            #if canImport(Sparkle)
            controller.updater.automaticallyDownloadsUpdates
            #else
            false
            #endif
        }
        set {
            #if canImport(Sparkle)
            if isUpdaterConfigured {
                controller.updater.automaticallyDownloadsUpdates = newValue
            }
            #endif
        }
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        guard isUpdaterConfigured else {
            NSSound.beep()
            return
        }
        controller.checkForUpdates(nil)
        statusDescription = Self.describe(lastCheck: Date())
        #else
        NSSound.beep()
        #endif
    }

    private static var shouldStartUpdater: Bool {
        #if DEBUG
        // Development builds should not poll the production appcast. It may
        // not exist until the first release has been published.
        return false
        #else
        guard let encodedKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let keyData = Data(base64Encoded: encodedKey) else {
            return false
        }
        return keyData.count == 32
        #endif
    }

    private static func describe(lastCheck: Date?) -> String {
        guard let lastCheck else {
            return NSLocalizedString("Nog niet gecontroleerd.", comment: "Updatestatus")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return String(format: NSLocalizedString("Laatst gecontroleerd: %@", comment: "Updatestatus"),
                      formatter.string(from: lastCheck))
    }
}
