import SwiftUI
import RemoteCodexCore

struct FilesView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var files: WorkspaceFiles
    private var crumbs: [WorkspacePath.Crumb] { (try? WorkspacePath.breadcrumbs(files.directory, rootLabel: files.label)) ?? [] }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { Task { await files.browse(try? WorkspacePath.parent(files.directory)) } } label: { Image(systemName: "arrow.up") }
                    .disabled(files.directory == ".").help("Parent folder").accessibilityLabel("Parent folder")
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(crumbs) { crumb in
                                if crumb.path != "." { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted) }
                                Button { Task { await files.browse(crumb.path) } } label: {
                                    HStack(spacing: 7) {
                                        if crumb.path == "." { Image(systemName: "folder") }
                                        Text(crumb.label).font(crumb.path == "." ? .headline : .system(size: 13, design: .monospaced)).fixedSize()
                                    }
                                }.buttonStyle(.plain).help(crumb.path == "." ? "Workspace root" : crumb.path)
                                    .accessibilityLabel("Browse folder " + (crumb.path == "." ? files.label + " (workspace root)" : crumb.path)).id(crumb.id)
                            }
                        }.padding(.vertical, 6)
                    }.scrollIndicators(.never)
                        .onChange(of: files.directory) { _, path in proxy.scrollTo(path, anchor: .trailing) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { state.contentMode = "chat" } label: { Label("Back to chat", systemImage: "bubble.left") }
                    .help("Return to conversation; keep file tabs and unsaved edits").accessibilityIdentifier("backToChat")
                Button { files.showingCreate = true } label: { Label("New File", systemImage: "doc.badge.plus") }
                Button { Task { await files.browse() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh directory")
            }.padding(16)
            if let error = files.error { InlineError(message: error) { files.error = nil } }
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        TextField("Filter files", text: $files.filter).textFieldStyle(.roundedBorder)
                        if files.loading { ProgressView().controlSize(.small) }
                    }.padding(10)
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
                                .contextMenu {
                                    if !node.isDirectory { Button("Download…") { Task { await files.download(node.path) } } }
                                    Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(node.path, forType: .string) }
                                }
                        }
                    }.listStyle(.inset).scrollContentBackground(.hidden).background(Palette.chrome)
                }.frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                VStack(spacing: 0) {
                    if !files.documents.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 4) {
                                ForEach(files.documents) { document in FileTab(document: document, files: files) }
                            }.padding(8)
                        }.scrollIndicators(.never)
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
        .buttonStyle(WorkbenchButton())
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
    var textSize = TextSizePreference()
    @ObservedObject var document: FileDocument
    @ObservedObject var files: WorkspaceFiles
    @State private var confirmReload = false
    @State private var preview = true
    private var markdown: Bool { ["md", "markdown", "mdown"].contains((document.id as NSString).pathExtension.lowercased()) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.id).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                if markdown { Button(preview ? "Edit Markdown" : "Preview") { preview.toggle() } }
                Button("Download…") { Task { await files.download(document.id) } }
                if document.dirty { Button("Save draft as…") { files.export(document) } }
                if document.editable {
                    Button("Reload") { if document.dirty { confirmReload = true } else { Task { await files.reload(document) } } }
                    Button(document.saving ? "Saving…" : "Save") { Task { await files.save(document) } }
                        .keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!document.dirty || document.saving)
                        .accessibilityIdentifier("saveFile")
                }
            }.padding(12)
            Divider()
            if document.editable {
                if markdown && preview {
                    ScrollView { MarkdownContent(text: document.text, document: document.id).padding(28) }.scrollIndicators(.never)
                } else {
                    CodeEditor(text: $document.text, path: document.id, fontSize: textSize.points(13)) { Task { await files.save(document) } }
                        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Text(document.dirty ? "Unsaved changes" : "Saved on device")
                    Spacer()
                    Text(document.text.utf16.count > CodeSyntax.maximumUTF16Length ? "Plain text (large file)" : (CodeSyntax.language(document.id) ?? "Plain text"))
                    Text("UTF-8 · \(document.text.utf8.count) bytes")
                }.font(.caption).foregroundStyle(.secondary).padding(10)
            } else if let image = document.image {
                ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 1200, maxHeight: 1000).padding(24) }
            } else {
                ContentUnavailableView("Read-only file", systemImage: "doc", description: Text("Binary, non-UTF-8 and text files over 4 MB cannot be safely edited here. Export the original bytes, or use the full workspace."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Palette.panel).buttonStyle(WorkbenchButton())
            .confirmationDialog("Replace your draft with the remote file?", isPresented: $confirmReload) {
                Button("Discard Draft and Reload", role: .destructive) { Task { await files.reload(document) } }
                Button("Cancel", role: .cancel) { }
            }
    }
}
