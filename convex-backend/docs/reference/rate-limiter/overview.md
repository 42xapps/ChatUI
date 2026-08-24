<!-- Source: https://www.convex.dev/components/rate-limiter | Pulled 2026-08-22 | @convex-dev/rate-limiter@0.3.2 -->

# Rate Limiter Component

Type-safe, transactional rate limiting for Convex apps: configurable
sharding, fair queuing via credit reservation. Fixed-window or token-bucket
algorithms. Enforcement is transactional — rolls back on mutation failure.

```
npm install @convex-dev/rate-limiter
```

- npm: https://www.npmjs.com/package/@convex-dev/rate-limiter
- GitHub: https://github.com/get-convex/rate-limiter

See `../convex-agent/rate-limiting.md` for the concrete usage pattern paired
with the Agent component (per-user message-frequency + token-usage limits).
