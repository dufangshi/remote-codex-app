import SwiftUI
import RemoteCodexCore

struct FilesView: View {
    @ObservedObject var files: WorkspaceFiles
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(files.label, systemImage: "folder").font(.headline)
                Spacer()
                Button { files.showingCreate = true } label: { Label("New File", systemImage: "doc.badge.plus") }
                Button { Task { await files.browse() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh directory")
            }.padding(16)
            if let error = files.error { InlineError(message: error) { files.error = nil } }
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            let parent = (files.directory as NSString).deletingLastPathComponent
                            Task { await files.browse(parent.isEmpty ? "." : parent) }
                        } label: { Image(systemName: "arrow.up") }.disabled(files.directory == ".")
                        Text(files.directory).font(.caption.monospaced()).lineLimit(1).truncationMode(.head)
                        Spacer()
                        if files.loading { ProgressView().controlSize(.small) }
                    }.padding(10)
                    TextField("Filter files", text: $files.filter).textFieldStyle(.roundedBorder).padding(.horizontal, 10).padding(.bottom, 8)
                    List {
                        ForEach(files.nodes.filter { files.filter.isEmpty || $0.name.localizedCaseInsensitiveContains(files.filter) }) { node in
                            Button { Task { await files.open(node) } } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.text").foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
                                    Text(node.name).lineLimit(1)
                                    Spacer()
                                    if node.isDirectory { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                                }.padding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("file-" + node.name)
                        }
                    }.listStyle(.inset)
                }.frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                VStack(spacing: 0) {
                    if !files.documents.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 4) {
                                ForEach(files.documents) { document in FileTab(document: document, files: files) }
                            }.padding(8)
                        }.scrollIndicators(.hidden)
                        Divider()
                    }
                    if let document = files.document {
                        FileEditor(document: document, files: files).id(document.id)
                    } else {
                        ContentUnavailableView("Workspace files", systemImage: "doc.text.magnifyingglass", description: Text("Browse folders and open a file. Text files open in the native editor; changes stay in their tabs until saved."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if files.nodes.isEmpty { await files.browse() } }
        .sheet(isPresented: $files.showingCreate) {
            VStack(alignment: .leading, spacing: 18) {
                Text("New workspace file").font(.title2.bold())
                TextField("Relative path (existing parent folder)", text: $files.newPath).textFieldStyle(.roundedBorder)
                if let error = files.error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("Cancel") { files.showingCreate = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create") { Task { await files.create() } }.disabled(files.newPath.isEmpty || files.loading).keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 420)
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: Binding(get: { files.closing != nil }, set: { if !$0 { files.closing = nil } })) {
            Button("Discard Changes", role: .destructive) { if let doc = files.closing { files.close(doc, discard: true) } }
            Button("Cancel", role: .cancel) { files.closing = nil }
        } message: { Text(files.closing?.id ?? "") }
    }
}

private struct FileTab: View {
    @ObservedObject var document: FileDocument
    @ObservedObject var files: WorkspaceFiles
    var body: some View {
        HStack(spacing: 8) {
            Button { files.selected = document.id } label: {
                HStack(spacing: 5) {
                    if document.dirty { Circle().fill(.orange).frame(width: 6, height: 6) }
                    Text((document.id as NSString).lastPathComponent).lineLimit(1)
                }
            }.buttonStyle(.plain)
            Button { files.close(document) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain)
        }.padding(9).background(files.selected == document.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .help(document.id)
    }
}

private struct FileEditor: View {
    @ObservedObject var document: FileDocument
    @ObservedObject var files: WorkspaceFiles
    @State private var confirmReload = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.id).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Export…") { files.export(document) }
                if document.editable {
                    Button("Reload") { if document.dirty { confirmReload = true } else { Task { await files.reload(document) } } }
                    Button(document.saving ? "Saving…" : "Save") { Task { await files.save(document) } }
                        .keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!document.dirty || document.saving)
                        .accessibilityIdentifier("saveFile")
                }
            }.padding(12)
            Divider()
            if document.editable {
                NativeComposer(text: $document.text, code: true, identifier: "fileEditor") { Task { await files.save(document) } }
                    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text(document.dirty ? "Unsaved changes" : "Saved on device")
                    Spacer(); Text("UTF-8 · \(document.text.utf8.count) bytes")
                }.font(.caption).foregroundStyle(.secondary).padding(10)
            } else if let image = document.image {
                ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 1200, maxHeight: 1000).padding(24) }
            } else {
                ContentUnavailableView("Read-only file", systemImage: "doc", description: Text("Binary, non-UTF-8 and text files over 4 MB cannot be safely edited here. Export the original bytes, or use the full workspace."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(nsColor: .textBackgroundColor))
            .confirmationDialog("Replace your draft with the remote file?", isPresented: $confirmReload) {
                Button("Discard Draft and Reload", role: .destructive) { Task { await files.reload(document) } }
                Button("Cancel", role: .cancel) { }
            }
    }
}
