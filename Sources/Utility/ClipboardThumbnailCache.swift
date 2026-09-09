import AppKit
import Foundation

/// 剪切板图片缩略图异步生成与内存缓存管理器
final class ClipboardThumbnailCache: @unchecked Sendable {
    static let shared = ClipboardThumbnailCache()
    
    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.aix.clipboard.thumbnail", qos: .userInitiated)
    
    private init() {
        // 限制内存缓存数量和占用大小，防止内存溢出
        cache.countLimit = 150
        cache.totalCostLimit = 60 * 1024 * 1024 // 60MB
    }
    
    /// 异步获取缩略图，优先命中内存缓存，未命中则在后台队列利用 CGImageSource 极速解码缩略图并在主线程回调
    func getThumbnail(for item: ClipboardItem, maxPixelSize: CGFloat = 320, completion: @escaping @Sendable @MainActor (NSImage?) -> Void) {
        guard item.type == .image else {
            Task { @MainActor in completion(nil) }
            return
        }
        
        let idString = item.id.uuidString
        let key = idString as NSString
        if let cached = cache.object(forKey: key) {
            Task { @MainActor in completion(cached) }
            return
        }
        
        let data = item.data
        guard !data.isEmpty else {
            Task { @MainActor in completion(nil) }
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 使用 CoreGraphics ImageSource 进行硬件/低内存按需采样，无需在内存中完整解压超大图
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
                // 如果 CGImageSource 无法识别，尝试回退常规 NSImage 解码
                self.fallbackDecode(data: data, idString: idString, completion: completion)
                return
            }
            
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
                let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / 2.0, height: CGFloat(cgImage.height) / 2.0))
                let cost = cgImage.bytesPerRow * cgImage.height
                self.cache.setObject(thumbnail, forKey: idString as NSString, cost: cost)
                
                DispatchQueue.main.async {
                    completion(thumbnail)
                }
            } else {
                self.fallbackDecode(data: data, idString: idString, completion: completion)
            }
        }
    }
    
    private func fallbackDecode(data: Data, idString: String, completion: @escaping @Sendable @MainActor (NSImage?) -> Void) {
        if let fullImage = NSImage(data: data) {
            let cost = Int(fullImage.size.width * fullImage.size.height * 4)
            self.cache.setObject(fullImage, forKey: idString as NSString, cost: cost)
            DispatchQueue.main.async { completion(fullImage) }
        } else {
            DispatchQueue.main.async { completion(nil) }
        }
    }
    
    /// 清除内存缓存
    func clearCache() {
        cache.removeAllObjects()
    }
}
