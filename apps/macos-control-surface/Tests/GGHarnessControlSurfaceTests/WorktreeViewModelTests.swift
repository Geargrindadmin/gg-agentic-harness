import Foundation
import Testing
@testable import GGHarnessControlSurface

@MainActor
struct WorktreeViewModelTests {
    @Test
    func refreshDecodesWorktreeListing() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let host = "fixture-worktree-success"

        FixtureURLProtocol.handlers["\(host)/api/worktree"] = (
            200,
            Data(
                """
                {
                  "path": "/tmp/run-fixture/builder-1",
                  "files": [
                    {
                      "name": "src",
                      "relativePath": "/tmp/run-fixture/builder-1/src",
                      "size": 0,
                      "modifiedAt": "2026-03-09T12:00:00.000Z",
                      "isDir": true,
                      "depth": 1
                    },
                    {
                      "name": "index.ts",
                      "relativePath": "/tmp/run-fixture/builder-1/src/index.ts",
                      "size": 512,
                      "modifiedAt": "2026-03-09T12:01:00.000Z",
                      "isDir": false,
                      "depth": 2
                    }
                  ],
                  "totalFiles": 2,
                  "totalSize": 512
                }
                """.utf8
            )
        )

        let viewModel = WorktreeViewModel(
            agentId: "builder-1",
            worktreePath: "/tmp/run-fixture/builder-1",
            session: session,
            controlPlaneAPIBaseURL: "http://\(host)/api",
            autoStart: false
        )

        await viewModel.refresh()

        #expect(viewModel.error == nil)
        #expect(viewModel.totalFiles == 2)
        #expect(viewModel.totalSize == 512)
        #expect(viewModel.files.first?.name == "src")
        #expect(viewModel.files.last?.relativePath == "/tmp/run-fixture/builder-1/src/index.ts")
    }

    @Test
    func refreshHandlesMissingWorktreeGracefully() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let host = "fixture-worktree-missing"

        FixtureURLProtocol.handlers["\(host)/api/worktree"] = (404, Data())

        let viewModel = WorktreeViewModel(
            agentId: "builder-1",
            worktreePath: "/tmp/run-fixture/builder-1",
            session: session,
            controlPlaneAPIBaseURL: "http://\(host)/api",
            autoStart: false
        )

        await viewModel.refresh()

        #expect(viewModel.totalFiles == 0)
        #expect(viewModel.totalSize == 0)
        #expect(viewModel.files.isEmpty)
        #expect(viewModel.error == "Worktree not created yet")
        #expect(viewModel.isLoading == false)
    }
}
