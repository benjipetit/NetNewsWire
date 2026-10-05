//
//  MLXSummaryGenerator.swift
//  NetNewsWire
//

import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs a small quantized Qwen3 model locally with MLX. The weights are downloaded
/// from Hugging Face on first use and cached on the device.
actor MLXSummaryGenerator: SummaryGenerating {

	private static let maxTokens = 80

	private var modelContainer: ModelContainer?

	func generate(prompt: String) async throws -> String {
		let container = try await loadedModelContainer()
		let parameters = GenerateParameters(maxTokens: Self.maxTokens, temperature: 0.3)
		let session = ChatSession(container, generateParameters: parameters)
		// "/no_think" turns off Qwen3’s reasoning mode so the answer comes back quickly.
		return try await session.respond(to: prompt + " /no_think")
	}
}

private extension MLXSummaryGenerator {

	func loadedModelContainer() async throws -> ModelContainer {
		if let modelContainer {
			return modelContainer
		}
		let container = try await #huggingFaceLoadModelContainer(configuration: LLMRegistry.qwen3_0_6b_4bit)
		modelContainer = container
		return container
	}
}
