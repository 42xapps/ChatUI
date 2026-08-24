/// <reference types="vite/client" />

import agentTest from "@convex-dev/agent/test";
import r2Test from "@convex-dev/r2/test";
import rateLimiterTest from "@convex-dev/rate-limiter/test";
import { APICallError, RetryError } from "ai";
import type { ModelMessage } from "ai";
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import {
  boundedContext,
  MAX_CONTEXT_CHARACTERS,
} from "./agents/companion";
import { classifyGenerationError } from "./ai";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const paginationOpts = { numItems: 100, cursor: null } as const;

function testBackend() {
  const t = convexTest(schema, modules);
  agentTest.register(t);
  rateLimiterTest.register(t);
  r2Test.register(t);
  return t;
}

function identity(subject: string) {
  return {
    subject,
    issuer: "https://clerk.test",
    tokenIdentifier: `https://clerk.test|${subject}`,
    name: subject === "alice" ? "Alice" : "Bob",
  };
}

async function signedInUser(
  t: ReturnType<typeof testBackend>,
  subject: string,
) {
  const client = t.withIdentity(identity(subject));
  const user = await client.mutation(api.users.syncCurrentUser, {});
  return { client, user };
}

function sendArgs(conversationId: Id<"conversations">, clientId: string) {
  return {
    conversationId,
    clientId,
    text: `Message ${clientId}`,
    attachments: [],
    createdAt: Date.now(),
  };
}

