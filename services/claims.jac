"""Code Shield server: shared claims knowledge graph + two agent workflows.

Graph: root -> Patient -> Claim -> (Policy -> PolicyClause), Provider, DenialHistory,
AppealCase, AuditEntry. Workflow 1 is the f"risk_predictor" walker, Workflow 2 the
f"appeal_executor" walker. Heavy helper bodies live in claims.impl.jac.
"""
import os;
import math;
import random;
import base64;
import from datetime { datetime, timedelta }
import from jaclang.byllm.lib { Image }

# ---------------------------------------------------------------- graph schema
node Patient {
    has name: str = "",
        member_id: str = "";
}

node Policy {
    has payer: str = "",
        plan_name: str = "",
        policy_number: str = "",
        policy_type: str = "";
}

node PolicyClause {
    has section: str = "",
        page: int = 0,
        title: str = "",
        text: str = "",
        codes: list[str] = [],
        keywords: list[str] = [];
}

node Provider {
    has name: str = "",
        npi: str = "",
        email: str = "",
        fax: str = "";
}

node DenialHistory {
    has code: str = "",
        reason: str = "",
        denied_on: str = "",
        level: int = 1;
}

node Claim {
    has claim_number: str = "",
        patient_name: str = "",
        condition: str = "",
        procedure: str = "",
        payer: str = "",
        policy_type: str = "PPO",
        network: str = "in",
        prior_auth: str = "yes",
        documentation: float = 0.8,
        amount: float = 0.0,
        filed: bool = False,
        status: str = "Under Review",
        risk_pct: int = 0,
        risk_reason: str = "",
        predicted_code: str = "",
        date_of_service: str = "",
        created_at: str = "";
}

node AppealCase {
    has claim_id: str = "",
        stage: str = "extracted",
        member_id: str = "",
        denial_code: str = "",
        denial_reason: str = "",
        date_of_service: str = "",
        denial_date: str = "",
        deadline: str = "",
        ocr_confidence: float = 1.0,
        extraction_source: str = "",
        raw_text: str = "",
        clause_section: str = "",
        clause_page: int = 0,
        clause_title: str = "",
        clause_text: str = "",
        clause_score: int = 0,
        classification: str = "",
        classification_why: str = "",
        wrongful_pct: int = 0,
        cover_letter: str = "",
        records_request: str = "",
        medical_necessity: str = "",
        checklist: list[str] = [],
        packet_source: str = "",
        confirmation: str = "",
        submitted_at: str = "",
        followup_date: str = "",
        denial_count: int = 1,
        escalated: bool = False,
        manual_review: bool = False,
        review_reason: str = "",
        rejected_reason: str = "";
}

node AuditEntry {
    has ts: str = "",
        claim_number: str = "",
        actor: str = "Code Shield agent",
        action: str = "",
        detail: str = "",
        evidence: str = "";
}

# ---------------------------------------------------------------- view models
obj ClaimView {
    has id: str = "",
        claim_number: str = "",
        patient: str = "",
        condition: str = "",
        procedure: str = "",
        payer: str = "",
        policy_type: str = "",
        network: str = "",
        prior_auth: str = "",
        documentation: float = 0.0,
        amount: float = 0.0,
        filed: bool = False,
        status: str = "",
        risk_pct: int = 0,
        risk_reason: str = "",
        predicted_code: str = "",
        appeal_id: str = "",
        deadline_days: int = -1,
        date_of_service: str = "",
        created_at: str = "";
}

obj RiskFactor {
    has name: str = "",
        value_label: str = "",
        share: int = 0,
        rate: int = 0,
        explanation: str = "";
}

obj Neighbor {
    has ref: str = "",
        condition: str = "",
        procedure: str = "",
        payer: str = "",
        network: str = "",
        prior_auth: str = "",
        similarity: int = 0,
        denied: bool = False,
        code: str = "",
        overturned: bool = False;
}

