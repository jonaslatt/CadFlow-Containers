# ADR-011: User Management and Billing

## Status
Proposed

## Date
2026-04-07

## Context

CadFlow is a web-based SaaS CAD tool with AI-powered features (Claude). Before building the product, we need to decide how users authenticate, how we bill them, and how we control costs — particularly around AI inference and compute resources that have real per-request costs.

Unlike traditional SaaS where marginal cost per user is near-zero, CadFlow has three significant variable cost drivers:
- **AI inference:** Every Claude call (intent parsing, code generation, geometry reasoning) costs money. A single complex query can cost $0.05-0.50 depending on context length and model tier.
- **Compute:** CadQuery/OCCT operations run server-side. CFD preprocessing (meshing, geometry cleanup) can be CPU-intensive. A complex boolean operation or mesh refinement can consume seconds to minutes of compute.
- **Storage:** 3D models, STEP/IGES exports, project history, and cached geometry results consume storage per user.

This means the billing model must be tightly coupled to usage — we cannot offer flat-rate "unlimited" plans without risking catastrophic unit economics. At the same time, we need predictable revenue for sustainability and investor confidence.

Key forces at play:
- **Product-led growth:** Users must experience value before paying. A free tier is essential, but it must have guardrails that prevent abuse while demonstrating the agentic CAD value proposition.
- **Developer experience:** The founding team is small. Every hour spent on billing plumbing is an hour not spent on the CAD engine. We need solutions that minimize operational overhead.
- **Tax compliance:** Selling globally means VAT, GST, and US state sales tax obligations. Handling this wrong creates legal risk.
- **Churn prevention:** CAD tools have high switching costs once users build projects. We need to detect churn signals early and act on them.
- **Support scaling:** Early users will need hand-holding. The support strategy must scale from 5 users to 5,000 without hiring a team.

## Research Findings

### Authentication and User Management

**Auth0** (Okta) is the incumbent identity platform. Enterprise-grade, supports every auth flow, but complex to configure and expensive at scale ($23/1000 MAU on Essentials plan). Best for teams that need SAML/SSO for enterprise customers. Source: Auth0 pricing page (2026), Auth0 documentation.

**Clerk** has become the default for Next.js applications. Pre-built UI components (`<SignIn />`, `<UserProfile />`), excellent DX, built-in organization management for team billing. Free up to 10,000 MAU, $0.02/MAU after. Ships with session management, MFA, and social login out of the box. Source: Clerk documentation, Clerk pricing page (2026), Next.js ecosystem surveys.

**Supabase Auth** is the best choice if already using Supabase for the database layer. Row-level security integrates directly with auth. Free tier is generous (50,000 MAU). Less polished UI components than Clerk, but deeply integrated with the Supabase ecosystem. Source: Supabase Auth documentation, Supabase pricing page (2026).

**Firebase Auth** remains a solid option with generous free tier (unlimited auth, effectively). However, it pulls you toward the Google Cloud ecosystem and has weaker organization/team management compared to Clerk. Source: Firebase Auth documentation (2026).

For CadFlow specifically, Clerk is the strongest fit if building on Next.js (which ADR-003 likely specifies). If using Supabase as the primary database, Supabase Auth avoids an extra dependency. The key requirement is support for **organization-level billing** — teams sharing a CadFlow workspace must be billed as a unit, not per-seat.

### Product-Led Growth and Onboarding

Research from OpenView Partners (2024-2025) and Pocus (2025) shows that the most successful PLG SaaS tools follow a consistent pattern:

1. **Time-to-value under 5 minutes.** Users must create their first 3D model in the first session. For CadFlow, this means the AI agent must work without requiring payment setup.
2. **Natural upgrade triggers.** The free tier should limit things users discover they need *after* getting value — not gate the initial experience. For CAD tools, the best triggers are: export formats (STEP/IGES locked to paid), project count limits, and AI operation quotas.
3. **Reverse trial (optional).** Give all users Pro features for 14 days, then downgrade to free. This lets users experience the full product before deciding. Ahrefs and Notion have used this successfully. Source: OpenView Partners PLG benchmarks (2025).

