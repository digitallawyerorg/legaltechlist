# Claude Tag Curator (MCP connector)

This app exposes a remote [MCP](https://modelcontextprotocol.io) connector so that
**@Claude in Slack (Claude Tag)** can act as a TechIndex curator: discover new
companies, review proposals, and maintain existing entries. It runs with **tiered
autonomy** — Claude may auto-publish only high-confidence entries that pass the
existing quality gate and have no duplicate signals; everything else is left for a
human to approve.

## How it works

- Endpoint: `POST /mcp` (stateless Streamable HTTP, JSON responses), handled by
  [`Mcp::CuratorController`](../app/controllers/mcp/curator_controller.rb).
- Auth (two ways):
  - **OAuth 2.1** (the path Claude's connector uses) — see the OAuth section below.
  - **Static bearer token** (`Authorization: Bearer <MCP_CURATOR_TOKEN>`) for MCP
    Inspector / curl testing and as a break-glass credential. Optional; only active
    when `MCP_CURATOR_TOKEN` is set.
- Server + tools: [`Mcp::CuratorServer`](../app/mcp/curator_server.rb) registers the
  tools in [`Mcp::Tools`](../app/mcp/tools.rb).
- All writes are attributed to a dedicated `AdminUser` (see
  [`Mcp::CuratorActor`](../app/mcp/curator_actor.rb)) and audited to `PipelineRun`
  with `run_type: "curator_mcp"`.
- Guardrails live in [`Mcp::CuratorPolicy`](../app/mcp/curator_policy.rb).

## Tools

Read / context: `search_companies`, `get_company`, `list_review_queue`,
`get_proposal`, `duplicate_check`, `get_taxonomy` (controlled vocabulary of
categories, business models, target clients, and canonical tags), `get_stats`
(directory size, data-quality gaps, and backlog counts for cadence planning).

Discovery: `discover_companies` (dry run by default; `queue_proposals: true` creates
`discovery_candidate` proposals).

Proposal curation (tiered): `enrich_proposal`, `assess_proposal`, `update_proposal`
(set allowlisted company fields into `final_changes` before approval; setting taxonomy
fields marks the taxonomy curator-confirmed and clears the low-confidence-taxonomy
blocker), `curate_pending`, `approve_proposal`, `reject_proposal`.

`list_review_queue` supports paging: it returns `total`, `offset`, `limit`, and
`has_more`, and accepts an `offset` param so the full backlog is reachable beyond the
first 50 items (page with offset=0, 50, 100, ... until `has_more` is false).

Maintenance: `run_company_review`, `propose_company_update` (queue an editorial edit
to an existing company as a `user_suggestion` proposal), `update_company_field`
(edit safe factual fields — founded_date/location/founders/status — directly on a
live company in one call; `founded_date` requires a 4-digit year and a `source_url`
citation), `apply_safe_fields`, `mark_review`, `suggest_taxonomy`.

Meta: `suggest_improvement` (Claude records tooling/workflow/data suggestions; logged
to `PipelineRun` and posted to Slack).

## Operating instructions

`Mcp::CuratorServer::INSTRUCTIONS` is sent to Claude on connect (MCP `instructions`).
It defines the curator goal, the academic/lifecycle policy (keep inactive companies;
record acquisitions/mergers and `acquired`/`defunct` status instead of deleting), the
encyclopedic non-promotional editorial voice for descriptions (no marketing language,
no internal notes or "missing info" remarks), the `get_taxonomy` classification
discipline, and the approval rules below.

## Tiering / guardrails

- `curate_pending` and `approve_proposal(publish: true)` only publish when
  `CompanyProposalQualityService#publish_ready` is true and the proposal has no
  duplicate signals.
- Autonomy is gated in two layers: objective checks (quality gate, duplicates, daily
  budget, kill-switches) AND a self-reported `confidence` on `approve_proposal`.
  Autonomous publish/apply requires `confidence >= MCP_CURATOR_MIN_CONFIDENCE`
  (default 0.8). Confidence can only reduce autonomy; it never bypasses the objective
  gates. `human_approved: true` overrides both layers after a human approves in Slack.
- New entries: auto-publish requires the quality gate + no duplicates +
  `MCP_CURATOR_AUTOPUBLISH=true` + sufficient confidence.
- Existing companies: `approve_proposal` applies a `user_suggestion` edit autonomously
  only when `MCP_CURATOR_AUTOAPPLY_UPDATES=true` + sufficient confidence; otherwise it
  requires `human_approved: true`.
- Externally-submitted proposals (`CompanyProposal#externally_submitted?`, i.e. those
  with a `submitter_email` from the public forms) can publish/apply autonomously, but at a
  higher confidence bar (`MCP_CURATOR_MIN_CONFIDENCE_EXTERNAL`, default 0.9) so spam that
  games the quality score is filtered out by the model's confidence judgment.
- `curate_pending` (batch, no per-item confidence) still queues external submissions for
  the confidence-bearing `approve_proposal` path rather than publishing them off the score.
- Spam pre-gate: for externally-submitted proposals only, `CompanyProposalQualityService`
  adds a publish blocker when it detects solicitation text (salary/recruitment pitches,
  `mailto:`/unsubscribe, money-transfer language, `$` amounts) or malformed `founded_date`
  (no plausible year) or `main_url` (not a valid HTTP URL). This keeps score-gamed spam
  (e.g. the ROHTO advance-fee submission that scored 100) out of `publish_ready`. It is
  scoped to public submissions to avoid false positives on internal discovery candidates.
- Low-confidence taxonomy: `update_proposal` now marks `agent_details.taxonomy_suggestion.accepted`
  when taxonomy fields are set, so a curator confirmation clears the blocker without
  re-running `enrich_proposal`.
- Founding year is optional: `founded_date` is NOT a publish blocker (it is unsourceable
  for many small/international companies). The quality gate emits a non-blocking warning
  when it is missing (`missing_publish_blocking_fields` excludes it), and `Company`
  allows a blank `founded_date` (but a present value must contain a 4-digit year).
  Never fabricate a year; publish without it and backfill from a real source later.
- Async enrichment: `enrich_proposal` is asynchronous — it enqueues `EnrichProposalJob`
  (processed by the durable Solid Queue worker on the dedicated `jobs` dyno, off the request
  thread so it is not bound by the 30s HTTP router timeout, and durable across deploys/restarts)
  and returns `enrichment_queued`. Callers poll `get_proposal`
  until `enriched_at` is newer than `enriched_at_before` (success) or
  `agent_details.enrichment_error` appears (failure). `curate_pending` likewise enqueues
  enrichment for un-enriched proposals and publishes only already-enriched ones on a
  later pass. Because the curator (Claude) has its own web browsing, prefer researching
  and writing fields via `update_proposal` (synchronous); use `enrich_proposal` for
  server-side web-grounded enrichment.
- Discovery-time classification (6a): the `discover_companies` web-search pass now also
  classifies each candidate using the controlled vocabulary and captures a founding year with
  its citing URL. At proposal creation the mapped taxonomy is written to `final_changes`
  (`category_id`, `business_model_id(s)`, `target_client_id(s)`) and recorded as an accepted
  `agent_details.taxonomy_suggestion` (mode `discovery_search`) when fully mapped, and a cited
  year is stored in `agent_details.founded_date_source`. This removes the separate enrich
  round-trip and the "low-confidence taxonomy" hold for confident items. It never overwrites an
  existing taxonomy suggestion or a proposal that already has a company, and a founding-year
  source is kept only if its URL was actually seen in search (uncited sources are dropped).
- Discovery-time description drafting: the same `discover_companies` pass now also drafts a
  neutral, encyclopedic description (18-32 words, no marketing language). At proposal creation the
  draft is cleaned (`CompanyProposalEnrichmentService.clean_description`) and run through the
  deterministic critic (`.description_critic_for`); only a draft that passes (and clears the
  quality gate's word-count bar) is promoted to `final_changes["description"]` with the recorded
  `agent_details.description_critic` verdict and a `description_draft` note. Because a confident
  candidate now arrives with description + taxonomy + optional cited year, it is publishable
  straight from discovery and `CompanyCandidateRowProcessorService` skips the enrichment
  round-trip entirely (`enrichment_needed?` is false). Weak/uncertain drafts are left blank so
  `enrich_proposal`/auto-enrichment drafts one as before. The discovery sentence is intentionally
  NOT stored as `source_description`, so promoting it never trips the copied-source guard.
- Missing-founded-date signal (Spec A): `founded_date` gaps are now a first-class quality
  signal — `Company.missing_founded_date` scope, `get_stats` `companies.missing_founded_date`
  count, and a `search_companies(missing_founded_date: true)` filter (AND-composable with
  `needs_review`).
- Server-side founded_date backfill (Spec B): `backfill_founded_dates` enqueues async
  `BackfillFoundedDateJob`s (durable Solid Queue on the `jobs` dyno, off the 30s router timeout;
  reliable at batch scale and safe across deploys) via `CompanyFoundedDateBackfillService`,
  which runs a targeted founding-year web search (`CompanyFoundedYearResearchService`, OpenAI
  Responses API web-search — server-side egress to LinkedIn/Crunchbase/registries), then reuses
  the exact cite-only guard (`sourced_year`) and the validated writer
  (`Company#founded_date_from_source!`, shared with `update_company_field`). Each fill records a
  `PipelineRun` (`run_type: "founded_date_backfill"`) and a `companies.founded_year_provenance`
  JSON blob (`status` + source_url + tier). Cheap to re-run: every attempt (fill or miss) writes
  `founded_year_provenance` with `status` + `attempted_at`, and a blind run only selects companies
  not attempted within `RE_ATTEMPT_COOLDOWN` (3 days) via `Company.founded_date_backfill_due` — so
  re-runs reach untried companies rather than re-researching known no-source ones. Pass
  `company_ids` (tool) / `COMPANY_IDS` (rake) to target specific companies and bypass the cooldown.
  Also runnable as `rake data_quality:backfill_founded_dates`
  (`DRY_RUN`/`INLINE`/`LIMIT`/`VERBOSE`/`FORCE`/`COMPANY_IDS`). `get_company` exposes
  `founded_year_provenance` and a derived `founded_date_backfill_status` (`filled` with citation /
  `no_source`/`error` attempted / `untried`) so backfill outcomes are auditable via the read API.
- Same-name entity guard (Spec C): a cited year is accepted only when the source is on the
  company's own domain, or on a known registry/profile host AND the evidence text names the
  company — blocking same-name/different-entity traps (e.g. `apualegal.com` for `apua.ai`).
- Registry-preference tiering (Spec D): when several cited years survive, the source is ranked
  registry > profile > owned > other; the chosen tier is stored in provenance.
- Sourced founding year: server-side enrichment fills `founded_date` only when the model
  returns a plausible 4-digit year (>= 1970, <= current year) whose citing source host is
  among the gathered evidence (web-research results or the company's own/crunchbase/
  linkedin domains); the citation is recorded in `agent_details.founded_date_source` and
  shown in the admin proposal view. Otherwise `founded_date` is left blank — it never
  writes an unsourced/guessed year. Enrichment prompts explicitly consult profile
  "Founded" fields and official registries (OpenCorporates / national registries),
  preferring a registry over a self-reported profile.
- Idempotent approval: `approve_proposal` on a proposal that already produced a company
  returns the existing company (`result` = `already_published` / `already_drafted` /
  `already_applied`) instead of minting a second record.
- Retryable errors: unexpected/transient failures on `approve_proposal`, `update_proposal`,
  and `update_company_field` return `retryable: true`; terminal rejections (validation /
  gate) return `retryable: false`, so clients can distinguish a blip from a rejection.
- Enrich cost guards: `enrich_proposal` returns `skipped_already_publishable` when the
  proposal already passes the gate and `skipped_recently_enriched` when it was enriched
  within the last few days; pass `force: true` to override.
- Authoritative responses: `approve_proposal` returns `result`
  (`published`/`drafted`/`update_applied`/`blocked`) plus a `published` boolean on every
  path (success and failure), so a caller cannot mistake a blocked/drafted item for a
  published one. `update_proposal` returns `persisted_changes`, `publish_ready`, and
  `blockers` so a write can be confirmed without a second `get_proposal`.
- Publishing a proposal that fails the gate requires `human_approved: true` on
  `approve_proposal` (set this only after a human approves in the Slack thread).
- `MCP_CURATOR_AUTOPUBLISH=false` is a global kill-switch for automatic publishing.
- `apply_safe_fields` can only write `quality_status`, `verification_verdict`,
  `quality_score`, `canonical_domain`, `fingerprint`.
- Edits to existing companies (`propose_company_update`) never apply automatically:
  `approve_proposal` routes `user_suggestion` proposals through
  `CompanyProposalApplyUpdateService` and requires `human_approved: true`.
- `update_proposal` / `propose_company_update` only accept fields in
  `CompanyProposal::EDITABLE_COMPANY_FIELDS`; anything else is dropped server-side.
- The legacy direct-write CSV import path is intentionally not exposed.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `MCP_CURATOR_EMAIL` | `claude-curator@techindex` | Curator AdminUser email. |
| `MCP_CURATOR_TOKEN` | (unset) | Optional static bearer token for testing / break-glass. |
| `MCP_OAUTH_ISSUER` | request base URL | OAuth issuer; set to the canonical HTTPS host on Heroku. |
| `MCP_OAUTH_SECRET` | `secret_key_base` | HMAC secret for signing OAuth JWTs. |
| `MCP_OAUTH_ALLOWED_REDIRECT_HOSTS` | `claude.ai,claude.com,console.anthropic.com` | Extra allowed OAuth redirect hosts (comma-separated). |
| `MCP_CURATOR_AUTOPUBLISH` | `true` | Auto-publish kill-switch for NEW entries. |
| `MCP_CURATOR_AUTOAPPLY_UPDATES` | `false` | Allow autonomous edits to EXISTING companies. |
| `MCP_CURATOR_MIN_CONFIDENCE` | `0.8` | Min self-reported confidence for autonomous publish/apply. |
| `MCP_CURATOR_MIN_CONFIDENCE_EXTERNAL` | `0.9` | Higher confidence bar for externally-submitted proposals. |
| `MCP_CURATOR_MAX_DISCOVERY_LIMIT` | `25` | Cap on discovery `limit`. |
| `MCP_CURATOR_MAX_CURATE_LIMIT` | `100` | Cap on `curate_pending` batch size. |
| `MCP_CURATOR_MAX_DAILY_PUBLISH` | `50` | Daily auto-publish budget. |
| `MCP_CURATOR_SLACK_SUMMARY` | `false` | Post a curator run summary to Slack. |
| `SITE_URL` | `https://techindex.law.stanford.edu` | Base URL in tool output links. |
| `APP_HOST` | `localhost:3000` | Host used for `/admin/proposals/:id` links. |

Slack summary posting reuses `SlackNotifier` (`SLACK_BOT_TOKEN` + `SLACK_CHANNEL_ID`).

## OAuth 2.1

The connector authenticates with OAuth 2.1 (authorization code + PKCE). It is
single-tenant: the authorization step is gated behind the existing admin Devise
login, and all tokens are stateless signed JWTs (no database tables).

Endpoints:

- `GET /.well-known/oauth-protected-resource` — resource metadata (RFC 9728).
- `GET /.well-known/oauth-authorization-server` — AS metadata (RFC 8414).
- `POST /oauth/register` — dynamic client registration (RFC 7591); public clients,
  redirect URIs restricted to `MCP_OAUTH_ALLOWED_REDIRECT_HOSTS`.
- `GET /oauth/authorize` — requires an admin login, then auto-approves and returns a
  code (redirect URIs are host-restricted, so codes can only reach trusted hosts).
- `POST /oauth/token` — `authorization_code` and `refresh_token` grants.

Access tokens are validated on `POST /mcp`; an unauthenticated request returns `401`
with `WWW-Authenticate: ... resource_metadata=...` so Claude can discover the flow.

Set `MCP_OAUTH_ISSUER` to the canonical HTTPS URL on Heroku (e.g.
`https://your-app.herokuapp.com`) so the issuer stays stable behind the router, and
set `MCP_OAUTH_SECRET` to a strong random value.

## Deploy on Heroku

1. Set config and create the curator identity:

```bash
heroku config:set MCP_OAUTH_ISSUER=https://your-app.herokuapp.com \
                  MCP_OAUTH_SECRET=$(openssl rand -hex 32) -a your-app
heroku run bin/rails curator:setup -a your-app
```

2. Deploy so `POST /mcp` and the `/.well-known/*` + `/oauth/*` routes are reachable
   over public HTTPS. Stateless mode means multiple dynos / Puma workers are fine.

### Background jobs (Solid Queue)

Active Job runs on the durable, DB-backed **Solid Queue** adapter (single database — the
tables live in the primary DB via `CreateSolidQueueTables`). Jobs are processed by a dedicated
`jobs` process type (`jobs: bundle exec bin/jobs` in the `Procfile`), separate from the `web`
dyno and the `worker` dyno (which still runs the `CompanyImportWorkerService` import loop). This
replaced the old in-process `:async` adapter, which ran jobs on the web dyno's threads and lost
still-queued jobs on deploy — the failure mode that made large `backfill_founded_dates` batches
drain slowly and drop. Enable it after deploying:

```bash
heroku run bin/rails db:migrate -a your-app   # creates the solid_queue_* tables
heroku ps:scale jobs=1 -a your-app            # start the worker (Standard-1x is plenty)
```

Concurrency is tunable via `JOB_CONCURRENCY` (processes) and `JOB_THREADS` (threads/process)
in `config/queue.yml`.

## Test the deployed server safely (no secrets in logs)

Use a static token with the **Authorization header** (Heroku does not log request
headers). Set `MCP_CURATOR_TOKEN` temporarily, then use MCP Inspector or curl:

```bash
heroku config:set MCP_CURATOR_TOKEN=$(openssl rand -hex 32) -a your-app
npx @modelcontextprotocol/inspector   # Transport: Streamable HTTP, URL: https://your-app/mcp,
                                       # header Authorization: Bearer <token>
```

```bash
curl -s https://your-app.herokuapp.com/mcp \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

Remove `MCP_CURATOR_TOKEN` afterward if you only want OAuth in production.

## Connect Claude (OAuth)

In Claude (**Settings > Connectors > Add custom connector**):

- **Name:** `TechIndex Curator` (anything).
- **Remote MCP server URL:** `https://your-app.herokuapp.com/mcp`.
- Leave **OAuth Client ID / Secret** blank (the server supports dynamic client
  registration) and leave **Individual sign-in** on.
- Click **Add**. Claude discovers the OAuth endpoints and opens the authorize page;
  sign in with an admin account to approve. No secret ever appears in a URL.

Then scope the connector to **#rover-techindex**, set a channel spend cap, and test in
a private channel before enabling it in #rover-techindex.

## Suggested Slack loop

1. `@Claude discover 10 legal-tech companies founded in 2025 and curate them.`
2. Claude calls `discover_companies` then `curate_pending`; high-confidence entries
   publish automatically, the rest are posted with `/admin/proposals/:id` links.
3. A human replies "approve 1234"; Claude calls
   `approve_proposal(id: 1234, publish: true, human_approved: true)`.
