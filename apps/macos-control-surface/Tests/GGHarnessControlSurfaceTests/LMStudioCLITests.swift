import Testing
@testable import GGHarnessControlSurface

struct LMStudioCLITests {
    @Test
    func parseLibraryModelsJSONDecodesInstalledModels() throws {
        let json = """
        [
          {
            "type": "llm",
            "modelKey": "qwen/qwen3.5-9b",
            "displayName": "Qwen3.5 9B",
            "publisher": "qwen",
            "path": "qwen/qwen3.5-9b",
            "sizeBytes": 10449383867,
            "indexedModelIdentifier": "qwen/qwen3.5-9b",
            "paramsString": "9B",
            "quantization": { "name": "Q8_0", "bits": 8 },
            "selectedVariant": "qwen/qwen3.5-9b@q8_0",
            "maxContextLength": 262144
          }
        ]
        """.data(using: .utf8)!

        let models = LMStudioCLI.parseLibraryModelsJSON(json)
        #expect(models.count == 1)
        #expect(models[0].id == "qwen/qwen3.5-9b@q8_0")
        #expect(models[0].publisher == "qwen")
        #expect(models[0].contextLength == 262144)
        #expect(models[0].state == "not-loaded")
    }

    @Test
    func parseLoadedModelIdentifiersJSONReadsIdentifiers() throws {
        let json = """
        [
          { "identifier": "qwen/qwen3.5-9b@q8_0" },
          { "modelKey": "zai-org/glm-4.7-flash@q4_k_m" }
        ]
        """.data(using: .utf8)!

        let ids = LMStudioCLI.parseLoadedModelIdentifiersJSON(json)
        #expect(ids.contains("qwen/qwen3.5-9b@q8_0"))
        #expect(ids.contains("zai-org/glm-4.7-flash@q4_k_m"))
    }

    @MainActor
    @Test
    func unloadIdentifierCandidatesPreferLoadedIdentifierMatches() {
        let candidates = LMStudioEngine.unloadIdentifierCandidates(
            for: "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf",
            loadedIds: [
                "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF/Qwen2.5-Coder-7B-Instruct-Q4_K_M",
                "other/model@q4"
            ]
        )

        #expect(candidates.contains("lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF/Qwen2.5-Coder-7B-Instruct-Q4_K_M"))
        #expect(candidates.first == "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF/Qwen2.5-Coder-7B-Instruct-Q4_K_M")
    }
}
