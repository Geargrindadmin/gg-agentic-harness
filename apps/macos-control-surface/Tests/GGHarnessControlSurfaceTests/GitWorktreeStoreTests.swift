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
}
