import from "@jac/runtime" { useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Upload01Icon, Camera01Icon, File01Icon, Alert01Icon, SentIcon, CheckmarkCircle02Icon }
import from .ui.button { Button }
import from .ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter }
import from .ui.input { Input }
import from .ui.field { Field, FieldLabel, FieldGroup }
import from .ui.alert { Alert, AlertTitle, AlertDescription }
import from .ui.skeleton { Skeleton }
import from .Shared { PageHeader }
sv import from ..services.claims { DenialExtraction, extract_denial_letter, open_upload_appeal }

glob FIELDS: list[list[str]] = [
    ["patient_name", "Patient name"], ["payer", "Payer"], ["member_id", "Member ID"],
    ["claim_number", "Claim number"], ["denial_code", "Denial reason code"], ["denial_reason", "Denial reason"],
    ["procedure", "Procedure"], ["condition", "Condition / diagnosis"], ["date_of_service", "Date of service"],
    ["denial_date", "Denial date"], ["appeal_deadline", "Appeal deadline"]
];

def read_data_url(file: any) -> any {
    reader: any = new(FileReader);
    p: any = new(Promise, lambda (resolve: any, reject: any) {
        reader.onload = lambda { resolve(reader.result); };
        reader.onerror = lambda { reject(reader.error); };
    });
    reader.readAsDataURL(file);
    return p;
}

