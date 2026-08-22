// import { httpRouter } from "convex/server";
// import { httpAction } from "./_generated/server";
// import { decodeKey } from "./model/attachments";
// import { r2 } from "./r2";

// const http = httpRouter();

// const R2_PREFIX = "/r2/";

// /**
//  * Serves an R2 object behind a stable URL by redirecting to a freshly signed
//  * one. Lets attachment URLs be persisted and cached client-side while the
//  * bucket itself stays private.
//  *
//  * Object keys embed a UUID, so a URL is only reachable by someone who was sent
//  * it — the same "unguessable download URL" model the Firebase Storage version
//  * of this app relied on. If you need real authorization on reads instead, put
//  * the bucket behind a Cloudflare Access policy or a custom domain with a
//  * signed-cookie rule.
//  */
// const serveAttachment = httpAction(async (_ctx, request) => {
//   const { pathname } = new URL(request.url);
//   const key = decodeKey(pathname.slice(R2_PREFIX.length));
//   if (key === "") {
//     return new Response("Missing object key", { status: 400 });
//   }

//   const expiresIn = 60 * 60;
//   const signedUrl = await r2.getUrl(key, { expiresIn });

//   return new Response(null, {
//     status: 302,
//     headers: {
//       Location: signedUrl,
//       // Let clients reuse the redirect, but never past the signature's life.
//       "Cache-Control": `private, max-age=${expiresIn - 60}`,
//     },
//   });
// });

// http.route({ pathPrefix: R2_PREFIX, method: "GET", handler: serveAttachment });
// http.route({ pathPrefix: R2_PREFIX, method: "HEAD", handler: serveAttachment });

// export default http;

// I commented code above to fix this issue:
// npx convex dev --once
// (node:86663) ExperimentalWarning: localStorage is not available because --localstorage-file was not provided.
// (Use `node --trace-warnings ...` to show where the warning was created)
// ✔ What would you like to configure? create a new project
// ✔ Project name: embie-backend
// ✔ Where should this dev deployment run?
// See https://www.convex.dev/pricing for pricing US East (N. Virginia)
// Tip: you can configure a default region for your team at https://dashboard.convex.dev/t/mo-san/settings
// ✔ Created project embie-backend, manage it at https://dashboard.convex.dev/t/mo-san/embie-backend
// ✔ Set up Convex AI files? (guidelines, AGENTS.md, agent skills) Yes
// ✔ /Users/bousttamohamed/Developer/tmp/ChatUI/convex-backend/convex/_generated/ai/guidelines.md written
// ✔ AGENTS.md written
// ✔ CLAUDE.md written
// Installing Convex agent skills...
// ✔ Skills installed
// ✔ Provisioned a dev deployment and saved its:
//     name as CONVEX_DEPLOYMENT
//     client URL as CONVEX_URL
//     HTTP actions URL as CONVEX_SITE_URL
//  to .env.local

// Write your Convex functions in convex/
// Give us feedback at https://convex.dev/community or support@convex.dev
// View the Convex dashboard at https://dashboard.convex.dev/d/exciting-vulture-777

// ▌ Developing against deployment:
// ▌  Development  mo-san:embie-backend:dev/mo-san (dev) (dashboard)
// ▌ └─ https://exciting-vulture-777.convex.cloud
// ✖ Error: Unable to start push to https://exciting-vulture-777.convex.cloud
// ✖ Error fetching POST  https://exciting-vulture-777.convex.cloud/api/deploy2/start_push 400 Bad Request: InvalidModules: Hit an error while pushing:
// Loading the pushed modules encountered the following
//     error:
// Failed to analyze http.js: Uncaught Error: 'HEAD' is not an allowed HTTP method (like GET, POST, PUT etc.)
//     at HttpRouter.route (../../node_modules/convex/src/server/router.ts:166:18)
//     at <anonymous> (../convex/http.ts:43:0)



import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { decodeKey } from "./model/attachments";
import { r2 } from "./r2";

const http = httpRouter();

const R2_PREFIX = "/r2/";

/**
 * Serves an R2 object behind a stable URL by redirecting to a freshly signed
 * one. Lets attachment URLs be persisted and cached client-side while the
 * bucket itself stays private.
 *
 * Object keys embed a UUID, so a URL is only reachable by someone who was sent
 * it — the same "unguessable download URL" model the Firebase Storage version
 * of this app relied on. If you need real authorization on reads instead, put
 * the bucket behind a Cloudflare Access policy or a custom domain with a
 * signed-cookie rule.
 */
const serveAttachment = httpAction(async (_ctx, request) => {
  const { pathname } = new URL(request.url);
  const key = decodeKey(pathname.slice(R2_PREFIX.length));
  if (key === "") {
    return new Response("Missing object key", { status: 400 });
  }

  const expiresIn = 60 * 60;
  const signedUrl = await r2.getUrl(key, { expiresIn });

  return new Response(null, {
    status: 302,
    headers: {
      Location: signedUrl,
      // Let clients reuse the redirect, but never past the signature's life.
      "Cache-Control": `private, max-age=${expiresIn - 60}`,
    },
  });
});

// Convex automatically routes HEAD requests through your GET handlers
http.route({ pathPrefix: R2_PREFIX, method: "GET", handler: serveAttachment });

export default http;
