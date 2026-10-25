//
//  WebWallpaperResponseTransformer.swift
//  MyWallpaperX
//

import Foundation

enum WebWallpaperResponseTransformer {
    static func transform(_ data: Data, fileURL: URL) -> Data {
        guard supportsTransformation(for: fileURL),
              let source = String(data: data, encoding: .utf8) else { return data }
        let transformed: String
        switch fileURL.pathExtension.lowercased() {
        case "html", "htm":
            transformed = WebWallpaperHTMLTransformer.transform(source)
        case "css":
            transformed = WebWallpaperCSSImportTransformer.transform(source)
        default:
            return data
        }
        guard transformed != source else { return data }
        return transformed.data(using: .utf8) ?? data
    }

    static func supportsTransformation(for fileURL: URL) -> Bool {
        ["html", "htm", "css"].contains(fileURL.pathExtension.lowercased())
    }
}
