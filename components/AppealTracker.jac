import from "@jac/runtime" { Link, useParams }
import from "sonner" { toast }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    ArrowRight01Icon, ArrowDown01Icon, CheckmarkCircle02Icon, Clock01Icon, UserIcon,
    Alert01Icon, SentIcon, PencilEdit01Icon, Cancel01Icon, BookOpen01Icon, File01Icon, Mail01Icon
}
import from .ui.button { Button }
import from .ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from .ui.skeleton { Skeleton }
import from .ui.textarea { Textarea }
import from .ui.badge { Badge }
import from .ui.alert { Alert, AlertTitle, AlertDescription }
import from .Shared { money, StatusChip, DeadlineBadge }
sv import from ..services.claims {
    AppealView, get_appeal, save_letter, override_review, approve_appeal,
    reject_appeal, simulate_payer_response
}

glob STEP_ORDER: list[str] = ["extracted", "clause", "drafted", "approval", "submitted", "tracking"];

def _progress(stage: str) -> int {
    if stage in ["extracted", "manual_review"] {
        return 0;
    }
    if stage in ["clause_matched", "classified"] {
        return 1;
    }
    if stage == "drafted" {
        return 2;
    }
    if stage in ["awaiting_approval", "rejected"] {
        return 3;
    }
    if stage == "under_review" {
        return 5;
    }
    return 5;
}

def:pub StepShell(
    index: int,
    title: str,
    summary: str,
    state: str,
    open: bool,
    onToggle: Callable[[], None],
    children: any = None
) -> JsxElement {
    dot = "border-border bg-card text-muted-foreground";
    icon = Clock01Icon;
    if state == "done" {
        dot = "border-primary bg-primary text-primary-foreground";
        icon = CheckmarkCircle02Icon;
    } elif state == "gate" {
        dot = "border-warning-foreground bg-warning text-warning-foreground";
        icon = UserIcon;
    } elif state == "active" {
        dot = "border-primary bg-primary/10 text-primary";
        icon = Clock01Icon;
    } elif state == "alert" {
        dot = "border-rose-300 bg-rose-50 text-rose-700 dark:bg-rose-950 dark:text-rose-300";
        icon = Alert01Icon;
    }
    return <li className="relative flex gap-4 pb-8 last:pb-0">
        <div className="flex flex-col items-center">
            <div className={"z-10 flex size-10 shrink-0 items-center justify-center rounded-full border-2 " + dot}>
                <HugeiconsIcon icon={icon} strokeWidth={2} className="size-5" />
            </div>
            <div className="w-px flex-1 bg-border" />
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-3 pt-1.5">
            <button type="button" onClick={lambda { onToggle(); }} disabled={state == "todo"} className="flex w-full items-start justify-between gap-3 text-left disabled:cursor-default">
                <div className="flex flex-col gap-0.5">
                    <span className="text-xs text-muted-foreground tabular-nums">{"Step " + str(index)}</span>
                    <span className={"text-base font-semibold " + ("text-muted-foreground" if state == "todo" else "")}>{title}</span>
                    <span className="text-sm text-muted-foreground">{summary}</span>
                </div>
                {state != "todo" and <HugeiconsIcon icon={ArrowDown01Icon} strokeWidth={2} className={"mt-5 size-4 shrink-0 text-muted-foreground transition-transform " + ("rotate-180" if open else "")} />}
            </button>
            {open and state != "todo" and <div className="animate-in fade-in slide-in-from-top-1 duration-300">{children}</div>}
        </div>
    </li>;
}

def:pub DocBlock(text: str) -> JsxElement {
    return <pre className="max-h-96 overflow-auto whitespace-pre-wrap rounded-lg border bg-card pt-4 pb-4 pl-5 pr-5 font-serif text-sm leading-relaxed">{text}</pre>;
}