obj RiskResult {
    has claim: ClaimView = ClaimView(),
        risk_pct: int = 0,
        wrongful_pct: int = 0,
        confidence: int = 0,
        predicted_code: str = "",
        predicted_reason: str = "",
        verdict: str = "",
        gate: str = "low",
        headline: str = "",
        recommended_action: str = "",
        factors: list[RiskFactor] = [],
        neighbors: list[Neighbor] = [];
}

obj DenialExtraction {
    has patient_name: str = "",
        payer: str = "",
        member_id: str = "",
        claim_number: str = "",
        denial_code: str = "",
        denial_reason: str = "",
        procedure: str = "",
        condition: str = "",
        date_of_service: str = "",
        denial_date: str = "",
        appeal_deadline: str = "",
        amount: float = 0.0,
        confidence: float = 0.0,
        source: str = "",
        raw_text: str = "";
}
sem DenialExtraction = "Structured fields extracted from a health insurance denial letter or EOB.";
sem DenialExtraction.patient_name = "Member / patient full name as printed.";
sem DenialExtraction.payer = "Insurance company name.";
sem DenialExtraction.member_id = "Member ID printed on the letter.";
sem DenialExtraction.claim_number = "Claim number / reference number.";
sem DenialExtraction.denial_code = "CARC denial reason code in the form CO-<number>, e.g. CO-197. Empty if not printed.";
sem DenialExtraction.denial_reason = "Denial reason exactly as stated on the letter.";
sem DenialExtraction.procedure = "Procedure or service that was denied, with CPT code if shown.";
sem DenialExtraction.condition = "Diagnosis / condition, with ICD-10 code if shown.";
sem DenialExtraction.date_of_service = "Date of service, YYYY-MM-DD.";
sem DenialExtraction.denial_date = "Date of the denial letter, YYYY-MM-DD.";
sem DenialExtraction.appeal_deadline = "Appeal filing deadline, YYYY-MM-DD. If absent, denial_date + 180 days.";
sem DenialExtraction.amount = "Billed or denied amount in dollars.";
sem DenialExtraction.confidence = "Your confidence 0.0-1.0 that every extracted field is correct and legible.";
sem DenialExtraction.raw_text = "Full transcribed text of the letter.";

obj AppealDraft {
    has cover_letter: str = "",
        medical_necessity: str = "",
        records_request: str = "";
}
sem AppealDraft.cover_letter = "Formal appeal cover letter to the payer. Rebut the denial reason and quote the provided policy clause citing its section and page exactly as given. Never invent clauses.";
sem AppealDraft.medical_necessity = "Short medical necessity statement for the treating provider to sign.";
sem AppealDraft.records_request = "Letter to the provider requesting the supporting medical records needed for the appeal.";

obj AppealView {
    has id: str = "",
        claim_id: str = "",
        claim_number: str = "",
        patient: str = "",
        payer: str = "",
        condition: str = "",
        procedure: str = "",
        amount: float = 0.0,
        member_id: str = "",
        denial_code: str = "",
        denial_reason: str = "",
        date_of_service: str = "",
        denial_date: str = "",
        deadline: str = "",
        days_left: int = 0,
        stage: str = "",
        ocr_confidence: float = 1.0,
        extraction_source: str = "",
        raw_text: str = "",
        clause_section: str = "",
        clause_page: int = 0,
        clause_title: str = "",
        clause_text: str = "",
        clause_score: int = 0,
        classification: str = "",
        classification_why: str = "",
        wrongful_pct: int = 0,
        cover_letter: str = "",
        records_request: str = "",
        medical_necessity: str = "",
        checklist: list[str] = [],
        packet_source: str = "",
        provider_name: str = "",
        provider_email: str = "",
        confirmation: str = "",
        submitted_at: str = "",
        followup_date: str = "",
        denial_count: int = 1,
        escalated: bool = False,
        manual_review: bool = False,
        review_reason: str = "",
        rejected_reason: str = "";
}

obj AuditView {
    has id: str = "",
        ts: str = "",
        claim_number: str = "",
        actor: str = "",
        action: str = "",
        detail: str = "",
        evidence: str = "";
}

