"""Implementation bodies for services/claims.jac."""

# ---------------------------------------------------------------- time helpers
impl _now -> str {
    return datetime.now().isoformat(timespec="milliseconds");
}

impl _today -> str {
    return datetime.now().strftime("%Y-%m-%d");
}

impl _add_days(date_str: str, days: int) -> str {
    try {
        d = datetime.strptime(date_str, "%Y-%m-%d");
        return (d + timedelta(days=days)).strftime("%Y-%m-%d");
    } except Exception {
        return (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d");
    }
}

impl _days_until(date_str: str) -> int {
    try {
        d = datetime.strptime(date_str, "%Y-%m-%d").date();
        return (d - datetime.now().date()).days;
    } except Exception {
        return 0;
    }
}

impl _has_llm -> bool {
    key = os.environ.get("OPENAI_API_KEY", "") or os.environ.get("ANTHROPIC_API_KEY", "") or os.environ.get("GOOGLE_API_KEY", "");
    return len(key.strip()) > 8;
}

# ---------------------------------------------------------------- features
impl _category(procedure: str) -> str {
    p = procedure.lower();
    if "mri" in p or "ct " in p or "imaging" in p or "scan" in p {
        return "mri";
    }
    if "cardiac" in p or "echo" in p or "stress" in p or "heart" in p {
        return "cardiac";
    }
    if "botox" in p or "onabotulinum" in p or "injection" in p or "infusion" in p {
        return "botox";
    }
    if "therapy" in p or "rehab" in p {
        return "pt";
    }
    if "glucose" in p or "cgm" in p or "monitor" in p or "pump" in p {
        return "cgm";
    }
    return "surgery";
}

glob CAT_LABELS: dict[str, str] = {
    "mri": "MRI",
    "cardiac": "cardiac testing",
    "botox": "specialty injection",
    "pt": "physical therapy",
    "cgm": "glucose monitor",
    "surgery": "outpatient surgery"
};

impl _build_history -> list[dict] {
    rng = random.Random(1187);
    cats: list[list[str]] = [
        ["mri", "Lumbar spine MRI (CPT 72148)", "Chronic low back pain"],
        ["cardiac", "Cardiac stress echocardiogram (CPT 93350)", "Chest pain"],
        ["botox", "OnabotulinumtoxinA injection (J0585)", "Chronic migraine"],
        ["pt", "Physical therapy, 12 visits (CPT 97110)", "Knee osteoarthritis"],
        ["cgm", "Continuous glucose monitor (E2103)", "Type 2 diabetes"],
        ["surgery", "Knee arthroscopy (CPT 29881)", "Meniscus tear"]
    ];
    cat_risk: dict[str, float] = {"mri": 0.12, "cardiac": 0.02, "botox": 0.15, "pt": 0.05, "cgm": 0.08, "surgery": 0.14};
    payers: list[str] = ["UnitedHealthcare", "Aetna", "Cigna", "BlueCross BlueShield"];
    payer_risk: dict[str, float] = {"UnitedHealthcare": 0.08, "Aetna": 0.03, "Cigna": 0.06, "BlueCross BlueShield": 0.0};
    out: list[dict] = [];
    for i in range(72) {
        cat = cats[i % 6];
        payer = rng.choice(payers);
        ptype = rng.choice(["PPO", "HMO", "EPO"]);
        network = "out" if rng.random() < 0.32 else "in";
        auth = rng.choice(["yes", "yes", "no", "pending"]);
        doc: float = float(int((0.35 + rng.random() * 0.65) * 100)) / 100.0;
        p = 0.05 + cat_risk[cat[0]] + payer_risk[payer];
        if network == "out" {
            p += 0.22;
        }
        if auth == "no" {
            p += 0.3;
        } elif auth == "pending" {
            p += 0.14;
        }
        p += (1.0 - doc) * 0.3;
        if ptype == "HMO" {
            p += 0.05;
        }
        denied = rng.random() < p;
        code = "";
        overturned = False;
        if denied {
            roll = rng.random();
            if auth == "no" and roll < 0.7 {
                code = "CO-197";
            } elif network == "out" and roll < 0.75 {
                code = "CO-242";
            } elif doc < 0.6 {
                code = "CO-16" if roll < 0.5 else "CO-252";
            } elif roll < 0.18 {
                code = "CO-45";
            } else {
                code = "CO-50";
            }
            overturned = code not in LEGIT_CODES and rng.random() < (0.3 + doc * 0.45);
        }
        out.append({
            "ref": f"HX-{1041 + i}",
            "category": cat[0],
            "procedure": cat[1],
            "condition": cat[2],
            "payer": payer,
            "policy_type": ptype,
            "network": network,
            "prior_auth": auth,
            "documentation": doc,
            "denied": denied,
            "code": code,
            "overturned": overturned
        });
    }
    return out;
}

impl _history -> list[dict] {
    if len(HISTORY) == 0 {
        HISTORY = _build_history();
    }
    return HISTORY;
}

impl _vec(category: str, payer: str, ptype: str, network: str, auth: str, doc: float) -> dict {
    return {
        "c_" + category: 1.3,
        "p_" + payer: 0.6,
        "t_" + ptype: 0.4,
        "n_" + network: 1.1,
        "a_" + auth: 1.2,
        "doc": doc,
        "gap": (1.0 - doc) * 1.2
    };
}

impl _cos(a: dict, b: dict) -> float {
    dot = 0.0;
    na = 0.0;
    nb = 0.0;
    for k in a {
        va = float(a[k]);
        na += va * va;
        if k in b {
            dot += va * float(b[k]);
        }
    }
    for k in b {
        vb = float(b[k]);
        nb += vb * vb;
    }
    if na == 0.0 or nb == 0.0 {
        return 0.0;
    }
    return dot / (math.sqrt(na) * math.sqrt(nb));
}

def _rate(rows: list[dict]) -> int {
    if len(rows) == 0 {
        return 0;
    }
    return int(round(100.0 * len([r for r in rows if r["denied"]]) / len(rows)));
}

def _doc_bucket(d: float) -> str {
    if d < 0.6 {
        return "low";
    }
    if d < 0.8 {
        return "partial";
    }
    return "complete";
}

impl _assess(c: Claim) -> RiskResult {
    hist = _history();
    cat = _category(c.procedure);
    v = _vec(cat, c.payer, c.policy_type, c.network, c.prior_auth, c.documentation);
    scored: list[dict] = [];
    for h in hist {
        hv = _vec(h["category"], h["payer"], h["policy_type"], h["network"], h["prior_auth"], float(h["documentation"]));
        scored.append({"s": _cos(v, hv), "h": h});
    }
    scored.sort(key=lambda (d: dict) -> float { return float(d["s"]); }, reverse=True);
    top = scored[:9];
    wsum = 0.0;
    wden = 0.0;
    wover = 0.0;
    simsum = 0.0;
    code_w: dict[str, float] = {};
    neighbors: list[Neighbor] = [];
    for item in top {
        s = float(item["s"]);
        h: dict = item["h"];
        w = s * s;
        wsum += w;
        simsum += s;
        if h["denied"] {
            wden += w;
            cd = str(h["code"]);
            code_w[cd] = code_w.get(cd, 0.0) + w;
            if h["overturned"] {
                wover += w;
            }
        }
        if len(neighbors) < 6 {
            neighbors.append(Neighbor(
                ref=h["ref"], condition=h["condition"], procedure=h["procedure"], payer=h["payer"],
                network=h["network"], prior_auth=h["prior_auth"], similarity=int(round(s * 100)),
                denied=bool(h["denied"]), code=str(h["code"]), overturned=bool(h["overturned"])
            ));
        }
    }
    risk_pct = int(round(100.0 * wden / wsum)) if wsum > 0 else 0;
    wrongful_pct = int(round(100.0 * wover / wden)) if wden > 0 else 0;
    confidence = int(round(100.0 * simsum / len(top))) if len(top) > 0 else 0;
    predicted = "CO-50";
    best = -1.0;
    for k in code_w {
        if code_w[k] > best {
            best = code_w[k];
            predicted = k;
        }
    }
    if c.status in ["Denied", "Appeal In Progress", "Manual Review"] and c.predicted_code {
        predicted = c.predicted_code;
    }
    # ---- contributing factors: lift of each attribute over the base denial rate
    base = _rate(hist);
    bucket = _doc_bucket(c.documentation);
    auth_rows = [h for h in hist if h["prior_auth"] == c.prior_auth];
    net_rows = [h for h in hist if h["network"] == c.network];
    doc_rows = [h for h in hist if _doc_bucket(float(h["documentation"])) == bucket];
    cat_rows = [h for h in hist if h["category"] == cat];
    pay_rows = [h for h in hist if h["payer"] == c.payer];
    auth_label = {"yes": "Obtained", "no": "Not obtained", "pending": "Pending"}.get(c.prior_auth, c.prior_auth);
    raw: list[dict] = [
        {"name": "Prior authorization", "value": auth_label, "rate": _rate(auth_rows)},
        {"name": "Network status", "value": "Out-of-network" if c.network == "out" else "In-network", "rate": _rate(net_rows)},
        {"name": "Documentation completeness", "value": f"{int(c.documentation * 100)}% complete", "rate": _rate(doc_rows)},
        {"name": "Procedure type", "value": CAT_LABELS.get(cat, cat), "rate": _rate(cat_rows)},
        {"name": "Payer", "value": c.payer, "rate": _rate(pay_rows)}
    ];
    total_lift = 0.0;
    for f in raw {
        total_lift += max(0.0, float(int(f["rate"]) - base) + 2.0);
    }
    factors: list[RiskFactor] = [];
    for f in raw {
        rate = int(f["rate"]);
        lift = max(0.0, float(rate - base) + 2.0);
        share = int(round(100.0 * lift / total_lift)) if total_lift > 0 else 20;
        name = str(f["name"]);
        expl = "";
        if name == "Prior authorization" {
            if c.prior_auth == "no" {
                expl = f"Prior authorization was not obtained. {rate}% of similar claims without it were denied (vs {base}% overall), so this alone accounts for about {share}% of the risk.";
            } elif c.prior_auth == "pending" {
                expl = f"Prior authorization is still pending. Claims filed before approval were denied {rate}% of the time.";
            } else {
                expl = f"Prior authorization is on file, which keeps this factor low ({rate}% denial rate in comparable claims).";
            }
        } elif name == "Network status" {
            if c.network == "out" {
                expl = f"The provider is out-of-network. {rate}% of out-of-network claims were denied, often as CO-242, which is frequently overturned under network adequacy rules.";
            } else {
                expl = f"The provider is in-network ({rate}% denial rate), so network status is not a meaningful driver here.";
            }
        } elif name == "Documentation completeness" {
            if bucket == "complete" {
                expl = f"The supporting documentation is complete. Claims like this were denied {rate}% of the time.";
            } else {
                expl = f"The supporting documentation is {bucket}. Claims with {bucket} records were denied {rate}% of the time, usually as CO-16 or CO-252.";
            }
        } elif name == "Procedure type" {
            expl = f"{CAT_LABELS.get(cat, cat).capitalize()} claims have a {rate}% historical denial rate across all payers.";
        } else {
            expl = f"{c.payer} denied {rate}% of comparable claims in the historical dataset.";
        }
        factors.append(RiskFactor(name=name, value_label=str(f["value"]), share=share, rate=rate, explanation=expl));
    }
    factors.sort(key=lambda (x: RiskFactor) -> int { return x.share; }, reverse=True);
    net_word = "out-of-network" if c.network == "out" else "in-network";
    auth_word = {"yes": "with prior auth", "no": "without prior auth", "pending": "with prior auth pending"}.get(c.prior_auth, "");
    headline = f"{risk_pct}% of similar {net_word} {CAT_LABELS.get(cat, cat)} claims {auth_word} were denied, and {wrongful_pct}% of those were later overturned on appeal.";
    denied_now = c.status in ["Denied", "Manual Review", "Appeal In Progress", "Upheld", "Overturned"];
    verdict = "";
    gate = "low";
    action = "";
    if denied_now {
        verdict = "Denied, and likely wrongfully" if wrongful_pct >= 45 else "Denied, with modest appeal odds";
        gate = "denied";
        action = "This claim has been denied. Hand it to the Appeal Executor to build and file the appeal.";
    } elif risk_pct >= 55 {
        verdict = "Likely to be wrongfully denied" if wrongful_pct >= 45 else "High risk of denial";
        if c.filed {
            gate = "appeal_prep";
            action = "This claim is already filed. Start appeal prep now so the packet is ready the day a denial arrives.";
        } else {
            gate = "prevent";
            action = "Fix before filing: resolve the top factors below (for example request prior authorization) to prevent the denial entirely.";
        }
    } elif risk_pct >= 30 {
        verdict = "Moderate risk, worth a quick check";
        action = "Review the documentation factor before filing. No agent action needed.";
    } else {
        verdict = "Low risk, likely to be paid";
        action = "Logged. The agent will keep watching this claim.";
    }
    return RiskResult(
        risk_pct=risk_pct, wrongful_pct=wrongful_pct, confidence=confidence,
        predicted_code=predicted, predicted_reason=DENIAL_CODES.get(predicted, "Unknown reason"),
        verdict=verdict, gate=gate, headline=headline, recommended_action=action,
        factors=factors, neighbors=neighbors
    );
}

# ---------------------------------------------------------------- lookups and views
impl _find_claim(claim_id: str) -> Claim | None {
    try {
        t = jobj(claim_id);
        if isinstance(t, Claim) {
            return t;
        }
    } except Exception {}
    return None;
}

impl _find_appeal(appeal_id: str) -> AppealCase | None {
    try {
        t = jobj(appeal_id);
        if isinstance(t, AppealCase) {
            return t;
        }
    } except Exception {}
    return None;
}

impl _all_claims -> list[Claim] {
    return [root -->[?:Patient]-->[?:Claim]];
}

impl _claim_view(c: Claim) -> ClaimView {
    appeals = [c -->[?:AppealCase]];
    aid = "";
    days = -1;
    if len(appeals) > 0 {
        a = appeals[-1];
        aid = jid(a);
        if a.stage not in ["overturned", "rejected"] {
            days = _days_until(a.deadline);
        }
    }
    return ClaimView(
        id=jid(c), claim_number=c.claim_number, patient=c.patient_name, condition=c.condition,
        procedure=c.procedure, payer=c.payer, policy_type=c.policy_type, network=c.network,
        prior_auth=c.prior_auth, documentation=c.documentation, amount=c.amount, filed=c.filed,
        status=c.status, risk_pct=c.risk_pct, risk_reason=c.risk_reason, predicted_code=c.predicted_code,
        appeal_id=aid, deadline_days=days, date_of_service=c.date_of_service, created_at=c.created_at
    );
}

impl _provider_for(c: Claim) -> Provider | None {
    ps = [c -->[?:Provider]];
    return ps[0] if len(ps) > 0 else None;
}

impl _policy_for(c: Claim) -> Policy | None {
    ps = [c -->[?:Policy]];
    return ps[0] if len(ps) > 0 else None;
}

impl _appeal_view(a: AppealCase) -> AppealView {
    c = _find_claim(a.claim_id);
    num = "";
    patient = "";
    payer = "";
    cond = "";
    proc = "";
    amt = 0.0;
    pname = "";
    pemail = "";
    if c is not None {
        num = c.claim_number;
        patient = c.patient_name;
        payer = c.payer;
        cond = c.condition;
        proc = c.procedure;
        amt = c.amount;
        prov = _provider_for(c);
        if prov is not None {
            pname = prov.name;
            pemail = prov.email;
        }
    }
    return AppealView(
        id=jid(a), claim_id=a.claim_id, claim_number=num, patient=patient, payer=payer,
        condition=cond, procedure=proc, amount=amt, member_id=a.member_id,
        denial_code=a.denial_code, denial_reason=a.denial_reason, date_of_service=a.date_of_service,
        denial_date=a.denial_date, deadline=a.deadline, days_left=_days_until(a.deadline),
        stage=a.stage, ocr_confidence=a.ocr_confidence, extraction_source=a.extraction_source,
        raw_text=a.raw_text, clause_section=a.clause_section, clause_page=a.clause_page,
        clause_title=a.clause_title, clause_text=a.clause_text, clause_score=a.clause_score,
        classification=a.classification, classification_why=a.classification_why,
        wrongful_pct=a.wrongful_pct, cover_letter=a.cover_letter, records_request=a.records_request,
        medical_necessity=a.medical_necessity, checklist=a.checklist, packet_source=a.packet_source,
        provider_name=pname, provider_email=pemail, confirmation=a.confirmation,
        submitted_at=a.submitted_at, followup_date=a.followup_date, denial_count=a.denial_count,
        escalated=a.escalated, manual_review=a.manual_review, review_reason=a.review_reason,
        rejected_reason=a.rejected_reason
    );
}

impl _audit(c: Claim, actor: str, action: str, detail: str, evidence: str) -> None {
    c ++> AuditEntry(ts=_now(), claim_number=c.claim_number, actor=actor, action=action, detail=detail, evidence=evidence);
}

# ---------------------------------------------------------------- graph construction
impl _ensure_policy(payer: str, ptype: str) -> Policy {
    for p in [root -->[?:Policy]] {
        if p.payer == payer and p.policy_type == ptype {
            return p;
        }
    }
    num = "".join([ch for ch in payer.upper() if ch.isalpha()])[:3] + "-" + ptype + "-" + str(random.randint(100000, 999999));
    pol = root ++> Policy(payer=payer, plan_name=f"{payer} {ptype} Summary Plan Description 2025", policy_number=num, policy_type=ptype);
    for cl in CLAUSES {
        pol ++> PolicyClause(section=cl["section"], page=int(cl["page"]), title=cl["title"], text=cl["text"], codes=cl["codes"], keywords=cl["keywords"]);
    }
    return pol;
}

impl _ensure_provider -> Provider {
    ps = [root -->[?:Provider]];
    if len(ps) > 0 {
        return ps[0];
    }
    return root ++> Provider(name="Riverside Medical Group", npi="1437 882 019", email="records@riversidemed.example", fax="(555) 214-7730");
}

impl _new_claim(patient: str, member_id: str, fields: dict) -> Claim {
    pat: Patient | None = None;
    for p in [root -->[?:Patient]] {
        if p.name == patient {
            pat = p;
        }
    }
    if pat is None {
        pat = root ++> Patient(name=patient, member_id=member_id);
    }
    person = pat as Patient;
    num = "CLM-" + str(random.randint(2400000, 2499999));
    c = person ++> Claim(
        claim_number=num, patient_name=patient,
        condition=str(fields.get("condition", "")), procedure=str(fields.get("procedure", "")),
        payer=str(fields.get("payer", "")), policy_type=str(fields.get("policy_type", "PPO")),
        network=str(fields.get("network", "in")), prior_auth=str(fields.get("prior_auth", "yes")),
        documentation=float(fields.get("documentation", 0.8)), amount=float(fields.get("amount", 0.0)),
        filed=bool(fields.get("filed", False)), status=str(fields.get("status", "Under Review")),
        date_of_service=str(fields.get("dos", _add_days(_today(), -10))), created_at=_now()
    );
    c ++> _ensure_policy(c.payer, c.policy_type);
    c ++> _ensure_provider();
    _audit(c, "Intake", "Claim added to knowledge graph", f"{c.procedure} for {c.condition}, billed to {c.payer} ({c.policy_type}).", "Structured claim intake form");
    return c;
}

impl _open_appeal(c: Claim, ext: DenialExtraction) -> AppealCase {
    denial_date = ext.denial_date or _today();
    deadline = ext.appeal_deadline or _add_days(denial_date, 180);
    code = ext.denial_code.strip().upper().replace(" ", "");
    if code and not code.startswith("CO-") and code[:2] == "CO" {
        code = "CO-" + code[2:];
    }
    reason = ext.denial_reason or DENIAL_CODES.get(code, "");
    a = c ++> AppealCase(
        claim_id=jid(c), member_id=ext.member_id, denial_code=code, denial_reason=reason,
        date_of_service=ext.date_of_service or c.date_of_service, denial_date=denial_date,
        deadline=deadline, ocr_confidence=ext.confidence, extraction_source=ext.source,
        raw_text=ext.raw_text, stage="extracted"
    );
    c ++> DenialHistory(code=code, reason=reason, denied_on=denial_date, level=1);
    c.status = "Denied";
    c.predicted_code = code;
    _audit(c, "Appeal executor", "Extracted denial details",
        f"Code {code} ({reason}). Denied {denial_date}. Appeal deadline {deadline}. Confidence {int(ext.confidence * 100)}%.",
        ext.source);
    return a;
}

# ---------------------------------------------------------------- workflow 2 steps
impl _match_clause(c: Claim, a: AppealCase) -> None {
    pol = _policy_for(c);
    clauses: list[PolicyClause] = [pol -->[?:PolicyClause]] if pol is not None else [];
    haystack = (c.procedure + " " + c.condition + " " + a.denial_reason).lower();
    best: PolicyClause | None = None;
    best_score = -1;
    hits_best: list[str] = [];
    for cl in clauses {
        score = 0;
        hits: list[str] = [];
        if a.denial_code in cl.codes {
            score += 3;
            hits.append(a.denial_code);
        }
        for kw in cl.keywords {
            if kw in haystack {
                score += 2;
                hits.append(kw);
            }
        }
        if score > best_score {
            best_score = score;
            best = cl;
            hits_best = hits;
        }
    }
    if best is None {
        a.clause_section = "";
        a.clause_score = 0;
        return;
    }
    b = best as PolicyClause;
    a.clause_section = b.section;
    a.clause_page = b.page;
    a.clause_title = b.title;
    a.clause_text = b.text;
    a.clause_score = min(98, 35 + best_score * 9);
    a.stage = "clause_matched";
    plan = pol.plan_name if pol is not None else "Plan document";
    _audit(c, "Policy matcher", f"Matched Section {b.section}, page {b.page}",
        f"\"{b.title}\" matched with {a.clause_score}% relevance.",
        f"{plan}; matched terms: " + ", ".join(hits_best));
}

impl _classify(c: Claim, a: AppealCase) -> None {
    r = _assess(c);
    code_ok = a.denial_code not in LEGIT_CODES;
    clause_ok = a.clause_score >= 50;
    pct = int(round(0.5 * r.wrongful_pct + (30 if code_ok else 0) + (20 if clause_ok else 0)));
    pct = max(5, min(97, pct));
    a.wrongful_pct = pct;
    if code_ok and (clause_ok or r.wrongful_pct >= 50) {
        a.classification = "wrongful";
        a.classification_why = f"{a.denial_code} ({DENIAL_CODES.get(a.denial_code, '')}) conflicts with Section {a.clause_section} of the plan, and {r.wrongful_pct}% of the most similar historical denials were overturned on appeal.";
    } else {
        a.classification = "legitimate";
        a.classification_why = f"{a.denial_code} is usually an administrative or contractual denial, and no plan clause strongly contradicts it.";
    }
    a.stage = "classified";
    _audit(c, "Classifier", f"Classified denial as {a.classification} ({pct}% likely wrongful)", a.classification_why,
        f"Reason-code heuristics + k-NN over {len(_history())} historical claims (" + ", ".join([n.ref for n in r.neighbors[:3]]) + ")");
}

impl _draft_packet(c: Claim, a: AppealCase) -> None {
    prov = _provider_for(c);
    pol = _policy_for(c);
    prov_name = prov.name if prov is not None else "Treating provider";
    policy_no = pol.policy_number if pol is not None else "";
    citation = f"Section {a.clause_section}, page {a.clause_page}: \"{a.clause_title}\". {a.clause_text}";
    facts = f"Patient {c.patient_name}, member ID {a.member_id}, payer {c.payer}, policy {policy_no}, claim {c.claim_number}. Procedure: {c.procedure}. Condition: {c.condition}. Date of service {a.date_of_service}. Denied {a.denial_date} with code {a.denial_code}: {a.denial_reason}. Provider: {prov_name}.";
    used_llm = False;
    if _has_llm() {
        try {
            d = llm_write_appeal(facts, citation);
            if d.cover_letter {
                a.cover_letter = d.cover_letter;
                a.medical_necessity = d.medical_necessity;
                a.records_request = d.records_request;
                used_llm = True;
            }
        } except Exception {}
    }
    if not used_llm {
        nl = chr(10);
        a.cover_letter = nl.join([
            f"{c.payer} Appeals Department",
            f"Re: Request for internal appeal of claim {c.claim_number}",
            f"Member: {c.patient_name}  |  Member ID: {a.member_id}  |  Policy: {policy_no}",
            f"Date of service: {a.date_of_service}  |  Denial date: {a.denial_date}",
            "",
            "To the Appeals Reviewer,",
            "",
            f"I am requesting a full and fair review of the denial of {c.procedure}, which was denied under reason code {a.denial_code} (\"{a.denial_reason}\").",
            "",
            f"This denial is inconsistent with the terms of my plan. Section {a.clause_section} of the Summary Plan Description (page {a.clause_page}), \"{a.clause_title}\", states:",
            "",
            f"    \"{a.clause_text}\"",
            "",
            f"My treating provider, {prov_name}, ordered this service to diagnose and treat {c.condition.lower()}. The enclosed records and letter of medical necessity document that the plan's coverage criteria were met on the date of service.",
            "",
            f"I ask that you reverse the denial and reprocess claim {c.claim_number} for payment. Under Section 12.1 of the plan, please issue a decision within 60 days of receipt of this appeal.",
            "",
            "Sincerely,",
            c.patient_name
        ]);
        a.medical_necessity = nl.join([
            "Letter of Medical Necessity",
            f"Patient: {c.patient_name}  |  Service: {c.procedure}",
            "",
            f"I am the treating clinician for the above patient. The requested service is medically necessary for the evaluation and management of {c.condition.lower()}. Conservative measures were documented prior to ordering, and the service is consistent with accepted standards of care and with Section {a.clause_section} of the member's plan.",
            "",
            f"Signature: ______________________   {prov_name}"
        ]);
        a.records_request = nl.join([
            f"To: {prov_name} Medical Records ({prov.email if prov is not None else ''})",
            f"Re: Records request for insurance appeal, claim {c.claim_number}",
            "",
            f"Please send the following for {c.patient_name} (date of service {a.date_of_service}) within 10 business days:",
            "  1. Office notes from the ordering visit and the prior 90 days",
            "  2. Documentation of conservative treatment tried and its outcome",
            "  3. Any prior authorization request and payer correspondence",
            "  4. A signed letter of medical necessity (draft enclosed)",
            "",
            "These records support an internal appeal. Thank you.",
            "Code Shield, on behalf of the patient"
        ]);
    }
    checklist: list[str] = [
        "Copy of the denial letter / EOB",
        "Appeal cover letter (signed)",
        f"Plan excerpt: Section {a.clause_section}, page {a.clause_page}",
        "Letter of medical necessity from the treating provider",
        "Office notes and relevant medical records"
    ];
    if a.denial_code in ["CO-197", "CO-15"] {
        checklist.append("Retroactive prior authorization request");
    }
    if a.denial_code == "CO-242" {
        checklist.append("Network adequacy attestation (no in-network specialist available)");
    }
    if a.denial_code in ["CO-16", "CO-252"] or c.documentation < 0.8 {
        checklist.append("Missing documentation requested from provider (records request letter)");
    }
    a.checklist = checklist;
    a.packet_source = "Generated by LLM (by llm) from matched clause" if used_llm else "Generated from verified template with matched clause";
    a.stage = "drafted";
    _audit(c, "Document assembler", "Drafted appeal packet",
        f"Cover letter, letter of medical necessity, records request and {len(checklist)}-item attachment checklist.",
        f"Cites Section {a.clause_section}, page {a.clause_page} verbatim. {a.packet_source}.");
}

impl _mock_extraction(filename: str) -> DenialExtraction {
    low = "blur" in filename.lower() or "low" in filename.lower();
    today = _today();
    denial_date = _add_days(today, -9);
    dos = _add_days(today, -31);
    deadline = _add_days(denial_date, 180);
    nl = chr(10);
    raw = nl.join([
        "UnitedHealthcare - Explanation of Benefits / Notice of Adverse Benefit Determination",
        f"Date: {denial_date}",
        "Member: Priya Raman    Member ID: UHC 884 210 337",
        "Claim number: CLM-2471190",
        f"Date of service: {dos}    Provider: Riverside Medical Group",
        "Service: Lumbar spine MRI without contrast (CPT 72148)",
        "Diagnosis: Lumbar radiculopathy (ICD-10 M54.16)",
        "Billed: $3,240.00    Plan paid: $0.00",
        "Reason: CO-197 Precertification/authorization/notification absent.",
        f"You may appeal this decision within 180 days (by {deadline})."
    ]);
    return DenialExtraction(
        patient_name="Priya Raman", payer="UnitedHealthcare", member_id="UHC 884 210 337",
        claim_number="CLM-2471190", denial_code="CO-197",
        denial_reason="Precertification/authorization/notification absent",
        procedure="Lumbar spine MRI without contrast (CPT 72148)",
        condition="Lumbar radiculopathy (ICD-10 M54.16)", date_of_service=dos,
        denial_date=denial_date, appeal_deadline=deadline, amount=3240.0,
        confidence=0.46 if low else 0.93,
        source=f"Simulated OCR of '{filename}' (no LLM key configured)", raw_text=raw
    );
}

# ---------------------------------------------------------------- endpoints
impl seed_demo() -> bool {
    if len(_all_claims()) > 0 {
        return False;
    }
    today = _today();
    # 1. At-risk, already filed: out-of-network MRI without prior auth
    c1 = _new_claim("Maya Okafor", "UHC 553 019 882", {
        "condition": "Chronic low back pain with sciatica", "procedure": "Lumbar spine MRI (CPT 72148)",
        "payer": "UnitedHealthcare", "policy_type": "PPO", "network": "out", "prior_auth": "no",
        "documentation": 0.55, "amount": 3240.0, "filed": True, "dos": _add_days(today, -6)
    });
    root spawn risk_predictor(claim_id=jid(c1));
    # 2. Low risk cardiac test
    c2 = _new_claim("Daniel Reyes", "AET 771 204 519", {
        "condition": "Exertional chest pain", "procedure": "Cardiac stress echocardiogram (CPT 93350)",
        "payer": "Aetna", "policy_type": "PPO", "network": "in", "prior_auth": "yes",
        "documentation": 0.92, "amount": 1850.0, "filed": True, "dos": _add_days(today, -4)
    });
    root spawn risk_predictor(claim_id=jid(c2));
    # 3. Not yet filed, high risk: prevention path
    c3 = _new_claim("Grace Liu", "UHC 208 441 973", {
        "condition": "Meniscus tear, right knee", "procedure": "Knee arthroscopy (CPT 29881)",
        "payer": "UnitedHealthcare", "policy_type": "HMO", "network": "out", "prior_auth": "no",
        "documentation": 0.6, "amount": 7480.0, "filed": False, "dos": _add_days(today, 12)
    });
    root spawn risk_predictor(claim_id=jid(c3));
    # 4. Denied: botox for chronic migraine, appeal paused at the approval gate
    c4 = _new_claim("Maya Okafor", "CIG 553 019 882", {
        "condition": "Chronic migraine (ICD-10 G43.709)", "procedure": "OnabotulinumtoxinA injection (J0585)",
        "payer": "Cigna", "policy_type": "PPO", "network": "in", "prior_auth": "no",
        "documentation": 0.78, "amount": 4120.0, "filed": True, "dos": _add_days(today, -40)
    });
    root spawn risk_predictor(claim_id=jid(c4));
    a4 = _open_appeal(c4, DenialExtraction(
        member_id="CIG 553 019 882", denial_code="CO-197",
        denial_reason="Precertification/authorization absent", date_of_service=c4.date_of_service,
        denial_date=_add_days(today, -156), appeal_deadline=_add_days(today, 24), confidence=0.97,
        source="Handed off by Risk Predictor (payer 835 remittance)", raw_text="835 ERA: CLP*" + c4.claim_number + "*4*4120*0**12~CAS*CO*197*4120~"
    ));
    root spawn appeal_executor(appeal_id=jid(a4));
    # 5. CGM: appeal already overturned
    c5 = _new_claim("Samuel Brooks", "BCB 330 918 245", {
        "condition": "Type 2 diabetes on insulin", "procedure": "Continuous glucose monitor (E2103)",
        "payer": "BlueCross BlueShield", "policy_type": "EPO", "network": "in", "prior_auth": "pending",
        "documentation": 0.84, "amount": 2380.0, "filed": True, "dos": _add_days(today, -70)
    });
    root spawn risk_predictor(claim_id=jid(c5));
    a5 = _open_appeal(c5, DenialExtraction(
        member_id="BCB 330 918 245", denial_code="CO-50", denial_reason="Not deemed a medical necessity",
        date_of_service=c5.date_of_service, denial_date=_add_days(today, -55),
        appeal_deadline=_add_days(today, 125), confidence=0.95,
        source="Uploaded denial letter photo (OCR)", raw_text="BlueCross BlueShield denial notice. Reason CO-50: not medically necessary."
    ));
    root spawn appeal_executor(appeal_id=jid(a5));
    approve_appeal(jid(a5));
    simulate_payer_response(jid(a5), "overturned");
    # 6. PT: appeal upheld twice -> escalated for human / ombudsman review
    c6 = _new_claim("Daniel Reyes", "AET 771 204 519", {
        "condition": "Knee osteoarthritis", "procedure": "Physical therapy, 12 visits (CPT 97110)",
        "payer": "Aetna", "policy_type": "HMO", "network": "in", "prior_auth": "yes",
        "documentation": 0.66, "amount": 960.0, "filed": True, "dos": _add_days(today, -95)
    });
    root spawn risk_predictor(claim_id=jid(c6));
    a6 = _open_appeal(c6, DenialExtraction(
        member_id="AET 771 204 519", denial_code="CO-119", denial_reason="Benefit maximum for this period has been reached",
        date_of_service=c6.date_of_service, denial_date=_add_days(today, -80),
        appeal_deadline=_add_days(today, 100), confidence=0.91,
        source="Uploaded EOB PDF (OCR)", raw_text="Aetna EOB. CO-119 Benefit maximum reached for physical therapy visits."
    ));
    root spawn appeal_executor(appeal_id=jid(a6), force=True);
    approve_appeal(jid(a6));
    simulate_payer_response(jid(a6), "upheld");
    approve_appeal(jid(a6));
    simulate_payer_response(jid(a6), "upheld");
    return True;
}

impl list_claims() -> list[ClaimView] {
    views = [_claim_view(c) for c in _all_claims()];
    views.sort(key=lambda (v: ClaimView) -> str { return v.created_at; }, reverse=True);
    return views;
}

impl check_claim(
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
) -> str {
    member = "".join([ch for ch in payer.upper() if ch.isalpha()])[:3] + " " + str(random.randint(100, 999)) + " " + str(random.randint(100, 999)) + " " + str(random.randint(100, 999));
    c = _new_claim(patient or "New patient", member, {
        "condition": condition, "procedure": procedure, "payer": payer, "policy_type": policy_type,
        "network": network, "prior_auth": prior_auth, "documentation": documentation,
        "amount": amount, "filed": filed
    });
    root spawn risk_predictor(claim_id=jid(c));
    return jid(c);
}

impl get_risk(claim_id: str) -> RiskResult | None {
    c = _find_claim(claim_id);
    if c is None {
        return None;
    }
    r = _assess(c);
    r.claim = _claim_view(c);
    return r;
}

impl mark_denied(claim_id: str, denial_code: str) -> str {
    c = _find_claim(claim_id);
    if c is None {
        return "";
    }
    ext = DenialExtraction(
        member_id=c.claim_number, denial_code=denial_code or c.predicted_code,
        denial_reason=DENIAL_CODES.get(denial_code or c.predicted_code, ""),
        date_of_service=c.date_of_service, denial_date=_today(), confidence=0.97,
        source="Payer remittance (835) received for filed claim"
    );
    a = _open_appeal(c, ext);
    root spawn appeal_executor(appeal_id=jid(a));
    return jid(a);
}

impl start_appeal(claim_id: str) -> str {
    c = _find_claim(claim_id);
    if c is None {
        return "";
    }
    existing = [c -->[?:AppealCase]];
    if len(existing) > 0 {
        return jid(existing[-1]);
    }
    code = c.predicted_code or "CO-50";
    pname: str = c.patient_name;
    pats = [p for p in [root -->[?:Patient]] if p.name == pname];
    member = pats[0].member_id if len(pats) > 0 else "";
    ext = DenialExtraction(
        member_id=member, denial_code=code, denial_reason=DENIAL_CODES.get(code, ""),
        date_of_service=c.date_of_service, denial_date=_today(), confidence=0.9,
        source="Handed off by Risk Predictor (predicted denial " + code + ")"
    );
    a = _open_appeal(c, ext);
    _audit(c, "Risk predictor", "Handed claim to Appeal Executor", f"Risk score {c.risk_pct}% crossed the 55% threshold.", "Decision gate");
    root spawn appeal_executor(appeal_id=jid(a));
    return jid(a);
}

impl extract_denial_letter(filename: str, mime: str, data_b64: str) -> DenialExtraction {
    if _has_llm() and mime.startswith("image/") and len(data_b64) > 0 {
        try {
            suffix = "." + (mime.split("/")[-1] or "png");
            tmp_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".upload_" + str(random.randint(1000, 9999)) + suffix);
            with open(tmp_path, "wb") as fh {
                fh.write(base64.b64decode(data_b64));
            }
            ext = llm_extract_denial(Image(tmp_path));
            ext.source = f"LLM vision extraction of '{filename}'";
            if not ext.appeal_deadline and ext.denial_date {
                ext.appeal_deadline = _add_days(ext.denial_date, 180);
            }
            return ext;
        } except Exception {}
    }
    return _mock_extraction(filename);
}

