import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Clock01Icon, Alert01Icon, CheckmarkCircle02Icon, Cancel01Icon, Loading03Icon,
    Search01Icon, ShieldUserIcon, UserIcon, Calendar03Icon
}

cl def:pub money(amount: float) -> str {
    text = f"{amount:.2f}";
    parts = text.split(".");
    whole = parts[0];
    sign = "";
    if whole.startswith("-") {
        sign = "-";
        whole = whole[1:];
    }
    groups: list[str] = [];
    while len(whole) > 3 {
        groups = [whole[len(whole) - 3:]] + groups;
        whole = whole[:len(whole) - 3];
    }
    return sign + "$" + ",".join([whole] + groups) + "." + parts[1];
}

def:pub BrandMark(inverted: bool = False) -> JsxElement {
    tile = "bg-primary-foreground/15 text-primary-foreground ring-1 ring-primary-foreground/20" if inverted else "bg-primary text-primary-foreground shadow-sm";
    return <div className="flex items-center gap-2.5">
        <div className={"flex size-9 items-center justify-center rounded-lg " + tile}>
            <HugeiconsIcon icon={ShieldUserIcon} strokeWidth={2} className="size-5" />
        </div>
        <div className="flex flex-col leading-tight">
            <span className="font-serif text-lg font-semibold tracking-tight">{"Code Shield"}</span>
            <span className="text-[11px] text-muted-foreground">{"Claims advocate agent"}</span>
        </div>
    </div>;
}

def:pub StatusChip(status: str) -> JsxElement {
    cls = "border-border bg-muted text-foreground";
    icon = Clock01Icon;
    if status == "At Risk" {
        cls = "border-warning-border bg-warning text-warning-foreground";
        icon = Alert01Icon;
    } elif status == "Appeal In Progress" {
        cls = "border-primary/30 bg-primary/10 text-primary";
        icon = Loading03Icon;
    } elif status == "Overturned" {
        cls = "border-emerald-300 bg-emerald-50 text-emerald-800 dark:border-emerald-800 dark:bg-emerald-950 dark:text-emerald-300";
        icon = CheckmarkCircle02Icon;
    } elif status == "Upheld" or status == "Denied" {
        cls = "border-rose-200 bg-rose-50 text-rose-800 dark:border-rose-900 dark:bg-rose-950 dark:text-rose-300";
        icon = Cancel01Icon;
    } elif status == "Manual Review" {
        cls = "border-warning-border bg-warning text-warning-foreground";
        icon = UserIcon;
    } elif status == "Ready to File" {
        cls = "border-border bg-card text-foreground";
        icon = CheckmarkCircle02Icon;
    } else {
        icon = Search01Icon;
    }
    return <span className={"inline-flex items-center gap-1.5 rounded-full border pt-1 pb-1 pl-2.5 pr-2.5 text-xs font-medium " + cls}>
        <HugeiconsIcon icon={icon} strokeWidth={2} className="size-3.5" />
        {status}
    </span>;
}

def:pub DeadlineBadge(days: int, large: bool = False) -> JsxElement {
    cls = "border-border bg-card text-foreground";
    label = str(days) + " days left to appeal";
    if days == 1 {
        label = "1 day left to appeal";
    }
    if days < 0 {
        label = "Appeal window closed";
        cls = "border-rose-200 bg-rose-50 text-rose-800 dark:border-rose-900 dark:bg-rose-950 dark:text-rose-300";
    } elif days <= 30 {
        cls = "border-warning-border bg-warning text-warning-foreground";
    }
    size = "pt-2 pb-2 pl-3.5 pr-3.5 text-sm" if large else "pt-1 pb-1 pl-2.5 pr-2.5 text-xs";
    return <span className={"inline-flex items-center gap-1.5 rounded-full border font-medium tabular-nums " + size + " " + cls}>
        <HugeiconsIcon icon={Calendar03Icon} strokeWidth={2} className="size-3.5" />
        {label}
    </span>;
}

def:pub PageHeader(title: str, subtitle: str, children: any = None) -> JsxElement {
    return <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="flex flex-col gap-1.5">
            <h1 className="text-3xl font-semibold tracking-tight">{title}</h1>
            <p className="max-w-2xl text-sm text-muted-foreground">{subtitle}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">{children}</div>
    </div>;
}