# ---------------------------------------------------------------- reference data
glob DENIAL_CODES: dict[str, str] = {
    "CO-4": "Procedure code inconsistent with modifier",
    "CO-11": "Diagnosis inconsistent with procedure",
    "CO-15": "Authorization number missing or invalid",
    "CO-16": "Claim lacks information needed for adjudication",
    "CO-27": "Expenses incurred after coverage terminated",
    "CO-29": "Time limit for filing has expired",
    "CO-45": "Charge exceeds fee schedule / maximum allowable",
    "CO-50": "Not deemed a medical necessity by the payer",
    "CO-96": "Non-covered charge",
    "CO-97": "Benefit included in payment for another service",
    "CO-119": "Benefit maximum for this period has been reached",
    "CO-197": "Precertification / prior authorization absent",
    "CO-242": "Services not provided by network providers",
    "CO-252": "Additional documentation required"
};

glob LEGIT_CODES: list[str] = ["CO-27", "CO-29", "CO-45", "CO-97"];

glob CLAUSES: list[dict] = [
    {"section": "4.2", "page": 23, "title": "Medically Necessary Diagnostic Imaging", "codes": ["CO-50", "CO-197", "CO-96"], "keywords": ["mri", "ct", "imaging", "scan", "radiology", "spine", "lumbar"], "text": "Advanced diagnostic imaging (MRI, CT, PET) is a Covered Service when ordered by a treating provider for a condition that has not responded to at least six weeks of conservative therapy, or immediately when red-flag neurological symptoms are documented."},
    {"section": "6.1", "page": 31, "title": "Prior Authorization Exceptions", "codes": ["CO-197", "CO-15"], "keywords": ["authorization", "prior", "precertification", "urgent"], "text": "Failure to obtain prior authorization shall not by itself be grounds for denial of a Medically Necessary service. The Plan shall accept retroactive authorization requests within 14 days of an urgent service, and may apply a benefit reduction of no more than 20% in lieu of denial."},
    {"section": "7.4", "page": 38, "title": "Out-of-Network Services and Network Adequacy", "codes": ["CO-242", "CO-45"], "keywords": ["network", "out-of-network", "provider", "access"], "text": "When no in-network provider of the required specialty is available within 30 miles or 15 business days, services from an out-of-network provider are covered at the in-network cost-sharing level."},
    {"section": "5.3", "page": 27, "title": "Cardiac Diagnostic Testing", "codes": ["CO-50", "CO-197"], "keywords": ["cardiac", "stress", "chest", "heart", "ecg", "echocardiogram"], "text": "Cardiac stress testing and echocardiography are Covered Services for members presenting with chest pain, dyspnea, syncope, or abnormal ECG findings, without a requirement for prior failed conservative treatment."},
    {"section": "9.2", "page": 44, "title": "Specialty Drugs and Injectable Therapies", "codes": ["CO-50", "CO-197", "CO-96"], "keywords": ["botox", "injection", "migraine", "drug", "infusion", "onabotulinumtoxina"], "text": "OnabotulinumtoxinA is covered for chronic migraine (15 or more headache days per month) after documented trial of at least two preventive medications. Coverage continues when a 50% reduction in headache days is recorded."},
    {"section": "8.1", "page": 41, "title": "Rehabilitation Therapy", "codes": ["CO-119", "CO-50"], "keywords": ["therapy", "physical", "rehabilitation", "knee", "pt"], "text": "Physical therapy is covered for up to 30 visits per plan year, with additional visits covered when the treating provider documents measurable functional improvement."},
    {"section": "10.5", "page": 47, "title": "Durable Medical Equipment", "codes": ["CO-50", "CO-197", "CO-96"], "keywords": ["cgm", "glucose", "monitor", "device", "pump", "equipment", "diabetes"], "text": "Continuous glucose monitors are covered for members with diabetes who use insulin or who have documented problematic hypoglycemia."},
    {"section": "11.3", "page": 52, "title": "Claims Documentation and Resubmission", "codes": ["CO-16", "CO-252", "CO-4", "CO-11"], "keywords": ["documentation", "records", "information", "missing"], "text": "A claim lacking information required for adjudication shall be pended rather than denied. The Plan must request missing information in writing and allow the provider 45 days to supply it."},
    {"section": "12.1", "page": 58, "title": "Internal Appeals", "codes": [], "keywords": ["appeal"], "text": "A member may file an internal appeal within 180 days of an adverse benefit determination. The Plan shall decide pre-service appeals within 30 days and post-service appeals within 60 days."}
];

