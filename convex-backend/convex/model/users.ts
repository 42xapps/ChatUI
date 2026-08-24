import { ConvexError, v } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";

const COMPANION_TOKEN_IDENTIFIER = "system|companion";

/** The subset of a `users` row that is safe to hand to any signed-in client. */
export const publicUser = v.object({
  _id: v.id("users"),
  _creationTime: v.number(),
  clerkId: v.string(),
  name: v.string(),
  avatarUrl: v.optional(v.string()),
});

/** Projects a `users` row onto `publicUser`, dropping `email`. */
export function toPublicUser(user: Doc<"users">) {
  return {
    _id: user._id,
    _creationTime: user._creationTime,
    clerkId: user.clerkId,
    name: user.name,
    avatarUrl: user.avatarUrl,
  };
}

/** The singleton synthetic sender used for all companion-authored messages. */
export async function getOrCreateCompanionUser(
  ctx: MutationCtx,
): Promise<Doc<"users">> {
  const existing = await ctx.db
    .query("users")
    .withIndex("by_token_identifier", (q) =>
      q.eq("tokenIdentifier", COMPANION_TOKEN_IDENTIFIER),
    )
    .unique();
  if (existing !== null) {
    return existing;
  }

  const id = await ctx.db.insert("users", {
    tokenIdentifier: COMPANION_TOKEN_IDENTIFIER,
    clerkId: "companion",
    name: "Embie",
  });
  const inserted = await ctx.db.get("users", id);
  if (inserted === null) {
    throw new ConvexError("Failed to create companion user");
  }
  return inserted;
}

/**
 * The `users` row for the caller.
 *
 * Throws for an unauthenticated request, and also for an authenticated one
 * whose row doesn't exist yet — which is the window between sign-in and
 * `users.syncCurrentUser` landing. The client gates on that mutation before
 * calling anything else, so reaching this error in practice means the
 * deployment is rejecting the token (usually a `CLERK_FRONTEND_API_URL`
 * mismatch).
 */
export async function requireCurrentUser(ctx: QueryCtx): Promise<Doc<"users">> {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw new ConvexError("Not signed in");
  }
  const user = await ctx.db
    .query("users")
    .withIndex("by_token_identifier", (q) =>
      q.eq("tokenIdentifier", identity.tokenIdentifier),
    )
    .unique();
  if (user === null) {
    throw new ConvexError("No user row for this identity yet");
  }
  return user;
}

/**
 * Creates or refreshes the caller's `users` row.
 *
 * Clerk's default session token carries very few claims, so `name`/`avatarUrl`
 * from the client are used as a fallback when the corresponding claim is
 * absent. Claims win when present, since those are the values Clerk signed.
 */
export async function upsertCurrentUser(
  ctx: MutationCtx,
  fallback: { name?: string; avatarUrl?: string },
): Promise<Doc<"users">> {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw new ConvexError("Not signed in");
  }

  const fields = {
    tokenIdentifier: identity.tokenIdentifier,
    clerkId: identity.subject,
    name: identity.name ?? fallback.name ?? "Anonymous",
    avatarUrl: identity.pictureUrl ?? fallback.avatarUrl,
    email: identity.email,
  };

  const existing = await ctx.db
    .query("users")
    .withIndex("by_token_identifier", (q) =>
      q.eq("tokenIdentifier", identity.tokenIdentifier),
    )
    .unique();

  if (existing === null) {
    const id = await ctx.db.insert("users", fields);
    const inserted = await ctx.db.get("users", id);
    if (inserted === null) {
      throw new ConvexError("Failed to create user");
    }
    return inserted;
  }

  await ctx.db.patch("users", existing._id, fields);
  return { ...existing, ...fields };
}
