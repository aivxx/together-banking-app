import SwiftUI
import CloudKit
import UIKit

@main struct TogetherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()
    @AppStorage("appearanceTheme") private var theme: AppTheme = .charcoal
    @Environment(\.scenePhase) var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environment(\.appTheme, theme).preferredColorScheme(.dark)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--verify-cloudkit") || ProcessInfo.processInfo.arguments.contains("--verify-family-sharing") {
                        await store.verifyCloudSetup()
                    }
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for: .shareAccepted)) { note in
                    if let metadata = note.object as? CKShare.Metadata { Task { await store.accept(metadata) } }
                }
                .onChange(of: phase) { _, value in
                    if value != .active && store.lockEnabled { store.unlocked = false }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--verify-cloudkit") || ProcessInfo.processInfo.arguments.contains("--verify-family-sharing") { return }
                    #endif
                    if value == .active && store.unlocked { Task { await store.sync() } }
                }
        }
    }
}
extension Notification.Name { static let shareAccepted = Notification.Name("shareAccepted") }
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareSceneDelegate.self
        return configuration
    }
}
class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: .shareAccepted, object: metadata)
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NotificationCenter.default.post(name: .shareAccepted, object: metadata) }
        }
    }
}
struct SharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onError: (String) -> Void
        init(onError: @escaping (String) -> Void) { self.onError = onError }
        func itemTitle(for csc: UICloudSharingController) -> String? { "Our household" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { onError(error.localizedDescription) }
    }
}
