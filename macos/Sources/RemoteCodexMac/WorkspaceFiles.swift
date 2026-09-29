import AppKit
import SwiftUI
import ImageIO
import RemoteCodexCore

@MainActor
final class FileDocument: ObservableObject, Identifiable {
    let id: String
    @Published var text: String
    @Published var original: Data
    let editable: Bool
    let image: NSImage?
    @Published var saving = false
    var dirty: Bool { editable && Data(text.utf8) != original }
    init(path: String, bytes: Data) {
        id = path; original = bytes
        if bytes.count <= 4 * 1024 * 1024, !bytes.contains(0), let value = String(data: bytes, encoding: .utf8) {
            text = value; editable = true; image = nil
        } else {
            text = ""; editable = false
            if let source = CGImageSourceCreateWithData(bytes as CFData, nil),
               let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                image = NSImage(cgImage: thumb, size: .zero)
            } else { image = nil }
        }
    }
}

@MainActor
final class WorkspaceFiles: ObservableObject {
    let api: WorkspaceAPI
    let label: String
    @Published var nodes: [FileNode] = []
    @Published var directory = "."
    @Published var documents: [FileDocument] = []
    @Published var selected: String?
    @Published var loading = false
    @Published var error: String?
    @Published var filter = ""
    @Published var newPath = ""
    @Published var showingCreate = false
    @Published var closing: FileDocument?
    private var revision = UUID()
    var document: FileDocument? { documents.first { $0.id == selected } }
    var hasUnsavedChanges: Bool { documents.contains { $0.dirty } }
    init(api: WorkspaceAPI, label: String) { self.api = api; self.label = label }
    func browse(_ path: String? = nil) async {
        let request = UUID(); revision = request
        loading = true; error = nil
        do {
            let target = try WorkspacePath.normalize(path ?? directory)
            let root = try await api.tree(target)
            guard revision == request, !Task.isCancelled else { return }
            directory = target; nodes = root.children ?? []; loading = false
        } catch {
            guard revision == request else { return }
            loading = false
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
    func open(_ node: FileNode) async {
        if node.isDirectory { await browse(node.path); return }
        await openPath(node.path)
    }
    func openPath(_ path: String) async {
        if documents.contains(where: { $0.id == path }) { selected = path; return }
        loading = true; error = nil; defer { loading = false }
        do {
            let data = try await api.read(path)
            guard !Task.isCancelled else { return }
            if !documents.contains(where: { $0.id == path }) { documents.append(FileDocument(path: path, bytes: data)) }
            selected = path
            let parent = (path as NSString).deletingLastPathComponent
            await browse(parent.isEmpty ? "." : parent)
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func save(_ doc: FileDocument) async {
        guard doc.dirty, !doc.saving else { return }
        let text = doc.text
        doc.saving = true; error = nil; defer { doc.saving = false }
        do { doc.original = try await api.save(doc.id, content: text, original: doc.original) }
        catch { self.error = error.localizedDescription }
    }
    func reload(_ doc: FileDocument) async {
        do {
            let bytes = try await api.read(doc.id)
            guard let text = String(data: bytes, encoding: .utf8), !bytes.contains(0), bytes.count <= 4 * 1024 * 1024 else { throw APIError("The remote file is no longer an editable UTF-8 text file.") }
            doc.text = text; doc.original = bytes; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func close(_ doc: FileDocument, discard: Bool = false) {
        if doc.dirty && !discard { closing = doc; return }
        documents.removeAll { $0.id == doc.id }
        if selected == doc.id { selected = documents.last?.id }
        closing = nil
    }
    func create() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let target = newPath
            try await api.create(target)
            let bytes = try await api.read(target)
            documents.append(FileDocument(path: target, bytes: bytes)); selected = target
            newPath = ""; showingCreate = false; await browse()
        } catch { self.error = error.localizedDescription }
    }
    func export(_ doc: FileDocument) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = (doc.id as NSString).lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try (doc.editable ? Data(doc.text.utf8) : doc.original).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func download(_ path: String, isDirectory: Bool = false) async {
        let panel = NSSavePanel(); panel.nameFieldStringValue = WorkspaceAPI.downloadFilename(for: path, isDirectory: isDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let bytes = try await api.download(path); try bytes.write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}
