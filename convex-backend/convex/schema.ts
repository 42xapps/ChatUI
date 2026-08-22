import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/** Mirrors `ExyteChat.AttachmentType`. */
export const attachmentType = v.union(v.literal("image"), v.literal("video"));

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
  })
    .index("by_user", ["userId"])
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
    .index("by_client_id", ["clientId"]),
});
