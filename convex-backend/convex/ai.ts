"use node";

import { APICallError, RetryError } from "ai";
import type { LanguageModelUsage, ModelMessage, UserContent } from "ai";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalAction } from "./_generated/server";
import {
  CompanionConfigurationError,
  createCompanionRuntime,
  GENERATION_TIMEOUT_MS,
} from "./agents/companion";
import { r2 } from "./r2";

const STREAM_PATCH_THROTTLE_MS = 250;
const MEDIA_URL_TTL_SECONDS = 10 * 60;
// A separately scheduled wake-up makes an abandoned lease recoverable even if
// the action is terminated before its `finally` block can schedule the queue.
const CLAIM_WATCHDOG_MS = 91_000;

type SafeGenerationError = {
  code:
    | "provider_configuration"
    | "provider_authentication"
    | "provider_billing"
    | "provider_rate_limited"
    | "provider_unavailable"
    | "timeout"
    | "unsupported_media"
    | "generation_failed";
  message: string;
  retryable: boolean;
  retryAfterMs?: number;
};

function retryAfterMs(headers: Record<string, string> | undefined) {
  const raw = headers?.["retry-after"];
  if (raw === undefined) return undefined;
  const seconds = Number(raw);
  return Number.isFinite(seconds) && seconds >= 0
    ? seconds * 1_000
    : undefined;
}

export function classifyGenerationError(
  error: unknown,
  streamError?: unknown,
): SafeGenerationError {
  // `textStream` intentionally drops AI SDK error chunks. When a provider
  // fails before producing output, result promises reject later with a generic
  // NoOutputGeneratedError. Prefer the original error captured by `onError`
  // so permanent billing/auth failures do not become misleading generic ones.
  const failure = streamError ?? error;

  if (failure instanceof CompanionConfigurationError) {
    return {
      code: "provider_configuration",
      message: "The companion is not configured right now.",
      retryable: false,
    };
  }

  const source = RetryError.isInstance(failure)
    ? failure.lastError
    : failure;
  const fallbackMessage =
    source instanceof Error ? source.message.toLowerCase() : "";

  if (
    fallbackMessage.includes("abort") ||
    fallbackMessage.includes("timed out") ||
    fallbackMessage.includes("timeout")
  ) {
    return {
      code: "timeout",
      message: "The reply took too long. Please try again.",
      retryable: true,
    };
  }

  if (APICallError.isInstance(source)) {
    const status = source.statusCode;
    if (status === 401 || status === 403) {
      return {
        code: "provider_authentication",
        message: "The companion is temporarily unavailable.",
        retryable: false,
      };
    }
    if (
      status === 402 ||
      fallbackMessage.includes("credit") ||
      fallbackMessage.includes("billing") ||
      fallbackMessage.includes("quota") ||
      fallbackMessage.includes("insufficient_quota")
    ) {
      return {
        code: "provider_billing",
        message: "The companion is temporarily unavailable.",
        retryable: false,
      };
    }
    if (status === 429) {
      return {
        code: "provider_rate_limited",
        message: "The companion is busy. Please try again shortly.",
        retryable: true,
        retryAfterMs: retryAfterMs(source.responseHeaders),
      };
    }
    if ((status !== undefined && status >= 500) || source.isRetryable) {
      return {
        code: "provider_unavailable",
        message: "The companion is having trouble responding. Please try again.",
        retryable: true,
      };
    }
  }

  return {
    code: "generation_failed",
    message: "The companion could not finish that reply.",
    retryable: RetryError.isInstance(failure),
  };
}

function normalizedUsage(usage: LanguageModelUsage) {
  const inputTokens = usage.inputTokens ?? 0;
  const outputTokens = usage.outputTokens ?? 0;
  return {
    inputTokens,
    outputTokens,
    totalTokens: usage.totalTokens ?? inputTokens + outputTokens,
    cacheReadTokens: usage.inputTokenDetails.cacheReadTokens,
    cacheWriteTokens: usage.inputTokenDetails.cacheWriteTokens,
    reasoningTokens: usage.outputTokenDetails.reasoningTokens,
  };
}

