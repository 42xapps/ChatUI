import { saveMessage } from "@convex-dev/agent";
import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { ConvexError, v } from "convex/values";
import { components, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { claimMessageAssets } from "./model/attachments";
import {
  deriveTitle,
  getOrCreateAgentThreadId,
  requireMembership,
} from "./model/conversations";
import { requeueFailedTurn } from "./model/generationTurns";
import {
  messageByClientId,
  resolveMessage,
  resolvedMessage,
} from "./model/messages";
import {
  getOrCreateCompanionUser,
  requireCurrentUser,
} from "./model/users";
import { rateLimiter } from "./rateLimiting";
import { storedAttachment, storedRecording } from "./schema";

const MAX_TEXT_LENGTH = 8_000;
const MAX_ATTACHMENTS_PER_MESSAGE = 10;
const MAX_WAVEFORM_SAMPLES = 512;
// The iOS client deliberately grows one reactive recent-message window instead
// of stitching cursor pages. Keep that strategy bounded while still allowing a
// long-running conversation to load substantially more than its first page.
const MAX_MESSAGE_PAGE_SIZE = 1_000;
const MAX_OUTPUT_TOKEN_RESERVATION = 600;

const rateLimitScope = v.union(
  v.literal("user_messages"),
  v.literal("global_messages"),
  v.literal("user_tokens"),
  v.literal("global_tokens"),
);

export const sendResult = v.union(
  v.object({
    status: v.literal("accepted"),
    duplicate: v.boolean(),
    assistantClientId: v.optional(v.string()),
    queuedUntil: v.optional(v.number()),
  }),
  v.object({
    status: v.literal("rate_limited"),
    scope: rateLimitScope,
    retryAfterMs: v.number(),
  }),
);

type RateLimitScope =
  | "user_messages"
  | "global_messages"
  | "user_tokens"
  | "global_tokens";

type Admission =
  | { status: "accepted"; retryAfterMs: number }
  | { status: "rate_limited"; scope: RateLimitScope; retryAfterMs: number };

function estimateTurnTokens(args: {
  text: string;
  attachments: Array<{ type: "image" | "video" }>;
  giphyMediaId?: string;
  recording?: unknown;
}) {
  const textTokens = Math.ceil(args.text.length / 4);
  const mediaTokens =
    args.attachments.reduce(
      (total, attachment) =>
        total + (attachment.type === "image" ? 1_200 : 2_000),
      0,
    ) +
    (args.giphyMediaId === undefined ? 0 : 1_200) +
    (args.recording === undefined ? 0 : 2_000);
  return textTokens + mediaTokens + MAX_OUTPUT_TOKEN_RESERVATION;
}

function agentPrompt(args: {
  text: string;
  attachments: Array<{ type: "image" | "video" }>;
  giphyMediaId?: string;
  recording?: unknown;
}) {
  const parts: string[] = [];
  const text = args.text.trim();
  if (text !== "") parts.push(text);

  const imageCount = args.attachments.filter(
    (attachment) => attachment.type === "image",
  ).length;
  const videoCount = args.attachments.length - imageCount;
  if (imageCount > 0) {
    parts.push(`[The user attached ${imageCount} image${imageCount === 1 ? "" : "s"}.]`);
  }
  if (videoCount > 0) {
    parts.push(
      `[The user attached ${videoCount} video${videoCount === 1 ? "" : "s"}; video understanding is not configured.]`,
    );
  }
  if (args.giphyMediaId !== undefined) parts.push("[The user shared a GIF.]");
  if (args.recording !== undefined) {
    parts.push(
      "[The user shared a voice recording; it has not been transcribed, so do not pretend to hear it.]",
    );
  }
  return parts.join("\n\n");
}

async function generationAdmission(
  ctx: MutationCtx,
  userId: Id<"users">,
  estimatedTokens: number,
): Promise<Admission> {
  const checks = [
    {
      scope: "user_messages" as const,
      status: await rateLimiter.check(ctx, "sendMessage", { key: userId }),
    },
    {
      scope: "global_messages" as const,
      status: await rateLimiter.check(ctx, "globalSendMessage"),
    },
    {
      scope: "user_tokens" as const,
      status: await rateLimiter.check(ctx, "tokenUsagePerUser", {
        key: userId,
        count: estimatedTokens,
        reserve: true,
      }),
    },
    {
      scope: "global_tokens" as const,
      status: await rateLimiter.check(ctx, "globalTokenUsage", {
        count: estimatedTokens,
        reserve: true,
      }),
    },
  ];

  for (const check of checks) {
    if (!check.status.ok) {
      return {
        status: "rate_limited",
        scope: check.scope,
        retryAfterMs: check.status.retryAfter,
      };
    }
  }

  const userMessage = await rateLimiter.limit(ctx, "sendMessage", {
    key: userId,
  });
  const globalMessage = await rateLimiter.limit(ctx, "globalSendMessage");
  const userTokens = await rateLimiter.limit(ctx, "tokenUsagePerUser", {
    key: userId,
    count: estimatedTokens,
    reserve: true,
  });
  const globalTokens = await rateLimiter.limit(ctx, "globalTokenUsage", {
    count: estimatedTokens,
    reserve: true,
  });

  // The preceding checks and these consumes share the parent transaction. If
  // concurrent admission changes a bucket, Convex retries this transaction.
  for (const [scope, status] of [
    ["user_messages", userMessage],
    ["global_messages", globalMessage],
    ["user_tokens", userTokens],
    ["global_tokens", globalTokens],
  ] as const) {
    if (!status.ok) {
      throw new ConvexError(`Rate limit changed during admission: ${scope}`);
    }
  }

  return {
    status: "accepted",
    retryAfterMs: Math.max(
      userTokens.retryAfter ?? 0,
      globalTokens.retryAfter ?? 0,
    ),
  };
}

/** One reactive, membership-scoped page ordered oldest-to-newest. */
export const listForConversation = query({
  args: {
    conversationId: v.id("conversations"),
    paginationOpts: paginationOptsValidator,
  },
  returns: paginationResultValidator(resolvedMessage),
  handler: async (ctx, args) => {
    const viewer = await requireCurrentUser(ctx);
    await requireMembership(ctx, args.conversationId, viewer._id);
    if (args.paginationOpts.numItems > MAX_MESSAGE_PAGE_SIZE) {
      throw new ConvexError(
        `Message page size cannot exceed ${MAX_MESSAGE_PAGE_SIZE}`,
      );
    }

    const result = await ctx.db
      .query("messages")
      .withIndex("by_conversation", (q) =>
        q.eq("conversationId", args.conversationId),
      )
      .order("desc")
      .paginate(args.paginationOpts);

    const page = [];
    for (const message of result.page) {
      const resolved = await resolveMessage(ctx, message);
      if (resolved !== null) page.push(resolved);
    }
    return { ...result, page: page.reverse() };
  },
});

/**
 * Atomically persists the user message, Agent prompt, assistant placeholder,
 * queued generation turn, upload claims, and schedule entry.
 */
export const send = mutation({
  args: {
    conversationId: v.id("conversations"),
    clientId: v.string(),
    text: v.string(),
    attachments: v.array(storedAttachment),
    giphyMediaId: v.optional(v.string()),
    recording: v.optional(storedRecording),
    replyToClientId: v.optional(v.string()),
    createdAt: v.number(),
  },
  returns: sendResult,
  handler: async (ctx, args) => {
    const viewer = await requireCurrentUser(ctx);
    const membership = await requireMembership(
      ctx,
      args.conversationId,
      viewer._id,
    );
    const conversation = await ctx.db.get(
      "conversations",
      args.conversationId,
    );
    if (conversation === null) {
      throw new ConvexError("Conversation no longer exists");
    }

    if (args.text.length > MAX_TEXT_LENGTH) {
      throw new ConvexError(`Message text exceeds ${MAX_TEXT_LENGTH} characters`);
    }
    if (args.attachments.length > MAX_ATTACHMENTS_PER_MESSAGE) {
      throw new ConvexError(
        `A message can have at most ${MAX_ATTACHMENTS_PER_MESSAGE} attachments`,
      );
    }
    if (
      args.recording !== undefined &&
      args.recording.waveformSamples.length > MAX_WAVEFORM_SAMPLES
    ) {
      throw new ConvexError(
        `A recording can have at most ${MAX_WAVEFORM_SAMPLES} waveform samples`,
      );
    }
    if (
      args.text.trim() === "" &&
      args.attachments.length === 0 &&
      args.giphyMediaId === undefined &&
      args.recording === undefined
    ) {
      throw new ConvexError("A message must contain text or media");
    }

    const duplicate = await messageByClientId(
      ctx,
      args.conversationId,
      args.clientId,
    );
    if (duplicate !== null) {
      const turn = await ctx.db
        .query("generationTurns")
        .withIndex("by_user_message_id", (q) =>
          q.eq("userMessageId", duplicate._id),
        )
        .unique();
      const assistant =
        turn === null
          ? null
          : await ctx.db.get("messages", turn.assistantMessageId);
      return {
        status: "accepted",
        duplicate: true,
        assistantClientId: assistant?.clientId,
        queuedUntil: turn?.notBefore,
      } as const;
    }

    const estimatedTokens = estimateTurnTokens(args);
    const admission = await generationAdmission(
      ctx,
      viewer._id,
      estimatedTokens,
    );
    if (admission.status === "rate_limited") return admission;

    let replyTo = undefined;
    if (args.replyToClientId !== undefined) {
      const parent = await messageByClientId(
        ctx,
        args.conversationId,
        args.replyToClientId,
      );
      if (parent === null) {
        throw new ConvexError("Replied-to message is not in this conversation");
      }
      replyTo = parent._id;
    }

    const userMessageId = await ctx.db.insert("messages", {
      conversationId: args.conversationId,
      clientId: args.clientId,
      senderId: viewer._id,
      text: args.text,
      attachments: args.attachments,
      giphyMediaId: args.giphyMediaId,
      recording: args.recording,
      replyTo,
      createdAt: args.createdAt,
    });
    await claimMessageAssets(ctx, {
      userId: viewer._id,
      conversationId: args.conversationId,
      messageId: userMessageId,
      attachments: args.attachments,
      recording: args.recording,
    });

    const threadId = await getOrCreateAgentThreadId(ctx, args.conversationId);
    const { messageId: agentPromptMessageId } = await saveMessage(
      ctx,
      components.agent,
      {
        threadId,
        userId: viewer._id,
        prompt: agentPrompt(args),
      },
    );

    const now = Date.now();
    const notBefore = now + admission.retryAfterMs;
    const companion = await getOrCreateCompanionUser(ctx);
    const assistantClientId = crypto.randomUUID();
    const assistantMessageId = await ctx.db.insert("messages", {
      conversationId: args.conversationId,
      clientId: assistantClientId,
      senderId: companion._id,
      text: "",
      attachments: [],
      createdAt: now,
      generationStatus: "queued",
      ...(notBefore > now ? { generationNotBefore: notBefore } : {}),
    });
    const turnId = await ctx.db.insert("generationTurns", {
      conversationId: args.conversationId,
      userId: viewer._id,
      userMessageId,
      assistantMessageId,
      agentPromptMessageId,
      status: "queued",
      queuedAt: now,
      notBefore,
      attemptCount: 0,
      estimatedTokens,
      streamPatchCount: 0,
      outputCharacters: 0,
    });
    await ctx.db.patch("messages", assistantMessageId, {
      generationTurnId: turnId,
    });

    await ctx.db.patch("conversations", args.conversationId, {
      lastMessageAt: now,
      ...(conversation.title === undefined ? { title: deriveTitle(args) } : {}),
    });
    await ctx.db.patch("conversationMembers", membership._id, {
      lastMessageAt: now,
    });
    await ctx.scheduler.runAfter(
      admission.retryAfterMs,
      internal.ai.processConversationQueue,
      { conversationId: args.conversationId },
    );

    return {
      status: "accepted",
      duplicate: false,
      assistantClientId,
      ...(notBefore > now ? { queuedUntil: notBefore } : {}),
    } as const;
  },
});

/** Requeues the same failed assistant row without duplicating the user prompt. */
export const retryGeneration = mutation({
  args: {
    conversationId: v.id("conversations"),
    assistantClientId: v.string(),
  },
  returns: sendResult,
  handler: async (ctx, args) => {
    const viewer = await requireCurrentUser(ctx);
    await requireMembership(ctx, args.conversationId, viewer._id);
    const assistant = await messageByClientId(
      ctx,
      args.conversationId,
      args.assistantClientId,
    );
    if (assistant === null) {
      throw new ConvexError("Assistant message no longer exists");
    }
    const turn = await ctx.db
      .query("generationTurns")
      .withIndex("by_assistant_message_id", (q) =>
        q.eq("assistantMessageId", assistant._id),
      )
      .unique();
    if (
      turn === null ||
      turn.userId !== viewer._id ||
      turn.status !== "failed" ||
      turn.error?.retryable !== true
    ) {
      throw new ConvexError("This companion reply cannot be retried");
    }

    const admission = await generationAdmission(
      ctx,
      viewer._id,
      turn.estimatedTokens,
    );
    if (admission.status === "rate_limited") return admission;

    const notBefore = Date.now() + admission.retryAfterMs;
    await requeueFailedTurn(ctx, turn, notBefore);
    await ctx.scheduler.runAfter(
      admission.retryAfterMs,
      internal.ai.processConversationQueue,
      { conversationId: args.conversationId },
    );
    return {
      status: "accepted",
      duplicate: false,
      assistantClientId: assistant.clientId,
      ...(admission.retryAfterMs > 0 ? { queuedUntil: notBefore } : {}),
    } as const;
  },
});