def:pub AppealTracker() -> JsxElement {
    has a: AppealView | None = None,
        loading: bool = True,
        error: str = "",
        opened: list[str] = [],
        doc_tab: str = "letter",
        editing: bool = False,
        draft: str = "",
        rejecting: bool = False,
        reject_reason: str = "",
        busy: bool = False;

    params = useParams();
    appeal_id: str = params["id"] or "";

    async def load -> None {
        try {
            res = await get_appeal(appeal_id);
            a = res;
            if res is None {
                error = "This appeal could not be found.";
            }
        } except Exception as e {
            error = "Could not load the appeal. " + str(e);
        }
        loading = False;
    }

    async can with entry {
        await load();
    }

    def toggle(key: str) {
        if key in opened {
            opened = [k for k in opened if k != key];
        } else {
            opened = opened + [key];
        }
    }

    async def approve -> None {
        busy = True;
        a = await approve_appeal(appeal_id);
        busy = False;
        toast.success("Appeal approved and submitted to the payer");
    }

    async def do_reject -> None {
        busy = True;
        a = await reject_appeal(appeal_id, reject_reason);
        rejecting = False;
        busy = False;
        toast("Appeal packet rejected. Nothing was sent.");
    }

    async def save_edit -> None {
        busy = True;
        a = await save_letter(appeal_id, draft);
        editing = False;
        busy = False;
        toast.success("Letter updated");
    }

    async def proceed -> None {
        busy = True;
        await override_review(appeal_id);
        a = await get_appeal(appeal_id);
        busy = False;
    }

    async def respond(outcome: str) -> None {
        busy = True;
        a = await simulate_payer_response(appeal_id, outcome);
        busy = False;
    }

    if loading {
        return <div className="flex flex-col gap-6"><Skeleton className="h-10 w-80" /><Skeleton className="h-96 rounded-xl" /></div>;
    }
    if a is None {
        return <div className="flex flex-col items-start gap-3">
            <p className="text-sm text-destructive">{error}</p>
            <Link to="/" className="text-sm font-medium text-primary">{"Back to claims"}</Link>
        </div>;
    }
    ap = a as AppealView;
    prog = _progress(ap.stage);
    gate_open = ap.stage == "awaiting_approval";

    def st(i: int) -> str {
        if ap.stage == "manual_review" and i == 0 {
            return "alert";
        }
        if i == 3 and gate_open {
            return "gate";
        }
        if i == 3 and ap.stage == "rejected" {
            return "alert";
        }
        if i == 5 {
            if ap.escalated {
                return "alert";
            }
            if ap.stage == "overturned" {
                return "done";
            }
            if ap.stage == "under_review" {
                return "active";
            }
            return "todo";
        }
        if i < prog {
            return "done";
        }
        return "todo";
    }

    def is_open(key: str) -> bool {
        return key in opened;
    }

    header_status = "Manual Review" if ap.stage == "manual_review" else ("Overturned" if ap.stage == "overturned" else ("Upheld" if ap.escalated or ap.denial_count > 1 else "Appeal In Progress"));
    outcome_text = "Tracking payer response";
    if ap.stage == "overturned" {
        outcome_text = "Denial overturned. The claim will be reprocessed for payment.";
    } elif ap.escalated {
        outcome_text = "Escalated to a human reviewer";
    } elif ap.stage == "under_review" {
        outcome_text = "Under review by " + ap.payer + ". Follow-up set for " + ap.followup_date + ".";
    }

    return <div className="flex flex-col gap-8">
        <Link to="/" className="inline-flex w-fit items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
            <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4 rotate-180" />{"All claims"}
        </Link>
        <div className="flex flex-wrap items-end justify-between gap-4">
            <div className="flex flex-col gap-2">
                <div className="flex flex-wrap items-center gap-2">
                    <StatusChip status={header_status} />
                    <span className="text-sm text-muted-foreground tabular-nums">{ap.claim_number}</span>
                    <Badge variant="outline" className="tabular-nums">{ap.denial_code}</Badge>
                </div>
                <h1 className="text-3xl font-semibold tracking-tight">{"Appeal for " + ap.procedure}</h1>
                <p className="text-sm text-muted-foreground">{ap.patient + " · " + ap.payer + " · " + money(ap.amount) + " denied on " + ap.denial_date}</p>
            </div>
            <div className="flex flex-col items-end gap-1">
                {ap.stage != "overturned" and <DeadlineBadge days={ap.days_left} large={True} />}
                <span className="text-xs text-muted-foreground tabular-nums">{"Filing window closes " + ap.deadline}</span>
            </div>
        </div>

        {ap.stage == "manual_review" and <Alert className="border-warning-border bg-warning text-warning-foreground">
            <HugeiconsIcon icon={UserIcon} strokeWidth={2} />
            <AlertTitle>{"The agent paused for a person to check"}</AlertTitle>
            <AlertDescription>
                <p>{ap.review_reason}</p>
                <div className="mt-3"><Button size="sm" disabled={busy} onClick={proceed}>{"I have checked it: continue"}</Button></div>
            </AlertDescription>
        </Alert>}

        <div className="grid gap-6 xl:grid-cols-5">
            <Card className="shadow-sm xl:col-span-3">
                <CardHeader>
                    <CardTitle className="font-serif text-lg">{"What the agent has done"}</CardTitle>
                    <CardDescription>{"Open any completed step to see exactly what was used and produced."}</CardDescription>
                </CardHeader>
                <CardContent>
                    <ol className="flex flex-col">
                        <StepShell index={1} title="Extracted claim details" summary={ap.extraction_source + " · " + str(int(ap.ocr_confidence * 100)) + "% confidence"} state={st(0) if ap.stage == "manual_review" else "done"} open={is_open("s1")} onToggle={lambda { toggle("s1"); }}>
                            <div className="flex flex-col gap-3">
                                <div className="grid gap-2 rounded-lg border bg-muted/30 pt-3 pb-3 pl-4 pr-4 text-sm sm:grid-cols-2">
                                    <span><span className="text-muted-foreground">{"Member ID: "}</span>{ap.member_id}</span>
                                    <span><span className="text-muted-foreground">{"Denial code: "}</span>{ap.denial_code}</span>
                                    <span><span className="text-muted-foreground">{"Reason: "}</span>{ap.denial_reason}</span>
                                    <span><span className="text-muted-foreground">{"Date of service: "}</span>{ap.date_of_service}</span>
                                </div>
                                {ap.raw_text and <pre className="whitespace-pre-wrap rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 font-mono text-xs leading-relaxed">{ap.raw_text}</pre>}
                            </div>
                        </StepShell>
                        <StepShell index={2} title="Matched policy clause" summary={("Section " + ap.clause_section + ", page " + str(ap.clause_page) + " · " + str(ap.clause_score) + "% relevance") if ap.clause_section else "Waiting"} state={st(1)} open={is_open("s2")} onToggle={lambda { toggle("s2"); }}>
                            <div className="flex flex-col gap-3">
                                <blockquote className="rounded-lg border-l-4 border-primary bg-primary/5 pt-3 pb-3 pl-4 pr-4 font-serif text-sm leading-relaxed">
                                    <p className="mb-1 font-sans text-xs font-semibold text-primary">{"Section " + ap.clause_section + " · " + ap.clause_title + " · page " + str(ap.clause_page)}</p>
                                    {"\u201c" + ap.clause_text + "\u201d"}
                                </blockquote>
                                <p className="text-sm text-muted-foreground"><span className="font-medium text-foreground">{"Classification: " + ap.classification + " (" + str(ap.wrongful_pct) + "% likely wrongful). "}</span>{ap.classification_why}</p>
                            </div>
                        </StepShell>
                        <StepShell index={3} title="Drafted appeal packet" summary={(str(len(ap.checklist)) + " documents · " + ap.packet_source) if ap.cover_letter else "Waiting"} state={st(2)} open={is_open("s3")} onToggle={lambda { toggle("s3"); }}>
                            <ul className="flex flex-col gap-2 text-sm">
                                {for item in ap.checklist {
                                    <li key={item} className="flex items-start gap-2">
                                        <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2} className="mt-0.5 size-4 shrink-0 text-primary" />{item}
                                    </li>
                                }}
                            </ul>
                        </StepShell>
                        <StepShell index={4} title="Awaiting your approval" summary={"Nothing is sent until you approve" if gate_open else ("Rejected: " + ap.rejected_reason if ap.stage == "rejected" else ("Approved" if prog > 3 else "Waiting"))} state={st(3)} open={True} onToggle={lambda { toggle("s4"); }}>
                            {gate_open and <p className="rounded-lg border border-warning-border bg-warning pt-3 pb-3 pl-4 pr-4 text-sm text-warning-foreground">{"Review the documents on the right, then approve, edit or reject. This is the only way anything leaves Code Shield."}</p>}
                            {not gate_open and prog > 3 and <p className="text-sm text-muted-foreground">{"Approved by you. Dispatched " + ap.submitted_at[:16].replace("T", " ") + "."}</p>}
                        </StepShell>
                        <StepShell index={5} title="Submitted to payer" summary={("Confirmation " + ap.confirmation) if ap.confirmation else "Waiting"} state={st(4)} open={is_open("s5")} onToggle={lambda { toggle("s5"); }}>
                            <div className="flex flex-col gap-2 text-sm">
                                <span className="flex items-center gap-2"><HugeiconsIcon icon={SentIcon} strokeWidth={2} className="size-4 text-primary" />{"Submitted to " + ap.payer + " appeals portal (confirmation " + ap.confirmation + ")"}</span>
                                <span className="flex items-center gap-2"><HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-4 text-primary" />{"Fax-ready PDF packet generated"}</span>
                                <span className="flex items-center gap-2"><HugeiconsIcon icon={Mail01Icon} strokeWidth={2} className="size-4 text-primary" />{"Records requested from " + ap.provider_name + " (" + ap.provider_email + ")"}</span>
                                <span className="flex items-center gap-2"><HugeiconsIcon icon={UserIcon} strokeWidth={2} className="size-4 text-primary" />{"Patient notified"}</span>
                            </div>
                        </StepShell>
                        <StepShell index={6} title="Tracking response" summary={outcome_text} state={st(5)} open={True} onToggle={lambda { toggle("s6"); }}>
                            {ap.stage == "under_review" and <div className="flex flex-col gap-3">
                                <p className="text-sm text-muted-foreground">{"Demo controls: simulate what the payer portal reports back."}</p>
                                <div className="flex flex-wrap gap-2">
                                    <Button size="sm" variant="outline" disabled={busy} onClick={lambda { respond("overturned"); }}>{"Payer overturns"}</Button>
                                    <Button size="sm" variant="outline" disabled={busy} onClick={lambda { respond("upheld"); }}>{"Payer upholds"}</Button>
                                    <Button size="sm" variant="outline" disabled={busy} onClick={lambda { respond("timeout"); }}>{"No response by deadline"}</Button>
                                </div>
                            </div>}
                            {ap.escalated and <p className="rounded-lg border border-rose-200 bg-rose-50 pt-3 pb-3 pl-4 pr-4 text-sm text-rose-800 dark:border-rose-900 dark:bg-rose-950 dark:text-rose-300">{"Denied " + str(ap.denial_count) + " times or no response. Recommended next step: external review or your state insurance ombudsman. Contacting a regulator requires your explicit approval."}</p>}
                        </StepShell>
                    </ol>
                </CardContent>
            </Card>

            <Card className={"shadow-sm xl:col-span-2 " + ("ring-2 ring-warning-border" if gate_open else "")}>
                <CardHeader>
                    <CardTitle className="font-serif text-lg">{"Appeal packet"}</CardTitle>
                    <CardDescription>{"Every clause is quoted from your plan document with its page reference."}</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    {not ap.cover_letter and <p className="rounded-lg border border-dashed pt-10 pb-10 text-center text-sm text-muted-foreground">{"The packet appears here once the agent drafts it."}</p>}
                    {ap.cover_letter and <div className="flex flex-col gap-4">
                        <div className="flex flex-wrap gap-1 rounded-lg bg-muted pt-1 pb-1 pl-1 pr-1">
                            {for tab in [["letter", "Cover letter"], ["clause", "Policy excerpt"], ["records", "Records request"], ["necessity", "Medical necessity"]] {
                                <button key={tab[0]} type="button" onClick={lambda { doc_tab = tab[0]; }} className={"flex-1 rounded-md pt-1.5 pb-1.5 pl-2 pr-2 text-xs font-medium transition-colors " + ("bg-card shadow-sm" if doc_tab == tab[0] else "text-muted-foreground hover:text-foreground")}>{tab[1]}</button>
                            }}
                        </div>
                        {doc_tab == "letter" and not editing and <DocBlock text={ap.cover_letter} />}
                        {doc_tab == "letter" and editing and <Textarea className="min-h-96 font-serif text-sm leading-relaxed" value={draft} onChange={lambda (e: ChangeEvent) { draft = e.target.value; }} />}
                        {doc_tab == "clause" and <div className="flex flex-col gap-2">
                            <span className="inline-flex items-center gap-2 text-xs font-medium text-primary"><HugeiconsIcon icon={BookOpen01Icon} strokeWidth={2} className="size-4" />{"Summary Plan Description · Section " + ap.clause_section + " · page " + str(ap.clause_page)}</span>
                            <DocBlock text={ap.clause_title + "\n\n" + ap.clause_text} />
                        </div>}
                        {doc_tab == "records" and <DocBlock text={ap.records_request} />}
                        {doc_tab == "necessity" and <DocBlock text={ap.medical_necessity} />}

                        {gate_open and not editing and not rejecting and <div className="flex flex-col gap-2 border-t pt-4">
                            <Button size="lg" className="h-12 text-base shadow-sm" disabled={busy} onClick={approve}>
                                <HugeiconsIcon icon={SentIcon} strokeWidth={2} />{"Approve & Send"}
                            </Button>
                            <div className="grid grid-cols-2 gap-2">
                                <Button variant="outline" className="h-11" onClick={lambda { draft = ap.cover_letter; doc_tab = "letter"; editing = True; }}>
                                    <HugeiconsIcon icon={PencilEdit01Icon} strokeWidth={2} />{"Edit"}
                                </Button>
                                <Button variant="outline" className="h-11" onClick={lambda { rejecting = True; }}>
                                    <HugeiconsIcon icon={Cancel01Icon} strokeWidth={2} />{"Reject"}
                                </Button>
                            </div>
                        </div>}
                        {editing and <div className="flex justify-end gap-2 border-t pt-4">
                            <Button variant="outline" onClick={lambda { editing = False; }}>{"Cancel"}</Button>
                            <Button disabled={busy} onClick={save_edit}>{"Save letter"}</Button>
                        </div>}
                        {rejecting and <div className="flex flex-col gap-2 border-t pt-4">
                            <Textarea placeholder="Why are you rejecting this packet? For example: wrong date of service." value={reject_reason} onChange={lambda (e: ChangeEvent) { reject_reason = e.target.value; }} />
                            <div className="flex justify-end gap-2">
                                <Button variant="outline" onClick={lambda { rejecting = False; }}>{"Cancel"}</Button>
                                <Button variant="destructive" disabled={busy} onClick={do_reject}>{"Reject packet"}</Button>
                            </div>
                        </div>}
                    </div>}
                    <Link to="/audit" className="text-sm font-medium text-primary hover:underline">{"See the full audit trail"}</Link>
                </CardContent>
            </Card>
        </div>
    </div>;
}
