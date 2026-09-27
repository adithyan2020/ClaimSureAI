# Code Shield

Code Shield is a demo claims-advocacy application built with Jac. It models claim review and appeal preparation as two agent workflows over a shared Object-Spatial Programming (OSP) knowledge graph. The Risk Predictor estimates denial risk before or after filing; the Appeal Executor prepares a cited appeal when a denial is uploaded or handed off from risk review.

> **Important:** This is a demonstration, not medical, legal, or insurance advice. Historical claims, payer submissions, provider contact, patient notifications, and appeal tracking in this project are simulated. A human must approve a packet before the demo dispatch actions run. Do not use it to make real coverage decisions or send real protected health information.

## Product workflow

### 1. Dashboard and claim intake

The dashboard (`/`) shows sample claims, their status, payer, amount, risk information, and appeal deadline where relevant. Use **Check a claim** to enter a condition, procedure, payer, policy type, network status, prior-authorization state, documentation completeness, amount, and whether the claim has been filed.

### 2. Workflow 1: Risk Predictor

The `risk_predictor` walker receives a claim ID, resolves the `Claim` node, and assesses it against a seeded synthetic history of 72 claims. The feature vector represents procedure category, payer, policy type, network status, authorization status, and documentation completeness. A cosine-similarity search finds the nearest examples; closer neighbors receive more weight in the estimate.

The risk detail page (`/claims/:id/risk`) presents:

- An estimated denial risk, confidence, and likely denial reason code.
- A separate estimate of how often similar denied claims were overturned on appeal.
- Ranked factors with plain-language explanations and historical rates.
- Similar claim references and their outcomes, as evidence for the estimate.
- A decision gate: low risk is logged; a high-risk unfiled claim gets a prevention recommendation; an already-filed or denied claim can be handed to appeal preparation.

This estimator uses made-up demo data and heuristic feature scoring. Its probabilities are not a validated production model.

### 3. Workflow 2: Appeal Executor

The Appeal Executor has two independent entry paths:

1. A risk-review handoff for an already-filed or denied claim.
2. A denial letter or EOB uploaded directly at `/upload`.

For an upload, the app displays the extracted fields for review and correction before starting the workflow. The configured model can extract fields from an image; the demo fallback supplies a sample extraction when model credentials are unavailable. PDF input is accepted by the UI, but model vision extraction currently targets image uploads; without model extraction the fallback is used.

The `appeal_executor` walker then:

1. Checks extraction confidence and the denial code. Low confidence or an unknown code routes to manual review rather than guessing.
2. Matches denial codes and procedure/condition keywords to seeded Summary Plan Description (SPD) clauses, showing the clause title, section, and page.
3. Classifies the denial using reason-code heuristics and the historical-neighbor estimate. If the denial appears legitimate, it pauses for a person to decide whether to continue.
4. Drafts an appeal cover letter, provider records request, medical-necessity note, and attachment checklist. With the configured LLM, drafting uses `by llm()` with typed structured output; otherwise a clause-citing template is used.
5. Pauses at **Awaiting your approval**. Review the letter and source clause; edit or reject the packet, or explicitly approve it. No dispatch actions run before approval.
6. After approval, simulates payer-portal submission, provider records request, fax packet preparation, patient notification, and a follow-up timer. The tracker can simulate payer responses. Repeated upheld denials or missed follow-up deadlines are escalated for human review.

The appeal tracker (`/appeals/:id`) displays these steps as an expandable timeline. The audit log (`/audit`) records decisions and simulated actions with timestamps and evidence citations.

## Architecture

```text
main.jac (client entry / manual routes)
  ├── components/AppLayout.jac       sidebar shell
  ├── components/Dashboard.jac       claim list and upload entry
  ├── components/ClaimIntake.jac     risk-check form
  ├── components/RiskDetail.jac      score, factors and neighbor evidence
  ├── components/UploadDenial.jac    file selection and editable extraction
  ├── components/AppealTracker.jac   appeal timeline, packet and approval gate
  └── components/AuditLog.jac        chronological evidence log

services/claims.jac                  graph schema, views, walkers, endpoints
services/claims.impl.jac             workflow and endpoint implementation
```

