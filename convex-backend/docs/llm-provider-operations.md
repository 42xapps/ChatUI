# Companion model-provider operations

Provider and model selection are server-only deployment settings. The iOS app
never sends either value, and `convex/agents/companion.ts` rejects anything not
in its reviewed allowlist before making a billable request.

The allowlist was checked against the providers' current catalogs on
2026-08-23. Recheck lifecycle, capabilities, and pricing before adding a model;
model aliases are operational dependencies, not arbitrary strings.

## Supported settings

| `COMPANION_PROVIDER` | Default model | Other allowlisted models | Required secret | Image input |
| --- | --- | --- | --- | --- |
| `openai` | `gpt-4o-mini` | `gpt-4.1-mini`, `gpt-4.1` | `OPENAI_API_KEY` | Yes |
| `google` | `gemini-3.7-flash` | `gemini-3.6-flash`, `gemini-3.5-flash` | `GOOGLE_GENERATIVE_AI_API_KEY` | Yes |
| `deepseek` | `deepseek-v4-flash` | `deepseek-v4-pro` | `DEEPSEEK_API_KEY` | No |
| `moonshot` | `kimi-k3` | `kimi-k2.6` | `MOONSHOT_API_KEY` | Yes |
| `qwen` | `qwen-plus` | `qwen3-vl-plus` | `QWEN_API_KEY` | Only `qwen3-vl-plus` |

Qwen also requires `QWEN_BASE_URL`, because DashScope endpoints and model
availability vary by region. Use the endpoint from the same Model Studio region
where the key and chosen model are provisioned.

DeepSeek's former `deepseek-chat` and `deepseek-reasoner` aliases were retired
on 2026-07-24, so they are intentionally not accepted. Kimi K2.5 is also
intentionally excluded because the provider announced its platform sunset for
2026-08-31. The registry uses current stable identifiers instead of keeping
aliases that are about to fail.

Primary catalogs:

- [Google Gemini models](https://ai.google.dev/gemini-api/docs/models)
- [DeepSeek models and pricing](https://api-docs.deepseek.com/quick_start/pricing/)
- [Kimi model list](https://platform.kimi.ai/docs/models)
- [Alibaba Model Studio model pricing/catalog](https://help.aliyun.com/en/model-studio/model-pricing)
- [Gemini API billing and prepaid credits](https://ai.google.dev/gemini-api/docs/billing#prepay)

Google's free tier covers only selected models. A project assigned to the
prepay plan serves API requests only while its billing account has a positive
prepaid balance, regardless of whether the API key itself is valid.

## Switching the development deployment

First confirm that `.env.local` points at the intended development deployment.
Then set the non-secret selector values explicitly, for example:

```sh
npx convex env set COMPANION_PROVIDER google
npx convex env set COMPANION_MODEL gemini-3.7-flash
```

Keep credentials out of shell history. On macOS, copy the real provider key and
pipe it to Convex:

```sh
pbpaste | npx convex env set GOOGLE_GENERATIVE_AI_API_KEY
```

For Qwen, set `QWEN_BASE_URL` to the official regional endpoint as well. Never
set a placeholder credential and never use `--prod` during development.

After changing provider settings:

1. Run `npm run typecheck` and `npm test`.
2. Run `npx convex dev --once` and confirm the printed target is the intended
   development deployment.
3. Send one real Simulator message and confirm `llmUsageEvents` records the
   actual provider/model and token counts.
4. Confirm text grows across multiple reads and visually inspect bubble height,
   bottom pinning, attachment interpretation, and the final completed state.
5. Enable a provider/model for users only after this smoke test succeeds. A
   typechecked adapter is not evidence that a credential, regional endpoint,
   model entitlement, multimodal behavior, or billing account works.

## Cost records

Every completed turn snapshots provider, model, input/output/cache/reasoning
tokens in `llmUsageEvents`. Dollar cost is deliberately calculated from those
immutable usage facts and the provider invoice/pricing effective for that date;
it is not hard-coded into a historical row using a price that can later drift.
Before launch, connect this ledger to the chosen billing report and reconcile
estimated totals against provider invoices.
