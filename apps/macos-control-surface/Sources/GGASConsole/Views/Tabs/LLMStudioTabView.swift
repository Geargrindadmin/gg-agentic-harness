import SwiftUI

struct LLMStudioTabView: View {
    @EnvironmentObject private var shell: AppShellState

    var body: some View {
        LMStudioManagerView(
            initialSearchQuery: shell.lmStudioCatalogQuery,
            autoDownloadInitialQuery: shell.lmStudioAutoDownload
        )
        .id("llmstudio:\(shell.lmStudioCatalogQuery):\(shell.lmStudioAutoDownload ? "auto" : "manual")")
        .navigationTitle("LLM Studio")
    }
}
