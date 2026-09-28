import Foundation
import CryptoKit

public struct ImageAttachment {
    public let data: Data
    public let mimeType: String
    public init(data: Data, mimeType: String) { self.data = data; self.mimeType = mimeType }
}

public enum PromptBody {
    public static func build(text: String, requestID: String, images: [ImageAttachment]) throws -> (body: Data, contentType: String) {
        guard !images.isEmpty else {
            return (try JSONSerialization.data(withJSONObject: ["prompt": text, "clientRequestId": requestID]), "application/json")
        }
        guard images.count <= 8, images.reduce(0, { $0 + $1.data.count }) <= 24 * 1024 * 1024 else {
            throw APIError("Image attachment limit exceeded.")
        }
        let boundary = "RemoteCodex-" + UUID().uuidString
        var body = Data(), prompt = text, manifest: [[String: String]] = []
        func append(_ text: String) { body.append(Data(text.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        for (index, image) in images.enumerated() {
            let ext: String
            switch image.mimeType {
            case "image/png": ext = "png"
            case "image/jpeg": ext = "jpg"
            case "image/gif": ext = "gif"
            case "image/webp": ext = "webp"
            default: throw APIError("Unsupported image type.")
            }
            guard image.data.count <= 10 * 1024 * 1024 else { throw APIError("Each image must be 10 MB or smaller.") }
            let identity = SHA256.hash(data: Data("\(requestID):\(index)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
            let name = "image-\(identity).\(ext)"
            let placeholder = "[PHOTO \(name)]"
            prompt += "\n" + placeholder
            manifest.append(["kind": "photo", "originalName": name, "placeholder": placeholder])
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(name)\"\r\nContent-Type: \(image.mimeType)\r\n\r\n")
            body.append(image.data); append("\r\n")
        }
        field("prompt", prompt)
        field("clientRequestId", requestID)
        field("attachmentManifest", String(decoding: try JSONSerialization.data(withJSONObject: manifest), as: UTF8.self))
        append("--\(boundary)--\r\n")
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
}

public struct MessageSegment: Identifiable {
    public let id: Int
    public let text: String?
    public let photoPath: String?
    public static func parse(_ text: String) -> [MessageSegment] {
        guard let expression = try? NSRegularExpression(pattern: #"\[PHOTO\s+([^\]]+)\]"#) else { return [] }
        let input = text as NSString
        var result: [MessageSegment] = [], cursor = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: input.length)) {
            if match.range.location > cursor {
                result.append(.init(id: cursor, text: input.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), photoPath: nil))
            }
            result.append(.init(id: match.range.location, text: nil, photoPath: input.substring(with: match.range(at: 1))))
            cursor = match.range.location + match.range.length
        }
        if cursor < input.length { result.append(.init(id: cursor, text: input.substring(from: cursor), photoPath: nil)) }
        return result
    }
}
