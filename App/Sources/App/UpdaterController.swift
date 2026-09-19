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
    private var cancellable: AnyCancellable?
    #endif

    init() {
        #if canImport(Sparkle)
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        canCheckForUpdates = controller.updater.canCheckForUpdates
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
        statusDescription = Self.describe(lastCheck: controller.updater.lastUpdateCheckDate)
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
            controller.updater.automaticallyChecksForUpdates = newValue
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
            controller.updater.automaticallyDownloadsUpdates = newValue
            #endif
        }
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        controller.checkForUpdates(nil)
        statusDescription = Self.describe(lastCheck: Date())
        #else
        NSSound.beep()
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
