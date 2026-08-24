# LLM chat production remediation

This checklist tracks the production-readiness work identified in the
2026-08-22 companion-chat audit. It deliberately separates work that can be
completed and tested locally from work that requires provider credentials,
funded usage, or a product decision.

## Implement now

- [x] Persist generation turns with explicit queued, generating, completed,
      failed, and cancelled states.
- [x] Serialize generation per conversation and bound global concurrency with
      attempt leases so stale actions cannot write.
- [x] Cancel queued/running turns when a conversation is deleted.
- [x] Return typed send-admission outcomes and retry-after values to iOS.
- [x] Preserve message identity and uploaded media across an outgoing retry.
- [x] Render companion thinking, streaming, and structured failure states.
- [x] Treat streamed text as a height-changing row update in ExyteChat.
- [x] Add an allowlisted OpenAI, Google, DeepSeek, Kimi, and Qwen provider
      registry; select it only from server environment variables.
- [x] Remove unused embeddings until vector retrieval is deliberately enabled.
- [x] Bound output, recent context, total context text, request duration,
      per-user/global request admission, token reservations, and concurrency.
- [x] Persist model/provider/token usage in an application-owned ledger.
- [x] Track every R2 upload, bind it to its user/conversation, claim it in the
      same transaction as the message, and delete abandoned/conversation media.
- [x] Require a revocable media capability token before issuing an R2 URL.
- [x] Scope message idempotency to conversation plus client ID.
- [x] Bound the conversation sidebar query and denormalize membership recency.
- [x] Pass images and Giphy media to vision-capable models without pretending
      unsupported providers saw them.
- [x] Add a deterministic initial companion greeting.
- [x] Add deterministic tests for state transitions, authorization,
      idempotency, deletion races, retry identity, and stream-row diffing.
- [x] Run typecheck, tests, authz/reviewer scans, an arm64 Simulator build, and
      push only to the existing Convex dev deployment.

## External or deliberately deferred

- [ ] Fund/configure at least one selected model provider and verify a real
      successful streamed reply in the Simulator.
- [ ] Exercise every enabled non-OpenAI provider/model combination with its
      real credential before enabling it for users; the registry is typechecked
      but provider-specific behavior is not yet integration-tested.
- [ ] Visually validate growing-bubble animation, bottom pinning, and scrolling
      during a real stream; tune stream cadence only from that evidence.
- [ ] Add voice transcription and video understanding after selecting and
      funding the corresponding provider pipeline.
- [ ] Add generated conversation titles after successful provider operation is
      available.
- [ ] Define crisis/safety policy and run provider-specific behavioral and
      persona evaluations before public launch.
- [ ] Add mem0 or another governed long-term-memory implementation in its
      existing context-handler seam; it remains out of scope for this pass.
- [ ] Roll schema/index changes to production with the staged migration and
      production-consent process; this pass targets development only.

## Verification notes

- 2026-08-23: the PepGPT arm64 Simulator build and ExyteChat test suite passed.
- 2026-08-23: a real Maestro chat flow observed the outgoing message, the
  `companion-generation-thinking` state, and the final structured
  `provider_billing` row against the unfunded OpenAI account. This verifies the
  failure lifecycle, not successful generation or growing streamed text.
- 2026-08-23: backend typecheck and all eleven deterministic companion tests
  passed. Runtime changes were pushed only to the development deployment
  `exciting-vulture-777`.
- 2026-08-23: current provider catalogs were rechecked. Retired DeepSeek aliases
  and the imminently sunset Kimi K2.5 entry were replaced with current stable
  model IDs; operational switching guidance is in
  `docs/llm-provider-operations.md`.
- 2026-08-23: the development deployment was switched to Google
  `gemini-3.7-flash`. A real Simulator message reached that exact model, but
  Google returned `RESOURCE_EXHAUSTED` because the linked prepayment balance is
  depleted. The provider retry boundary was corrected and a second live run
  confirmed this permanent billing failure now makes one request, not three.
