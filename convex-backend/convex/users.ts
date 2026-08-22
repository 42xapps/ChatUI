import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { publicUser, toPublicUser, upsertCurrentUser } from "./model/users";

/**
 * Creates the caller's `users` row if it doesn't exist yet, and keeps name and
 * avatar in sync with Clerk.
 *
 * The iOS app calls this once per sign-in and adopts the row it returns, before
 * anything else runs — every other function calls `requireCurrentUser` and
 * throws without it.
 */
export const syncCurrentUser = mutation({
  args: {
    name: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
  },
  returns: publicUser,
  handler: async (ctx, args) => toPublicUser(await upsertCurrentUser(ctx, args)),
});
