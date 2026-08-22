import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { requireMembership } from "./model/conversations";
import { requireCurrentUser } from "./model/users";
import { r2 } from "./r2";

/**
 * What the bytes are for. Determines the object key's extension, which is what
 * R2 and Cloudflare's cache use to pick a content type when one wasn't sent.
 */
const uploadKind = v.union(
  v.literal("image"),
  v.literal("video"),
  v.literal("videoThumbnail"),
  v.literal("recording"),
);

const extensionFor = {
  image: "jpg",
  video: "mov",
  videoThumbnail: "jpg",
  recording: "aac",
} as const;

/**
 * Mints a presigned PUT URL so the client can stream bytes straight to R2,
 * without them passing through Convex.
 *
 * The caller must be a member of the conversation the attachment is destined
 * for, and the key is derived server-side — a client can't choose where in the
 * bucket it writes, or overwrite another conversation's objects.
 */
export const requestUploadUrl = mutation({
  args: {
    conversationId: v.id("conversations"),
    kind: uploadKind,
  },
  returns: v.object({ key: v.string(), url: v.string() }),
  handler: async (ctx, args) => {
    const viewer = await requireCurrentUser(ctx);
    await requireMembership(ctx, args.conversationId, viewer._id);

    const key = `conversations/${args.conversationId}/${viewer._id}/${crypto.randomUUID()}.${extensionFor[args.kind]}`;
    return await r2.generateUploadUrl(key);
  },
});
