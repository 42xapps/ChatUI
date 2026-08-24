import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import { httpAction } from "./_generated/server";
import { decodeKey } from "./model/attachments";
import { r2 } from "./r2";

const http = httpRouter();
const R2_PREFIX = "/r2/";
const SIGNED_URL_TTL_SECONDS = 10 * 60;

/**
 * Exchanges a revocable, message-bound capability URL for a short-lived R2
 * redirect. An object key by itself is intentionally insufficient.
 */
const serveAttachment = httpAction(async (ctx, request) => {
  const url = new URL(request.url);
  let key: string;
  try {
    key = decodeKey(url.pathname.slice(R2_PREFIX.length));
  } catch {
    return new Response("Malformed object key", { status: 400 });
  }
  const accessToken = url.searchParams.get("token") ?? "";
  if (key === "" || accessToken === "") {
    return new Response("Missing media capability", { status: 400 });
  }

  const authorized = await ctx.runQuery(
    internal.model.attachments.authorizeDownload,
    { key, accessToken },
  );
  if (!authorized) {
    return new Response("Media not found", { status: 404 });
  }

  const signedUrl = await r2.getUrl(key, {
    expiresIn: SIGNED_URL_TTL_SECONDS,
  });
  return new Response(null, {
    status: 302,
    headers: {
      Location: signedUrl,
      "Cache-Control": `private, max-age=${SIGNED_URL_TTL_SECONDS - 30}`,
      "Referrer-Policy": "no-referrer",
    },
  });
});

// Convex routes HEAD requests through GET handlers automatically.
http.route({ pathPrefix: R2_PREFIX, method: "GET", handler: serveAttachment });

export default http;
