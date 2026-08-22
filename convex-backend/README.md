# convex-backend

Convex backend for `ChatConvexExample`: chat history, realtime message delivery,
and presigned Cloudflare R2 uploads for attachments.

Kept as its own npm project because the Convex CLI expects a `convex/` folder
inside a JS/TS project and knows nothing about the Xcode project next door.

One conversation per user. No groups, no human-to-human chat — the app opens
straight into the signed-in user's thread.

## Layout

| Path | Purpose |
| --- | --- |
| `convex/schema.ts` | Tables, indexes, and the shared attachment/recording validators |
| `convex/auth.config.ts` | Clerk as the JWT issuer |
| `convex/convex.config.ts` | Installs the `@convex-dev/r2` component, declares typed env |
| `convex/users.ts` | `syncCurrentUser` |
| `convex/conversations.ts` | `getOrCreateMine` |
| `convex/messages.ts` | `listForConversation` (paginated), `send` |
| `convex/attachments.ts` | `requestUploadUrl` — authenticated, membership-scoped presigned PUT |
| `convex/http.ts` | `GET /r2/<key>` → redirect to a freshly signed download URL |
| `convex/model/` | Shared helpers: auth lookups, membership checks, URL derivation |

Six public functions plus the HTTP action. `convex/model/` holds no registered
functions, only helpers.

## Per-user isolation

`conversationMembers` is the join table between `users` and `conversations`, and
the only path from a user to a conversation:

- `conversations.getOrCreateMine` reads `by_user`, so a caller can only ever
  reach their own thread.
- `messages.send` and `messages.listForConversation` call `requireMembership`
  — via `by_conversation_and_user` — before reading or writing anything.
- `attachments.requestUploadUrl` does the same, and derives the object key from
  the verified conversation and user ids, so a client can't write outside its
  own prefix.

This replaces the reference app's `.whereField("users", arrayContains: uid)`
filter, which was a client-side query constraint rather than an authorization
check. It stays a join table rather than a `userId` column on `conversations`
because that's what keeps the authorization check indexed and keeps the door
open to more than one member per thread (an assistant, later) without a
migration.

## Setup

```sh
npm install
npx convex dev        # links this folder to a Convex deployment, then watches
```

### Environment variables

Set on the deployment (`npx convex env set NAME 'value'`), not in a local
`.env`:

| Variable | Required | Notes |
| --- | --- | --- |
| `CLERK_FRONTEND_API_URL` | yes | **Must include the scheme**: `https://verb-noun-00.clerk.accounts.dev`. Convex matches it against the JWT `iss` claim and fetches `{domain}/.well-known/openid-configuration`; without `https://` every authenticated call fails with "Not signed in". |
| `R2_BUCKET` | yes | Bucket name |
| `R2_ENDPOINT` | yes | `https://<account-id>.r2.cloudflarestorage.com` (account-level; the SDK appends the bucket) |
| `R2_ACCESS_KEY_ID` | yes | From **Manage R2 API Tokens** → Object Read & Write |
| `R2_SECRET_ACCESS_KEY` | yes | ditto |
| `R2_PUBLIC_BASE_URL` | no | An R2 custom domain or the bucket's `r2.dev` URL. When set, attachment URLs point straight at Cloudflare's edge instead of through the `/r2/*` redirect. Declared in `convex.config.ts` and read via the typed `env` object, so a typo fails the deploy rather than silently yielding `undefined`. |

`auth.config.ts` is evaluated at push time, so **changing
`CLERK_FRONTEND_API_URL` requires a redeploy**, not just `env set`.

The `@convex-dev/r2` README also lists `R2_TOKEN`, but nothing reads it —
`createR2Client` builds the S3 client from the endpoint and the access key pair
only. It's the "Token Value" Cloudflare shows next to the key pair; the
S3-compatible API doesn't use it.

**No CORS policy is needed for the iOS app.** CORS is a browser mechanism, and
`URLSession` isn't subject to it, so presigned PUTs from the app work against a
bucket with no CORS rules at all. Add one only if a web client is introduced.

### Clerk

`applicationID: "convex"` in `auth.config.ts` is matched against the `aud`
claim of Clerk's **default session token** — the Clerk Dashboard's Convex
integration pre-maps it. `ClerkConvexAuthProvider` on iOS calls
`session.getToken()` with no template argument, so there is no separately named
`convex` JWT template to create for the Swift client.

## Attachment URLs

Messages persist R2 object *keys*, never URLs; `model/attachments.ts` derives a
URL on read. Two schemes, chosen by whether `R2_PUBLIC_BASE_URL` is set:

- **Set** — `https://cdn.example.com/<key>`. Cached at Cloudflare's edge, no
  redirect.
- **Unset** — `https://<deployment>.convex.site/r2/<key>`, which 302s to a
  one-hour signed URL. Keeps the bucket private and needs no extra Cloudflare
  setup.

Either way the URL for a key is stable, which matters because
`messages.listForConversation` is a live subscription: URLs that changed on
every update would miss the client's image cache on every re-render. The keys
are also returned alongside the URLs and used as cache keys, so caching survives
flipping `R2_PUBLIC_BASE_URL` on or off.

## Verifying credentials without the app

The `/r2/*` action signs a redirect using the same config the component uses, so
it doubles as a credential check:

```sh
curl -sL -w '%{http_code}\n' "https://<deployment>.convex.site/r2/does-not-exist.jpg"
```

`404` with `<Code>NoSuchKey</Code>` means the key pair, endpoint and bucket are
all correct. `403` means they aren't. A `500` from the redirect itself means one
of the four `R2_*` variables is missing.