glob HISTORY: list[dict] = [];

# ---------------------------------------------------------------- helper decls (bodies in impl)
def _now -> str;
def _today -> str;
def _add_days(date_str: str, days: int) -> str;
def _days_until(date_str: str) -> int;
def _category(procedure: str) -> str;
def _build_history -> list[dict];
def _history -> list[dict];
def _vec(category: str, payer: str, ptype: str, network: str, auth: str, doc: float) -> dict;
def _cos(a: dict, b: dict) -> float;
def _assess(c: Claim) -> RiskResult;
def _find_claim(claim_id: str) -> Claim | None;
def _find_appeal(appeal_id: str) -> AppealCase | None;
def _claim_view(c: Claim) -> ClaimView;
def _appeal_view(a: AppealCase) -> AppealView;
def _audit(c: Claim, actor: str, action: str, detail: str, evidence: str) -> None;
def _policy_for(c: Claim) -> Policy | None;
def _provider_for(c: Claim) -> Provider | None;
def _match_clause(c: Claim, a: AppealCase) -> None;
def _classify(c: Claim, a: AppealCase) -> None;
def _draft_packet(c: Claim, a: AppealCase) -> None;
def _mock_extraction(filename: str) -> DenialExtraction;
def _has_llm -> bool;
def _ensure_policy(payer: str, ptype: str) -> Policy;
def _ensure_provider -> Provider;
def _new_claim(patient: str, member_id: str, fields: dict) -> Claim;
def _open_appeal(c: Claim, ext: DenialExtraction) -> AppealCase;
def _all_claims -> list[Claim];

# LLM-powered steps (used only when an API key is configured; deterministic fallbacks otherwise)
def llm_extract_denial(letter: Image) -> DenialExtraction by llm(temperature=0.0);
sem llm_extract_denial = "Read this photo/scan of a health insurance denial letter or Explanation of Benefits and extract every field precisely. Do not guess: lower the confidence when text is unclear.";
sem llm_extract_denial.letter = "Image of the denial letter or EOB.";

def llm_write_appeal(facts: str, clause_citation: str) -> AppealDraft by llm(temperature=0.2);
sem llm_write_appeal = "Write an appeal packet for a wrongfully denied health insurance claim. Be calm, precise and factual. Cite ONLY the policy clause given, by section and page.";
sem llm_write_appeal.facts = "Claim facts: patient, payer, member id, claim number, procedure, condition, dates, denial code and reason.";
sem llm_write_appeal.clause_citation = "The matched policy clause with section, page and verbatim text.";

# ---------------------------------------------------------------- Workflow 1: risk predictor
walker risk_predictor {
    has claim_id: str = "",
        result: RiskResult | None = None;

    can locate with Root entry {
        target = jobj(self.claim_id);
        if isinstance(target, Claim) {
            visit [target];
        }
    }

    can assess with Claim entry {
        r = _assess(here);
        if here.status not in ["Denied", "Appeal In Progress", "Overturned", "Upheld", "Manual Review"] {
            if r.risk_pct >= 55 {
                here.status = "At Risk";
            } elif here.filed {
                here.status = "Under Review";
            } else {
                here.status = "Ready to File";
            }
        }
        here.risk_pct = r.risk_pct;
        here.risk_reason = r.headline;
        here.predicted_code = r.predicted_code;
        r.claim = _claim_view(here);
        _audit(
            here, "Risk predictor", f"Scored denial risk at {r.risk_pct}%",
            f"Verdict: {r.verdict}. Predicted denial code {r.predicted_code}. Decision gate: {r.gate}.",
            f"k-NN over {len(_history())} historical claims; nearest: " + ", ".join([n.ref + " (" + str(n.similarity) + "% similar)" for n in r.neighbors[:4]])
        );
        self.result = r;
        disengage;
    }
}

