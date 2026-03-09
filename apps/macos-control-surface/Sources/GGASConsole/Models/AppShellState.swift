import Foundation

@MainActor
final class AppShellState: ObservableObject {
    @Published var selectedTab: ConsoleTab = .tasks
    @Published var showUsage = false
    @Published var showLMStudioManager = false
    @Published var lmStudioCatalogQuery = ""

    func openLMStudioCatalog(query: String = "") {
        lmStudioCatalogQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        showLMStudioManager = true
    }
}
