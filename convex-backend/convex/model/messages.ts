import { v } from "convex/values";
import type { Doc, Id } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";
import {
  attachmentType,
  generationError,
  generationStatus,
} from "../schema";
import { resolvedAttachmentUrl } from "./attachments";
import {
  publicUser,
  toPublicUser,
} from "./users";

/**
 * An attachment as the client sees it: R2 keys resolved to fetchable URLs.
 *
 * Both keys come along for the ride because the client uses them as image-cache
 * keys. That keeps caching independent of the short-lived capability URL — a
 * refreshed redirect URL does not invalidate the client's object-key cache.
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
  generationStatus: v.optional(generationStatus),
  generationError: v.optional(generationError),
  generationNotBefore: v.optional(v.number()),
});

async function resolveAttachments(
  ctx: QueryCtx,
  attachments: Doc<"messages">["attachments"],
) {
  const resolved = [];
  for (const attachment of attachments) {
    const url = await resolvedAttachmentUrl(ctx, attachment.r2Key);
    const thumbUrl =
      attachment.thumbR2Key === attachment.r2Key
        ? url
        : await resolvedAttachmentUrl(ctx, attachment.thumbR2Key);
    if (url === null || thumbUrl === null) continue;
    resolved.push({
      type: attachment.type,
      url,
      thumbUrl,
      r2Key: attachment.r2Key,
      thumbR2Key: attachment.thumbR2Key,
    });
  }
  return resolved;
}

async function resolveRecording(
  ctx: QueryCtx,
  recording: Doc<"messages">["recording"],
) {
  if (recording === undefined) {
    return undefined;
  }
  const url = await resolvedAttachmentUrl(ctx, recording.r2Key);
  if (url === null) return undefined;
  return {
    duration: recording.duration,
    waveformSamples: recording.waveformSamples,
    url,
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
        attachments: await resolveAttachments(ctx, parent.attachments),
        recording: await resolveRecording(ctx, parent.recording),
      };
    }
  }

  return {
    _id: message._id,
    _creationTime: message._creationTime,
    clientId: message.clientId,
    sender: toPublicUser(sender),
    text: message.text,
    attachments: await resolveAttachments(ctx, message.attachments),
    giphyMediaId: message.giphyMediaId,
    recording: await resolveRecording(ctx, message.recording),
    replyTo,
    generationStatus: message.generationStatus,
    generationError: message.generationError,
    generationNotBefore: message.generationNotBefore,
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
    .withIndex("by_conversation_and_client_id", (q) =>
      q.eq("conversationId", conversationId).eq("clientId", clientId),
    )
    .unique();
  return message;
}
