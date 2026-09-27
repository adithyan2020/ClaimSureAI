import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Task01Icon, BookOpen01Icon }
import from .ui.button { Button }
import from .ui.card { Card, CardContent }
import from .ui.input { Input }
import from .ui.skeleton { Skeleton }
import from .ui.badge { Badge }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription }
import from .Shared { PageHeader }
sv import from ..services.claims { AuditView, list_audit }

def:pub AuditLog() -> JsxElement {
    has entries: list[AuditView] = [],
        loading: bool = True,
        error: str = "",
        query: str = "";

    async def load -> None {
        loading = True;
        error = "";
        try {
            entries = await list_audit("");
        } except Exception as e {
            error = "Could not load the audit log. " + str(e);
        }
        loading = False;
    }

    async can with entry {
        await load();
    }

    q = query.lower().strip();
    rows = [e for e in entries if not q or q in (e.claim_number + " " + e.action + " " + e.actor + " " + e.detail).lower()];

    return <div className="flex flex-col gap-8">
        <PageHeader title="Audit log" subtitle="Every automated decision and action, newest first, with the evidence it was based on. Nothing is hidden." />
        <Card className="shadow-sm">
            <CardContent className="flex flex-col gap-5">
                <div className="flex flex-wrap items-center justify-between gap-3">
                    <Input className="h-10 w-full max-w-sm" placeholder="Filter by claim number, action or actor" value={query} onChange={lambda (e: ChangeEvent) { query = e.target.value; }} />
                    <span className="text-sm text-muted-foreground tabular-nums">{str(len(rows)) + (" entry" if len(rows) == 1 else " entries")}</span>
                </div>
                {if loading {
                    <div className="flex flex-col gap-3"><Skeleton className="h-20" /><Skeleton className="h-20" /><Skeleton className="h-20" /></div>
                    skip;
                }}
                {if error {
                    <div className="flex items-center gap-3 text-sm text-destructive"><span>{error}</span><Button size="sm" variant="outline" onClick={load}>{"Try again"}</Button></div>
                    skip;
                }}
                {if len(rows) == 0 {
                    <Empty className="border border-dashed pt-12 pb-12">
                        <EmptyHeader>
                            <EmptyMedia variant="icon"><HugeiconsIcon icon={Task01Icon} strokeWidth={2} /></EmptyMedia>
                            <EmptyTitle>{"No actions logged yet"}</EmptyTitle>
                            <EmptyDescription>{"When the agent scores a claim or works an appeal, every step shows up here."}</EmptyDescription>
                        </EmptyHeader>
                    </Empty>
                    skip;
                }}
                <ol className="flex flex-col">
                    {for e in rows {
                        <li key={e.id} className="grid gap-2 border-b pt-4 pb-4 last:border-b-0 md:grid-cols-[11rem_1fr]">
                            <div className="flex flex-col gap-1">
                                <span className="text-sm font-medium tabular-nums">{e.ts[:10]}</span>
                                <span className="text-xs text-muted-foreground tabular-nums">{e.ts[11:19]}</span>
                            </div>
                            <div className="flex flex-col gap-1.5">
                                <div className="flex flex-wrap items-center gap-2">
                                    <span className="font-medium">{e.action}</span>
                                    <Badge variant="outline" className="tabular-nums">{e.claim_number}</Badge>
                                    <Badge variant="secondary">{e.actor}</Badge>
                                </div>
                                <p className="text-sm text-muted-foreground">{e.detail}</p>
                                {e.evidence and <p className="flex items-start gap-1.5 text-xs text-muted-foreground">
                                    <HugeiconsIcon icon={BookOpen01Icon} strokeWidth={2} className="mt-0.5 size-3.5 shrink-0 text-primary" />
                                    <span><span className="font-medium text-foreground">{"Source: "}</span>{e.evidence}</span>
                                </p>}
                            </div>
                        </li>
                    }}
                </ol>
            </CardContent>
        </Card>
    </div>;
}
