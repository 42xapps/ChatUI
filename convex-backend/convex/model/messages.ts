import { v } from "convex/values";
import type { Doc, Id } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";
import { attachmentType } from "../schema";
import { attachmentUrl } from "./attachments";
import { publicUser, toPublicUser } from "./users";

/**
 * An attachment as the client sees it: R2 keys resolved to fetchable URLs.
 *
 * Both keys come along for the ride because the client uses them as image-cache
 * keys. That keeps caching independent of the URL scheme — switching
 * `R2_PUBLIC_BASE_URL` on or off changes every URL but no cache key.
 */
export const resolvedAttachment = v.object({
  type: attachmentType,
  url: v.string(),
  thumbUrl: v.string(),
  r2Key: v.string(),
  thumbR2Key: v.string(),
});

export const resolvedRecording = v.object({
  duration: v.number(),
  waveformSamples: v.array(v.number()),
  url: v.string(),
});

/**
 * The quoted message shown above a reply. Flattened rather than recursive: a
 * reply to a reply quotes only its immediate parent, matching the UI.
 */
export const resolvedReply = v.object({
  clientId: v.string(),
  sender: publicUser,
  _creationTime: v.number(),
  text: v.string(),
  attachments: v.array(resolvedAttachment),
  recording: v.optional(resolvedRecording),
});

export const resolvedMessage = v.object({
  _id: v.id("messages"),
  _creationTime: v.number(),
  clientId: v.string(),
  sender: publicUser,
  text: v.string(),
  attachments: v.array(resolvedAttachment),
  giphyMediaId: v.optional(v.string()),
  recording: v.optional(resolvedRecording),
  replyTo: v.optional(resolvedReply),
});

function resolveAttachments(attachments: Doc<"messages">["attachments"]) {
  return attachments.map((attachment) => ({
    type: attachment.type,
    url: attachmentUrl(attachment.r2Key),
    thumbUrl: attachmentUrl(attachment.thumbR2Key),
    r2Key: attachment.r2Key,
    thumbR2Key: attachment.thumbR2Key,
  }));
}

function resolveRecording(recording: Doc<"messages">["recording"]) {
  if (recording === undefined) {
    return undefined;
  }
  return {
    duration: recording.duration,
    waveformSamples: recording.waveformSamples,
    url: attachmentUrl(recording.r2Key),
  };
}

/**
 * Joins a stored message with its sender and quoted parent, and turns R2 keys
 * into URLs.
 *
 * Returns `null` when the sender row is missing, so a message can never render
 * without an author.
 */
export async function resolveMessage(ctx: QueryCtx, message: Doc<"messages">) {
  const sender = await ctx.db.get("users", message.senderId);
  if (sender === null) {
    return null;
  }

  let replyTo = undefined;
  if (message.replyTo !== undefined) {
    const parent = await ctx.db.get("messages", message.replyTo);
    const parentSender =
      parent === null ? null : await ctx.db.get("users", parent.senderId);
    if (parent !== null && parentSender !== null) {
      replyTo = {
        clientId: parent.clientId,
        sender: toPublicUser(parentSender),
        _creationTime: parent._creationTime,
        text: parent.text,
        attachments: resolveAttachments(parent.attachments),
        recording: resolveRecording(parent.recording),
      };
    }
  }

  return {
    _id: message._id,
    _creationTime: message._creationTime,
    clientId: message.clientId,
    sender: toPublicUser(sender),
    text: message.text,
    attachments: resolveAttachments(message.attachments),
    giphyMediaId: message.giphyMediaId,
    recording: resolveRecording(message.recording),
    replyTo,
  };
}

/** Looks a message up by the id its sender assigned it. */
export async function messageByClientId(
  ctx: QueryCtx,
  conversationId: Id<"conversations">,
  clientId: string,
): Promise<Doc<"messages"> | null> {
  const message = await ctx.db
    .query("messages")
    .withIndex("by_client_id", (q) => q.eq("clientId", clientId))
    .unique();
  return message !== null && message.conversationId === conversationId
    ? message
    : null;
}
