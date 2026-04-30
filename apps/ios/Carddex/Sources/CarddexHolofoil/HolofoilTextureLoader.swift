import Foundation

#if canImport(Metal) && canImport(MetalKit) && canImport(UIKit)
import Metal
import MetalKit
import UIKit

/// Loads textures by `HolofoilCatalogCard.image`-style path. The web app
/// references `/cards/<id>/<file>`; on iOS we either ship those assets in
/// the main bundle (`Resources/cards/<id>/...`) or read them from the
/// app's documents dir after download.
public struct HolofoilTextureLoader {
    public enum Source {
        /// Look for assets under the main bundle's `cards/` directory.
        case mainBundle
        /// Look for assets in `Application Support/cards/<id>/`.
        case applicationSupport
    }

    public var source: Source
    public init(source: Source = .mainBundle) { self.source = source }

    public func load(_ path: String, on device: MTLDevice) throws -> MTLTexture {
        let url = try resolveURL(path)
        let loader = MTKTextureLoader(device: device)
        return try loader.newTexture(URL: url, options: [
            .SRGB: false,
            .generateMipmaps: true,
        ])
    }

    private func resolveURL(_ path: String) throws -> URL {
        // Strip a leading "/cards/" so callers can use the same paths as the web app.
        let trimmed = path.hasPrefix("/cards/") ? String(path.dropFirst("/cards/".count)) : path
        switch source {
        case .mainBundle:
            guard let url = Bundle.main.url(forResource: trimmed, withExtension: nil, subdirectory: "cards") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return url
        case .applicationSupport:
            let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
            return base.appendingPathComponent("cards").appendingPathComponent(trimmed)
        }
    }
}
#endif
