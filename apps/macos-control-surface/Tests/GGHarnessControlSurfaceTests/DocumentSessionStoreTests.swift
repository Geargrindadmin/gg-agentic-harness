import Foundation
import Testing
@testable import GGHarnessControlSurface

struct DocumentSessionStoreTests {
    @MainActor
    @Test
    func sessionTracksDirtyStateAndPersistsSaveRevertCycle() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("main.swift")
        try "print(\"hello\")\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let sessionStore = DocumentSessionStore()
        let session = sessionStore.session(
            path: fileURL.path,
            sourceLabel: "Workspace",
            workspaceRootPath: rootURL.path,
            selectedRunRootPath: nil
        )

        await session.load()

        #expect(session.content == "print(\"hello\")\n")
        #expect(session.isDirty == false)
        #expect(session.isEditable == true)

        session.replaceContent("print(\"updated\")\n")

        #expect(session.isDirty == true)
        #expect(session.content == "print(\"updated\")\n")

        try await session.save()

        #expect(session.isDirty == false)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "print(\"updated\")\n")

        session.replaceContent("print(\"draft\")\n")
        #expect(session.isDirty == true)

        await session.revert()

        #expect(session.isDirty == false)
        #expect(session.content == "print(\"updated\")\n")
    }

    @MainActor
    @Test
    func cachedSessionRetainsUnsavedBufferAcrossLookups() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-session-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("Task.md")
        try "# Task\n\nHello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let sessionStore = DocumentSessionStore()
        let first = sessionStore.session(
            path: fileURL.path,
            sourceLabel: "Workspace",
            workspaceRootPath: rootURL.path,
            selectedRunRootPath: nil
        )
        await first.load()
        first.replaceContent("# Task\n\nUnsaved\n")

        let second = sessionStore.session(
            path: fileURL.path,
            sourceLabel: "Workspace",
            workspaceRootPath: rootURL.path,
            selectedRunRootPath: nil
        )

        #expect(first === second)
        #expect(second.isDirty == true)
        #expect(second.content.contains("Unsaved"))
    }

    @MainActor
    @Test
    func sessionStagesPatchPreviewAndAppliesIntoDraft() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-session-patch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("main.swift")
        try "print(\"hello\")\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let patch = """
        --- a/main.swift
        +++ b/main.swift
        @@ -1 +1 @@
        -print("hello")
        +print("patched")
        """

        let sessionStore = DocumentSessionStore()
        let session = sessionStore.session(
            path: fileURL.path,
            sourceLabel: "Workspace",
            workspaceRootPath: rootURL.path,
            selectedRunRootPath: nil
        )

        await session.load()
        try await session.stagePatch(patch)

        #expect(session.hasStagedPatch == true)
        #expect(session.mode == .patch)
        #expect(session.content == "print(\"hello\")\n")
        #expect(session.stagedPatchPreviewContent == "print(\"patched\")\n")

        session.applyStagedPatch()

        #expect(session.hasStagedPatch == false)
        #expect(session.isDirty == true)
        #expect(session.content == "print(\"patched\")\n")

        try await session.save()

        #expect(session.isDirty == false)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "print(\"patched\")\n")
    }
}