def:pub UploadDenial() -> JsxElement {
    has stage: str = "pick",
        filename: str = "",
        ext: DenialExtraction | None = None,
        form: dict = {},
        busy: bool = False,
        dragging: bool = False,
        error: str = "";

    nav = useNavigate();

    async def process(file: any) -> None {
        if not file {
            return;
        }
        filename = file.name;
        stage = "reading";
        error = "";
        mime: str = file.type or "application/octet-stream";
        data = "";
        if file.size < 4000000 {
            url: str = await read_data_url(file);
            idx = url.find(",");
            data = url[idx + 1:] if idx >= 0 else "";
        }
        try {
            res = await extract_denial_letter(filename, mime, data);
            ext = res;
            form = {
                "patient_name": res.patient_name, "payer": res.payer, "member_id": res.member_id,
                "claim_number": res.claim_number, "denial_code": res.denial_code, "denial_reason": res.denial_reason,
                "procedure": res.procedure, "condition": res.condition, "date_of_service": res.date_of_service,
                "denial_date": res.denial_date, "appeal_deadline": res.appeal_deadline
            };
            stage = "review";
        } except Exception as e {
            error = "We could not read that file. " + str(e);
            stage = "pick";
        }
    }

    def on_file(e: ChangeEvent) {
        files: any = e.target.files;
        if files and files.length > 0 {
            process(files[0]);
        }
    }

    def on_drop(e: any) {
        e.preventDefault();
        dragging = False;
        files: any = e.dataTransfer.files;
        if files and files.length > 0 {
            process(files[0]);
        }
    }

    def on_drag(e: any) {
        e.preventDefault();
        dragging = True;
    }

    def set_field(key: str, value: str) {
        form = {**form, key: value};
    }

    async def confirm -> None {
        if ext is None {
            return;
        }
        busy = True;
        base = ext as DenialExtraction;
        payload: dict = {
            **form, "amount": base.amount, "confidence": base.confidence,
            "source": base.source, "raw_text": base.raw_text
        };
        try {
            aid = await open_upload_appeal(payload);
            nav(f"/appeals/{aid}");
        } except Exception as e {
            error = "Could not start the appeal. " + str(e);
        }
        busy = False;
    }

    return <div className="flex flex-col gap-8">
        <PageHeader title="Upload a denial letter" subtitle="A photo or PDF of your denial letter or Explanation of Benefits is enough. You check every field we read before the agent does anything." />
        {if stage == "pick" {
            <div className="flex flex-col gap-4">
                <label
                    htmlFor="denial-file"
                    onDragOver={on_drag}
                    onDragLeave={lambda { dragging = False; }}
                    onDrop={on_drop}
                    className={"flex cursor-pointer flex-col items-center justify-center gap-4 rounded-2xl border-2 border-dashed pt-16 pb-16 pl-6 pr-6 text-center transition-colors " + ("border-primary bg-primary/5" if dragging else "border-primary/30 bg-card hover:bg-primary/5")}
                >
                    <div className="flex size-16 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                        <HugeiconsIcon icon={Upload01Icon} strokeWidth={2} className="size-8" />
                    </div>
                    <div className="flex flex-col gap-1">
                        <span className="font-serif text-2xl font-semibold">{"Drop your denial letter here"}</span>
                        <span className="text-sm text-muted-foreground">{"JPG, PNG or PDF, up to 4 MB. Or click to choose a file."}</span>
                    </div>
                    <input id="denial-file" type="file" accept="image/*,application/pdf" className="sr-only" onChange={on_file} />
                </label>
                <div className="flex flex-wrap items-center justify-center gap-3">
                    <label htmlFor="denial-camera" className="inline-flex h-11 cursor-pointer items-center gap-2 rounded-md border bg-card pl-4 pr-4 text-sm font-medium shadow-sm transition-colors hover:bg-muted">
                        <HugeiconsIcon icon={Camera01Icon} strokeWidth={2} className="size-4" />{"Take a photo with your camera"}
                    </label>
                    <input id="denial-camera" type="file" accept="image/*" capture="environment" className="sr-only" onChange={on_file} />
                </div>
                {error and <p className="text-center text-sm text-destructive">{error}</p>}
            </div>
            skip;
        }}
        {if stage == "reading" {
            <Card className="shadow-sm">
                <CardContent className="flex flex-col gap-4">
                    <div className="flex items-center gap-3">
                        <HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-5 text-primary" />
                        <span className="font-medium">{"Reading " + filename + "..."}</span>
                    </div>
                    <Skeleton className="h-4 w-2/3" /><Skeleton className="h-4 w-1/2" /><Skeleton className="h-4 w-3/4" />
                </CardContent>
            </Card>
            skip;
        }}
        {if ext is not None {
            <div className="grid gap-6 lg:grid-cols-5">
                <Card className="shadow-sm lg:col-span-3">
                    <CardHeader>
                        <CardTitle className="font-serif text-lg">{"Check what we read"}</CardTitle>
                        <CardDescription>{"Correct anything that looks wrong. The agent uses exactly these values."}</CardDescription>
                    </CardHeader>
                    <CardContent className="flex flex-col gap-5">
                        {ext.confidence < 0.6 and <Alert className="border-warning-border bg-warning text-warning-foreground">
                            <HugeiconsIcon icon={Alert01Icon} strokeWidth={2} />
                            <AlertTitle>{"Low reading confidence (" + str(int(ext.confidence * 100)) + "%)"}</AlertTitle>
                            <AlertDescription>{"Please check each field carefully. The agent will pause for manual review rather than guess."}</AlertDescription>
                        </Alert>}
                        <FieldGroup>
                            <div className="grid gap-4 sm:grid-cols-2">
                                {for f in FIELDS {
                                    <Field key={f[0]}>
                                        <FieldLabel htmlFor={f[0]}>{f[1]}</FieldLabel>
                                        <Input id={f[0]} className="h-11" value={form[f[0]] or ""} onChange={lambda (e: ChangeEvent) { set_field(f[0], e.target.value); }} />
                                    </Field>
                                }}
                            </div>
                        </FieldGroup>
                    </CardContent>
                    <CardFooter className="flex flex-wrap items-center justify-between gap-3">
                        <Button variant="outline" onClick={lambda { stage = "pick"; ext = None; }}>{"Upload a different file"}</Button>
                        <Button size="lg" className="h-11 shadow-sm" disabled={busy} onClick={confirm}>
                            <HugeiconsIcon icon={SentIcon} strokeWidth={2} />{"Starting appeal..." if busy else "Looks right: build my appeal"}
                        </Button>
                    </CardFooter>
                </Card>
                <Card className="bg-muted/40 shadow-sm lg:col-span-2">
                    <CardHeader>
                        <CardTitle className="font-serif text-lg">{"Extracted text"}</CardTitle>
                        <CardDescription>
                            <span className="inline-flex items-center gap-1.5">
                                <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2} className="size-4 text-primary" />
                                {ext.source + " · " + str(int(ext.confidence * 100)) + "% confidence"}
                            </span>
                        </CardDescription>
                    </CardHeader>
                    <CardContent>
                        <pre className="whitespace-pre-wrap rounded-lg border bg-card pt-4 pb-4 pl-4 pr-4 font-mono text-xs leading-relaxed">{ext.raw_text or "No text available."}</pre>
                        {error and <p className="mt-3 text-sm text-destructive">{error}</p>}
                    </CardContent>
                </Card>
            </div>
        }}
    </div>;
}