async function multimodalInput(
  claim: {
    text: string;
    attachments: Array<{
      type: "image" | "video";
      r2Key: string;
      thumbR2Key: string;
    }>;
    giphyMediaId?: string;
    recording?: { duration: number; waveformSamples: number[]; r2Key: string };
  },
  supportsImages: boolean,
): Promise<ModelMessage[] | undefined> {
  const imageAttachments = claim.attachments.filter(
    (attachment) => attachment.type === "image",
  );
  const hasGiphy = claim.giphyMediaId !== undefined;
  if (!supportsImages || (imageAttachments.length === 0 && !hasGiphy)) {
    return undefined;
  }

  const textParts: string[] = [];
  if (claim.text.trim() !== "") textParts.push(claim.text.trim());
  if (claim.attachments.some((attachment) => attachment.type === "video")) {
    textParts.push(
      "The user also attached a video that is not available to inspect in this chat.",
    );
  }
  if (claim.recording !== undefined) {
    textParts.push(
      "The user also attached a voice recording that has not been transcribed; do not pretend to hear it.",
    );
  }
  if (textParts.length === 0) {
    textParts.push("The user shared this image.");
  }

  const content: UserContent = [
    { type: "text", text: textParts.join("\n\n") },
  ];
  for (const attachment of imageAttachments) {
    const signedUrl = await r2.getUrl(attachment.r2Key, {
      expiresIn: MEDIA_URL_TTL_SECONDS,
    });
    content.push({
      type: "file",
      mediaType: "image/jpeg",
      data: new URL(signedUrl),
    });
  }
  if (claim.giphyMediaId !== undefined) {
    const id = encodeURIComponent(claim.giphyMediaId);
    content.push({
      type: "file",
      mediaType: "image/gif",
      data: new URL(`https://media.giphy.com/media/${id}/giphy.gif`),
    });
  }

  return [{ role: "user", content }];
}

/** Processes at most one claimed turn, then schedules the next queued turn. */
export const processConversationQueue = internalAction({
  args: { conversationId: v.id("conversations") },
  returns: v.null(),
  handler: async (ctx, { conversationId }) => {
    let runtime;
    try {
      runtime = createCompanionRuntime();
    } catch (error) {
      const safeError = classifyGenerationError(error);
      const failed = await ctx.runMutation(
        internal.model.generationTurns.failNextQueuedTurn,
        { conversationId, error: safeError },
      );
      if (failed) {
        await ctx.scheduler.runAfter(
          0,
          internal.ai.processConversationQueue,
          { conversationId },
        );
      }
      return null;
    }

    const claim = await ctx.runMutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      {
        conversationId,
        provider: runtime.provider,
        model: runtime.model,
      },
    );
    if (claim.kind === "idle") {
      return null;
    }
    if (claim.kind === "wait") {
      await ctx.scheduler.runAfter(
        claim.retryAfterMs,
        internal.ai.processConversationQueue,
        { conversationId },
      );
      return null;
    }

    await ctx.scheduler.runAfter(
      CLAIM_WATCHDOG_MS,
      internal.ai.processConversationQueue,
      { conversationId },
    );

    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(new Error("Generation timed out")),
      GENERATION_TIMEOUT_MS,
    );
    let text = "";
    let lastPatchAt = 0;
    let providerStreamError: unknown;

    try {
      const messages = await multimodalInput(claim, runtime.supportsImages);
      const result = await runtime.agent.streamText(
        ctx,
        { threadId: claim.threadId, userId: claim.userId },
        {
          promptMessageId: claim.agentPromptMessageId,
          ...(messages === undefined ? {} : { messages }),
          abortSignal: controller.signal,
          onError: ({ error }) => {
            providerStreamError = error;
          },
        },
      );

      for await (const chunk of result.textStream) {
        text += chunk;
        const now = Date.now();
        if (now - lastPatchAt < STREAM_PATCH_THROTTLE_MS) continue;
        const accepted = await ctx.runMutation(
          internal.model.generationTurns.patchGenerationText,
          {
            turnId: claim.turnId,
            attemptId: claim.attemptId,
            text,
          },
        );
        if (!accepted) {
          controller.abort(new Error("Generation lease is no longer active"));
          return null;
        }
        lastPatchAt = now;
      }

      if (providerStreamError !== undefined) {
        throw providerStreamError;
      }

      const usage = normalizedUsage(await result.usage);
      await ctx.runMutation(
        internal.model.generationTurns.completeGenerationTurn,
        {
          turnId: claim.turnId,
          attemptId: claim.attemptId,
          text,
          usage,
        },
      );
    } catch (error) {
      const safeError = classifyGenerationError(error, providerStreamError);
      console.error("Companion generation failed", {
        code: safeError.code,
        retryable: safeError.retryable,
        provider: runtime.provider,
        model: runtime.model,
      });
      const resolution = await ctx.runMutation(
        internal.model.generationTurns.handleGenerationFailure,
        {
          turnId: claim.turnId,
          attemptId: claim.attemptId,
          error: safeError,
          partialText: text,
        },
      );
      if (resolution.kind === "requeued") {
        console.warn("Companion generation requeued", {
          provider: runtime.provider,
          model: runtime.model,
          retryAfterMs: resolution.retryAfterMs,
        });
      }
    } finally {
      clearTimeout(timeout);
      await ctx.scheduler.runAfter(
        0,
        internal.ai.processConversationQueue,
        { conversationId },
      );
    }
    return null;
  },
});
