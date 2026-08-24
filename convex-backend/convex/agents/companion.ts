"use node";

import { createDeepSeek } from "@ai-sdk/deepseek";
import { createGoogle } from "@ai-sdk/google";
import { createMoonshotAI } from "@ai-sdk/moonshotai";
import { createOpenAI } from "@ai-sdk/openai";
import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import type { LanguageModelV4 } from "@ai-sdk/provider";
import { Agent, extractText } from "@convex-dev/agent";
import type { ModelMessage } from "ai";
import { components } from "../_generated/api";
import { env } from "../_generated/server";

export const MAX_OUTPUT_TOKENS = 600;
export const MAX_CONTEXT_CHARACTERS = 24_000;
export const GENERATION_TIMEOUT_MS = 60_000;

export type CompanionProvider =
  | "openai"
  | "google"
  | "deepseek"
  | "moonshot"
  | "qwen";

export type CompanionRuntime = {
  agent: Agent;
  provider: CompanionProvider;
  model: string;
  supportsImages: boolean;
};

type ModelConfiguration = {
  id: string;
  supportsImages: boolean;
};

// Deliberately small and reviewed against provider catalogs on 2026-08-23:
// changing providers/models is an operator-only env change, but every billable
// model still has to be reviewed and admitted in code first. This prevents a
// typo, retired alias, or compromised deployment setting from silently
// selecting an unknown high-cost model.
const MODEL_REGISTRY: Record<CompanionProvider, readonly ModelConfiguration[]> = {
  openai: [
    { id: "gpt-4o-mini", supportsImages: true },
    { id: "gpt-4.1-mini", supportsImages: true },
    { id: "gpt-4.1", supportsImages: true },
  ],
  google: [
    { id: "gemini-3.7-flash", supportsImages: true },
    { id: "gemini-3.6-flash", supportsImages: true },
    { id: "gemini-3.5-flash", supportsImages: true },
  ],
  deepseek: [
    { id: "deepseek-v4-flash", supportsImages: false },
    { id: "deepseek-v4-pro", supportsImages: false },
  ],
  moonshot: [
    { id: "kimi-k3", supportsImages: true },
    { id: "kimi-k2.6", supportsImages: true },
  ],
  qwen: [
    { id: "qwen-plus", supportsImages: false },
    { id: "qwen3-vl-plus", supportsImages: true },
  ],
};

const DEFAULT_MODEL: Record<CompanionProvider, string> = {
  openai: "gpt-4o-mini",
  google: "gemini-3.7-flash",
  deepseek: "deepseek-v4-flash",
  moonshot: "kimi-k3",
  qwen: "qwen-plus",
};

export class CompanionConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CompanionConfigurationError";
  }
}

const instructions = `You are Embie, a warm, steady affirmation companion.

Voice and character:
- Respond conversationally, with empathy and grounded practical encouragement.
- Help the user reflect, reframe unhelpful self-talk, and form realistic affirmations when useful.
- Be concise unless the user asks for detail. Ask at most one useful follow-up question at a time.
- Never claim a memory, relationship, experience, diagnosis, or fact that is not present in the supplied conversation.

Boundaries and safety:
- You are not a medical or mental-health professional. Do not diagnose, prescribe, or replace professional care.
- Do not reinforce delusions, paranoia, mania, coercive control, or self-destructive behavior. Validate feelings without validating an unsafe belief.
- If the user appears to be in immediate danger or considering self-harm, respond calmly, encourage contacting local emergency services or a crisis service now, and suggest reaching a trusted person who can stay with them. Do not use guilt, threats, or false certainty.
- If media is described as unavailable, say plainly that you cannot inspect or hear it; never pretend you did.`;

function requiredSecret(value: string | undefined, name: string): string {
  if (value === undefined || value.trim() === "") {
    throw new CompanionConfigurationError(
      `${name} is required for the selected companion provider`,
    );
  }
  return value;
}

function selectedProvider(): CompanionProvider {
  const value = (env.COMPANION_PROVIDER ?? "openai").toLowerCase();
  switch (value) {
    case "openai":
    case "google":
    case "deepseek":
    case "moonshot":
    case "qwen":
      return value;
    default:
      throw new CompanionConfigurationError(
        `Unsupported COMPANION_PROVIDER: ${value}`,
      );
  }
}

