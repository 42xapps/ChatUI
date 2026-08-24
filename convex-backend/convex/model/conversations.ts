import { createThread, saveMessage } from "@convex-dev/agent";
import { paginationOptsValidator } from "convex/server";
import { ConvexError, v } from "convex/values";
import { components, internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import { internalMutation } from "../_generated/server";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { deleteConversationAssetsBatch } from "./attachments";
import { cancelActiveTurnsForConversation } from "./generationTurns";
import { getOrCreateCompanionUser } from "./users";

const DELETE_BATCH_SIZE = 100;
const MAX_RECENT_CONVERSATIONS = 100;
const INITIAL_GREETING = "Hi, I’m Embie. What’s on your mind today?";

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
    .withIndex("by_user_and_last_message_at", (q) => q.eq("userId", userId))
    .order("desc")
    .take(MAX_RECENT_CONVERSATIONS);

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

/** Starts a brand new conversation with Embie's deterministic greeting. */
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
  const threadId = await createThread(ctx, components.agent, { userId });
  await ctx.db.patch("conversations", conversationId, {
    agentThreadId: threadId,
  });
  await ctx.db.insert("conversationMembers", {
    conversationId,
    userId,
    lastMessageAt: now,
  });

  const companion = await getOrCreateCompanionUser(ctx);
  await ctx.db.insert("messages", {
    conversationId,
    clientId: crypto.randomUUID(),
    senderId: companion._id,
    text: INITIAL_GREETING,
    attachments: [],
    generationStatus: "completed",
    createdAt: now,
  });
  await saveMessage(ctx, components.agent, {
    threadId,
    userId,
    message: { role: "assistant", content: INITIAL_GREETING },
  });
  return conversationId;
}

/** Lazily links an app conversation to its internal Agent history thread. */
export async function getOrCreateAgentThreadId(
  ctx: MutationCtx,
  conversationId: Id<"conversations">,
): Promise<string> {
  const conversation = await ctx.db.get("conversations", conversationId);
  if (conversation === null) {
    throw new ConvexError("Conversation no longer exists");
  }
  if (conversation.agentThreadId !== undefined) {
    return conversation.agentThreadId;
  }

  const threadId = await createThread(ctx, components.agent, {
    userId: conversation.createdBy,
    ...(conversation.title === undefined ? {} : { title: conversation.title }),
  });
  await ctx.db.patch("conversations", conversationId, { agentThreadId: threadId });
  return threadId;
}

/**
 * Deletes a conversation, its Agent thread, generation/usage rows, messages,
 * memberships, and every tracked R2 object in bounded continuation batches.
 */
export async function deleteConversation(
  ctx: MutationCtx,
  conversationId: Id<"conversations">,
): Promise<void> {
  const conversation = await ctx.db.get("conversations", conversationId);
  await cancelActiveTurnsForConversation(ctx, conversationId);
  if (conversation?.agentThreadId !== undefined) {
    // This is Agent.deleteThreadAsync's underlying component call. Importing
    // the Node-only companion Agent into a mutation would violate runtimes.
    await ctx.runMutation(components.agent.threads.deleteAllForThreadIdAsync, {
      threadId: conversation.agentThreadId,
    });
  }

  await deleteConversationBatch(ctx, conversationId);
}

async function deleteConversationBatch(
  ctx: MutationCtx,
  conversationId: Id<"conversations">,
): Promise<void> {
  const moreAssets = await deleteConversationAssetsBatch(ctx, conversationId);

  const usageEvents = await ctx.db
    .query("llmUsageEvents")
    .withIndex("by_conversation_and_created_at", (q) =>
      q.eq("conversationId", conversationId),
    )
    .take(DELETE_BATCH_SIZE);
  for (const event of usageEvents) {
    await ctx.db.delete("llmUsageEvents", event._id);
  }

  const turns = await ctx.db
    .query("generationTurns")
    .withIndex("by_conversation_and_status_and_queued_at", (q) =>
      q.eq("conversationId", conversationId),
    )
    .take(DELETE_BATCH_SIZE);
  for (const turn of turns) {
    await ctx.db.delete("generationTurns", turn._id);
  }

  const messages = await ctx.db
    .query("messages")
    .withIndex("by_conversation", (q) => q.eq("conversationId", conversationId))
    .take(DELETE_BATCH_SIZE);
  for (const message of messages) {
    await ctx.db.delete("messages", message._id);
  }

  const members = await ctx.db
    .query("conversationMembers")
    .withIndex("by_conversation_and_user", (q) =>
      q.eq("conversationId", conversationId),
    )
    .take(DELETE_BATCH_SIZE);
  for (const member of members) {
    await ctx.db.delete("conversationMembers", member._id);
  }

  if (
    moreAssets ||
    usageEvents.length === DELETE_BATCH_SIZE ||
    turns.length === DELETE_BATCH_SIZE ||
    messages.length === DELETE_BATCH_SIZE ||
    members.length === DELETE_BATCH_SIZE
  ) {
    const scheduledId: Id<"_scheduled_functions"> =
      await ctx.scheduler.runAfter(
        0,
        internal.model.conversations.continueDeleteConversation,
        { conversationId },
      );
    void scheduledId;
    return;
  }

  await ctx.db.delete("conversations", conversationId);
}

/** Continues bounded cleanup for conversations too large for one mutation. */
export const continueDeleteConversation = internalMutation({
  args: { conversationId: v.id("conversations") },
  returns: v.null(),
  handler: async (ctx, { conversationId }) => {
    await deleteConversationBatch(ctx, conversationId);
    return null;
  },
});

/** One-time rollout helper for the sidebar's recency index. */
export const backfillMembershipRecency = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  returns: v.null(),
  handler: async (ctx, args) => {
    const result = await ctx.db
      .query("conversationMembers")
      .order("asc")
      .paginate(args.paginationOpts);
    for (const member of result.page) {
      const conversation = await ctx.db.get(
        "conversations",
        member.conversationId,
      );
      if (conversation !== null) {
        await ctx.db.patch("conversationMembers", member._id, {
          lastMessageAt: conversation.lastMessageAt,
        });
      }
    }
    if (!result.isDone) {
      await ctx.scheduler.runAfter(
        0,
        internal.model.conversations.backfillMembershipRecency,
        {
          paginationOpts: {
            numItems: args.paginationOpts.numItems,
            cursor: result.continueCursor,
          },
        },
      );
    }
    return null;
  },
});
