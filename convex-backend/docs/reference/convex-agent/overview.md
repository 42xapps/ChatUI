<!-- Source: https://docs.convex.dev/agents/overview | Pulled 2026-08-22 | @convex-dev/agent@0.7.1
     Note: fetched via WebFetch's summarizer (page required JS rendering for full prose);
     content below is a faithful summary, not verbatim page text. Sub-page list confirmed
     against the authoritative https://docs.convex.dev/llms.txt index. -->

# Convex Agent Component Overview

## What is the Agent Component?

The Agent component is a foundational building block for constructing AI agent
applications. It manages threads and messages that enable agents to function
within static or dynamic workflows, allowing developers to embed agentic logic
directly into Convex actions alongside other business logic.

## Core Concepts

- **Agents**: organize LLM prompting with associated models, prompts, and
  Tools, and can generate both text and objects.
- **Threads**: persist messages and can be shared by multiple users and
  agents.
- **Conversation context**: automatically included in each LLM call,
  including built-in hybrid vector/text search.

## Full Agents docs sub-page index (from /llms.txt)

- `/agents/getting-started.md` — Setting up the agent component
- `/agents/agent-usage.md` — Configuring and using the Agent class
- `/agents/threads.md` — Group messages together in a conversation history
- `/agents/messages.md` — Sending and receiving messages with an agent
- `/agents/context.md` — Customizing the context provided to the Agent's LLM
- `/agents/streaming.md` — Streaming messages with an agent
- `/agents/tools.md` — Using tool calls with the Agent component
- `/agents/tool-approval.md` — Human-in-the-loop tool approval for the Agent component
- `/agents/rag.md` — Examples of how to use RAG with the Convex Agent component
- `/agents/files.md` — Working with images and files in the Agent component
- `/agents/human-agents.md` — Saving messages from a human as an agent
- `/agents/rate-limiting.md` — Control the rate of requests to your AI agent
- `/agents/usage-tracking.md` — Tracking token usage of the Agent component
- `/agents/workflows.md` — Defining long-lived workflows for the Agent component
- `/agents/playground.md` — A simple way to test, debug, and develop with the agent
- `/agents/debugging.md` — Debugging the Agent component

Deep-fetched into this directory: getting-started, agent-usage, threads,
messages, context, streaming, tools, rag, rate-limiting, usage-tracking.
Not deep-fetched (lower priority for this app's v1 — one-liner description
above is from the official index, not fabricated): files, human-agents,
workflows, playground, debugging, tool-approval.