impl open_upload_appeal(ext: DenialExtraction) -> str {
    code = ext.denial_code.strip().upper();
    proc = ext.procedure or "Denied service";
    c = _new_claim(ext.patient_name or "Uploaded claim", ext.member_id, {
        "condition": ext.condition or "Not stated", "procedure": proc, "payer": ext.payer or "Unknown payer",
        "policy_type": "PPO", "network": "in", "prior_auth": "no" if code == "CO-197" else "yes",
        "documentation": 0.7, "amount": ext.amount, "filed": True, "status": "Denied",
        "dos": ext.date_of_service or _add_days(_today(), -30)
    });
    if ext.claim_number {
        c.claim_number = ext.claim_number;
    }
    _audit(c, "Patient", "Uploaded denial letter and confirmed extracted fields", "Fields reviewed and corrected by the patient before the agent proceeded.", ext.source);
    a = _open_appeal(c, ext);
    root spawn appeal_executor(appeal_id=jid(a));
    return jid(a);
}

impl get_appeal(appeal_id: str) -> AppealView | None {
    a = _find_appeal(appeal_id);
    if a is None {
        return None;
    }
    if a.stage == "under_review" and not a.escalated and _days_until(a.followup_date) < 0 {
        c = _find_claim(a.claim_id);
        a.escalated = True;
        a.stage = "escalated";
        if c is not None {
            _audit(c, "Tracker", "Follow-up deadline passed with no payer response", "Sent a follow-up to the payer and flagged for human review.", "Follow-up timer");
        }
    }
    return _appeal_view(a);
}

