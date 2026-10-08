import CloudKit
import SwiftUI
import UIKit

struct ShoppingListCloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let itemProvider = NSItemProvider()
        let options = CKAllowedSharingOptions(
            allowedParticipantPermissionOptions: .readWrite,
            allowedParticipantAccessOptions: .specifiedRecipientsOnly
        )
        itemProvider.registerCKShare(share, container: container, allowedSharingOptions: options)
        return UIActivityViewController(activityItems: [itemProvider], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
