import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/** Mirrors `ExyteChat.AttachmentType`. */
export const attachmentType = v.union(v.literal("image"), v.literal("video"));

/** What a presigned R2 upload is expected to contain. */
export const uploadKind = v.union(
  v.literal("image"),
  v.literal("video"),
  v.literal("videoThumbnail"),
  v.literal("recording"),
);

/** Lifecycle mirrored onto an assistant message for the native client. */
export const generationStatus = v.union(
  v.literal("queued"),
  v.literal("generating"),
  v.literal("completed"),
  v.literal("failed"),
  v.literal("cancelled"),
);

export const generationErrorCode = v.union(
  v.literal("provider_configuration"),
  v.literal("provider_authentication"),
  v.literal("provider_billing"),
  v.literal("provider_rate_limited"),
  v.literal("provider_unavailable"),
  v.literal("timeout"),
  v.literal("unsupported_media"),
  v.literal("generation_failed"),
);

/** Safe, user-facing failure information. Provider response bodies stay out. */
export const generationError = v.object({
  code: generationErrorCode,
  message: v.string(),
  retryable: v.boolean(),
  retryAfterMs: v.optional(v.number()),
});

/**
 * An attachment as it is stored: R2 object keys only.
 *
 * Absolute URLs are never persisted — they are derived from the keys on read
 * (see `model/attachments.ts`), so rotating the R2 bucket or switching between
 * a proxied and a CDN-backed URL scheme doesn't require a data migration.
 *
 * `thumbR2Key` equals `r2Key` for images; videos upload a separate thumbnail.
 */
export const storedAttachment = v.object({
  type: attachmentType,
  r2Key: v.string(),
  thumbR2Key: v.string(),
});

/** A voice note. `waveformSamples` drives the static waveform in the bubble. */
export const storedRecording = v.object({
  duration: v.number(),
  waveformSamples: v.array(v.number()),
  r2Key: v.string(),
});