**Churn signals specific to CAD SaaS:**
- Login frequency drops from daily to weekly
- Fewer projects saved or modified in the last 30 days
- AI operations per session declining (users stop using the differentiating feature)
- Support ticket sentiment turns negative
- Export activity drops (users are no longer taking output to downstream tools)
- Session duration shortens significantly

Source: General SaaS churn analysis patterns (Baremetrics, ProfitWell/Paddle), adapted for CAD workflow characteristics.

### Billing Platforms

#### Stripe
- **Fees:** 2.9% + $0.30 per transaction (standard US pricing)
- **Usage-based billing:** Native support via the Meters API (GA 2024). Define meters for AI operations, compute minutes, storage GB. Stripe aggregates and bills automatically.
- **Stripe Checkout:** Hosted payment page, fully PCI compliant. No credit card data touches CadFlow servers.
- **Stripe Customer Portal:** Self-service subscription management — users can upgrade, downgrade, cancel, and update payment methods without CadFlow building any UI.
- **Stripe Tax:** Automatic tax calculation and collection, 0.5% per transaction on top of standard fees. Covers US state sales tax, EU VAT, UK VAT, Canadian GST/HST, Australian GST, and more.
- **Stripe Billing:** Supports tiered pricing, per-seat pricing, usage-based pricing, and hybrid models. Subscription lifecycle webhooks are comprehensive.
- **Ecosystem:** Integrates with every analytics tool (ChartMogul, Baremetrics, ProfitWell). SDKs for every language. By far the largest developer ecosystem.
- **Downsides:** You are the merchant of record — responsible for tax filing, refund policies, and compliance. Stripe Tax helps with calculation but you still file returns.

Source: Stripe documentation (2026), Stripe pricing page, Stripe Meters API documentation.

#### Paddle
- **Fees:** 5% + $0.50 per transaction
- **Merchant of Record (MoR):** Paddle is the legal seller. They handle all tax calculation, collection, filing, and remittance globally. CadFlow never deals with tax authorities.
- **Usage-based billing:** Supported but less flexible than Stripe's Meters API. Paddle's approach is quantity-based adjustments on subscriptions rather than true metered billing.
- **Downsides:** Less control over the checkout experience, fewer integrations, smaller ecosystem. The 5% fee is ~2% more than Stripe — on $100K MRR, that is $2,000/month extra.
- **Best for:** Teams without finance/legal resources to handle global tax compliance.

Source: Paddle documentation (2026), Paddle pricing page, Paddle MoR documentation.

#### LemonSqueezy (now part of Stripe)
- **Fees:** 5% + $0.50 per transaction (same as Paddle)
- **Merchant of Record:** Yes, similar to Paddle.
- **Usage-based billing:** Limited. Primarily designed for flat-rate subscriptions and one-time purchases.
- **Downsides:** Least flexible of the three. Limited API, fewer webhooks, less mature ecosystem. Poor fit for usage-based billing models.
- **Best for:** Simple SaaS with flat-rate plans and no usage tracking.

Source: LemonSqueezy documentation (2026), LemonSqueezy pricing page.

#### Comparison Summary

| Feature | Stripe | Paddle | LemonSqueezy |
|---|---|---|---|
| Transaction fee | 2.9% + $0.30 | 5% + $0.50 | 5% + $0.50 |
| Merchant of Record | No (you handle tax) | Yes | Yes |
| Usage-based billing | Excellent (Meters API) | Adequate | Poor |
| Tax handling | +0.5% (Stripe Tax) | Included | Included |
| Effective cost on $30 sub | $1.17 (no tax) / $1.32 (w/ tax) | $2.00 | $2.00 |
| Ecosystem/integrations | Best | Good | Limited |
| Checkout customization | Full control | Limited | Limited |
| Self-service portal | Yes (Customer Portal) | Yes | Basic |

For CadFlow, **Stripe is preferred** because usage-based billing for AI and compute is a core requirement. The Meters API is purpose-built for this. The 2% fee savings compounds significantly at scale. The tax burden is manageable with Stripe Tax at 0.5%, and the total effective rate (3.4% + $0.30) is still well below Paddle's 5% + $0.50.