function selectedModel(provider: CompanionProvider): ModelConfiguration {
  const id = env.COMPANION_MODEL ?? DEFAULT_MODEL[provider];
  const configuration = MODEL_REGISTRY[provider].find(
    (candidate) => candidate.id === id,
  );
  if (configuration === undefined) {
    throw new CompanionConfigurationError(
      `Unsupported COMPANION_MODEL for ${provider}: ${id}`,
    );
  }
  return configuration;
}

function createLanguageModel(provider: CompanionProvider): {
  languageModel: LanguageModelV4;
  model: string;
  supportsImages: boolean;
} {
  const configuration = selectedModel(provider);
  const model = configuration.id;
  switch (provider) {
    case "openai": {
      const client = createOpenAI({
        apiKey: requiredSecret(env.OPENAI_API_KEY, "OPENAI_API_KEY"),
      });
      return {
        languageModel: client.chat(model),
        model,
        supportsImages: configuration.supportsImages,
      };
    }
    case "google": {
      const client = createGoogle({
        apiKey: requiredSecret(
          env.GOOGLE_GENERATIVE_AI_API_KEY,
          "GOOGLE_GENERATIVE_AI_API_KEY",
        ),
      });
      return {
        languageModel: client.chat(model),
        model,
        supportsImages: configuration.supportsImages,
      };
    }
    case "deepseek": {
      const client = createDeepSeek({
        apiKey: requiredSecret(env.DEEPSEEK_API_KEY, "DEEPSEEK_API_KEY"),
      });
      return {
        languageModel: client.chat(model),
        model,
        supportsImages: configuration.supportsImages,
      };
    }
    case "moonshot": {
      const client = createMoonshotAI({
        apiKey: requiredSecret(env.MOONSHOT_API_KEY, "MOONSHOT_API_KEY"),
      });
      return {
        languageModel: client.chatModel(model),
        model,
        supportsImages: configuration.supportsImages,
      };
    }
    case "qwen": {
      const client = createOpenAICompatible({
        name: "qwen",
        apiKey: requiredSecret(env.QWEN_API_KEY, "QWEN_API_KEY"),
        baseURL: requiredSecret(env.QWEN_BASE_URL, "QWEN_BASE_URL"),
        includeUsage: true,
      });
      return {
        languageModel: client.chatModel(model),
        model,
        supportsImages: configuration.supportsImages,
      };
    }
  }
}

function approximateMessageCharacters(message: ModelMessage): number {
  const text = extractText(message) ?? "";
  if (typeof message.content === "string") {
    return text.length;
  }
  // Budget non-text parts too. Provider tokenization differs, but no request
  // can accumulate unbounded history.
  return text.length + message.content.length * 1_000;
}

/** Keeps the newest complete messages under a provider-neutral text budget. */
export function boundedContext(messages: ModelMessage[]): ModelMessage[] {
  const selected: ModelMessage[] = [];
  let characters = 0;

  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index]!;
    const cost = approximateMessageCharacters(message);
    if (selected.length > 0 && characters + cost > MAX_CONTEXT_CHARACTERS) {
      break;
    }
    selected.push(message);
    characters += cost;
  }

  return selected.reverse();
}

/**
 * Creates the configured Agent at action runtime. Provider choice is never
 * accepted from a client and credentials never leave Convex environment vars.
 */
export function createCompanionRuntime(): CompanionRuntime {
  const provider = selectedProvider();
  const { languageModel, model, supportsImages } =
    createLanguageModel(provider);

  const agent = new Agent(components.agent, {
    name: "Companion",
    languageModel,
    instructions,
    callSettings: {
      // Provider SDKs frequently mark every HTTP 429 as retryable, including
      // permanent billing/quota failures. Retry only after our provider-neutral
      // classifier has seen the real error and the durable turn state can make
      // the decision safely.
      maxRetries: 0,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      temperature: 0.7,
    },
    contextOptions: {
      excludeToolMessages: true,
      recentMessages: 40,
      searchOptions: {
        limit: 0,
        textSearch: false,
        vectorSearch: false,
        messageRange: { before: 0, after: 0 },
      },
      searchOtherThreads: false,
    },
    contextHandler: async (_ctx, args) => {
      // TODO(mem0): Retrieve governed user memories here and prepend them.
      // Input messages replace the stored prompt only for the current
      // multimodal turn; the stored text prompt remains the durable history.
      const current =
        args.inputMessages.length > 0
          ? args.inputMessages
          : args.inputPrompt;
      return boundedContext([
        ...args.search,
        ...args.recent,
        ...current,
      ]);
    },
  });

  return { agent, provider, model, supportsImages };
}
