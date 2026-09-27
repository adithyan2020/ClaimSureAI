import from "@jac/runtime" { Link, useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Upload01Icon, FileAddIcon, Camera01Icon, ArrowRight01Icon, Alert01Icon, Task01Icon
}
import from .ui.button { Button }
import from .ui.card { Card, CardContent }
import from .ui.skeleton { Skeleton }
import from .ui.native_select { NativeSelect, NativeSelectOption }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from .Shared { money, StatusChip, DeadlineBadge, PageHeader }
sv import from ..services.claims { ClaimView, seed_demo, list_claims }

glob FILTERS: list[str] = ["All", "At Risk", "Appeal In Progress", "Under Review", "Ready to File", "Manual Review", "Denied", "Overturned", "Upheld"];

def _by_risk(c: ClaimView) -> int {
    return c.risk_pct;
}

def _by_amount(c: ClaimView) -> float {
    return c.amount;
}

def _by_deadline(c: ClaimView) -> int {
    return c.deadline_days if c.deadline_days >= 0 else 9999;
}

def:pub ClaimCard(c: ClaimView) -> JsxElement {
    at_risk = c.status == "At Risk";
    target = f"/appeals/{c.appeal_id}" if c.appeal_id else f"/claims/{c.id}/risk";
    surface = "border-warning-border bg-warning/40" if at_risk else "bg-card";
    return <Link to={target} className="group block">
        <Card className={"h-full shadow-sm transition-all group-hover:-translate-y-0.5 group-hover:shadow-md " + surface}>
            <CardContent className="flex h-full flex-col gap-4">
                <div className="flex items-start justify-between gap-3">
                    <StatusChip status={c.status} />
                    <span className="text-xs text-muted-foreground tabular-nums">{c.claim_number}</span>
                </div>
                <div className="flex flex-col gap-1">
                    <h3 className="text-lg font-semibold leading-snug">{c.condition}</h3>
                    <p className="text-sm text-muted-foreground">{c.procedure}</p>
                </div>
                <div className="grid grid-cols-2 gap-3 text-sm">
                    <div className="flex flex-col gap-0.5">
                        <span className="text-xs text-muted-foreground">{"Payer"}</span>
                        <span className="font-medium">{c.payer}</span>
                    </div>
                    <div className="flex flex-col gap-0.5 text-right">
                        <span className="text-xs text-muted-foreground">{"Claim amount"}</span>
                        <span className="font-medium tabular-nums">{money(c.amount)}</span>
                    </div>
                </div>
                {at_risk and <div className="flex items-start gap-2 rounded-lg border border-warning-border bg-card/70 pt-2.5 pb-2.5 pl-3 pr-3 text-sm text-warning-foreground">
                    <HugeiconsIcon icon={Alert01Icon} strokeWidth={2} className="mt-0.5 size-4 shrink-0" />
                    <span><span className="font-semibold tabular-nums">{str(c.risk_pct) + "% risk. "}</span>{c.risk_reason}</span>
                </div>}
                <div className="mt-auto flex items-center justify-between gap-2 border-t pt-3 text-sm">
                    <span className="text-muted-foreground">{c.patient}</span>
                    {c.deadline_days >= 0 and <DeadlineBadge days={c.deadline_days} />}
                    {c.deadline_days < 0 and <span className="inline-flex items-center gap-1 font-medium text-primary">
                        {"View risk" if not c.appeal_id else "View appeal"}
                        <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4" />
                    </span>}
                </div>
            </CardContent>
        </Card>
    </Link>;
}

