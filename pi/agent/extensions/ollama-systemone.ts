/**
 * Ollama System One classifier provider.
 *
 * Ollama serves System-One-compatible decision models (e.g. `nimble`) at
 * `POST {base}/systemone` using the same request/response shape as TypeSafe's
 * System One API. Classifier models can only be registered from an extension
 * (models.json model definitions are chat-only), so this registers a
 * `ollama-systemone` provider exposing `nimble:latest` as a classifier.
 *
 * Use from codemode:
 *   const m = await models.getModelOfType("classifier", "ollama-systemone", "nimble:latest");
 *   await models.classify(m, { state, questions });
 */

import type { ExtensionAPI, ProviderClassifier } from "@earendil-works/pi-coding-agent";
import type { ClassifierAnswer, ClassifierResult, Usage } from "@earendil-works/pi-ai";

const BASE_URL = process.env.OLLAMA_SYSTEMONE_BASE_URL ?? "http://artemis.home:11434/v1";
const MODEL_ID = "nimble:latest";

function normalizeAnswer(answer: any): ClassifierAnswer | undefined {
  if (!answer || typeof answer !== "object") return undefined;
  if (answer.type === "choice" && typeof answer.choice === "string") {
    return { type: "choice", choice: answer.choice, probabilities: answer.probabilities, confidence: answer.confidence };
  }
  if (answer.type === "score") {
    return { type: "score", score: answer.score, confidence: answer.confidence };
  }
  // Ollama returns the Noul wire form; Pi's typed answer is `bool`.
  if (answer.type === "noul" || answer.type === "bool") {
    const probability = answer.noul ?? answer.probability;
    if (typeof probability === "number") return { type: "bool", probability };
  }
  return undefined;
}

const classify: ProviderClassifier["classify"] = async (model, context, options) => {
  const result: ClassifierResult = {
    api: model.api,
    provider: model.provider,
    model: model.id,
    answers: {},
    stopReason: "stop",
    timestamp: Date.now(),
  };
  const questions = Object.fromEntries(
    Object.entries(context.questions).map(([id, q]) => [id, q.type === "bool" ? { ...q, type: "noul" } : q]),
  );
  const base = (model.baseUrl ?? BASE_URL).replace(/\/+$/, "");
  try {
    const response = await fetch(`${base}/systemone`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${options?.apiKey ?? "ollama"}`,
      },
      body: JSON.stringify({ model: model.id, state: context.state, questions }),
      signal: options?.signal,
    });
    if (!response.ok) throw new Error(`ollama /systemone returned ${response.status}: ${await response.text()}`);
    const body: any = await response.json();
    for (const [id, answer] of Object.entries(body?.answers ?? {})) {
      const normalized = normalizeAnswer(answer);
      if (normalized) result.answers[id] = normalized;
    }
    if (body?.usage) {
      const input = Number(body.usage.input_tokens) || 0;
      const output = Number(body.usage.output_tokens) || 0;
      const usage: Usage = {
        input,
        output,
        cacheRead: 0,
        cacheWrite: 0,
        totalTokens: input + output,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
      };
      result.usage = usage;
    }
  } catch (error) {
    result.stopReason = options?.signal?.aborted ? "aborted" : "error";
    result.errorMessage = error instanceof Error ? error.message : String(error);
  }
  return result;
};

export default function (pi: ExtensionAPI) {
  pi.registerProvider("ollama-systemone", {
    name: "Ollama System One",
    baseUrl: BASE_URL,
    apiKey: "ollama",
    models: [
      {
        type: "classifier",
        id: MODEL_ID,
        name: "Nimble (ollama)",
        api: "ollama-systemone",
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 8192,
      },
    ],
    classifiers: { "ollama-systemone": { classify } },
  });
}
