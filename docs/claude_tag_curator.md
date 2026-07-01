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
`get_proposal`, `duplicate_check`.

Discovery: `discover_companies` (dry run by default; `queue_proposals: true` creates
`discovery_candidate` proposals).

Proposal curation (tiered): `enrich_proposal`, `assess_proposal`, `curate_pending`,
`approve_proposal`, `reject_proposal`.

Maintenance: `run_company_review`, `apply_safe_fields`, `mark_review`,
`suggest_taxonomy`.

## Tiering / guardrails

- `curate_pending` and `approve_proposal(publish: true)` only publish when
  `CompanyProposalQualityService#publish_ready` is true and the proposal has no
  duplicate signals.
- Publishing a proposal that fails the gate requires `human_approved: true` on
  `approve_proposal` (set this only after a human approves in the Slack thread).
- `MCP_CURATOR_AUTOPUBLISH=false` is a global kill-switch for automatic publishing.
- `apply_safe_fields` can only write `quality_status`, `verification_verdict`,
  `quality_score`, `canonical_domain`, `fingerprint`.
- The legacy direct-write CSV import path is intentionally not exposed.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `MCP_CURATOR_EMAIL` | `claude-curator@techindex` | Curator AdminUser email. |
| `MCP_CURATOR_TOKEN` | (unset) | Optional static bearer token for testing / break-glass. |
| `MCP_OAUTH_ISSUER` | request base URL | OAuth issuer; set to the canonical HTTPS host on Heroku. |
| `MCP_OAUTH_SECRET` | `secret_key_base` | HMAC secret for signing OAuth JWTs. |
| `MCP_OAUTH_ALLOWED_REDIRECT_HOSTS` | `claude.ai,claude.com,console.anthropic.com` | Extra allowed OAuth redirect hosts (comma-separated). |
| `MCP_CURATOR_AUTOPUBLISH` | `true` | Auto-publish kill-switch. |
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
