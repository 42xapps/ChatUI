<!-- Source: https://docs.convex.dev/agents/rag.md | Pulled 2026-08-22 | @convex-dev/agent@0.7.1 -->

# RAG with the Agent component

The Agent has built-in hybrid text+vector search over its OWN message
history (see context.md's `searchOptions`/`searchOtherThreads`). For
external/custom knowledge bases, there's a **separate, standalone**
`@convex-dev/rag` component (https://www.convex.dev/components/rag) — chunks
data, generates embeddings, supports namespaces (per-user/team isolation),
importance weighting, custom filters, and migrations.

Note: mem0 (planned future work for this app — see architecture doc) serves a
similar but distinct role to the RAG component: cross-session distilled
*personal facts about the user*, vs. RAG's general "search a knowledge base"
model. Not necessarily mutually exclusive, but this app doesn't need the RAG
component today — no external knowledge base exists yet.

## Two approaches (if/when a knowledge base is added)

### 1. Prompt-based RAG (always searches, simple/predictable)

```ts
const context = await rag.search(ctx, { namespace: "global", query: userPrompt, limit: 10 });
const result = await agent.generateText(ctx, { threadId }, {
  prompt: `# Context:\n\n ${context.text}\n\n---\n\n# Question:\n\n"""${userPrompt}\n"""`,
});
```

### 2. Tool-based RAG (LLM decides when to search)

```ts
searchContext: createTool({
  description: "Search for context related to this user prompt",
  args: z.object({ query: z.string() }),
  handler: async (ctx, { query }) => {
    const context = await rag.search(ctx, { namespace: userId, query });
    return context.text;
  },
}),
```

| | Prompt-based | Tool-based |
|---|---|---|
| Context search | Always | AI decides |
| Adding context | Manual | AI can add during conversation |
| Predictability | High | Adaptive but may over/under-query |

## Ingesting non-text content

- **Images**: works surprisingly well — use `generateText` with an image part
  to get a text description, then embed that description.
- **PDFs**: prefer parsing client-side with Pdf.js (server-side parsing is
  memory-heavy and the pdfjs bundle is large) — see the RAG demo's
  `pdfUtils.ts`/`UploadSection.tsx`.
- **Text/code/markdown**: usable directly; an LLM pass can still improve
  embedding quality by restructuring first.