However, if the founding team has zero appetite for tax compliance work, Paddle's MoR model is worth the 2% premium — especially pre-product-market-fit when every hour matters.

### Pricing Models and Tier Design

**Industry benchmarks for AI-augmented SaaS pricing (2025-2026):**
- GitHub Copilot: $10/month (Individual), $19/month (Business) — flat rate with fair-use limits
- Cursor: $20/month (Pro), $40/month (Business) — usage-based with included requests
- Replit: $25/month (Hacker), usage-based AI add-on — hybrid model
- Vercel: Free tier + $20/month Pro — usage-based compute billing on top

Source: Public pricing pages of GitHub Copilot, Cursor, Replit, Vercel (2026).

The emerging consensus for AI-augmented developer tools is **tiered subscription + usage credits**. This provides:
- Predictable base revenue (subscription)
- Cost protection (credits cap AI/compute usage)
- Upgrade pressure (running out of credits is a natural trigger)
- Transparency (users see exactly what they are spending credits on)

**Proposed CadFlow tier structure:**

| | Free | Pro | Team |
|---|---|---|---|
| Price | $0/month | $29/month | $49/user/month |
| Projects | 3 | Unlimited | Unlimited |
| AI operations/month | 50 | 500 | 1,000/user |
| Compute minutes/month | 10 | 120 | 300/user |
| Storage | 500 MB | 10 GB | 50 GB/user |
| STEP/IGES export | No | Yes | Yes |
| Version history | 7 days | 90 days | Unlimited |
| Priority support | No | Email | Email + Chat |
| Team workspaces | No | No | Yes |
| SSO/SAML | No | No | Yes |
| Credit top-ups | No | $10/100 credits | $8/100 credits |

**Credit cost model (approximate):**

| Operation | Credits | Estimated cost to CadFlow |
|---|---|---|
| Simple AI query (sketch help) | 1 | $0.01-0.03 |
| Complex AI query (multi-step agent) | 5 | $0.05-0.15 |
| AI code generation (CadQuery) | 3 | $0.03-0.10 |
| Geometry boolean operation | 1 | $0.005-0.02 |
| Mesh generation | 5 | $0.02-0.10 |
| CFD preprocessing pipeline | 10 | $0.05-0.30 |
| STEP/IGES export | 2 | $0.01-0.05 |

**Free tier design principles:**
- 3 projects is enough to evaluate but not enough to run a business on
- 50 AI operations/month lets users experience the agentic workflow ~2-3 sessions
- No STEP/IGES export is the strongest upgrade trigger — users who reach the export step are already invested
- 10 compute minutes prevents abuse of server-side OCCT operations

Source: Pricing strategy informed by SaaS pricing benchmarks (ProfitWell/Paddle Price Intelligently, 2025), AI-tool pricing analysis (a16z "Cost of AI" reports, 2024-2025).

### Financial Control and Unit Economics

**Target unit economics per tier:**

| Metric | Free | Pro ($29) | Team ($49/user) |
|---|---|---|---|
| AI cost/month | $0.50-1.50 | $3.00-7.00 | $5.00-10.00 |
| Compute cost/month | $0.10-0.30 | $0.50-1.50 | $1.00-3.00 |
| Storage cost/month | $0.01 | $0.05-0.10 | $0.10-0.50 |
| Infrastructure overhead | $0.50 | $0.50 | $0.50 |
| **Total cost/user** | **$1.11-2.31** | **$4.05-9.10** | **$6.60-14.00** |
| **Gross margin** | Negative | 69-86% | 71-87% |

**Target SaaS metrics:**
- Monthly churn rate: < 5% for SMB segment, < 2% for Team/Enterprise (source: SaaS benchmarks, Baremetrics 2025)
- LTV > 3x CAC (minimum viable, 5x+ preferred) (source: general SaaS benchmarks)
- ARPU target: $35-45/month blended across paid tiers
- Payback period: < 6 months on CAC

