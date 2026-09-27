import from "@jac/runtime" { Link, useNavigate, useParams }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowRight01Icon, Alert01Icon, CheckmarkCircle02Icon, FileAddIcon, SentIcon }
import from .ui.button { Button }
import from .ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from .ui.skeleton { Skeleton }
import from .ui.badge { Badge }
import from .Shared { money, StatusChip }
sv import from ..services.claims { RiskResult, RiskFactor, Neighbor, get_risk, start_appeal, mark_denied }

def:pub RiskGauge(pct: int, warm: bool) -> JsxElement {
    r = 80.0;
    circ = 3.14159 * r;
    offset = circ * (1.0 - float(pct) / 100.0);
    stroke = "var(--warning-foreground)" if warm else "var(--primary)";
    return <div className="relative flex w-full max-w-xs flex-col items-center">
        <svg viewBox="0 0 200 115" className="w-full">
            <path d="M 20 100 A 80 80 0 0 1 180 100" fill="none" stroke="var(--muted)" strokeWidth="16" strokeLinecap="round" />
            <path d="M 20 100 A 80 80 0 0 1 180 100" fill="none" stroke={stroke} strokeWidth="16" strokeLinecap="round"
                strokeDasharray={str(circ)} strokeDashoffset={str(offset)} style={{"transition": "stroke-dashoffset 900ms ease"}} />
        </svg>
        <div className="absolute bottom-1 flex flex-col items-center">
            <span className="text-5xl font-semibold tracking-tight tabular-nums">{str(pct) + "%"}</span>
            <span className="text-xs text-muted-foreground">{"chance of denial"}</span>
        </div>
    </div>;
}

def:pub FactorRow(f: RiskFactor, rank: int) -> JsxElement {
    return <div className="flex flex-col gap-2 border-b pt-4 pb-4 last:border-b-0">
        <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-2.5">
                <span className="flex size-6 items-center justify-center rounded-full bg-muted text-xs font-semibold tabular-nums">{str(rank)}</span>
                <span className="font-medium">{f.name}</span>
                <Badge variant="outline">{f.value_label}</Badge>
            </div>
            <span className="text-sm font-medium tabular-nums">{str(f.share) + "% of risk"}</span>
        </div>
        <div className="h-2 overflow-hidden rounded-full bg-muted">
            <div className="h-full rounded-full bg-primary transition-all duration-700" style={{"width": str(max(f.share, 2)) + "%"}} />
        </div>
        <p className="text-sm leading-relaxed text-muted-foreground">{f.explanation}</p>
    </div>;
}

