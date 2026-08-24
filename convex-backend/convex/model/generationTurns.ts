import { v } from "convex/values";
import type { Doc, Id } from "../_generated/dataModel";
import { internalMutation } from "../_generated/server";
import type { MutationCtx } from "../_generated/server";
import {
  generationError,
  storedAttachment,
  storedRecording,
} from "../schema";

const MAX_GLOBAL_CONCURRENT_GENERATIONS = 8;
const GENERATION_LEASE_MS = 90_000;
const GLOBAL_SLOT_RETRY_MS = 1_000;
const MAX_AUTOMATIC_ATTEMPTS = 3;
const INITIAL_AUTOMATIC_RETRY_MS = 1_000;
const MAX_AUTOMATIC_RETRY_DELAY_MS = 30_000;

const claimResult = v.union(
  v.object({ kind: v.literal("idle") }),
  v.object({ kind: v.literal("wait"), retryAfterMs: v.number() }),
  v.object({
    kind: v.literal("claimed"),
    turnId: v.id("generationTurns"),
    attemptId: v.string(),
    userId: v.id("users"),
    conversationId: v.id("conversations"),
    threadId: v.string(),
    agentPromptMessageId: v.string(),
    text: v.string(),
    attachments: v.array(storedAttachment),
    giphyMediaId: v.optional(v.string()),
    recording: v.optional(storedRecording),
  }),
);

const failureResolution = v.union(
  v.object({ kind: v.literal("stale") }),
  v.object({ kind: v.literal("failed") }),
  v.object({ kind: v.literal("requeued"), retryAfterMs: v.number() }),
);

async function cancelTurn(
  ctx: MutationCtx,
  turn: Doc<"generationTurns">,
  now: number,
) {
  await ctx.db.patch("generationTurns", turn._id, {
    status: "cancelled",
    attemptId: undefined,
    leaseExpiresAt: undefined,
    finishedAt: now,
  });
  const assistant = await ctx.db.get("messages", turn.assistantMessageId);
  if (assistant !== null) {
    const conversation = await ctx.db.get(
      "conversations",
      turn.conversationId,
    );
    if (conversation === null) {
      await ctx.db.delete("messages", assistant._id);
    } else {
      await ctx.db.patch("messages", assistant._id, {
        generationStatus: "cancelled",
        generationError: undefined,
      });
    }
  }
}

async function requeueExpiredLeases(ctx: MutationCtx, now: number) {
  const expired = await ctx.db
    .query("generationTurns")
    .withIndex("by_status_and_lease_expires_at", (q) =>
      q.eq("status", "generating").lt("leaseExpiresAt", now),
    )
    .take(MAX_GLOBAL_CONCURRENT_GENERATIONS);

  for (const turn of expired) {
    const conversation = await ctx.db.get("conversations", turn.conversationId);
    const assistant = await ctx.db.get("messages", turn.assistantMessageId);
    if (conversation === null || assistant === null) {
      await cancelTurn(ctx, turn, now);
      continue;
    }
    await ctx.db.patch("generationTurns", turn._id, {
      status: "queued",
      notBefore: now,
      attemptId: undefined,
      leaseExpiresAt: undefined,
      error: undefined,
    });
    await ctx.db.patch("messages", assistant._id, {
      generationStatus: "queued",
      generationError: undefined,
      generationNotBefore: now,
    });
  }
}