**Danger zones to monitor:**
- Power users making 1,000+ AI calls/month on Pro ($29) — each call at $0.05-0.15 means these users cost $50-150/month against $29 revenue. Credit caps are essential.
- Free tier abuse: users creating multiple accounts to bypass limits. Mitigation: rate limiting by IP + email domain, require email verification.
- Compute spikes: a single complex CFD preprocessing job can consume minutes of CPU. Queue-based execution with priority by tier prevents free users from starving paid users.

**Cost tracking implementation:**
- Tag every AI call and compute job with `user_id` and `organization_id`
- Store cost events in a time-series table: `(timestamp, user_id, org_id, operation_type, credits_consumed, estimated_cost_usd)`
- Daily aggregation job for dashboard and alerts
- Per-user cost alerts: warn at 80% of credit quota, hard stop at 100% for free tier, soft cap (allow overage with billing) for paid tiers
- Circuit breaker: if any single user's daily cost exceeds $50, pause their account and alert the team. This prevents runaway API calls from bugs or abuse.

Source: Cost management patterns from AWS Well-Architected Framework (cost optimization pillar), adapted for SaaS with AI workloads. AI cost tracking recommendations from a16z "Who Owns the AI Inference Cost?" (2025).

### Support and Feedback Infrastructure

**Phase 1: 0-100 users (pre-revenue)**
- Shared team email (support@cadflow.com) using Google Workspace or Fastmail
- Discord community server for peer support, feature discussion, bug reports
- GitHub Issues for bug tracking (public, builds trust with technical audience)
- Time investment: ~2-5 hours/week

**Phase 2: 100-1,000 users (~20+ tickets/week)**
- **Crisp** for live chat widget: free for 2 operators, $25/operator/month for Pro. Includes shared inbox, knowledge base, and chatbot. Budget-friendly alternative to Intercom ($74/seat/month). Source: Crisp pricing page (2026).
- **Canny** for feature request voting: free tier available, $79/month for Growth. Users vote on features, team communicates roadmap. Builds community engagement and prioritizes development. Source: Canny pricing page (2026).
- Continue Discord for community, but route support questions to Crisp.
- Time investment: ~10-15 hours/week

**Phase 3: 1,000-10,000 users**
- Evaluate **Plain** (developer-focused support tool, built for API-first teams) or **Intercom** (if budget allows)
- **Linear** for internal issue tracking (likely already in use for development)
- Dedicated part-time support hire or contract
- Source: Plain documentation (2026), Linear documentation.

**NPS and user feedback:**
- In-app NPS survey at day 7, day 30, and day 90 using **Refiner.io** (free for <1,000 responses/month) or **Satismeter** ($199/month for up to 1,000 responses). Alternative: build a simple custom modal — NPS is just one question ("How likely are you to recommend CadFlow to a colleague? 0-10") plus an optional text field.
- Trigger satisfaction surveys after key moments: first STEP export, first AI-assisted model, first team collaboration session.
- Source: Refiner.io pricing (2026), Satismeter pricing (2026), NPS methodology (Bain & Company).

### Payment Integration Architecture

**Stripe integration flow:**

```
User clicks "Upgrade to Pro"
  -> Redirect to Stripe Checkout (hosted page)
  -> User enters payment details (PCI-compliant, no card data touches our servers)
  -> Stripe creates Subscription + Customer
  -> Webhook: checkout.session.completed
  -> CadFlow backend updates user tier in database
  -> User redirected to CadFlow with Pro features active

Monthly billing cycle:
  -> Stripe Meters API receives usage events throughout the month
  -> Stripe calculates usage charges at period end
  -> Stripe charges card: base subscription + overage
  -> Webhook: invoice.payment_succeeded
  -> CadFlow resets monthly credit counters

Failed payment:
  -> Webhook: invoice.payment_failed
  -> CadFlow sends in-app notification + email
  -> Stripe retries (Smart Retries, up to 4 attempts over ~3 weeks)
  -> If all retries fail: Webhook subscription.deleted
  -> CadFlow downgrades user to free tier, preserves data for 90 days
```

