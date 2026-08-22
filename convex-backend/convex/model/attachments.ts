import { env } from "../_generated/server";

/**
 * Turns an R2 object key into a URL the iOS app can hand straight to an image
 * loader.
 *
 * The result is stable for a given key, which matters: the messages query is a
 * live subscription, and a URL that changed on every update would defeat the
 * client's image cache. `r2.getUrl` returns a freshly signed, expiring URL, so
 * it is not used here — the `/r2/*` HTTP action (see `http.ts`) signs on demand
 * behind a stable path instead.
 *
 * Set `R2_PUBLIC_BASE_URL` to serve straight from Cloudflare's edge and skip
 * the redirect hop.
 */
export function attachmentUrl(key: string): string {
  const base = env.R2_PUBLIC_BASE_URL ?? `${env.CONVEX_SITE_URL}/r2`;
  return `${base.replace(/\/$/, "")}/${encodeKey(key)}`;
}

/** Percent-encodes each path segment while keeping the `/` separators. */
export function encodeKey(key: string): string {
  return key.split("/").map(encodeURIComponent).join("/");
}

/** Inverse of `encodeKey`, for the `/r2/*` HTTP action. */
export function decodeKey(path: string): string {
  return path.split("/").map(decodeURIComponent).join("/");
}
