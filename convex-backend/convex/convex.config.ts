import { defineApp } from "convex/server";
import { v } from "convex/values";
import agent from "@convex-dev/agent/convex.config";
import r2 from "@convex-dev/r2/convex.config.js";
import rateLimiter from "@convex-dev/rate-limiter/convex.config";

const app = defineApp({
  env: {
    /** Server-only allowlisted provider selection; defaults to OpenAI. */
    COMPANION_PROVIDER: v.optional(v.string()),
    /** Optional provider-specific model override. */
    COMPANION_MODEL: v.optional(v.string()),
    /** Only the selected provider's credential is required at runtime. */
    OPENAI_API_KEY: v.optional(v.string()),
    GOOGLE_GENERATIVE_AI_API_KEY: v.optional(v.string()),
    DEEPSEEK_API_KEY: v.optional(v.string()),
    MOONSHOT_API_KEY: v.optional(v.string()),
    QWEN_API_KEY: v.optional(v.string()),
    /** Region-specific OpenAI-compatible endpoint supplied by the operator. */
    QWEN_BASE_URL: v.optional(v.string()),
  },
});

app.use(r2);
app.use(agent);
app.use(rateLimiter);

export default app;
