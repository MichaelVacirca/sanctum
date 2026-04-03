import Foundation
import Metal
import MetalKit

final class AssetLibrary {
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    private var textures: [String: MTLTexture] = [:]

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    func loadAssets(from directory: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for item in contents {
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue {
                try loadAssets(from: item)
            } else if item.pathExtension == "png" || item.pathExtension == "exr" {
                let name = item.deletingPathExtension().lastPathComponent
                let texture = try loadTexture(from: item)
                textures[name] = texture
            }
        }
    }

    func loadTexture(from url: URL) throws -> MTLTexture {
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage([.shaderRead]).rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .generateMipmaps: true,
            .SRGB: false
        ]
        return try textureLoader.newTexture(URL: url, options: options)
    }

    func texture(named name: String) -> MTLTexture? {
        textures[name]
    }

    var textureNames: [String] { Array(textures.keys) }
    var count: Int { textures.count }

    @discardableResult
    func createSolidTexture(width: Int, height: Int, color: (UInt8, UInt8, UInt8, UInt8), name: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = color.2     // B
            pixels[i+1] = color.1   // G
            pixels[i+2] = color.0   // R
            pixels[i+3] = color.3   // A
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        textures[name] = texture
        return texture
    }
}
