# ChatConvexExample: Convex + Clerk + Cloudflare R2 backend

## Context

`ChatFirestoreExample/` is the existing reference app: Firebase Firestore for chat
history/realtime, Firebase Storage for media, a bespoke device-ID+nickname auth flow.
It stays **untouched** as a reference — do not modify it.

This spec defines a **new** app target, `ChatConvexExample/`, that gives the same
chat experience (built on the `ExyteChat` SwiftUI package) but backed by:

- **Convex** for chat history, conversation list, and realtime message delivery
- **Clerk** for auth (Sign in with Apple + email/password)
- **Cloudflare R2** for attachment storage (images / video / voice notes; GIFs from
  Giphy need no upload — they're already hosted on Giphy's CDN)

Explicitly **out of scope** for this pass: LLM integration, voice-to-voice, mem0.
Don't build placeholders or stubs for any of these — just leave the surface for
"send a message" as the terminal action for now.

Accounts already exist: Convex project, Clerk application, Cloudflare R2 bucket +
API token. The user will supply the deployment URL / publishable key / JWT template
name / R2 credentials as env values when you start — ask for whichever you need,
don't invent placeholders and move on silently.

## Reference docs — use these, don't hallucinate SDK APIs

- `docs/convex-llm.txt` — Convex docs index (llms.txt format: links + one-line
  descriptions). Use it to find the right page, then fetch that specific page
  (`https://docs.convex.dev/...`) via WebFetch/WebSearch for the real API surface.
- `docs/cloudflare-r2-llms-full.txt` — **this is the full Cloudflare docs dump
  (1.17M lines), not R2-scoped.** Don't read it wholesale. `grep -n` it for R2
  keywords (`presigned`, `PutObject`, `S3 API`, `CORS`) or just fetch
  `https://developers.cloudflare.com/r2/llms.txt` directly instead.
- Convex ↔ Clerk (backend): https://docs.convex.dev/auth/clerk
- Convex ↔ Clerk (iOS): https://clerk.com/docs/ios/reference/native-mobile/integrations/convex
- Convex Swift client: https://docs.convex.dev/client/swift ,
  https://docs.convex.dev/quickstart/swift