impl save_letter(appeal_id: str, letter: str) -> AppealView | None {
    a = _find_appeal(appeal_id);
    if a is None {
        return None;
    }
    a.cover_letter = letter;
    c = _find_claim(a.claim_id);
    if c is not None {
        _audit(c, "Human reviewer", "Edited the appeal cover letter", f"{len(letter)} characters after edit.", "Manual edit at approval gate");
    }
    return _appeal_view(a);
}

impl override_review(appeal_id: str) -> AppealView | None {
    a = _find_appeal(appeal_id);
    if a is None {
        return None;
    }
    c = _find_claim(a.claim_id);
    if c is not None {
        _audit(c, "Human reviewer", "Confirmed fields and told the agent to proceed", a.review_reason, "Manual review override");
    }
    root spawn appeal_executor(appeal_id=appeal_id, force=True);
    return _appeal_view(a);
}

impl approve_appeal(appeal_id: str) -> AppealView | None {
    a = _find_appeal(appeal_id);
    if a is None {
        return None;
    }
    c = _find_claim(a.claim_id);
    if c is None or a.stage != "awaiting_approval" {
        return _appeal_view(a);
    }
    claim = c as Claim;
    prefix = "".join([ch for ch in claim.payer.upper() if ch.isalpha()])[:3];
    a.confirmation = f"{prefix}-APL-{random.randint(100000, 999999)}";
    a.submitted_at = _now();
    a.followup_date = _add_days(_today(), 30);
    a.stage = "under_review";
    claim.status = "Appeal In Progress";
    prov = _provider_for(claim);
    prov_email = prov.email if prov is not None else "provider";
    prov_fax = prov.fax if prov is not None else "";
    _audit(claim, "Human reviewer", "Approved the appeal packet for dispatch", "One-click approval at the human-in-the-loop gate.", "Approval checkpoint");
    _audit(claim, "Dispatcher", "Requested supporting records from provider", f"Records request emailed to {prov_email} (simulated).", "Records request letter v1");
    _audit(claim, "Dispatcher", f"Submitted appeal to {claim.payer} portal", f"Mock payer portal API accepted the packet. Confirmation {a.confirmation}.", f"Cover letter + {len(a.checklist)} attachments, cites Section {a.clause_section} p.{a.clause_page}");
    _audit(claim, "Dispatcher", "Generated fax-ready PDF", f"Fax cover sheet and packet queued for {claim.payer} appeals fax. Provider fax on file: {prov_fax}.", "Fax packet (simulated)");
    _audit(claim, "Dispatcher", "Notified patient", f"{claim.patient_name} notified that the appeal was filed.", "Patient notification (simulated email)");
    _audit(claim, "Tracker", "Set follow-up timer", f"Will follow up on {a.followup_date} if the payer has not responded.", "Section 12.1: 60-day post-service decision window");
    return _appeal_view(a);
}

