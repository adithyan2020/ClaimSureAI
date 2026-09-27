import from "@jac/runtime" { Link, Outlet, useLocation }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    DashboardSquare01Icon, FileAddIcon, Upload01Icon, Task01Icon, Shield01Icon
}
import from .ui.sidebar {
    SidebarProvider, Sidebar, SidebarHeader, SidebarContent, SidebarFooter,
    SidebarGroup, SidebarGroupLabel, SidebarMenu, SidebarMenuItem,
    SidebarMenuButton, SidebarInset, SidebarTrigger
}
import from .ui.separator { Separator }
import from .Shared { BrandMark }

glob NAV: list[dict] = [
    {"label": "Claims", "to": "/", "icon": DashboardSquare01Icon},
    {"label": "Check a claim", "to": "/claims/new", "icon": FileAddIcon},
    {"label": "Upload denial letter", "to": "/upload", "icon": Upload01Icon},
    {"label": "Audit log", "to": "/audit", "icon": Task01Icon}
];

def _section_title(path: str) -> str {
    if path.startswith("/claims/new") {
        return "Risk Predictor / New claim check";
    }
    if path.startswith("/claims/") {
        return "Risk Predictor";
    }
    if path.startswith("/appeals/") {
        return "Appeal Executor";
    }
    if path.startswith("/upload") {
        return "Appeal Executor / Upload";
    }
    if path.startswith("/audit") {
        return "Audit log";
    }
    return "Claims";
}

def:pub AppLayout() -> JsxElement {
    path = useLocation().pathname;
    return <SidebarProvider>
        <Sidebar variant="inset">
            <SidebarHeader>
                <div className="pt-2 pb-2 pl-2 pr-2"><BrandMark /></div>
            </SidebarHeader>
            <SidebarContent>
                <SidebarGroup>
                    <SidebarGroupLabel>{"Workflows"}</SidebarGroupLabel>
                    <SidebarMenu>
                        {for item in NAV {
                            <SidebarMenuItem key={item["to"]}>
                                <SidebarMenuButton asChild={True} isActive={path == item["to"]} size="lg">
                                    <Link to={item["to"]}>
                                        <HugeiconsIcon icon={item["icon"]} strokeWidth={2} />
                                        <span>{item["label"]}</span>
                                    </Link>
                                </SidebarMenuButton>
                            </SidebarMenuItem>
                        }}
                    </SidebarMenu>
                </SidebarGroup>
            </SidebarContent>
            <SidebarFooter>
                <div className="flex items-start gap-2.5 rounded-lg border bg-card pt-3 pb-3 pl-3 pr-3 text-xs text-muted-foreground">
                    <HugeiconsIcon icon={Shield01Icon} strokeWidth={2} className="mt-0.5 size-4 shrink-0 text-primary" />
                    <span>{"Nothing leaves Code Shield without your approval. Every action is logged with its evidence."}</span>
                </div>
            </SidebarFooter>
        </Sidebar>
        <SidebarInset>
            <header className="flex h-14 shrink-0 items-center gap-2 border-b pl-4 pr-4">
                <SidebarTrigger />
                <Separator orientation="vertical" className="mr-2 h-4" />
                <span className="text-sm font-medium">{_section_title(path)}</span>
            </header>
            <main className="flex flex-1 flex-col gap-8 pt-8 pb-12 pl-4 pr-4 md:pl-10 md:pr-10 animate-in fade-in slide-in-from-bottom-1 duration-500">
                <Outlet />
            </main>
        </SidebarInset>
    </SidebarProvider>;
}
