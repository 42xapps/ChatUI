import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {

        var parent: DocumentPickerView

        init(parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            DispatchQueue.main.async {
                self.parent.dismiss()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            DispatchQueue.main.async {
                self.parent.dismiss()
            }
        }
    }
}
