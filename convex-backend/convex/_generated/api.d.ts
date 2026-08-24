/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as agents_companion from "../agents/companion.js";
import type * as ai from "../ai.js";
import type * as attachments from "../attachments.js";
import type * as conversations from "../conversations.js";
import type * as http from "../http.js";
import type * as llmUsage from "../llmUsage.js";
import type * as messages from "../messages.js";
import type * as model_attachments from "../model/attachments.js";
import type * as model_conversations from "../model/conversations.js";
import type * as model_generationTurns from "../model/generationTurns.js";
import type * as model_messages from "../model/messages.js";
import type * as model_users from "../model/users.js";
import type * as r2 from "../r2.js";
import type * as rateLimiting from "../rateLimiting.js";
import type * as users from "../users.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  "agents/companion": typeof agents_companion;
  ai: typeof ai;
  attachments: typeof attachments;
  conversations: typeof conversations;
  http: typeof http;
  llmUsage: typeof llmUsage;
  messages: typeof messages;
  "model/attachments": typeof model_attachments;
  "model/conversations": typeof model_conversations;
  "model/generationTurns": typeof model_generationTurns;
  "model/messages": typeof model_messages;
  "model/users": typeof model_users;
  r2: typeof r2;
  rateLimiting: typeof rateLimiting;
  users: typeof users;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {
  r2: import("@convex-dev/r2/_generated/component.js").ComponentApi<"r2">;
  agent: import("@convex-dev/agent/_generated/component.js").ComponentApi<"agent">;
  rateLimiter: import("@convex-dev/rate-limiter/_generated/component.js").ComponentApi<"rateLimiter">;
};
