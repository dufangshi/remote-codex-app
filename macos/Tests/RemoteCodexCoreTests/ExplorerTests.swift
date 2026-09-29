import XCTest
@testable import RemoteCodexCore

final class ExplorerTests: XCTestCase {
    func testBreadcrumbsStayWithinWorkspace() throws {
        let crumbs = try WorkspacePath.breadcrumbs("apps/web/app/(platform)/home", rootLabel: "ElAgente")
        XCTAssertEqual(crumbs.map(\.label), ["ElAgente", "apps", "web", "app", "(platform)", "home"])
        XCTAssertEqual(crumbs.map(\.path), [".", "apps", "apps/web", "apps/web/app", "apps/web/app/(platform)", "apps/web/app/(platform)/home"])
        XCTAssertEqual(try WorkspacePath.parent("."), ".")
        XCTAssertEqual(try WorkspacePath.parent("apps"), ".")
        XCTAssertEqual(try WorkspacePath.normalize("apps/../docs/./中文 文件"), "docs/中文 文件")
        for path in ["../", "apps/../../secret", "/etc", "C:\\Users", "\\\\server\\share", "bad\0path"] {
            XCTAssertThrowsError(try WorkspacePath.breadcrumbs(path, rootLabel: "Root"), path)
        }
    }
    func testTSXHighlightsLexicallyWithoutChangingUnicodeOrStrings() {
        let source = "// const comment = 123\n'use client';\nimport { useState } from 'react';\nconst 标题 = \"🙂 return 42\";\nconst count = 42;\nexport function Page() { return <Panel title='hello' />; }"
        let tokens = CodeSyntax.tokens(source, path: "page.tsx")
        func colored(_ value: String, _ kind: CodeSyntax.Kind) -> Bool {
            tokens.contains { $0.kind == kind && (source as NSString).substring(with: $0.range) == value }
        }
        XCTAssertTrue(colored("// const comment = 123", .comment))
        XCTAssertTrue(colored("'use client'", .string))
        XCTAssertTrue(colored("import", .keyword))
        XCTAssertTrue(colored("\"🙂 return 42\"", .string))
        XCTAssertTrue(colored("42", .number))
        XCTAssertTrue(colored("Panel", .type))
        for pair in zip(tokens, tokens.dropFirst()) { XCTAssertLessThanOrEqual(NSMaxRange(pair.0.range), pair.1.range.location) }
        XCTAssertEqual(tokens.filter { $0.kind == .number }.count, 1, "Numbers inside strings/comments must stay part of that token")
    }
    func testLanguageSpecificCommentsAndUnknownFileFallback() {
        for (path, source, comment) in [("a.py", "value = 'hi' # return 2", "# return 2"), ("a.sql", "SELECT 1 -- comment", "-- comment"), ("a.html", "<Panel><!-- comment --></Panel>", "<!-- comment -->")] {
            XCTAssertTrue(CodeSyntax.tokens(source, path: path).contains { $0.kind == .comment && (source as NSString).substring(with: $0.range) == comment })
        }
        XCTAssertTrue(CodeSyntax.tokens("const plain = 42", path: "notes.txt").isEmpty)
        XCTAssertTrue(CodeSyntax.tokens(String(repeating: "x", count: CodeSyntax.maximumUTF16Length + 1), path: "large.ts").isEmpty)
    }
    func testDownloadFilenameAppendsZipOnlyForDirectories() {
        XCTAssertEqual(WorkspaceAPI.downloadFilename(for: "notes.txt", isDirectory: false), "notes.txt")
        XCTAssertEqual(WorkspaceAPI.downloadFilename(for: "apps/web", isDirectory: true), "web.zip")
        XCTAssertEqual(WorkspaceAPI.downloadFilename(for: ".", isDirectory: true), "workspace.zip")
    }
}