/** Atomically claims the oldest runnable turn for one conversation. */
export const claimNextGenerationTurn = internalMutation({
  args: {
    conversationId: v.id("conversations"),
    provider: v.string(),
    model: v.string(),
  },
  returns: claimResult,
  handler: async (ctx, args) => {
    const now = Date.now();
    await requeueExpiredLeases(ctx, now);

    const activeForConversation = await ctx.db
      .query("generationTurns")
      .withIndex("by_conversation_and_status_and_queued_at", (q) =>
        q.eq("conversationId", args.conversationId).eq("status", "generating"),
      )
      .first();
    if (activeForConversation !== null) {
      // Keep a recovery wake-up alive even when streaming patches extend the
      // lease beyond the action's original watchdog time.
      return {
        kind: "wait",
        retryAfterMs: Math.max(
          1,
          (activeForConversation.leaseExpiresAt ?? now) - now + 1_000,
        ),
      } as const;
    }

    const turn = await ctx.db
      .query("generationTurns")
      .withIndex("by_conversation_and_status_and_queued_at", (q) =>
        q.eq("conversationId", args.conversationId).eq("status", "queued"),
      )
      .order("asc")
      .first();
    if (turn === null) {
      return { kind: "idle" } as const;
    }

    if (turn.notBefore > now) {
      return {
        kind: "wait",
        retryAfterMs: Math.max(1, turn.notBefore - now),
      } as const;
    }

    const activeGlobal = await ctx.db
      .query("generationTurns")
      .withIndex("by_status_and_lease_expires_at", (q) =>
        q.eq("status", "generating"),
      )
      .take(MAX_GLOBAL_CONCURRENT_GENERATIONS);
    if (activeGlobal.length >= MAX_GLOBAL_CONCURRENT_GENERATIONS) {
      return { kind: "wait", retryAfterMs: GLOBAL_SLOT_RETRY_MS } as const;
    }

    const conversation = await ctx.db.get(
      "conversations",
      turn.conversationId,
    );
    const userMessage = await ctx.db.get("messages", turn.userMessageId);
    const assistantMessage = await ctx.db.get(
      "messages",
      turn.assistantMessageId,
    );
    if (
      conversation?.agentThreadId === undefined ||
      userMessage === null ||
      assistantMessage === null
    ) {
      await cancelTurn(ctx, turn, now);
      return { kind: "wait", retryAfterMs: 1 } as const;
    }

    const attemptId = crypto.randomUUID();
    await ctx.db.patch("generationTurns", turn._id, {
      status: "generating",
      provider: args.provider,
      model: args.model,
      attemptId,
      attemptCount: turn.attemptCount + 1,
      leaseExpiresAt: now + GENERATION_LEASE_MS,
      startedAt: now,
      finishedAt: undefined,
      error: undefined,
      streamPatchCount: 0,
      outputCharacters: 0,
    });
    await ctx.db.patch("messages", assistantMessage._id, {
      text: "",
      generationStatus: "generating",
      generationError: undefined,
      generationNotBefore: undefined,
    });

    return {
      kind: "claimed",
      turnId: turn._id,
      attemptId,
      userId: turn.userId,
      conversationId: turn.conversationId,
      threadId: conversation.agentThreadId,
      agentPromptMessageId: turn.agentPromptMessageId,
      text: userMessage.text,
      attachments: userMessage.attachments,
      giphyMediaId: userMessage.giphyMediaId,
      recording: userMessage.recording,
    } as const;
  },
});

/** Applies a stream patch only while the action still owns the active lease. */
export const patchGenerationText = internalMutation({
  args: {
    turnId: v.id("generationTurns"),
    attemptId: v.string(),
    text: v.string(),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const turn = await ctx.db.get("generationTurns", args.turnId);
    if (
      turn === null ||
      turn.status !== "generating" ||
      turn.attemptId !== args.attemptId
    ) {
      return false;
    }

    const conversation = await ctx.db.get(
      "conversations",
      turn.conversationId,
    );
    const assistant = await ctx.db.get("messages", turn.assistantMessageId);
    if (conversation === null || assistant === null) {
      await cancelTurn(ctx, turn, Date.now());
      return false;
    }

    const now = Date.now();
    await ctx.db.patch("messages", assistant._id, {
      text: args.text,
      generationStatus: "generating",
    });
    await ctx.db.patch("generationTurns", turn._id, {
      leaseExpiresAt: now + GENERATION_LEASE_MS,
      streamPatchCount: turn.streamPatchCount + 1,
      outputCharacters: args.text.length,
    });
    return true;
  },
});

const usageValidator = v.object({
  inputTokens: v.number(),
  outputTokens: v.number(),
  totalTokens: v.number(),
  cacheReadTokens: v.optional(v.number()),
  cacheWriteTokens: v.optional(v.number()),
  reasoningTokens: v.optional(v.number()),
});

