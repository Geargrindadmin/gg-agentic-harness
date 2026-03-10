import Testing
@testable import GGHarnessControlSurface

struct GitWorktreeStoreTests {
    @Test
    func parseWorktreeListDecodesWorkspaceBranchDetachedAndPrunableEntries() throws {
        let output = """
        worktree /tmp/repo
        HEAD abc123
        branch refs/heads/main

        worktree /tmp/repo/.agent/control-plane/worktrees/run-1/scout-1
        HEAD def456
        detached

        worktree /tmp/repo/.agent/control-plane/worktrees/run-2/builder-2
        HEAD ghi789
        branch refs/heads/feature/agent
        prunable gitdir file points to non-existent location
        """

        let parsed = try GitWorktreeStore.parseWorktreeList(output, projectRoot: "/tmp/repo")

        #expect(parsed.count == 3)
        #expect(parsed[0].path == "/tmp/repo")
        #expect(parsed[0].branch == "main")
        #expect(parsed[0].detached == false)
        #expect(parsed[1].detached == true)
        #expect(parsed[1].branch == nil)
        #expect(parsed[2].branch == "feature/agent")
        #expect(parsed[2].prunable == true)
    }

    @MainActor
    @Test
    func summaryLookupNormalizesPathsAcrossGroups() {
        let store = GitWorktreeStore.shared
        store.groups = [
            GitWorktreeGroup(
                title: "run-1",
                subtitle: nil,
                worktrees: [
                    GitWorktreeSummary(
                        path: "/tmp/repo/.agent/control-plane/worktrees/run-1/builder-1",
                        label: "builder-1",
                        branch: "feature/agent",
                        head: "abc123",
                        detached: false,
                        prunable: false,
                        isMain: false,
                        runId: "run-1",
                        agentId: "builder-1",
                        runtime: "kimi",
                        role: "builder",
                        aheadCount: nil,
                        behindCount: nil,
                        changedFilesCount: 2,
                        untrackedFilesCount: 0,
                        changedFilesList: [
                            "/tmp/repo/.agent/control-plane/worktrees/run-1/builder-1/src/app.ts",
                            "/tmp/repo/.agent/control-plane/worktrees/run-1/builder-1/README.md"
                        ]
                    )
                ]
            )
        ]

        let summary = store.summary(for: "/tmp/repo/.agent/control-plane/worktrees/run-1/./builder-1")
        #expect(summary?.agentId == "builder-1")
        #expect(store.changedFiles(for: "/tmp/repo/.agent/control-plane/worktrees/run-1/builder-1").count == 2)
    }
}
