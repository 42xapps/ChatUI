import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import {
  createForUser,
  deleteConversation,
  listForUser,
} from "./model/conversations";
import { requireMembership } from "./model/conversations";
import { requireCurrentUser } from "./model/users";

/** A conversation as it appears in the chat-history sidebar. */
export const conversationSummary = v.object({
  _id: v.id("conversations"),
  title: v.optional(v.string()),
  lastMessageAt: v.number(),
});

/** Every conversation the signed-in user belongs to, most recent first. */
export const listMine = query({
  args: {},
  returns: v.array(conversationSummary),
  handler: async (ctx) => {
    const viewer = await requireCurrentUser(ctx);
    return await listForUser(ctx, viewer._id);
  },
});

/** Starts a new, empty conversation — the sidebar's "New Chat". */
export const create = mutation({
  args: {},
  returns: v.id("conversations"),
  handler: async (ctx) => {
    const viewer = await requireCurrentUser(ctx);
    return await createForUser(ctx, viewer._id);
  },
});

/** Deletes a conversation. The caller must be a member. */
export const remove = mutation({
  args: { conversationId: v.id("conversations") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const viewer = await requireCurrentUser(ctx);
    await requireMembership(ctx, args.conversationId, viewer._id);
    await deleteConversation(ctx, args.conversationId);
    return null;
  },
});