/** Finalizes a successful turn and records exactly one usage event. */
export const completeGenerationTurn = internalMutation({
  args: {
    turnId: v.id("generationTurns"),
    attemptId: v.string(),
    text: v.string(),
    usage: usageValidator,
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const turn = await ctx.db.get("generationTurns", args.turnId);
    if (
      turn === null ||
      turn.status !== "generating" ||
      turn.attemptId !== args.attemptId
    ) {
      return false;
    }

    const conversation = await ctx.db.get(
      "conversations",
      turn.conversationId,
    );
    const assistant = await ctx.db.get("messages", turn.assistantMessageId);
    if (conversation === null || assistant === null) {
      await cancelTurn(ctx, turn, Date.now());
      return false;
    }

    const now = Date.now();
    await ctx.db.patch("messages", assistant._id, {
      text: args.text,
      generationStatus: "completed",
      generationError: undefined,
      generationNotBefore: undefined,
    });
    await ctx.db.patch("generationTurns", turn._id, {
      status: "completed",
      attemptId: undefined,
      leaseExpiresAt: undefined,
      finishedAt: now,
      error: undefined,
      outputCharacters: args.text.length,
    });
    await ctx.db.patch("conversations", conversation._id, {
      lastMessageAt: now,
    });

    const existingUsage = await ctx.db
      .query("llmUsageEvents")
      .withIndex("by_turn_id", (q) => q.eq("turnId", turn._id))
      .unique();
    if (existingUsage === null) {
      await ctx.db.insert("llmUsageEvents", {
        turnId: turn._id,
        conversationId: turn.conversationId,
        userId: turn.userId,
        provider: turn.provider ?? "unknown",
        model: turn.model ?? "unknown",
        ...args.usage,
        createdAt: now,
      });
    }
    return true;
  },
});

async function persistGenerationFailure(
  ctx: MutationCtx,
  turn: Doc<"generationTurns">,
  assistant: Doc<"messages">,
  error: Doc<"generationTurns">["error"],
  now: number,
  partialText?: string,
) {
  if (error === undefined) {
    throw new Error("A generation failure requires a structured error");
  }
  await ctx.db.patch("messages", assistant._id, {
    ...(partialText === undefined ? {} : { text: partialText }),
    generationStatus: "failed",
    generationError: error,
    generationNotBefore: undefined,
  });
  await ctx.db.patch("generationTurns", turn._id, {
    status: "failed",
    attemptId: undefined,
    leaseExpiresAt: undefined,
    finishedAt: now,
    error,
    ...(partialText === undefined
      ? {}
      : { outputCharacters: partialText.length }),
  });
}

/**
 * Retries only classified transient failures that happened before any output.
 * A partial stream is surfaced intact instead of replaying and overwriting it.
 */
export const handleGenerationFailure = internalMutation({
  args: {
    turnId: v.id("generationTurns"),
    attemptId: v.string(),
    error: generationError,
    partialText: v.string(),
  },
  returns: failureResolution,
  handler: async (ctx, args) => {
    const turn = await ctx.db.get("generationTurns", args.turnId);
    if (
      turn === null ||
      turn.status !== "generating" ||
      turn.attemptId !== args.attemptId
    ) {
      return { kind: "stale" } as const;
    }

    const now = Date.now();
    const conversation = await ctx.db.get(
      "conversations",
      turn.conversationId,
    );
    const assistant = await ctx.db.get("messages", turn.assistantMessageId);
    if (conversation === null || assistant === null) {
      await cancelTurn(ctx, turn, now);
      return { kind: "stale" } as const;
    }

    const exponentialDelay = Math.min(
      INITIAL_AUTOMATIC_RETRY_MS * 2 ** Math.max(0, turn.attemptCount - 1),
      MAX_AUTOMATIC_RETRY_DELAY_MS,
    );
    const retryAfterMs = Math.max(
      exponentialDelay,
      args.error.retryAfterMs ?? 0,
    );
    const canRetryAutomatically =
      args.error.retryable &&
      args.partialText.length === 0 &&
      turn.attemptCount < MAX_AUTOMATIC_ATTEMPTS &&
      retryAfterMs <= MAX_AUTOMATIC_RETRY_DELAY_MS;

    if (canRetryAutomatically) {
      const notBefore = now + retryAfterMs;
      await ctx.db.patch("generationTurns", turn._id, {
        status: "queued",
        notBefore,
        attemptId: undefined,
        leaseExpiresAt: undefined,
        finishedAt: undefined,
        error: undefined,
      });
      await ctx.db.patch("messages", assistant._id, {
        text: "",
        generationStatus: "queued",
        generationError: undefined,
        generationNotBefore: notBefore,
      });
      return { kind: "requeued", retryAfterMs } as const;
    }

    await persistGenerationFailure(
      ctx,
      turn,
      assistant,
      args.error,
      now,
      args.partialText,
    );
    await ctx.db.patch("conversations", conversation._id, {
      lastMessageAt: now,
    });
    return { kind: "failed" } as const;
  },
});