**Critical webhooks to handle:**
- `checkout.session.completed` — activate subscription
- `invoice.payment_succeeded` — confirm billing cycle, reset credits
- `invoice.payment_failed` — notify user, begin grace period
- `customer.subscription.updated` — plan changes (upgrade/downgrade)
- `customer.subscription.deleted` — cancellation, trigger offboarding flow
- `customer.subscription.trial_will_end` — if using reverse trial, warn 3 days before

**Webhook reliability:**
- Stripe retries failed webhook deliveries for up to 72 hours with exponential backoff
- Implement idempotent webhook handlers (use Stripe event ID as idempotency key)
- Store raw webhook events in a `stripe_events` table for audit and replay
- Verify webhook signatures to prevent spoofing (`stripe.webhooks.constructEvent()`)

Source: Stripe Webhooks documentation (2026), Stripe Checkout integration guide, Stripe Billing lifecycle documentation.

### Cost Control and Infrastructure Efficiency

**Compute cost management:**
- **Queue-based execution:** All CadQuery/OCCT operations go through a job queue (e.g., BullMQ on Redis, or Celery on Redis). Priority: Team > Pro > Free.
- **Scale-to-zero:** Use serverless containers (AWS Fargate, Google Cloud Run, or Fly Machines) for compute workers. Idle workers shut down after 5 minutes of inactivity.
- **Spot/preemptible instances:** For batch operations (CFD preprocessing pipelines, mesh generation), use spot instances at 60-90% discount. These operations are interruptible by nature — checkpoint progress and resume if preempted.
- **Geometry caching:** Cache OCCT computation results (TopoDS_Shape serialized as BREP) keyed by input hash. Many operations are repeated across users (same fillet radius on similar geometry). Use Redis or S3 for cache storage with TTL-based eviction.
- **Rate limiting:** Per-user, per-minute rate limits on API calls. Free: 10 req/min. Pro: 60 req/min. Team: 120 req/min. Prevents both abuse and accidental infinite loops in client code.

**AI cost management:**
- **Prompt caching:** Use Claude's prompt caching for system prompts and CadQuery documentation context. This reduces cost by up to 90% on the cached portion. Source: Anthropic prompt caching documentation (2025).
- **Model routing:** Use Claude Haiku for simple operations (parameter extraction, validation) and Claude Sonnet/Opus for complex reasoning (multi-step geometry planning, error diagnosis). Cost difference is 10-50x.
- **Context window management:** Truncate conversation history aggressively. Most CAD operations need only the current model state and the last 2-3 exchanges, not the full conversation.
- **Streaming with early termination:** If the user cancels an operation mid-stream, terminate the API call immediately to avoid paying for unused tokens.

Source: Anthropic API pricing and documentation (2026), cloud provider spot instance documentation (AWS, GCP, Fly.io).

## Options Considered

### Option 1: Simple Flat-Rate Subscription (No Usage Tracking)

Two tiers: Free ($0) and Pro ($25/month). No credit system, no usage metering. AI and compute are "included" with fair-use limits enforced manually.

**Pros:**
- Simplest to implement — no metering infrastructure, no credit accounting
- Easiest for users to understand — one price, everything included
- Fastest time-to-market
- Lower engineering investment in billing (~1 week vs. ~3-4 weeks)

**Cons:**
- **Financially dangerous.** A power user making 1,000+ AI calls/month costs $50-150 against $25 revenue. With no metering, you cannot even detect this until the Anthropic bill arrives.
- "Fair use" policies are vague, create user frustration, and are hard to enforce consistently.
- No natural upgrade trigger beyond the free/paid boundary.
- No data on per-user costs — flying blind on unit economics.
- If AI costs spike (model price changes, new features encouraging more usage), there is no lever to pull except raising prices (which causes churn).

**Verdict:** Unacceptable risk for a product with significant variable costs per user.

### Option 2: Pure Usage-Based Pay-As-You-Go

No subscription. Users pay per AI operation, per compute minute, and per GB of storage. Like AWS billing — you pay exactly for what you use.

**Pros:**
- Perfect unit economics — every user is profitable by definition
- No pricing tiers to design or maintain
- Users who use more, pay more — inherently fair
- Scales naturally from light users to power users