def:pub Dashboard() -> JsxElement {
    has claims: list[ClaimView] = [],
        loading: bool = True,
        error: str = "",
        filter_by: str = "All",
        sort_by: str = "risk",
        dragging: bool = False;

    nav = useNavigate();

    async def load -> None {
        loading = True;
        error = "";
        try {
            await seed_demo();
            claims = await list_claims();
        } except Exception as e {
            error = "Could not load your claims. " + str(e);
        }
        loading = False;
    }

    async can with entry {
        await load();
    }

    def on_drop(e: any) {
        e.preventDefault();
        dragging = False;
        nav("/upload");
    }

    def on_drag(e: any) {
        e.preventDefault();
        dragging = True;
    }

    visible = [c for c in claims if filter_by == "All" or c.status == filter_by];
    if sort_by == "risk" {
        visible = sorted(visible, key=_by_risk, reverse=True);
    } elif sort_by == "amount" {
        visible = sorted(visible, key=_by_amount, reverse=True);
    } elif sort_by == "deadline" {
        visible = sorted(visible, key=_by_deadline);
    }
    at_risk = len([c for c in claims if c.status == "At Risk"]);
    appeals = len([c for c in claims if c.status == "Appeal In Progress" or c.status == "Manual Review"]);
    recovered = 0.0;
    for c in claims {
        if c.status == "Overturned" {
            recovered += c.amount;
        }
    }

    return <div className="flex flex-col gap-8">
        <PageHeader title="Your claims" subtitle="Code Shield watches every claim for wrongful-denial risk and builds the appeal for you when one is denied.">
            <Button variant="outline" size="lg" onClick={lambda { nav("/claims/new"); }}>
                <HugeiconsIcon icon={FileAddIcon} strokeWidth={2} />{"Check a claim"}
            </Button>
        </PageHeader>

        <div
            onDragOver={on_drag}
            onDragLeave={lambda { dragging = False; }}
            onDrop={on_drop}
            className={"flex flex-col items-start gap-5 rounded-2xl border-2 border-dashed pt-7 pb-7 pl-7 pr-7 transition-colors md:flex-row md:items-center " + ("border-primary bg-primary/5" if dragging else "border-primary/30 bg-card")}
        >
            <div className="flex size-14 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                <HugeiconsIcon icon={Upload01Icon} strokeWidth={2} className="size-7" />
            </div>
            <div className="flex flex-1 flex-col gap-1">
                <h2 className="text-xl font-semibold">{"Received a denial letter?"}</h2>
                <p className="text-sm text-muted-foreground">{"Drop a photo or PDF of the letter or EOB here. You check what we read, then the agent builds your appeal."}</p>
            </div>
            <div className="flex flex-wrap gap-2">
                <Button size="lg" className="h-11 shadow-sm" onClick={lambda { nav("/upload"); }}>
                    <HugeiconsIcon icon={Upload01Icon} strokeWidth={2} />{"Upload a denial letter"}
                </Button>
                <Button size="lg" variant="outline" className="h-11" onClick={lambda { nav("/upload"); }}>
                    <HugeiconsIcon icon={Camera01Icon} strokeWidth={2} />{"Take a photo"}
                </Button>
            </div>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <Card className="shadow-sm"><CardContent className="flex flex-col gap-1">
                <span className="text-sm text-muted-foreground">{"At risk of wrongful denial"}</span>
                <span className="text-3xl font-semibold tracking-tight tabular-nums">{str(at_risk)}</span>
            </CardContent></Card>
            <Card className="shadow-sm"><CardContent className="flex flex-col gap-1">
                <span className="text-sm text-muted-foreground">{"Appeals being worked"}</span>
                <span className="text-3xl font-semibold tracking-tight tabular-nums">{str(appeals)}</span>
            </CardContent></Card>
            <Card className="shadow-sm"><CardContent className="flex flex-col gap-1">
                <span className="text-sm text-muted-foreground">{"Recovered through appeals"}</span>
                <span className="text-3xl font-semibold tracking-tight tabular-nums text-primary">{money(recovered)}</span>
            </CardContent></Card>
        </div>

        <div className="flex flex-col gap-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-xl font-semibold">{"Active claims"}</h2>
                <div className="flex flex-wrap items-center gap-2">
                    <NativeSelect value={filter_by} onChange={lambda (e: ChangeEvent) { filter_by = e.target.value; }} aria-label="Filter by status">
                        {for f in FILTERS {
                            <NativeSelectOption key={f} value={f}>{"All statuses" if f == "All" else f}</NativeSelectOption>
                        }}
                    </NativeSelect>
                    <NativeSelect value={sort_by} onChange={lambda (e: ChangeEvent) { sort_by = e.target.value; }} aria-label="Sort claims">
                        <NativeSelectOption value="risk">{"Sort: highest risk"}</NativeSelectOption>
                        <NativeSelectOption value="deadline">{"Sort: nearest deadline"}</NativeSelectOption>
                        <NativeSelectOption value="amount">{"Sort: largest amount"}</NativeSelectOption>
                    </NativeSelect>
                </div>
            </div>
            {if loading {
                <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                    <Skeleton className="h-60 rounded-xl" />
                    <Skeleton className="h-60 rounded-xl" />
                    <Skeleton className="h-60 rounded-xl" />
                </div>
                skip;
            }}
            {if error {
                <div className="flex items-center gap-3 text-sm text-destructive">
                    <span>{error}</span>
                    <Button variant="outline" size="sm" onClick={load}>{"Try again"}</Button>
                </div>
                skip;
            }}
            {if len(visible) == 0 {
                <Empty className="border border-dashed pt-12 pb-12">
                    <EmptyHeader>
                        <EmptyMedia variant="icon"><HugeiconsIcon icon={Task01Icon} strokeWidth={2} /></EmptyMedia>
                        <EmptyTitle>{"No claims here"}</EmptyTitle>
                        <EmptyDescription>{"Check a claim before you file it, or upload a denial letter to start an appeal."}</EmptyDescription>
                    </EmptyHeader>
                    <EmptyContent><Button onClick={lambda { nav("/claims/new"); }}>{"Check a claim"}</Button></EmptyContent>
                </Empty>
                skip;
            }}
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                {for c in visible {
                    <ClaimCard key={c.id} c={c} />
                }}
            </div>
        </div>
    </div>;
}