def:pub RiskDetail() -> JsxElement {
    has result: RiskResult | None = None,
        loading: bool = True,
        error: str = "",
        busy: bool = False;

    params = useParams();
    claim_id = params["id"];
    nav = useNavigate();

    async def load -> None {
        loading = True;
        try {
            result = await get_risk(claim_id);
            if result is None {
                error = "This claim could not be found.";
            }
        } except Exception as e {
            error = "Could not load the risk assessment. " + str(e);
        }
        loading = False;
    }

    async can with entry {
        await load();
    }

    async def go_appeal -> None {
        busy = True;
        aid = await start_appeal(claim_id);
        busy = False;
        if aid {
            nav(f"/appeals/{aid}");
        }
    }

    async def simulate_denial -> None {
        busy = True;
        code = result.predicted_code if result is not None else "CO-50";
        aid = await mark_denied(claim_id, code);
        busy = False;
        if aid {
            nav(f"/appeals/{aid}");
        }
    }

    if loading {
        return <div className="flex flex-col gap-6">
            <Skeleton className="h-10 w-72" />
            <div className="grid gap-6 lg:grid-cols-3"><Skeleton className="h-80 rounded-xl" /><Skeleton className="h-80 rounded-xl lg:col-span-2" /></div>
        </div>;
    }
    if result is None {
        return <div className="flex flex-col items-start gap-3">
            <p className="text-sm text-destructive">{error}</p>
            <Button variant="outline" onClick={load}>{"Try again"}</Button>
        </div>;
    }
    r = result as RiskResult;
    c = r.claim;
    warm = r.risk_pct >= 55;
    return <div className="flex flex-col gap-8">
        <Link to="/" className="inline-flex w-fit items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
            <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4 rotate-180" />{"All claims"}
        </Link>
        <div className="flex flex-wrap items-end justify-between gap-4">
            <div className="flex flex-col gap-2">
                <div className="flex flex-wrap items-center gap-2">
                    <StatusChip status={c.status} />
                    <span className="text-sm text-muted-foreground tabular-nums">{c.claim_number}</span>
                </div>
                <h1 className="text-3xl font-semibold tracking-tight">{c.procedure}</h1>
                <p className="text-sm text-muted-foreground">{c.patient + " · " + c.condition + " · " + c.payer + " " + c.policy_type + " · " + money(c.amount)}</p>
            </div>
        </div>

        <div className="grid gap-6 lg:grid-cols-5">
            <Card className={"shadow-sm lg:col-span-2 " + ("border-warning-border bg-warning/40" if warm else "")}>
                <CardContent className="flex flex-col items-center gap-5 pt-2 text-center">
                    <div className="flex items-center gap-2 text-sm font-medium">
                        <HugeiconsIcon icon={Alert01Icon if warm else CheckmarkCircle02Icon} strokeWidth={2} className={"size-4 " + ("text-warning-foreground" if warm else "text-primary")} />
                        <span>{"Risk Predictor verdict"}</span>
                    </div>
                    <h2 className="text-2xl font-semibold leading-snug">{r.verdict}</h2>
                    <RiskGauge pct={r.risk_pct} warm={warm} />
                    <div className="grid w-full grid-cols-3 gap-2 border-t pt-4 text-sm">
                        <div className="flex flex-col"><span className="text-xs text-muted-foreground">{"Likely code"}</span><span className="font-semibold tabular-nums">{r.predicted_code}</span></div>
                        <div className="flex flex-col"><span className="text-xs text-muted-foreground">{"Overturn rate"}</span><span className="font-semibold tabular-nums">{str(r.wrongful_pct) + "%"}</span></div>
                        <div className="flex flex-col"><span className="text-xs text-muted-foreground">{"Confidence"}</span><span className="font-semibold tabular-nums">{str(r.confidence) + "%"}</span></div>
                    </div>
                    <p className="text-sm leading-relaxed text-muted-foreground">{r.headline}</p>
                </CardContent>
            </Card>

            <Card className="shadow-sm lg:col-span-3">
                <CardHeader>
                    <CardTitle className="font-serif text-lg">{"What is driving the risk"}</CardTitle>
                    <CardDescription>{"Ranked by how much each factor raises the denial rate above the " + "historical baseline."}</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col">
                    {for (i, f) in enumerate(r.factors) {
                        <FactorRow key={f.name} f={f} rank={i + 1} />
                    }}
                </CardContent>
            </Card>
        </div>

        <Card className="border-primary/30 shadow-sm">
            <CardContent className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
                <div className="flex flex-col gap-1">
                    <span className="text-xs font-medium text-primary">{"Recommended action"}</span>
                    <p className="max-w-2xl text-base">{r.recommended_action}</p>
                </div>
                <div className="flex flex-wrap gap-2">
                    {r.gate == "prevent" and <Button size="lg" className="h-11 shadow-sm" onClick={lambda { nav("/claims/new"); }}>
                        <HugeiconsIcon icon={FileAddIcon} strokeWidth={2} />{"Prevent this: fix before filing"}
                    </Button>}
                    {(r.gate == "appeal_prep" or r.gate == "denied") and <Button size="lg" className="h-11 shadow-sm" disabled={busy} onClick={go_appeal}>
                        <HugeiconsIcon icon={SentIcon} strokeWidth={2} />{"Already filed: start appeal prep" if r.gate == "appeal_prep" else "Open the appeal"}
                    </Button>}
                    {c.filed and not c.appeal_id and <Button size="lg" variant="outline" className="h-11" disabled={busy} onClick={simulate_denial}>
                        {"Simulate payer denial"}
                    </Button>}
                </div>
            </CardContent>
        </Card>

        <Card className="shadow-sm">
            <CardHeader>
                <CardTitle className="font-serif text-lg">{"Most similar historical claims"}</CardTitle>
                <CardDescription>{"The evidence behind this score. Weighted by similarity, not just counted."}</CardDescription>
            </CardHeader>
            <CardContent>
                <div className="overflow-x-auto rounded-lg border">
                    <table className="w-full text-sm">
                        <thead className="bg-muted/50 text-left text-xs text-muted-foreground">
                            <tr>
                                <th className="pt-2.5 pb-2.5 pl-3 pr-3 font-medium">{"Reference"}</th>
                                <th className="pt-2.5 pb-2.5 pl-3 pr-3 font-medium">{"Procedure"}</th>
                                <th className="pt-2.5 pb-2.5 pl-3 pr-3 font-medium">{"Payer"}</th>
                                <th className="pt-2.5 pb-2.5 pl-3 pr-3 font-medium">{"Network / auth"}</th>
                                <th className="pt-2.5 pb-2.5 pl-3 pr-3 text-right font-medium">{"Similarity"}</th>
                                <th className="pt-2.5 pb-2.5 pl-3 pr-3 font-medium">{"Outcome"}</th>
                            </tr>
                        </thead>
                        <tbody>
                            {for n in r.neighbors {
                                <tr key={n.ref} className="border-t">
                                    <td className="pt-2.5 pb-2.5 pl-3 pr-3 font-medium tabular-nums">{n.ref}</td>
                                    <td className="pt-2.5 pb-2.5 pl-3 pr-3">{n.procedure}</td>
                                    <td className="pt-2.5 pb-2.5 pl-3 pr-3">{n.payer}</td>
                                    <td className="pt-2.5 pb-2.5 pl-3 pr-3 text-muted-foreground">{("Out" if n.network == "out" else "In") + " / auth " + n.prior_auth}</td>
                                    <td className="pt-2.5 pb-2.5 pl-3 pr-3 text-right tabular-nums">{str(n.similarity) + "%"}</td>
                                    <td className="pt-2.5 pb-2.5 pl-3 pr-3">{("Denied " + n.code + (", overturned" if n.overturned else ", upheld")) if n.denied else "Paid"}</td>
                                </tr>
                            }}
                        </tbody>
                    </table>
                </div>
            </CardContent>
        </Card>
    </div>;
}
