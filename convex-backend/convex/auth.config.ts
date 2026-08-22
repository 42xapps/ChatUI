import type { AuthConfig } from "convex/server";

/**
 * `domain` is the Clerk Frontend API URL for this instance, e.g.
 * `https://verb-noun-00.clerk.accounts.dev` in development. Set it with:
 *
 *     npx convex env set CLERK_FRONTEND_API_URL https://...
 *
 * `applicationID` must be `"convex"`: it is matched against the `aud` claim of
 * the Clerk session token, which the Clerk Dashboard's Convex integration
 * pre-maps for you. `ClerkConvexAuthProvider` on iOS calls
 * `session.getToken()` with no template argument, so this works off the default
 * session token — there is no separately named `convex` JWT template to create.
 */
export default {
  providers: [
    {
      domain: process.env.CLERK_FRONTEND_API_URL!,
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
