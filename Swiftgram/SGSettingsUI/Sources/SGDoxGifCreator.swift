import Foundation
import UIKit
import Photos
import PhotosUI
import ImageIO
import AVFoundation
import MobileCoreServices
import UniformTypeIdentifiers
import Display
import AccountContext
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramPresentationData
import OverlayStatusController
import PresentationDataUtils
import UndoUI

public final class SGDoxGifCreator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public static let shared = SGDoxGifCreator()
    
    private weak var currentParentController: ViewController?
    private var currentContext: AccountContext?
    private var currentPeerId: PeerId?
    private var currentSendDirectly: ((Data) -> Void)?
    private var loadingController: ViewController?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    public static func presentGifCreator(
        from parentViewController: ViewController,
        context: AccountContext,
        peerId: PeerId?,
        sendGifDirectly: ((Data) -> Void)?
    ) {
        SGDoxGifCreator.shared.start(
            from: parentViewController,
            context: context,
            peerId: peerId,
            sendGifDirectly: sendGifDirectly
        )
    }
    
    private func start(
        from parentViewController: ViewController,
        context: AccountContext,
        peerId: PeerId?,
        sendGifDirectly: ((Data) -> Void)?
    ) {
        self.currentParentController = parentViewController
        self.currentContext = context
        self.currentPeerId = peerId
        self.currentSendDirectly = sendGifDirectly
        
        if #available(iOS 14, *) {
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 20
            configuration.filter = .any(of: [.images, .videos])
            configuration.preferredAssetRepresentationMode = .current
            
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            picker.modalPresentationStyle = .fullScreen
            
            parentViewController.view.window?.rootViewController?.present(picker, animated: true)
        } else {
            let picker = UIImagePickerController()
            picker.delegate = self
            picker.sourceType = .photoLibrary
            picker.mediaTypes = ["public.image", "public.movie"]
            parentViewController.view.window?.rootViewController?.present(picker, animated: true)
        }
    }
    
    // MARK: - PHPickerViewControllerDelegate
    
    @available(iOS 14, *)
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard !results.isEmpty else {
            return
        }
        
        self.showLoading(true)
        
        // If a video is selected, handle video conversion
        if let videoItem = results.first(where: { $0.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }) {
            videoItem.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                guard let self = self, let url = url, error == nil else {
                    DispatchQueue.main.async {
                        self?.showLoading(false)
                    }
                    return
                }
                
                let tempCopy = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("video_\(UUID().uuidString).\(url.pathExtension)")
                try? FileManager.default.copyItem(at: url, to: tempCopy)
                
                Self.convertVideoToGif(url: tempCopy, maxDuration: 6.0, fps: 12) { [weak self] gifData in
                    try? FileManager.default.removeItem(at: tempCopy)
                    DispatchQueue.main.async {
                        self?.showLoading(false)
                        if let gifData = gifData {
                            self?.handleGeneratedGif(gifData)
                        }
                    }
                }
            }
            return
        }
        
        // Multiple or single images: collect images in order
        let group = DispatchGroup()
        var imagesByIndex: [Int: UIImage] = [:]
        let lock = NSLock()
        
        for (index, result) in results.enumerated() {
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    if let image = image as? UIImage {
                        lock.lock()
                        imagesByIndex[index] = image
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self = self else { return }
            let sortedImages = imagesByIndex.keys.sorted().compactMap { imagesByIndex[$0] }
            guard !sortedImages.isEmpty else {
                DispatchQueue.main.async {
                    self.showLoading(false)
                }
                return
            }
            
            let frameDelay: Double = sortedImages.count > 1 ? 0.35 : 0.5
            let gifData = Self.convertImagesToGif(images: sortedImages, frameDelay: frameDelay, loopCount: 0)
            
            DispatchQueue.main.async {
                self.showLoading(false)
                if let gifData = gifData {
                    self.handleGeneratedGif(gifData)
                }
            }
        }
    }
    
    // MARK: - UIImagePickerControllerDelegate (Fallback)
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        self.showLoading(true)
        if let videoUrl = info[.mediaURL] as? URL {
            Self.convertVideoToGif(url: videoUrl, maxDuration: 6.0, fps: 12) { [weak self] gifData in
                DispatchQueue.main.async {
                    self?.showLoading(false)
                    if let gifData = gifData {
                        self?.handleGeneratedGif(gifData)
                    }
                }
            }
        } else if let image = info[.originalImage] as? UIImage {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let gifData = Self.convertImagesToGif(images: [image], frameDelay: 0.5, loopCount: 0)
                DispatchQueue.main.async {
                    self?.showLoading(false)
                    if let gifData = gifData {
                        self?.handleGeneratedGif(gifData)
                    }
                }
            }
        } else {
            self.showLoading(false)
        }
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
    // MARK: - Core GIF Encoding Engine
    
    public static func convertImagesToGif(images: [UIImage], frameDelay: Double = 0.25, loopCount: Int = 0) -> Data? {
        guard !images.isEmpty else { return nil }
        
        let fileData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(fileData as CFMutableData, kUTTypeGIF, images.count, nil) else {
            return nil
        }
        
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]
        
        let maxSide: CGFloat = 512.0
        for image in images {
            let scaleFactor = min(1.0, maxSide / max(image.size.width, image.size.height))
            let targetSize = CGSize(width: floor(image.size.width * scaleFactor), height: floor(image.size.height * scaleFactor))
            
            UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: targetSize))
            let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let cgImage = normalizedImage?.cgImage ?? image.cgImage {
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            }
        }
        
        if CGImageDestinationFinalize(destination) {
            return fileData as Data
        }
        return nil
    }
    
    public static func convertVideoToGif(url: URL, maxDuration: Double = 6.0, fps: Int = 12, completion: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: url)
            let durationSeconds = CMTimeGetSeconds(asset.duration)
            guard durationSeconds > 0 && !durationSeconds.isNaN else {
                completion(nil)
                return
            }
            
            let effectiveDuration = min(durationSeconds, maxDuration)
            let frameCount = max(2, Int(effectiveDuration * Double(fps)))
            let timeInterval = effectiveDuration / Double(frameCount)
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512.0, height: 512.0)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            
            var frames: [UIImage] = []
            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) * timeInterval, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    frames.append(UIImage(cgImage: cgImage))
                }
            }
            
            guard !frames.isEmpty else {
                completion(nil)
                return
            }
            
            let gifData = Self.convertImagesToGif(images: frames, frameDelay: 1.0 / Double(fps), loopCount: 0)
            completion(gifData)
        }
    }
    
    // MARK: - Handlers & UI
    
    private func showLoading(_ show: Bool) {
        if show {
            if self.loadingController == nil, let context = self.currentContext {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let status = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                self.loadingController = status
                self.currentParentController?.present(status, in: .window(.root))
            }
        } else {
            self.loadingController?.dismiss()
            self.loadingController = nil
        }
    }
    
    private func handleGeneratedGif(_ data: Data) {
        guard let parent = self.currentParentController, let context = self.currentContext else {
            return
        }
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let isRu = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
        
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        let sizeKb = data.count / 1024
        let titleString = isRu ? "GIF успешно создана (\(sizeKb) КБ)" : "GIF Created (\(sizeKb) KB)"
        items.append(ActionSheetTextItem(title: titleString))
        
        if let sendDirectly = self.currentSendDirectly {
            items.append(ActionSheetButtonItem(title: isRu ? "Отправить в чат" : "Send to Chat", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                sendDirectly(data)
            }))
        }
        
        items.append(ActionSheetButtonItem(title: isRu ? "Сохранить в фото / гифки" : "Save to Photos", color: .accent, action: { [weak actionSheet, weak parent] in
            actionSheet?.dismissAnimated()
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { success, _ in
                DispatchQueue.main.async {
                    if success {
                        parent?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: isRu ? "GIF сохранена в галерею" : "GIF saved to Photos", timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .window(.root))
                    }
                }
            })
        }))
        
        items.append(ActionSheetButtonItem(title: isRu ? "Поделиться" : "Share", color: .accent, action: { [weak actionSheet, weak parent] in
            actionSheet?.dismissAnimated()
            let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("doxgram_\(UUID().uuidString).gif")
            try? data.write(to: tempUrl)
            let activity = UIActivityViewController(activityItems: [tempUrl], applicationActivities: nil)
            parent?.view.window?.rootViewController?.present(activity, animated: true)
        }))
        
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        
        parent.present(actionSheet, in: .window(.root))
    }
}
