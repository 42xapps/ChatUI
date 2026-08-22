import { R2 } from "@convex-dev/r2";
import { components } from "./_generated/api";

/**
 * Shared R2 client. Reads `R2_BUCKET`, `R2_ENDPOINT`, `R2_ACCESS_KEY_ID` and
 * `R2_SECRET_ACCESS_KEY` from the deployment's environment variables.
 *
 * Presigned upload URLs are minted by `attachments.requestUploadUrl`; download
 * URLs are built by `model/attachments.ts`.
 */
export const r2 = new R2(components.r2);