export default defineSchema({
  /**
   * One row per Clerk user, created lazily on the first authenticated write
   * (see `users.syncCurrentUser`).
   *
   * `tokenIdentifier` (`issuer|subject`) is the indexed identity key, because
   * it is the only field guaranteed unique across issuers. `clerkId` is the raw
   * `sub` claim, kept because it's what Clerk's own APIs take.
   */
  users: defineTable({
    tokenIdentifier: v.string(),
    clerkId: v.string(),
    name: v.string(),
    avatarUrl: v.optional(v.string()),
    email: v.optional(v.string()),
  }).index("by_token_identifier", ["tokenIdentifier"]),

  /**
   * A chat thread. A user can have many — the sidebar's chat history lists
   * every conversation they're a member of, most recently active first.
   */
  conversations: defineTable({
    /**
     * Unset until the first message lands (see `deriveTitle` in
     * `model/conversations.ts`), the same way ChatGPT titles a chat from its
     * opening message rather than asking upfront.
     */
    title: v.optional(v.string()),
    createdAt: v.number(),
    createdBy: v.id("users"),
    /** Internal Agent component thread used only for LLM context/history. */
    agentThreadId: v.optional(v.string()),
    /**
     * Denormalized onto the conversation (rather than computed by scanning
     * its messages) so `conversations.listMine` can sort by recency in one
     * pass over a user's membership rows. Updated by `messages.send`.
     */
    lastMessageAt: v.number(),
  }),

  /**
   * Join table between `users` and `conversations`. This is what scopes chat
   * history per user: `by_user` is the only way the client reaches a
   * conversation, and `by_conversation_and_user` is the membership check that
   * `messages.send` runs before accepting a write.
   */
  conversationMembers: defineTable({
    conversationId: v.id("conversations"),
    userId: v.id("users"),
    /** Optional while existing rows are backfilled. */
    lastMessageAt: v.optional(v.number()),
  })
    .index("by_user", ["userId"])
    .index("by_user_and_last_message_at", ["userId", "lastMessageAt"])
    .index("by_conversation_and_user", ["conversationId", "userId"]),

  messages: defineTable({
    conversationId: v.id("conversations"),
    /**
     * Client-generated id, and the id the iOS app uses for a message end to
     * end. The sender inserts a local message with this id and `.sending`
     * status, then reconciles against the server copy when it arrives with the
     * same id. Also makes `messages.send` idempotent under retry.
     */
    clientId: v.string(),
    senderId: v.id("users"),
    text: v.string(),
    attachments: v.array(storedAttachment),
    /** Giphy GIFs are referenced by media id — nothing is uploaded to R2. */
    giphyMediaId: v.optional(v.string()),
    recording: v.optional(storedRecording),
    replyTo: v.optional(v.id("messages")),
    /** Present only on companion-authored messages. */
    generationTurnId: v.optional(v.id("generationTurns")),
    generationStatus: v.optional(generationStatus),
    generationError: v.optional(generationError),
    generationNotBefore: v.optional(v.number()),
    /**
     * Compose-time clock of the sender's device. Kept for display/debugging
     * only — a skewed device clock, or a message composed offline and sent
     * after reconnecting, would otherwise misorder it. Ordering and
     * pagination use Convex's own monotonic `_creationTime` instead (see
     * `by_conversation` below and `messages.listForConversation`).
     */
    createdAt: v.number(),
  })
    // Single-field index: within a matching `conversationId`, `.order()`
    // falls back to `_creationTime`, which is what `listForConversation`
    // relies on for a correct, clock-skew-proof chronological order.
    .index("by_conversation", ["conversationId"])
    .index("by_conversation_and_client_id", ["conversationId", "clientId"]),

  /**
   * Durable orchestration record for one user-message -> companion-response
   * turn. Attempt IDs and leases make delayed or stale actions harmless.
   */
  generationTurns: defineTable({
    conversationId: v.id("conversations"),
    userId: v.id("users"),
    userMessageId: v.id("messages"),
    assistantMessageId: v.id("messages"),
    agentPromptMessageId: v.string(),
    status: generationStatus,
    queuedAt: v.number(),
    notBefore: v.number(),
    attemptCount: v.number(),
    estimatedTokens: v.number(),
    provider: v.optional(v.string()),
    model: v.optional(v.string()),
    attemptId: v.optional(v.string()),
    leaseExpiresAt: v.optional(v.number()),
    startedAt: v.optional(v.number()),
    finishedAt: v.optional(v.number()),
    error: v.optional(generationError),
    /** Bounded counters used to measure bridge write amplification. */
    streamPatchCount: v.number(),
    outputCharacters: v.number(),
  })
    .index("by_conversation_and_status_and_queued_at", [
      "conversationId",
      "status",
      "queuedAt",
    ])
    .index("by_status_and_lease_expires_at", ["status", "leaseExpiresAt"])
    .index("by_assistant_message_id", ["assistantMessageId"])
    .index("by_user_message_id", ["userMessageId"]),

  /** Append-only provider usage suitable for product and cost reporting. */
  llmUsageEvents: defineTable({
    turnId: v.id("generationTurns"),
    conversationId: v.id("conversations"),
    userId: v.id("users"),
    provider: v.string(),
    model: v.string(),
    inputTokens: v.number(),
    outputTokens: v.number(),
    totalTokens: v.number(),
    cacheReadTokens: v.optional(v.number()),
    cacheWriteTokens: v.optional(v.number()),
    reasoningTokens: v.optional(v.number()),
    createdAt: v.number(),
  })
    .index("by_user_and_created_at", ["userId", "createdAt"])
    .index("by_conversation_and_created_at", ["conversationId", "createdAt"])
    .index("by_turn_id", ["turnId"]),

  /**
   * Ownership and lifecycle record for every object uploaded directly to R2.
   * The access token is revocable; knowing an object key alone is insufficient
   * to mint a download URL.
   */
  mediaAssets: defineTable({
    r2Key: v.string(),
    accessToken: v.string(),
    kind: uploadKind,
    userId: v.id("users"),
    conversationId: v.id("conversations"),
    createdAt: v.number(),
    claimedMessageId: v.optional(v.id("messages")),
    claimedAt: v.optional(v.number()),
  })
    .index("by_r2_key", ["r2Key"])
    .index("by_conversation_and_created_at", ["conversationId", "createdAt"])
    .index("by_claimed_message_id", ["claimedMessageId"]),
});