**Cons:**
- **Revenue is completely unpredictable.** Monthly recurring revenue (MRR) does not exist. Financial planning and fundraising become very difficult.
- **Users hate unpredictable bills.** AWS bill shock is a meme for a reason. CAD users — especially individual engineers and students — will not tolerate surprise charges.
- Higher churn: users feel no commitment, easy to stop using and never come back.
- Complex billing UI: users need dashboards showing current spend, projected spend, cost breakdown by operation type.
- Harder to market: "starts at $0.01 per operation" is less compelling than "$29/month."
- Payment friction on every interaction reduces usage of the AI features — the core differentiator.

**Verdict:** Wrong model for a product that needs users to engage frequently with AI features. Usage fear kills adoption.

### Option 3: Tiered Subscription with Credit-Based Usage (Recommended)

Three tiers (Free, Pro, Team) with monthly subscription fees. Each tier includes a credit allotment. Credits are consumed by AI operations and compute. Overages are either blocked (free tier) or billed (paid tiers). Top-up credit packs available for purchase.

**Pros:**
- **Predictable base revenue** from subscriptions enables financial planning.
- **Cost protection** from credit caps prevents any single user from causing losses.
- **Natural upgrade pressure** — running out of credits mid-project is a strong trigger.
- **Transparent cost model** — users understand exactly what consumes credits.
- **Data-rich** — credit consumption patterns reveal which features users value, which are expensive, and where to optimize.
- **Flexible levers** — can adjust credit allotments, credit costs per operation, and top-up pricing independently without changing subscription prices.
- Industry-validated: Cursor, Vercel, and GitHub Copilot (with its usage limits on Opus) all use variants of this model.

**Cons:**
- Most complex to implement — requires metering infrastructure, credit accounting, webhook handling, and overage billing.
- Requires careful credit pricing — too expensive and users feel nickel-and-dimed, too cheap and unit economics suffer.
- Users must learn the credit system — adds cognitive load to onboarding.
- Credit systems can feel adversarial if not designed with transparency ("Why did that cost 5 credits?").

**Mitigation of cons:**
- Use Stripe Meters API to handle most of the metering complexity server-side.
- Show credit costs before executing operations ("This will use ~3 credits. Proceed?").
- Provide a clear credit usage dashboard in the app.
- Start with simple credit tiers and refine pricing based on real usage data.

**Verdict:** Best balance of revenue predictability, cost control, and user experience. The implementation complexity is manageable with Stripe's tooling.

## Decision

**We will adopt Option 3: Tiered Subscription with Credit-Based Usage**, with the following specific choices:

**Authentication:** Clerk for user management and authentication. It provides the best DX for a Next.js application, has built-in organization support for team billing, and the free tier covers early growth. If the stack uses Supabase for the database layer, evaluate Supabase Auth as an alternative to reduce dependencies.

**Billing:** Stripe for all payment processing. Specifically:
- Stripe Checkout for payment collection (PCI compliance with zero effort)
- Stripe Billing with Meters API for usage-based credit tracking
- Stripe Customer Portal for self-service subscription management
- Stripe Tax for automated tax calculation (accept the 0.5% fee to avoid manual tax compliance)
- Stripe webhooks for subscription lifecycle management

**Pricing:** Three tiers as defined in the Research Findings section (Free at $0, Pro at $29/month, Team at $49/user/month). Credit allotments and per-operation costs as specified. These are starting points — we commit to reviewing pricing within 90 days of launch based on real usage data.

**Cost control:**
- Hard credit caps for free tier (operations blocked at 0 credits)
- Soft caps for paid tiers (allow overage, bill at top-up rates)
- Per-user daily cost circuit breaker at $50
- Queue-based compute with tier-based priority
- AI model routing (Haiku for simple, Sonnet for complex operations)
- Aggressive geometry caching

**Support:**
- Phase 1: Shared email + Discord community
- Phase 2: Crisp for live chat at ~20 tickets/week
- Phase 3: Evaluate Plain or Intercom at scale
- Canny for feature request voting from Phase 2 onward
- In-app NPS surveys starting at day 7