### Shared OSP knowledge graph

Jac nodes represent the durable domain entities: `Patient`, `Claim`, `Policy`, `PolicyClause`, `Provider`, `DenialHistory`, `AppealCase`, and `AuditEntry`. Relationships are expressed as graph connections: claims are attached to patients and linked with payer policy and provider context; appeal cases and audit entries are connected to the claim. The root graph is the demo store, persisted by Jac's graph runtime (SQLite by default under `.jac/data/`).

Two walkers operate on the same graph:

- `risk_predictor` traverses from the root to the requested claim, scores it, updates its risk/status fields, and adds an audit entry.
- `appeal_executor` traverses from the root to an appeal case, follows its claim relationship, performs confidence checks, policy matching, classification, and packet generation, then stops at the approval boundary.

Typed `obj` view models (`ClaimView`, `RiskResult`, `AppealView`, `AuditView`, and related objects) shape data sent to the client. Public server functions in `services/claims.jac` are registered through the imports in `main.jac`; client components call them using `sv import` and `await`.

### LLM integration

LLM work is implemented with Jac's native `by llm()` declarations, not a manually written provider HTTP client or a separate SDK. The declared tasks are `llm_extract_denial` (structured `DenialExtraction`) and `llm_write_appeal` (structured `AppealDraft`). The code selects deterministic fallback behavior when no usable key is available or an LLM call fails. Policy clause matching is a local keyword/code lookup over the seeded clauses, not a live document-retrieval service.

## Run locally

From the project root, with Jac 0.34.20 installed:

```bash
jac install
jac start --dev main.jac
```

Open the app URL printed by `jac start` (commonly `http://localhost:8000`). In JacHammer, use the live preview instead of starting another server manually.

## Configure Gemini

`jac.toml` configures the default model and reads its API key from an environment variable:

```toml
[byllm.model]
default_model = "${LLM_MODEL:-gemini/gemini-3.8-flash}"
api_key = "${GOOGLE_API_KEY:-}"
```

Add your own `GOOGLE_API_KEY` in JacHammer **Settings → Environment**, then restart the preview so the server receives the new value. For local runs, provide `GOOGLE_API_KEY` in the process environment. `LLM_MODEL` can override the default model identifier. Never commit API keys or place them in client-side code.

The model name above must be available to your configured provider/account. If your Gemini account uses a different model identifier, set `LLM_MODEL` to that provider-supported name.

## Routes

| Route | Purpose |
|---|---|
| `/` | Dashboard, claim cards, filters, sorting, upload entry |
| `/claims/new` | New claim risk check |
| `/claims/:id/risk` | Risk prediction, factors, similar-claim evidence |
| `/upload` | Denial upload and editable extracted fields |
| `/appeals/:id` | Appeal steps, clause and packet review, approval, simulated tracking |
| `/audit` | Reverse-chronological audit history |

## Source map

- `services/claims.jac` — graph entities, typed view models, reference policy clauses, both walkers, and public endpoint declarations.
- `services/claims.impl.jac` — synthetic historical data, weighted similarity scoring, claim/appeal graph operations, clause matching, LLM calls and fallbacks, mock dispatch, response simulation, and audit writes.
- `components/` — routed UI screens, sidebar shell, and shared status/formatting components.
- `main.jac` — imports server endpoints for registration and wires the manual client routes.
- `styles/global.css` — Tailwind/shadcn theme plus Code Shield's teal, warm-neutral, warning, and heading tokens.

## Limitations and production considerations

- Sample patient, policy, provider, claim-history, and denial data are synthetic. The policy text is illustrative, not an actual payer plan document.
- The prediction method and wrongful-denial classification are demo heuristics, not a calibrated or clinically validated model.
- The simulated payer portal, fax, email, notification, and timers do not contact external parties or guarantee a filing.
- The demo does not provide authentication, tenant isolation, production-grade PHI controls, or a real EHR/claims connector. Do not upload real patient data.
- A production system would need verified policy-document ingestion and citation validation, privacy/security controls, identity and access management, audit retention, reliable deadline services, payer/provider integrations, model evaluation, and clinician/legal/compliance review. External actions should remain explicitly authorized and auditable.