- Clerk-Convex Swift glue package: https://github.com/clerk/clerk-convex-swift
  (`ClerkConvexAuthProvider` — use this, don't hand-write a token-fetch bridge)
- Clerk iOS SDK: https://clerk.com/docs/ios/getting-started/quickstart ,
  https://github.com/clerk/clerk-ios
- Convex R2 component: https://www.convex.dev/components/cloudflare-r2 ,
  https://github.com/get-convex/r2 (`@convex-dev/r2` — use its `generateUploadUrl`
  flow, don't hand-roll S3 signing)

Before writing any integration code, fetch the specific doc page for that piece
and confirm the exact API (import names, function signatures) rather than
guessing from memory or from this spec's paraphrase.

**Open question to verify, not assume:** whether Clerk's Swift `ClerkConvexAuthProvider`
also requires the JWT template to be named exactly `convex` (confirmed true for the
JS `ConvexProviderWithClerk`; check the `clerk-convex-swift` README for the Swift
equivalent before wiring `auth.config.ts`).

## Why this isn't a literal 1:1 port of ChatFirestoreExample

`ChatFirestoreExample` scopes each user's conversations via
`.whereField("users", arrayContains: currentUserId)` — a full-array-scan filter.
That's the mechanism guaranteeing per-user chat history isolation today.

Convex's correct equivalent is a **`conversationMembers` join table**
(`conversationId`, `userId`, `unreadCount`) with an indexed `by_user` field —
same guarantee, indexed instead of scanned, and it lets `messages.send` reject
writes from non-members server-side (real authorization, not just a client-side
query filter). Build it this way, not as a `users: string[]` array field on
`conversations`.

## Convex backend (`convex-backend/` at repo root, sibling to `ChatConvexExample/`)

New Node/TS project (own `package.json`, `tsconfig.json`) — Convex's CLI expects
a `convex/` folder in a JS/TS project; it has no awareness of the Xcode project
structure, so keep it separate from `ChatConvexExample/`.

`convex/schema.ts`:
- `users` — clerkId (indexed), name, avatarUrl. Upserted lazily on first
  authenticated call (or via a Clerk webhook if you find that's the documented
  pattern — check the docs page, don't assume).
- `conversations` — title, isGroup, pictureUrl, createdAt.
- `conversationMembers` — conversationId, userId, unreadCount. Index `by_user`
  and `by_conversation`.
- `messages` — conversationId (index `by_conversation`), senderId, text,
  attachments (array of `{url, thumbUrl, type, r2Key}`), recording
  (`{duration, waveformSamples, url}`), replyTo (optional message ref), createdAt.

`convex/auth.config.ts` — Clerk JWT issuer per the docs page above.

Functions (exact file split up to you, but cover):
- `users`: get-or-create current user from `ctx.auth.getUserIdentity()`.
- `conversations`: `listMine` (via `conversationMembers.by_user`), `create`
  (inserts conversation + membership rows), `markRead`.
- `messages`: `listForConversation` (paginated — use Convex's built-in
  `.paginate()`, indexed `by_conversation`), `send` (must verify the caller is a
  member of the conversation before writing — this is the authorization check
  Firestore's client-permissive model didn't give us).
- R2 upload: wrap `@convex-dev/r2`'s `generateUploadUrl` in an authenticated
  mutation; attach the resulting key/URL to a message via `messages.send`'s
  attachment payload.

## iOS (`ChatConvexExample/`)

Copy `ChatFirestoreExample`'s pure-SwiftUI views (`ConversationsView`,
`ConversationView`, `AvatarView`, etc. — anything with no `Firebase*` import)
as the starting point. Then, file by file:

- `Managers/SessionManager.swift` — keep the local-caching shape; current-user
  identity now comes from Clerk's session + the synced Convex `users` row
  instead of device-ID/nickname lookup.
- `Auth/AuthViewModel.swift` → replace with Clerk's SwiftUI sign-in flow
  (Sign in with Apple + email/password), using Clerk's prebuilt components if
  the SDK offers them for this — don't hand-build screens the SDK already gives you.
- `Managers/DataStorageManager.swift` → `.addSnapshotListener()` calls become
  `ConvexClientWithAuth` query subscriptions (`conversations.listMine`,
  `users` list). Keep the `@Published` array shape and the
  `storeConversations`/`makeConversation` mapping logic as-is.
- `Conversation/ConversationViewModel.swift` → `subscribeToMessages()` becomes a
  subscription to `messages.listForConversation`; `sendMessage(_:)` calls the
  `messages.send` mutation. **Keep the optimistic-insert-then-reconcile-by-id
  logic verbatim** (insert locally with `.sending` status, replace with the
  server copy once it arrives with the same id, flip to `.sent`) — it was never
  Firestore-specific.
- `Managers/UploadingManager.swift` → keep the same 4 method signatures
  (`uploadImageMedia`, `uploadVideoMedia`, `uploadRecording`, `uploadImageData`);
  internals become: call the R2 upload-URL mutation → `URLSession.upload` the
  raw bytes directly to R2 → return the resulting URL. Giphy attachments need
  no upload step — they're already a hosted URL.
- `Model/Conversation.swift` / message model → plain Codable structs matching
  Convex's document shape (`_id`/`_creationTime`, no `@DocumentID`/`@ServerTimestamp`).
- `Conversations/ConversationsViewModel.swift` and the SwiftUI views — copy
  over near-verbatim; they were never Firebase-dependent.
- New SPM dependencies: `get-convex/convex-swift`, `clerk/clerk-ios`,
  `clerk/clerk-convex-swift`.
- App entry point: configure `Clerk.shared`, construct `ConvexClientWithAuth`
  with `ClerkConvexAuthProvider`, drive root navigation off `authState`
  (signed-out → Clerk sign-in, signed-in → conversations list).

## Suggested order of work

1. Convex backend: schema, `auth.config.ts`, functions, R2 component wiring.
   Verify with `npx convex dev` that everything deploys and typechecks.
2. iOS: add the three SPM packages.
3. iOS: Clerk sign-in (Apple + email/password) wired to `authState`.
4. iOS: `ConvexClientWithAuth` wiring + root view driven by auth state.
5. iOS: port conversations list + conversation screen, file by file per the
   mapping above.
6. iOS: `UploadingManager` R2 rewrite, wired into the attachment-send path.
7. Build after each phase (`swift build` / `xcodebuild` for the
   `ChatConvexExample` scheme) — don't let more than one phase's worth of
   unverified code stack up.

## Verification

- Sign in as two distinct Clerk test users (two simulators, or simulator +
  device) and confirm each only ever sees their own conversations —
  this is the specific thing the join-table design above needs to prove out.
- Send text, an image (Photos), and a GIF (Giphy) in a conversation; confirm
  realtime delivery to the other simulator, and that image attachments resolve
  to working R2 URLs.
- Kill and relaunch the app mid-conversation; confirm chat history reloads
  correctly from Convex (not just from the optimistic local cache).
- No dead code, no `// TODO` stubs left for out-of-scope features — if
  something from this spec turns out to need LLM/voice/mem0 hooks, leave a
  clean extension point, not a half-built stub.
