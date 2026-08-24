import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { ConvexError, v } from "convex/values";
import { query } from "./_generated/server";
import { requireCurrentUser } from "./model/users";

const MAX_USAGE_PAGE_SIZE = 200;

const publicUsageEvent = v.object({
  _id: v.id("llmUsageEvents"),
  _creationTime: v.number(),
  conversationId: v.id("conversations"),
  provider: v.string(),
  model: v.string(),
  inputTokens: v.number(),
  outputTokens: v.number(),
  totalTokens: v.number(),
  cacheReadTokens: v.optional(v.number()),
  cacheWriteTokens: v.optional(v.number()),
  reasoningTokens: v.optional(v.number()),
  createdAt: v.number(),
});

/** Paginated, authenticated usage ledger for the current account. */
export const listMine = query({
  args: { paginationOpts: paginationOptsValidator },
  returns: paginationResultValidator(publicUsageEvent),
  handler: async (ctx, args) => {
    const viewer = await requireCurrentUser(ctx);
    if (args.paginationOpts.numItems > MAX_USAGE_PAGE_SIZE) {
      throw new ConvexError(
        `Usage page size cannot exceed ${MAX_USAGE_PAGE_SIZE}`,
      );
    }
    const result = await ctx.db
      .query("llmUsageEvents")
      .withIndex("by_user_and_created_at", (q) =>
        q.eq("userId", viewer._id),
      )
      .order("desc")
      .paginate(args.paginationOpts);
    return {
      ...result,
      page: result.page.map(({ userId: _userId, turnId: _turnId, ...event }) =>
        event,
      ),
    };
  },
});