**Metrics to track from day one:**
- MRR, ARR, churn rate (monthly), ARPU
- Per-user cost (AI + compute + storage + overhead)
- Credit utilization rate per tier (what % of allotment are users consuming?)
- LTV:CAC ratio
- Free-to-paid conversion rate
- Credit top-up purchase frequency

## Consequences

### Positive

1. **Revenue predictability.** Subscription base provides reliable MRR for financial planning. Usage-based component captures additional value from power users.
2. **Cost protection.** Credit caps ensure no individual user can cause losses. Circuit breakers prevent runaway costs from bugs or abuse.
3. **Data-driven pricing.** Credit consumption data reveals true cost-of-goods-sold per feature, enabling informed pricing adjustments.
4. **Natural upgrade funnel.** Free tier limitations (3 projects, no STEP export, 50 AI ops) create organic upgrade pressure at the right moments — when users are already invested.
5. **Scalable support.** Phased support strategy avoids premature hiring while ensuring users always have a channel for help.
6. **Tax compliance from day one.** Stripe Tax handles global tax obligations, avoiding the legal debt that many startups accumulate.

### Negative

1. **Implementation complexity.** Credit metering, webhook handling, overage billing, and usage dashboards add ~3-4 weeks to the billing integration compared to simple flat-rate plans.
2. **Credit system friction.** Some users will find the credit system confusing or adversarial. Must invest in clear UI (credit balance visible at all times, cost preview before operations, usage breakdown dashboard).
3. **Pricing risk.** Initial credit costs and allotments are estimates. If wrong, we either leave money on the table (too generous) or frustrate users (too stingy). Commit to 90-day pricing reviews.
4. **Stripe dependency.** Deep integration with Stripe Meters, Checkout, Customer Portal, and Tax creates significant vendor lock-in. Migrating to another payment provider would require substantial engineering effort.
5. **Webhook reliability.** Billing depends on webhook delivery. Must implement idempotent handlers, event storage for replay, and reconciliation jobs to catch missed events.
6. **Ongoing operational cost.** Stripe Tax adds 0.5% per transaction. Clerk adds per-MAU cost beyond 10,000 users. These are acceptable but must be factored into unit economics.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Credit pricing too generous, negative unit economics | Medium | High | Monitor per-user cost weekly. Adjust credits at 90-day review. |
| Free tier abuse (multi-account) | Medium | Medium | Email verification, IP-based rate limiting, device fingerprinting. |
| Stripe outage affects billing | Low | High | Cache subscription status locally. Grace period for API failures. |
| Users confused by credit system | Medium | Medium | In-app credit explainer, cost preview before operations, transparent dashboard. |
| AI cost increase (Anthropic pricing change) | Low | High | Credit system decouples user pricing from provider costs. Adjust credit costs, not subscription prices. |
| Power user costs exceed revenue | Medium | Medium | Per-user daily circuit breaker ($50). Credit caps prevent unlimited consumption. |

## Dependencies

- **ADR-003 (or equivalent):** Frontend framework decision — Clerk assumes Next.js. If the framework is different, re-evaluate auth provider.
- **ADR for database/backend:** If Supabase is chosen, reconsider Supabase Auth over Clerk to reduce dependencies.
- **ADR for compute architecture:** Queue-based execution and scale-to-zero patterns depend on the compute infrastructure decision (containers, serverless, etc.).
- **ADR for AI integration:** Model routing strategy (Haiku vs. Sonnet vs. Opus) and prompt caching depend on how Claude is integrated into the CadQuery generation pipeline.
- **Stripe account setup:** Business entity must be registered before Stripe can process payments. For early development, use Stripe Test Mode.
- **Domain and email:** support@cadflow.com must be configured before Phase 1 support can begin.
- **Legal:** Terms of Service and Privacy Policy must be drafted before accepting payments. Stripe requires a refund policy.
- **Anthropic API agreement:** Usage terms must permit resale of AI-generated output in a SaaS context. Verify the Anthropic Terms of Service allow this use case.