# ---------------------------------------------------------------- Workflow 2: appeal executor
walker appeal_executor {
    has appeal_id: str = "",
        force: bool = False,
        stage_reached: str = "";

    can locate with Root entry {
        target = jobj(self.appeal_id);
        if isinstance(target, AppealCase) {
            visit [target];
        }
    }

    can execute with AppealCase entry {
        c = _find_claim(here.claim_id);
        if c is None {
            disengage;
        }
        claim = c as Claim;
        # Confidence-based fallback: never guess.
        if not self.force {
            if here.ocr_confidence < 0.6 {
                here.manual_review = True;
                here.stage = "manual_review";
                here.review_reason = f"Extraction confidence is {int(here.ocr_confidence * 100)}%, below the 60% threshold. A person should confirm the fields before the agent proceeds.";
                claim.status = "Manual Review";
                _audit(claim, "Appeal executor", "Routed to manual review", here.review_reason, "OCR confidence score");
                self.stage_reached = here.stage;
                disengage;
            }
            if here.denial_code not in DENIAL_CODES {
                here.manual_review = True;
                here.stage = "manual_review";
                here.review_reason = f"Denial code '{here.denial_code}' is not a recognised CARC code, so the agent will not guess at a rebuttal.";
                claim.status = "Manual Review";
                _audit(claim, "Appeal executor", "Routed to manual review", here.review_reason, "CARC code table (" + str(len(DENIAL_CODES)) + " codes)");
                self.stage_reached = here.stage;
                disengage;
            }
        }
        here.manual_review = False;
        here.review_reason = "";
        _match_clause(claim, here);
        _classify(claim, here);
        if here.classification == "legitimate" and not self.force {
            here.manual_review = True;
            here.stage = "manual_review";
            here.review_reason = "This denial looks legitimate under the plan terms. The agent recommends a human decide whether an appeal is worthwhile.";
            claim.status = "Manual Review";
            self.stage_reached = here.stage;
            disengage;
        }
        _draft_packet(claim, here);
        here.stage = "awaiting_approval";
        claim.status = "Appeal In Progress";
        _audit(claim, "Appeal executor", "Paused for human approval", "Appeal packet is ready. Nothing is sent to the payer, provider or patient until a person approves it.", "Human-in-the-loop checkpoint");
        self.stage_reached = here.stage;
        disengage;
    }
}

# ---------------------------------------------------------------- endpoints
def:pub seed_demo() -> bool;
def:pub list_claims() -> list[ClaimView];
def:pub check_claim(
    patient: str,
    condition: str,
    procedure: str,
    payer: str,
    policy_type: str,
    network: str,
    prior_auth: str,
    documentation: float,
    amount: float,
    filed: bool
) -> str;
def:pub get_risk(claim_id: str) -> RiskResult | None;
def:pub mark_denied(claim_id: str, denial_code: str) -> str;
def:pub start_appeal(claim_id: str) -> str;
def:pub extract_denial_letter(filename: str, mime: str, data_b64: str) -> DenialExtraction;
def:pub open_upload_appeal(ext: DenialExtraction) -> str;
def:pub get_appeal(appeal_id: str) -> AppealView | None;
def:pub save_letter(appeal_id: str, letter: str) -> AppealView | None;
def:pub override_review(appeal_id: str) -> AppealView | None;
def:pub approve_appeal(appeal_id: str) -> AppealView | None;
def:pub reject_appeal(appeal_id: str, reason: str) -> AppealView | None;
def:pub simulate_payer_response(appeal_id: str, outcome: str) -> AppealView | None;
def:pub list_audit(claim_number: str) -> list[AuditView];
