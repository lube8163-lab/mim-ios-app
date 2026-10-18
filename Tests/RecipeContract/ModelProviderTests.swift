import XCTest
@testable import MimRecipeContract

final class ModelProviderTests: XCTestCase {
    private let sourceHash = String(repeating: "0", count: 64)
    private let environment = StageEnvironment(deviceModel: "SyntheticDevice", osVersion: "fixture-only", executionTarget: .mac)
    private func understanding() -> UnderstandingStageEvidence {
        .init(stage: .understanding, caseID: "synthetic-fixture", status: .notRun, sourceSHA256: sourceHash,
              identity: .init(modelID: "synthetic-vlm", modelRevision: "fixture-v1", runtime: "SyntheticFixture",
                              runtimeVersion: nil, assetManifestSHA256: nil),
              environment: environment, measurements: .init(),
              input: .init(processedWidth: 512, processedHeight: 512, preprocessingVersion: "synthetic-v1",
                           processedSHA256: nil, instructionVersion: "synthetic-v1"),
              result: .init(prompt: "One red cup on a white table", caption: "Synthetic text, not model output",
                            observations: [], uncertainties: nil, editedPrompt: "Two red cups on a white table"),
              recordedAt: "2026-10-06T00:00:00Z")
    }
    private func generation(_ understanding: UnderstandingStageEvidence) throws -> GenerationStageEvidence {
        .init(stage: .generation, caseID: understanding.caseID, status: .notRun, sourceSHA256: sourceHash,
              identity: .unconfiguredCoreAI, environment: environment, measurements: .init(),
              input: .init(prompt: "Two red cups on a white table", negativePrompt: "", promptSource: .editedUnderstanding,
                           understandingRecordSHA256: try canonicalDigest(understanding)),
              result: .init(imageSHA256: nil), recordedAt: "2026-10-06T00:00:00Z")
    }
    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(value)) as? [String: Any])
    }
    func testProvidersHaveSeparateSelections() {
        XCTAssertEqual(Set(UnderstandingProviderID.allCases.map(\.rawValue)), ["foundationModels", "coreAIVLM"])
        XCTAssertEqual(Set(GenerationProviderID.allCases.map(\.rawValue)), ["coreML", "coreAI"])
        XCTAssertNotEqual(StageModelIdentity.foundationBaseline.runtime, StageModelIdentity.unconfiguredCoreAI.runtime)
    }
    func testWindowsCPUEnvironmentRoundTrip() throws {
        let data = Data(#"{"deviceModel":"SyntheticCPU","osVersion":"fixture-only","executionTarget":"windowsCPU"}"#.utf8)
        let environment = try JSONDecoder().decode(StageEnvironment.self, from: data)
        XCTAssertEqual(environment.executionTarget, .windowsCPU)
        XCTAssertEqual(try object(environment)["executionTarget"] as? String, "windowsCPU")
    }
    func testCoreAIUnavailableGateDoesNotRunBaseline() {
        var calls = 0
        for state in [ProviderAvailability.coreAI(sdkAvailable: false), .coreAI(sdkAvailable: true),
                      .coreAI(sdkAvailable: true, assetsAvailable: true)] {
            XCTAssertFalse(state.canRun)
            XCTAssertThrowsError(try { try state.requireReady(); calls += 1 }())
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(ProviderAvailability.coreAI(sdkAvailable: true).status, .missingAssets)
        XCTAssertEqual(ProviderAvailability.coreAI(sdkAvailable: true, assetsAvailable: true).status, .runnerNotImplemented)
    }
    func testUnknownMemoryAndVersionAreExplicitNull() throws {
        let record = try object(understanding())
        let metrics = try XCTUnwrap(record["measurements"] as? [String: Any])
        XCTAssertEqual(Set(metrics.keys), ["preparationSeconds", "inferenceSeconds", "elapsedSeconds", "elapsedScope",
            "peakMemoryBytes", "peakMemoryMethod", "memoryScope", "samplingIntervalMilliseconds"])
        XCTAssertTrue(metrics.values.allSatisfy { $0 is NSNull })
        let identity = try XCTUnwrap(record["identity"] as? [String: Any])
        XCTAssertTrue(identity["runtimeVersion"] is NSNull)
        XCTAssertTrue(identity["assetManifestSHA256"] is NSNull)
    }
    func testSamplingNeedsMethodScopeAndInterval() throws {
        XCTAssertThrowsError(try StageMeasurements(peakMemoryBytes: 100).validate())
        XCTAssertThrowsError(try StageMeasurements(peakMemoryBytes: 100, peakMemoryMethod: "sampling", memoryScope: "process").validate())
        try StageMeasurements(peakMemoryBytes: 100, peakMemoryMethod: "sampling", memoryScope: "process",
                              samplingIntervalMilliseconds: 50).validate()
        XCTAssertThrowsError(try canonicalData(StageMeasurements(inferenceSeconds: -.infinity)))
    }
    func testMeasuredStagesRemainSeparate() throws {
        var u = understanding()
        u.status = .completed
        u.measurements = .init(preparationSeconds: 0.2, inferenceSeconds: 1, elapsedSeconds: 1.2, elapsedScope: "synthetic")
        var g = try generation(u)
        g.measurements = .init(preparationSeconds: 0.3, inferenceSeconds: 2, elapsedSeconds: 2.3, elapsedScope: "synthetic")
        XCTAssertEqual(u.measurements.inferenceSeconds, 1)
        XCTAssertEqual(g.measurements.inferenceSeconds, 2)
        XCTAssertNil(u.measurements.peakMemoryBytes)
        XCTAssertNil(g.measurements.peakMemoryBytes)
    }
    func testRawEditedPromptAndUnderstandingReferenceAreIndependent() throws {
        let u = understanding()
        let g = try generation(u)
        XCTAssertNotEqual(u.result.prompt, u.result.editedPrompt)
        XCTAssertEqual(g.input.prompt, u.result.editedPrompt)
        XCTAssertEqual(g.input.promptSource, .editedUnderstanding)
        XCTAssertEqual(g.input.understandingRecordSHA256, try canonicalDigest(u))
        let roundTrip = try JSONDecoder().decode(GenerationStageEvidence.self, from: canonicalData(g))
        XCTAssertEqual(roundTrip.caseID, u.caseID)
        XCTAssertEqual(roundTrip.environment.executionTarget, .mac)
        XCTAssertEqual(roundTrip.recordedAt, "2026-10-06T00:00:00Z")
        XCTAssertTrue(try object(g.result)["imageSHA256"] is NSNull)
    }
    func testComparisonV2FixtureContainsNoImageBytes() throws {
        let u = understanding()
        let record = MimComparisonRecord<String>(version: 2, sourceID: u.caseID, understandingBackend: "syntheticFixture",
            sourceSHA256: sourceHash, osVersion: environment.osVersion, deviceModel: environment.deviceModel,
            processedWidth: 512, processedHeight: 512, understandingElapsedSeconds: nil, scene: nil, recipe: nil,
            editedPrompt: u.result.editedPrompt!, understandingRecord: u, generationRecord: try generation(u))
        let data = try canonicalData(record)
        let decoded = try JSONDecoder().decode(MimComparisonRecord<String>.self, from: data)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.understandingRecord?.status, .notRun)
        XCTAssertEqual(decoded.generationRecord.status, .notRun)
        let json = String(decoding: data, as: UTF8.self).lowercased()
        for banned in ["base64", "pixels", "jpeg", "latent", "embedding", "token"] { XCTAssertFalse(json.contains(banned)) }
        if let path = ProcessInfo.processInfo.environment["MIM_SYNTHETIC_FIXTURE_PATH"] {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