/** Persists a structured failure without masquerading as assistant prose. */
export const failGenerationTurn = internalMutation({
  args: {
    turnId: v.id("generationTurns"),
    attemptId: v.string(),
    error: generationError,
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const turn = await ctx.db.get("generationTurns", args.turnId);
    if (
      turn === null ||
      turn.status !== "generating" ||
      turn.attemptId !== args.attemptId
    ) {
      return false;
    }
    const now = Date.now();
    const conversation = await ctx.db.get(
      "conversations",
      turn.conversationId,
    );
    const assistant = await ctx.db.get("messages", turn.assistantMessageId);
    if (conversation === null || assistant === null) {
      await cancelTurn(ctx, turn, now);
      return false;
    }

    await persistGenerationFailure(ctx, turn, assistant, args.error, now);
    await ctx.db.patch("conversations", conversation._id, {
      lastMessageAt: now,
    });
    return true;
  },
});

/** Handles invalid provider configuration before a turn can be claimed. */
export const failNextQueuedTurn = internalMutation({
  args: {
    conversationId: v.id("conversations"),
    error: generationError,
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const turn = await ctx.db
      .query("generationTurns")
      .withIndex("by_conversation_and_status_and_queued_at", (q) =>
        q.eq("conversationId", args.conversationId).eq("status", "queued"),
      )
      .order("asc")
      .first();
    if (turn === null) {
      return false;
    }
    const now = Date.now();
    await ctx.db.patch("generationTurns", turn._id, {
      status: "failed",
      finishedAt: now,
      error: args.error,
    });
    const assistant = await ctx.db.get("messages", turn.assistantMessageId);
    if (assistant !== null) {
      await ctx.db.patch("messages", assistant._id, {
        generationStatus: "failed",
        generationError: args.error,
        generationNotBefore: undefined,
      });
    }
    return true;
  },
});

/** Requeues a failed turn after the public mutation has re-authorized it. */
export async function requeueFailedTurn(
  ctx: MutationCtx,
  turn: Doc<"generationTurns">,
  notBefore: number,
): Promise<void> {
  if (turn.status !== "failed" || turn.error?.retryable !== true) {
    throw new Error("Generation turn is not retryable");
  }
  await ctx.db.patch("generationTurns", turn._id, {
    status: "queued",
    queuedAt: Date.now(),
    notBefore,
    attemptId: undefined,
    leaseExpiresAt: undefined,
    finishedAt: undefined,
    error: undefined,
  });
  const assistant = await ctx.db.get("messages", turn.assistantMessageId);
  if (assistant === null) {
    throw new Error("Assistant message no longer exists");
  }
  await ctx.db.patch("messages", assistant._id, {
    text: "",
    generationStatus: "queued",
    generationError: undefined,
    generationNotBefore: notBefore,
  });
}

/** Invalidates active attempts before batched conversation deletion begins. */
export async function cancelActiveTurnsForConversation(
  ctx: MutationCtx,
  conversationId: Id<"conversations">,
): Promise<void> {
  const now = Date.now();
  for (const status of ["queued", "generating"] as const) {
    const turns = await ctx.db
      .query("generationTurns")
      .withIndex("by_conversation_and_status_and_queued_at", (q) =>
        q.eq("conversationId", conversationId).eq("status", status),
      )
      .take(100);
    for (const turn of turns) {
      await cancelTurn(ctx, turn, now);
    }
  }
}
