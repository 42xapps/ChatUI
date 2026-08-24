import { paginationOptsValidator } from "convex/server";
import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import {
  env,
  internalMutation,
  internalQuery,
} from "../_generated/server";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { r2 } from "../r2";

const MEDIA_ACCESS_QUERY_PARAMETER = "token";
const MEDIA_DELETE_BATCH_SIZE = 50;

type UploadKind = Doc<"mediaAssets">["kind"];

/** Stable app URL carrying a revocable media capability. */
export function attachmentUrl(key: string, accessToken: string): string {
  const path = `${encodeKey(key)}?${MEDIA_ACCESS_QUERY_PARAMETER}=${encodeURIComponent(accessToken)}`;
  return `${env.CONVEX_SITE_URL}/r2/${path}`;
}

/** Percent-encodes each path segment while keeping the `/` separators. */
export function encodeKey(key: string): string {
  return key.split("/").map(encodeURIComponent).join("/");
}

/** Inverse of `encodeKey`, for the `/r2/*` HTTP action. */
export function decodeKey(path: string): string {
  return path.split("/").map(decodeURIComponent).join("/");
}

export async function mediaAssetByKey(
  ctx: Pick<QueryCtx, "db">,
  key: string,
): Promise<Doc<"mediaAssets"> | null> {
  return await ctx.db
    .query("mediaAssets")
    .withIndex("by_r2_key", (q) => q.eq("r2Key", key))
    .unique();
}

/** Returns a URL only for a claimed asset that is still attached to a row. */
export async function resolvedAttachmentUrl(
  ctx: QueryCtx,
  key: string,
): Promise<string | null> {
  const asset = await mediaAssetByKey(ctx, key);
  if (asset?.claimedMessageId === undefined) return null;
  const message = await ctx.db.get("messages", asset.claimedMessageId);
  if (message === null || message.conversationId !== asset.conversationId) {
    return null;
  }
  return attachmentUrl(asset.r2Key, asset.accessToken);
}

/**
 * Verifies all supplied keys belong to this caller/conversation and atomically
 * consumes their upload grants for the new message.
 */
export async function claimMessageAssets(
  ctx: MutationCtx,
  args: {
    userId: Id<"users">;
    conversationId: Id<"conversations">;
    messageId: Id<"messages">;
    attachments: Doc<"messages">["attachments"];
    recording?: Doc<"messages">["recording"];
  },
): Promise<void> {
  const expected = new Map<string, UploadKind>();
  for (const attachment of args.attachments) {
    if (attachment.type === "image") {
      expected.set(attachment.r2Key, "image");
      if (attachment.thumbR2Key !== attachment.r2Key) {
        throw new ConvexError("An image must use itself as its thumbnail");
      }
    } else {
      expected.set(attachment.r2Key, "video");
      expected.set(attachment.thumbR2Key, "videoThumbnail");
    }
  }
  if (args.recording !== undefined) {
    expected.set(args.recording.r2Key, "recording");
  }

  const assets: Doc<"mediaAssets">[] = [];
  for (const [key, kind] of expected) {
    const asset = await mediaAssetByKey(ctx, key);
    if (
      asset === null ||
      asset.userId !== args.userId ||
      asset.conversationId !== args.conversationId ||
      asset.kind !== kind
    ) {
      throw new ConvexError("Attachment upload is not valid for this conversation");
    }
    if (
      asset.claimedMessageId !== undefined &&
      asset.claimedMessageId !== args.messageId
    ) {
      throw new ConvexError("Attachment upload was already used by another message");
    }
    assets.push(asset);
  }

  const now = Date.now();
  for (const asset of assets) {
    await ctx.db.patch("mediaAssets", asset._id, {
      claimedMessageId: args.messageId,
      claimedAt: now,
    });
  }
}

/** R2 download authorization for the public HTTP capability URL. */
export const authorizeDownload = internalQuery({
  args: { key: v.string(), accessToken: v.string() },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const asset = await mediaAssetByKey(ctx, args.key);
    if (
      asset === null ||
      asset.accessToken !== args.accessToken ||
      asset.claimedMessageId === undefined
    ) {
      return false;
    }
    const message = await ctx.db.get("messages", asset.claimedMessageId);
    const conversation = await ctx.db.get(
      "conversations",
      asset.conversationId,
    );
    return (
      message !== null &&
      conversation !== null &&
      message.conversationId === asset.conversationId
    );
  },
});

/** Deletes an upload that was never committed to a message. */
export const cleanupUnclaimedAsset = internalMutation({
  args: { assetId: v.id("mediaAssets") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const asset = await ctx.db.get("mediaAssets", args.assetId);
    if (asset === null || asset.claimedMessageId !== undefined) return null;
    await r2.deleteObject(ctx, asset.r2Key);
    await ctx.db.delete("mediaAssets", asset._id);
    return null;
  },
});

/** Deletes one bounded batch of a conversation's R2 objects and asset rows. */
export async function deleteConversationAssetsBatch(
  ctx: MutationCtx,
  conversationId: Id<"conversations">,
): Promise<boolean> {
  const assets = await ctx.db
    .query("mediaAssets")
    .withIndex("by_conversation_and_created_at", (q) =>
      q.eq("conversationId", conversationId),
    )
    .take(MEDIA_DELETE_BATCH_SIZE);
  for (const asset of assets) {
    await r2.deleteObject(ctx, asset.r2Key);
    await ctx.db.delete("mediaAssets", asset._id);
  }
  return assets.length === MEDIA_DELETE_BATCH_SIZE;
}

/**
 * One-time dev/prod rollout helper for media referenced before `mediaAssets`
 * existed. Invoke with `{paginationOpts:{numItems:50,cursor:null}}`; it
 * schedules subsequent pages itself.
 */
export const backfillMediaAssets = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  returns: v.null(),
  handler: async (ctx, args) => {
    const result = await ctx.db
      .query("messages")
      .order("asc")
      .paginate(args.paginationOpts);

    for (const message of result.page) {
      const keys = new Map<string, UploadKind>();
      for (const attachment of message.attachments) {
        keys.set(attachment.r2Key, attachment.type === "image" ? "image" : "video");
        keys.set(
          attachment.thumbR2Key,
          attachment.type === "image" ? "image" : "videoThumbnail",
        );
      }
      if (message.recording !== undefined) {
        keys.set(message.recording.r2Key, "recording");
      }
      for (const [r2Key, kind] of keys) {
        if ((await mediaAssetByKey(ctx, r2Key)) !== null) continue;
        await ctx.db.insert("mediaAssets", {
          r2Key,
          accessToken: crypto.randomUUID(),
          kind,
          userId: message.senderId,
          conversationId: message.conversationId,
          createdAt: message._creationTime,
          claimedMessageId: message._id,
          claimedAt: message._creationTime,
        });
      }
    }

    if (!result.isDone) {
      await ctx.scheduler.runAfter(
        0,
        internal.model.attachments.backfillMediaAssets,
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
