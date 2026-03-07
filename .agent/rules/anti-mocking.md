---
trigger: always_on
priority: T2
---

# Anti-Mocking Testing Rule

> **Board Decision**: 5-0 APPROVED (2026-03-02) — Allowlist approach
> **Principle**: Never mock what you can use for real.

## The Rule

When writing tests, **DO NOT MOCK** unless the dependency falls on the explicit allowlist below. LLMs default to heavy mocking, producing tests that don't actually verify real code paths. This is unacceptable.

## Allowlist — These MAY Be Mocked

| Dependency | Why Mock Is Acceptable |
|------------|----------------------|
| **Stripe API** | Charges real money; use Stripe test mode or fixture responses |
| **SendGrid / Email** | Sends real emails; mock transport layer |
| **ShipEngine / Carrier APIs** | External paid API; use fixture responses |
| **`Date.now()` / `new Date()`** | Time-dependent tests need deterministic values |
| **`Math.random()` / `crypto.randomUUID()`** | Non-deterministic; seed or mock for reproducibility |
| **Rate limiters** | Timing-dependent; mock to test limit behavior |
| **File system (production paths)** | Use temp directories instead of mocking |

## Everything Else — DO NOT MOCK

| Use Instead | Rather Than Mocking |
|------------|-------------------|
| **MongoDB Memory Server** | Mocking Mongoose models/queries |
| **Real middleware chain** | Mocking `req`/`res`/`next` |
| **Real service instances** | Mocking service methods |
| **Test database with fixtures** | Mocking DB calls |
| **Real Express app** (`supertest`) | Mocking route handlers |
| **Real BullMQ with test queues** | Mocking job processors |
| **Real Socket.IO test server** | Mocking socket events |

## Critical Rules

1. **Auth tests must NEVER mock auth middleware** — if auth passes in tests but fails in production, the test is worthless
2. **Payment tests must NEVER mock the core WalletService** — mock Stripe, not your own service
3. **If a test passes with the implementation deleted, the test is invalid** — it's testing mocks, not code
4. **Every test must exercise the actual code path it claims to test**

## Test Validation Checklist

Before submitting any test:

- [ ] Does this test actually call real code (not mocked code)?
- [ ] Would this test FAIL if I introduced a bug in the real implementation?
- [ ] Am I mocking something on the allowlist? If not, use the real thing.
- [ ] For integration tests: am I testing the full middleware chain?

## Enforcement

- This rule is enforced during **C2 (Implementation + Security)** gate
- Test files with excessive mocking (>3 mocks not on allowlist) should be flagged for rewrite
- Agents that produce mock-heavy tests should have their output **scrapped and rerun**
