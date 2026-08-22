import { ConvexError } from "convex/values";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";

/** Mirrors `conversationSummary` in `conversations.ts`. */
export function toSummary(conversation: Doc<"conversations">) {
  return {
    _id: conversation._id,
    title: conversation.title,
    lastMessageAt: conversation.lastMessageAt,
  };
}

const MAX_TITLE_LENGTH = 40;

/**
 * A ChatGPT-style title derived from a conversation's first message, since
 * there's no LLM yet to generate a real one. Falls back to describing the
 * message's kind for a text-less first message (an image, a voice note, a
 * GIF), and to a generic label if even that isn't available.
 */
export function deriveTitle(message: {
  text: string;
  attachments: unknown[];
  giphyMediaId?: string;
  recording?: unknown;
}): string {
  const trimmed = message.text.trim();
  if (trimmed.length > 0) {
    return trimmed.length > MAX_TITLE_LENGTH
      ? `${trimmed.slice(0, MAX_TITLE_LENGTH).trimEnd()}…`
      : trimmed;
  }
  if (message.attachments.length > 0) return "Photo";
  if (message.recording !== undefined) return "Voice message";
  if (message.giphyMediaId !== undefined) return "GIF";
  return "New chat";
}

/**
 * The caller's membership row, or `null` if they aren't in the conversation.
 *
 * Every read and write path goes through this: it is the server-side
 * replacement for the reference app's client-side `array-contains` filter.
 */
export async function membership(
  ctx: QueryCtx,
  conversationId: Id<"conversations">,
  userId: Id<"users">,
): Promise<Doc<"conversationMembers"> | null> {
  return await ctx.db
    .query("conversationMembers")
    .withIndex("by_conversation_and_user", (q) =>
      q.eq("conversationId", conversationId).eq("userId", userId),
    )
    .unique();
}

/** Like `membership`, but throws for non-members. */
export async function requireMembership(
  ctx: QueryCtx,
  conversationId: Id<"conversations">,
  userId: Id<"users">,
): Promise<Doc<"conversationMembers">> {
  const member = await membership(ctx, conversationId, userId);
  if (member === null) {
    throw new ConvexError("Not a member of this conversation");
  }
  return member;
}

/** Every conversation `userId` belongs to, most recently active first. */
export async function listForUser(ctx: QueryCtx, userId: Id<"users">) {
  const memberships = await ctx.db
    .query("conversationMembers")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect();

  const conversations = await Promise.all(
    memberships.map((membership) =>
      ctx.db.get("conversations", membership.conversationId),
    ),
  );

  return conversations
    .filter((conversation): conversation is Doc<"conversations"> => conversation !== null)
    .sort((a, b) => b.lastMessageAt - a.lastMessageAt)
    .map(toSummary);
}

/** Starts a brand new, empty conversation for `userId` — a "New Chat". */
export async function createForUser(
  ctx: MutationCtx,
  userId: Id<"users">,
): Promise<Id<"conversations">> {
  const now = Date.now();
  const conversationId = await ctx.db.insert("conversations", {
    createdAt: now,
    createdBy: userId,
    lastMessageAt: now,
  });
  await ctx.db.insert("conversationMembers", { conversationId, userId });
  return conversationId;
}

/**
 * Deletes a conversation, its membership rows, and all of its messages.
 *
 * Does not delete the R2 objects any deleted messages referenced — that
 * needs an action calling R2's delete API, deliberately left for a follow-up
 * rather than folded in here half-finished. Documented, not silent: those
 * objects become unreferenced but keep costing (small amounts of) storage.
 */
export async function deleteConversation(
  ctx: MutationCtx,
  conversationId: Id<"conversations">,
): Promise<void> {
  const messages = await ctx.db
    .query("messages")
    .withIndex("by_conversation", (q) => q.eq("conversationId", conversationId))
    .collect();
  for (const message of messages) {
    await ctx.db.delete("messages", message._id);
  }

  const members = await ctx.db
    .query("conversationMembers")
    .withIndex("by_conversation_and_user", (q) =>
      q.eq("conversationId", conversationId),
    )
    .collect();
  for (const member of members) {
    await ctx.db.delete("conversationMembers", member._id);
  }

  await ctx.db.delete("conversations", conversationId);
}