describe("companion chat bridge", () => {
  test("keeps only the newest complete messages inside the context budget", () => {
    const oldest = {
      role: "user",
      content: "a".repeat(13_000),
    } satisfies ModelMessage;
    const middle = {
      role: "assistant",
      content: "b".repeat(13_000),
    } satisfies ModelMessage;
    const newest = {
      role: "user",
      content: "latest turn",
    } satisfies ModelMessage;

    expect(MAX_CONTEXT_CHARACTERS).toBe(24_000);
    expect(boundedContext([oldest, middle, newest])).toEqual([middle, newest]);

    const oversizedNewest = {
      role: "user",
      content: "c".repeat(MAX_CONTEXT_CHARACTERS + 1),
    } satisfies ModelMessage;
    expect(boundedContext([oldest, oversizedNewest])).toEqual([
      oversizedNewest,
    ]);
  });

  test("classifies provider auth and transient rate-limit failures", () => {
    const authentication = new APICallError({
      message: "Invalid API key",
      url: "https://provider.test/v1/chat",
      requestBodyValues: {},
      statusCode: 401,
      isRetryable: false,
    });
    expect(classifyGenerationError(authentication)).toEqual({
      code: "provider_authentication",
      message: "The companion is temporarily unavailable.",
      retryable: false,
    });

    const rateLimited = new APICallError({
      message: "Too many requests",
      url: "https://provider.test/v1/chat",
      requestBodyValues: {},
      statusCode: 429,
      responseHeaders: { "retry-after": "2" },
      isRetryable: true,
    });
    expect(classifyGenerationError(rateLimited)).toEqual({
      code: "provider_rate_limited",
      message: "The companion is busy. Please try again shortly.",
      retryable: true,
      retryAfterMs: 2_000,
    });
  });

  test("keeps the original provider failure when textStream reports no output", () => {
    const quotaError = new APICallError({
      message: "You exceeded your current quota. Check your plan and billing details.",
      url: "https://api.openai.test/v1/responses",
      requestBodyValues: {},
      statusCode: 429,
      isRetryable: true,
    });
    const exhaustedRetries = new RetryError({
      message: "Failed after 3 attempts",
      reason: "maxRetriesExceeded",
      errors: [quotaError, quotaError, quotaError],
    });

    expect(
      classifyGenerationError(
        new Error("No output generated. Check the stream for errors."),
        exhaustedRetries,
      ),
    ).toEqual({
      code: "provider_billing",
      message: "The companion is temporarily unavailable.",
      retryable: false,
    });
  });

  test("retries only transient pre-stream failures and preserves partial output", async () => {
    const t = testBackend();
    const { client: alice } = await signedInUser(t, "alice");
    const transientConversation = await alice.mutation(api.conversations.create);
    await alice.mutation(
      api.messages.send,
      sendArgs(transientConversation, "transient-pre-stream"),
    );
    const transientClaim = await t.mutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      {
        conversationId: transientConversation,
        provider: "test",
        model: "test-model",
      },
    );
    if (transientClaim.kind !== "claimed") {
      throw new Error("Expected transient turn to be claimed");
    }

    const requeued = await t.mutation(
      internal.model.generationTurns.handleGenerationFailure,
      {
        turnId: transientClaim.turnId,
        attemptId: transientClaim.attemptId,
        error: {
          code: "provider_unavailable",
          message: "Please try again.",
          retryable: true,
        },
        partialText: "",
      },
    );
    expect(requeued.kind).toBe("requeued");
    const requeuedTurn = await t.run((ctx) =>
      ctx.db.get("generationTurns", transientClaim.turnId),
    );
    expect(requeuedTurn).toMatchObject({ status: "queued", attemptCount: 1 });

    const partialConversation = await alice.mutation(api.conversations.create);
    await alice.mutation(
      api.messages.send,
      sendArgs(partialConversation, "partial-stream"),
    );
    const partialClaim = await t.mutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      {
        conversationId: partialConversation,
        provider: "test",
        model: "test-model",
      },
    );
    if (partialClaim.kind !== "claimed") {
      throw new Error("Expected partial-stream turn to be claimed");
    }
    const partialText = "A useful partial reply";
    expect(
      await t.mutation(internal.model.generationTurns.patchGenerationText, {
        turnId: partialClaim.turnId,
        attemptId: partialClaim.attemptId,
        text: partialText,
      }),
    ).toBe(true);
    const partialFailure = await t.mutation(
      internal.model.generationTurns.handleGenerationFailure,
      {
        turnId: partialClaim.turnId,
        attemptId: partialClaim.attemptId,
        error: {
          code: "provider_unavailable",
          message: "Please try again.",
          retryable: true,
        },
        partialText,
      },
    );
    expect(partialFailure.kind).toBe("failed");
    const failedPartialTurn = await t.run((ctx) =>
      ctx.db.get("generationTurns", partialClaim.turnId),
    );
    if (failedPartialTurn === null) throw new Error("Expected failed turn");
    const failedPartialMessage = await t.run((ctx) =>
      ctx.db.get("messages", failedPartialTurn.assistantMessageId),
    );
    expect(failedPartialMessage).toMatchObject({
      text: partialText,
      generationStatus: "failed",
    });

    const { client: bob } = await signedInUser(t, "bob");
    const billingConversation = await bob.mutation(api.conversations.create);
    await bob.mutation(
      api.messages.send,
      sendArgs(billingConversation, "permanent-billing"),
    );
    const billingClaim = await t.mutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      {
        conversationId: billingConversation,
        provider: "test",
        model: "test-model",
      },
    );
    if (billingClaim.kind !== "claimed") {
      throw new Error("Expected billing turn to be claimed");
    }
    const billingFailure = await t.mutation(
      internal.model.generationTurns.handleGenerationFailure,
      {
        turnId: billingClaim.turnId,
        attemptId: billingClaim.attemptId,
        error: {
          code: "provider_billing",
          message: "The companion is temporarily unavailable.",
          retryable: false,
        },
        partialText: "",
      },
    );
    expect(billingFailure.kind).toBe("failed");
    const failedBillingTurn = await t.run((ctx) =>
      ctx.db.get("generationTurns", billingClaim.turnId),
    );
    expect(failedBillingTurn).toMatchObject({
      status: "failed",
      attemptCount: 1,
      error: { code: "provider_billing", retryable: false },
    });
  });

  test("rejects unauthenticated reads and creates an explicit initial greeting", async () => {
    const t = testBackend();
    await expect(t.query(api.conversations.listMine)).rejects.toThrow(
      "Not signed in",
    );

    const { client } = await signedInUser(t, "alice");
    const conversationId = await client.mutation(api.conversations.create);
    const page = await client.query(api.messages.listForConversation, {
      conversationId,
      paginationOpts,
    });

    expect(page.page).toHaveLength(1);
    expect(page.page[0]).toMatchObject({
      text: "Hi, I’m Embie. What’s on your mind today?",
      generationStatus: "completed",
    });
    expect(page.page[0]?.sender.clerkId).toBe("companion");
  });

  test("scopes idempotency to a conversation and does not consume admission twice", async () => {
    const t = testBackend();
    const { client } = await signedInUser(t, "alice");
    const firstConversation = await client.mutation(api.conversations.create);
    const secondConversation = await client.mutation(api.conversations.create);

    const first = await client.mutation(
      api.messages.send,
      sendArgs(firstConversation, "same-client-id"),
    );
    const duplicate = await client.mutation(
      api.messages.send,
      sendArgs(firstConversation, "same-client-id"),
    );
    const otherConversation = await client.mutation(
      api.messages.send,
      sendArgs(secondConversation, "same-client-id"),
    );

    expect(first).toMatchObject({ status: "accepted", duplicate: false });
    expect(duplicate).toMatchObject({ status: "accepted", duplicate: true });
    if (first.status !== "accepted" || duplicate.status !== "accepted") {
      throw new Error("Expected both idempotent sends to be accepted");
    }
    expect(duplicate.assistantClientId).toBe(first.assistantClientId);
    expect(otherConversation).toMatchObject({
      status: "accepted",
      duplicate: false,
    });

    const rows = await t.run(async (ctx) =>
      ctx.db.query("messages").collect(),
    );
    expect(
      rows.filter(
        (row) =>
          row.conversationId === firstConversation &&
          row.clientId === "same-client-id",
      ),
    ).toHaveLength(1);
    expect(
      rows.filter(
        (row) =>
          row.conversationId === secondConversation &&
          row.clientId === "same-client-id",
      ),
    ).toHaveLength(1);
  });

  test("returns a typed per-user admission result instead of throwing", async () => {
    const t = testBackend();
    const { client } = await signedInUser(t, "alice");
    const conversationId = await client.mutation(api.conversations.create);

    await client.mutation(api.messages.send, sendArgs(conversationId, "one"));
    await client.mutation(api.messages.send, sendArgs(conversationId, "two"));
    const limited = await client.mutation(
      api.messages.send,
      sendArgs(conversationId, "three"),
    );

    expect(limited.status).toBe("rate_limited");
    if (limited.status === "rate_limited") {
      expect(limited.scope).toBe("user_messages");
      expect(limited.retryAfterMs).toBeGreaterThan(0);
    }
  });

  test("serializes turns, rejects stale patches, and records completion usage", async () => {
    const t = testBackend();
    const { client } = await signedInUser(t, "alice");
    const conversationId = await client.mutation(api.conversations.create);
    await client.mutation(api.messages.send, sendArgs(conversationId, "one"));
    await client.mutation(api.messages.send, sendArgs(conversationId, "two"));

    const first = await t.mutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      { conversationId, provider: "test", model: "test-model" },
    );
    expect(first.kind).toBe("claimed");
    if (first.kind !== "claimed") throw new Error("Expected a claimed turn");

    const overlapping = await t.mutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      { conversationId, provider: "test", model: "test-model" },
    );
    expect(overlapping.kind).toBe("wait");

    expect(
      await t.mutation(internal.model.generationTurns.patchGenerationText, {
        turnId: first.turnId,
        attemptId: "stale-attempt",
        text: "must not land",
      }),
    ).toBe(false);
    expect(
      await t.mutation(internal.model.generationTurns.patchGenerationText, {
        turnId: first.turnId,
        attemptId: first.attemptId,
        text: "Growing reply",
      }),
    ).toBe(true);
    expect(
      await t.mutation(internal.model.generationTurns.completeGenerationTurn, {
        turnId: first.turnId,
        attemptId: first.attemptId,
        text: "Growing reply completed",
        usage: { inputTokens: 10, outputTokens: 4, totalTokens: 14 },
      }),
    ).toBe(true);

    const second = await t.mutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      { conversationId, provider: "test", model: "test-model" },
    );
    expect(second.kind).toBe("claimed");

    const usage = await client.query(api.llmUsage.listMine, { paginationOpts });
    expect(usage.page).toHaveLength(1);
    expect(usage.page[0]).toMatchObject({
      provider: "test",
      model: "test-model",
      totalTokens: 14,
    });
    expect(usage.page[0]).not.toHaveProperty("userId");
    expect(usage.page[0]).not.toHaveProperty("turnId");
  });

  test("retries the same assistant row only for a retryable owned turn", async () => {
    const t = testBackend();
    const { client } = await signedInUser(t, "alice");
    const conversationId = await client.mutation(api.conversations.create);
    const sent = await client.mutation(
      api.messages.send,
      sendArgs(conversationId, "retry-user-message"),
    );
    if (sent.status !== "accepted" || sent.assistantClientId === undefined) {
      throw new Error("Expected accepted send with assistant identity");
    }

    const claim = await t.mutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      { conversationId, provider: "test", model: "test-model" },
    );
    if (claim.kind !== "claimed") throw new Error("Expected claimed turn");
    await t.mutation(internal.model.generationTurns.failGenerationTurn, {
      turnId: claim.turnId,
      attemptId: claim.attemptId,
      error: {
        code: "provider_unavailable",
        message: "Please try again.",
        retryable: true,
      },
    });

    const retried = await client.mutation(api.messages.retryGeneration, {
      conversationId,
      assistantClientId: sent.assistantClientId,
    });
    expect(retried).toMatchObject({
      status: "accepted",
      assistantClientId: sent.assistantClientId,
    });

    const assistants = await t.run(async (ctx) =>
      ctx.db
        .query("messages")
        .withIndex("by_conversation_and_client_id", (q) =>
          q
            .eq("conversationId", conversationId)
            .eq("clientId", sent.assistantClientId!),
        )
        .collect(),
    );
    expect(assistants).toHaveLength(1);
    expect(assistants[0]?.generationStatus).toBe("queued");
  });

  test("cancels deletion races so an old lease cannot recreate or patch rows", async () => {
    const t = testBackend();
    const { client } = await signedInUser(t, "alice");
    const conversationId = await client.mutation(api.conversations.create);
    await client.mutation(
      api.messages.send,
      sendArgs(conversationId, "delete-race"),
    );
    const claim = await t.mutation(
      internal.model.generationTurns.claimNextGenerationTurn,
      { conversationId, provider: "test", model: "test-model" },
    );
    if (claim.kind !== "claimed") throw new Error("Expected claimed turn");

    await client.mutation(api.conversations.remove, { conversationId });
    expect(
      await t.mutation(internal.model.generationTurns.patchGenerationText, {
        turnId: claim.turnId,
        attemptId: claim.attemptId,
        text: "orphan",
      }),
    ).toBe(false);
    expect(
      await t.run(async (ctx) => ctx.db.get("conversations", conversationId)),
    ).toBeNull();
    expect(
      await t.run(async (ctx) =>
        ctx.db
          .query("messages")
          .withIndex("by_conversation", (q) =>
            q.eq("conversationId", conversationId),
          )
          .collect(),
      ),
    ).toHaveLength(0);
  });

  test("requires membership and rejects upload grants from another conversation", async () => {
    const t = testBackend();
    const { client: alice, user: aliceUser } = await signedInUser(t, "alice");
    const { client: bob } = await signedInUser(t, "bob");
    const sourceConversation = await alice.mutation(api.conversations.create);
    const targetConversation = await alice.mutation(api.conversations.create);

    await expect(
      bob.mutation(
        api.messages.send,
        sendArgs(sourceConversation, "unauthorized"),
      ),
    ).rejects.toThrow("Not a member");

    const key = "conversations/source/alice/image.jpg";
    await t.run(async (ctx) => {
      await ctx.db.insert("mediaAssets", {
        r2Key: key,
        accessToken: "secret-capability",
        kind: "image",
        userId: aliceUser._id,
        conversationId: sourceConversation,
        createdAt: Date.now(),
      });
    });

    await expect(
      alice.mutation(api.messages.send, {
        ...sendArgs(targetConversation, "wrong-upload-scope"),
        attachments: [{ type: "image", r2Key: key, thumbR2Key: key }],
      }),
    ).rejects.toThrow("Attachment upload is not valid for this conversation");
  });
});
