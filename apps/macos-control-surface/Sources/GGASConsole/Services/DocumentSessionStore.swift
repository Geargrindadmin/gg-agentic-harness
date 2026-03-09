import Foundation

@MainActor
final class DocumentSessionStore {
    static let shared = DocumentSessionStore()

    private var sessions: [String: DocumentViewerStore] = [:]

    func session(
        path: String,
        sourceLabel: String,
        workspaceRootPath: String,
        selectedRunRootPath: String?
    ) -> DocumentViewerStore {
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        if let existing = sessions[key] {
            existing.configure(
                sourceLabel: sourceLabel,
                workspaceRootPath: workspaceRootPath,
                selectedRunRootPath: selectedRunRootPath
            )
            return existing
        }

        let created = DocumentViewerStore(
            path: key,
            sourceLabel: sourceLabel,
            workspaceRootPath: workspaceRootPath,
            selectedRunRootPath: selectedRunRootPath
        )
        sessions[key] = created
        return created
    }

    func sessionIfLoaded(path: String) -> DocumentViewerStore? {
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        return sessions[key]
    }
}
