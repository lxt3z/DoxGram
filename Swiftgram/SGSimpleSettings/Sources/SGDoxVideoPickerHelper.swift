import Foundation
import UIKit
import MobileCoreServices

public final class SGDoxVideoPickerHelper: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
    public static let shared = SGDoxVideoPickerHelper()
    
    private var onPicked: ((URL?) -> Void)?
    
    private override init() {
        super.init()
    }
    
    public func pickVideoFromGallery(presentation: (UIViewController) -> Void, completion: @escaping (URL?) -> Void) {
        self.onPicked = completion
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeHigh
        picker.allowsEditing = false
        if UIDevice.current.userInterfaceIdiom == .pad {
            picker.modalPresentationStyle = .formSheet
        }
        presentation(picker)
    }

    public func pickVideoFromGallery(from presenter: UIViewController, completion: @escaping (URL?) -> Void) {
        self.pickVideoFromGallery(presentation: { presenter.present($0, animated: true) }, completion: completion)
    }
    
    public func pickVideoFromFiles(presentation: (UIViewController) -> Void, completion: @escaping (URL?) -> Void) {
        self.onPicked = completion
        let types = ["public.movie", "public.video", "com.apple.quicktime-movie", "public.mpeg-4"]
        let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        if UIDevice.current.userInterfaceIdiom == .pad {
            picker.modalPresentationStyle = .formSheet
        }
        presentation(picker)
    }

    public func pickVideoFromFiles(from presenter: UIViewController, completion: @escaping (URL?) -> Void) {
        self.pickVideoFromFiles(presentation: { presenter.present($0, animated: true) }, completion: completion)
    }
    
    // MARK: - UIImagePickerControllerDelegate
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        let mediaUrl = info[.mediaURL] as? URL
        let cb = self.onPicked
        self.onPicked = nil
        cb?(mediaUrl)
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        let cb = self.onPicked
        self.onPicked = nil
        cb?(nil)
    }
    
    // MARK: - UIDocumentPickerDelegate
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let selectedUrl = urls.first
        let cb = self.onPicked
        self.onPicked = nil
        cb?(selectedUrl)
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let cb = self.onPicked
        self.onPicked = nil
        cb?(nil)
    }
}
