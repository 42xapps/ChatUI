import { defineApp } from "convex/server";
import { v } from "convex/values";
import r2 from "@convex-dev/r2/convex.config.js";

const app = defineApp({
  env: {
    /**
     * An R2 custom domain or the bucket's `r2.dev` URL. When set, attachment
     * URLs point straight at Cloudflare's edge instead of going through the
     * `/r2/*` redirect in `http.ts`.
     */
    R2_PUBLIC_BASE_URL: v.optional(v.string()),
  },
});

app.use(r2);

export default app;