impl reject_appeal(appeal_id: str, reason: str) -> AppealView | None {
    a = _find_appeal(appeal_id);
    if a is None {
        return None;
    }
    a.stage = "rejected";
    a.rejected_reason = reason or "Rejected by reviewer";
    c = _find_claim(a.claim_id);
    if c is not None {
        c.status = "Denied";
        _audit(c, "Human reviewer", "Rejected the appeal packet", a.rejected_reason, "Approval checkpoint");
    }
    return _appeal_view(a);
}

impl simulate_payer_response(appeal_id: str, outcome: str) -> AppealView | None {
    a = _find_appeal(appeal_id);
    if a is None {
        return None;
    }
    c = _find_claim(a.claim_id);
    if c is None {
        return _appeal_view(a);
    }
    claim = c as Claim;
    if outcome == "overturned" {
        a.stage = "overturned";
        claim.status = "Overturned";
        _audit(claim, "Tracker", "Payer overturned the denial", f"{claim.payer} reversed the denial. Claim will be reprocessed for payment.", f"Payer portal status for {a.confirmation}");
    } elif outcome == "upheld" {
        a.denial_count += 1;
        claim ++> DenialHistory(code=a.denial_code, reason="Appeal upheld by payer", denied_on=_today(), level=a.denial_count);
        if a.denial_count >= 3 {
            a.stage = "escalated";
            a.escalated = True;
            claim.status = "Upheld";
            _audit(claim, "Tracker", "Appeal denied twice: escalated to a human", "Recommended next step: external review or state insurance ombudsman. Contacting a regulator requires human approval.", f"Denial history: {a.denial_count} adverse decisions");
        } else {
            a.stage = "awaiting_approval";
            claim.status = "Upheld";
            _audit(claim, "Tracker", "Payer upheld the denial", "The agent prepared a second-level appeal with the same citation. Awaiting your approval.", f"Payer portal status for {a.confirmation}");
        }
    } else {
        a.stage = "escalated";
        a.escalated = True;
        _audit(claim, "Tracker", "No payer response by follow-up date", "Automatic follow-up sent. Flagged for human review.", "Follow-up timer");
    }
    return _appeal_view(a);
}

impl list_audit(claim_number: str) -> list[AuditView] {
    out: list[AuditView] = [];
    for c in _all_claims() {
        if claim_number and c.claim_number != claim_number {
            continue;
        }
        for e in [c -->[?:AuditEntry]] {
            out.append(AuditView(id=jid(e), ts=e.ts, claim_number=e.claim_number, actor=e.actor, action=e.action, detail=e.detail, evidence=e.evidence));
        }
    }
    out.sort(key=lambda (v: AuditView) -> str { return v.ts; }, reverse=True);
    return out;
}
