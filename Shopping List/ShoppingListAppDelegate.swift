import CloudKit
import UIKit

final class ShoppingListAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = ShoppingListSceneDelegate.self
        return configuration
    }
}

final class ShoppingListSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        accept(cloudKitShareMetadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task {
            do {
                let share: CKShare
                if metadata.participantStatus == .pending {
                    let container = CKContainer(identifier: metadata.containerIdentifier)
                    share = try await container.accept(metadata)
                } else {
                    share = metadata.share
                }
                await MainActor.run {
                    ShoppingListShareManager.storeAcceptedShare(share)
                }
            } catch {
                print("Could not accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}
