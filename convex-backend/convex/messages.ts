import { paginationOptsValidator, paginationResultValidator } from "convex/server";
import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { deriveTitle, requireMembership } from "./model/conversations";
import {
  messageByClientId,
  resolveMessage,
  resolvedMessage,
} from "./model/messages";
import { requireCurrentUser } from "./model/users";
import { storedAttachment, storedRecording } from "./schema";

/** Generous bounds — the iOS client never sends more than one attachment per
 * message today, but nothing enforced that server-side. */
const MAX_TEXT_LENGTH = 8000;
const MAX_ATTACHMENTS_PER_MESSAGE = 10;

/**
 * One page of a conversation's messages, oldest first within the page.
 *
 * Pages walk backwards from the newest message — the natural direction for a
 * chat — so `continueCursor` fetches *older* messages, while the page itself is
 * ordered chronologically so the client can render it as-is.
 */
export const listForConversation = query({
  args: {
    conversationId: v.id("conversations"),
    paginationOpts: paginationOptsValidator,
  },
  returns: paginationResultValidator(resolvedMessage),
  handler: async (ctx, args) => {
    const viewer = await requireCurrentUser(ctx);
    await requireMembership(ctx, args.conversationId, viewer._id);

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
      if (resolved !== null) {
        page.push(resolved);
      }
    }

    return { ...result, page: page.reverse() };
  },
});

/**
 * Appends a message to a conversation.
 *
 * Membership is verified before anything is written — the authorization the
 * reference app's client-side query filter couldn't provide. Re-sending the
 * same `clientId` is a no-op, so a retry after a dropped connection can't
 * duplicate a message.
 */
export const send = mutation({
  args: {
    conversationId: v.id("conversations"),
    clientId: v.string(),
    text: v.string(),
    attachments: v.array(storedAttachment),
    giphyMediaId: v.optional(v.string()),
    recording: v.optional(storedRecording),
    /** `clientId` of the message being replied to, if any. */
    replyToClientId: v.optional(v.string()),
    createdAt: v.number(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const viewer = await requireCurrentUser(ctx);
    await requireMembership(ctx, args.conversationId, viewer._id);

    const conversation = await ctx.db.get("conversations", args.conversationId);
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
      (await messageByClientId(ctx, args.conversationId, args.clientId)) !== null
    ) {
      return null;
    }

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

    await ctx.db.insert("messages", {
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

    await ctx.db.patch("conversations", args.conversationId, {
      lastMessageAt: Date.now(),
      // Title from whichever message lands first; never overwritten after.
      ...(conversation.title === undefined ? { title: deriveTitle(args) } : {}),
    });

    return null;
  },
});
