//
//  Summarizer.swift
//  NetNewsWire
//
//  Created by Ben Petit on 05/10/2026.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//


import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

actor Summarizer {
    private var model: ModelContainer?

    private func loadModel() async throws -> ModelContainer {
        if let model {
            return model
        }

        let model = try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            id: "mlx-community/Qwen3-0.6B-4bit"
        )

        self.model = model
        return model
    }

    func summarize(_ text: String) async throws -> String {
        let model = try await loadModel()

        // Fresh session so summaries don't leak context into one another.
        let session = ChatSession(model)

        let response = try await session.respond(
            to: """
            /no_think

            Summarize the following text concisely.

            Requirements:
            - preserve the important facts
            - don't add information
            - use the same language as the source
            - maximum one sentence

            TEXT:
            \(text)
            """
        )
        return visibleSummary(from: response)
    }

    private func visibleSummary(from response: String) -> String {
        var summary = response

        while let startRange = summary.range(of: "<think>", options: .caseInsensitive) {
            if let endRange = summary.range(of: "</think>", options: .caseInsensitive, range: startRange.upperBound..<summary.endIndex) {
                summary.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                summary.removeSubrange(startRange.lowerBound..<summary.endIndex)
            }
        }

        if let endRange = summary.range(of: "</think>", options: .caseInsensitive) {
            summary = String(summary[endRange.upperBound...])
        }

        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
