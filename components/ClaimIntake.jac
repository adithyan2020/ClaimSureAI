import from "@jac/runtime" { useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Analytics01Icon, Shield01Icon }
import from .ui.button { Button }
import from .ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter }
import from .ui.input { Input }
import from .ui.field { Field, FieldLabel, FieldGroup, FieldDescription }
import from .ui.native_select { NativeSelect, NativeSelectOption }
import from .Shared { PageHeader }
sv import from ..services.claims { check_claim }

glob PROCEDURES: list[list[str]] = [
    ["Lumbar spine MRI (CPT 72148)", "Chronic low back pain with sciatica"],
    ["Cardiac stress echocardiogram (CPT 93350)", "Exertional chest pain"],
    ["OnabotulinumtoxinA injection (J0585)", "Chronic migraine"],
    ["Physical therapy, 12 visits (CPT 97110)", "Knee osteoarthritis"],
    ["Continuous glucose monitor (E2103)", "Type 2 diabetes on insulin"],
    ["Knee arthroscopy (CPT 29881)", "Meniscus tear"]
];

glob PAYERS: list[str] = ["UnitedHealthcare", "Aetna", "Cigna", "BlueCross BlueShield"];

def:pub ClaimIntake() -> JsxElement {
    has patient: str = "",
        procedure: str = "Lumbar spine MRI (CPT 72148)",
        condition: str = "Chronic low back pain with sciatica",
        payer: str = "UnitedHealthcare",
        policy_type: str = "PPO",
        network: str = "out",
        prior_auth: str = "no",
        documentation: str = "60",
        amount: str = "3240",
        filed: str = "no",
        busy: bool = False,
        error: str = "";

    nav = useNavigate();

    def pick_procedure(e: ChangeEvent) {
        procedure = e.target.value;
        for p in PROCEDURES {
            if p[0] == e.target.value {
                condition = p[1];
            }
        }
    }

    async def submit -> None {
        if not patient.strip() {
            error = "Add the patient's name so the claim can be tracked.";
            return;
        }
        busy = True;
        error = "";
        try {
            doc = float(documentation or "0") / 100.0;
            amt = float(amount or "0");
            cid = await check_claim(patient, condition, procedure, payer, policy_type, network, prior_auth, doc, amt, filed == "yes");
            nav(f"/claims/{cid}/risk");
        } except Exception as e {
            error = "The risk check failed. " + str(e);
        }
        busy = False;
    }

    def on_submit(e: FormEvent) {
        e.preventDefault();
        submit();
    }

    return <div className="flex flex-col gap-8">
        <PageHeader title="Check a claim for denial risk" subtitle="Enter the claim details. The Risk Predictor compares it with similar historical claims and tells you how likely a wrongful denial is, and why." />
        <div className="grid gap-6 lg:grid-cols-3">
            <form onSubmit={on_submit} className="lg:col-span-2">
                <Card className="shadow-sm">
                    <CardHeader>
                        <CardTitle>{"Claim details"}</CardTitle>
                        <CardDescription>{"Everything here stays in your claims graph and is cited in the audit log."}</CardDescription>
                    </CardHeader>
                    <CardContent>
                        <FieldGroup>
                            <div className="grid gap-5 sm:grid-cols-2">
                                <Field>
                                    <FieldLabel htmlFor="patient">{"Patient name"}</FieldLabel>
                                    <Input id="patient" className="h-11" placeholder="Priya Raman" value={patient} onChange={lambda (e: ChangeEvent) { patient = e.target.value; }} />
                                </Field>
                                <Field>
                                    <FieldLabel htmlFor="amount">{"Billed amount (USD)"}</FieldLabel>
                                    <Input id="amount" type="number" className="h-11 tabular-nums" placeholder="3240" value={amount} onChange={lambda (e: ChangeEvent) { amount = e.target.value; }} />
                                </Field>
                            </div>
                            <Field>
                                <FieldLabel htmlFor="procedure">{"Procedure"}</FieldLabel>
                                <NativeSelect id="procedure" className="h-11 w-full" value={procedure} onChange={pick_procedure}>
                                    {for p in PROCEDURES {
                                        <NativeSelectOption key={p[0]} value={p[0]}>{p[0]}</NativeSelectOption>
                                    }}
                                </NativeSelect>
                            </Field>
                            <Field>
                                <FieldLabel htmlFor="condition">{"Condition / diagnosis"}</FieldLabel>
                                <Input id="condition" className="h-11" placeholder="Chronic low back pain" value={condition} onChange={lambda (e: ChangeEvent) { condition = e.target.value; }} />
                            </Field>
                            <div className="grid gap-5 sm:grid-cols-2">
                                <Field>
                                    <FieldLabel htmlFor="payer">{"Payer"}</FieldLabel>
                                    <NativeSelect id="payer" className="h-11 w-full" value={payer} onChange={lambda (e: ChangeEvent) { payer = e.target.value; }}>
                                        {for p in PAYERS {
                                            <NativeSelectOption key={p} value={p}>{p}</NativeSelectOption>
                                        }}
                                    </NativeSelect>
                                </Field>
                                <Field>
                                    <FieldLabel htmlFor="ptype">{"Policy type"}</FieldLabel>
                                    <NativeSelect id="ptype" className="h-11 w-full" value={policy_type} onChange={lambda (e: ChangeEvent) { policy_type = e.target.value; }}>
                                        <NativeSelectOption value="PPO">{"PPO"}</NativeSelectOption>
                                        <NativeSelectOption value="HMO">{"HMO"}</NativeSelectOption>
                                        <NativeSelectOption value="EPO">{"EPO"}</NativeSelectOption>
                                    </NativeSelect>
                                </Field>
                                <Field>
                                    <FieldLabel htmlFor="network">{"Network status"}</FieldLabel>
                                    <NativeSelect id="network" className="h-11 w-full" value={network} onChange={lambda (e: ChangeEvent) { network = e.target.value; }}>
                                        <NativeSelectOption value="in">{"In-network"}</NativeSelectOption>
                                        <NativeSelectOption value="out">{"Out-of-network"}</NativeSelectOption>
                                    </NativeSelect>
                                </Field>
                                <Field>
                                    <FieldLabel htmlFor="auth">{"Prior authorization"}</FieldLabel>
                                    <NativeSelect id="auth" className="h-11 w-full" value={prior_auth} onChange={lambda (e: ChangeEvent) { prior_auth = e.target.value; }}>
                                        <NativeSelectOption value="yes">{"Obtained"}</NativeSelectOption>
                                        <NativeSelectOption value="pending">{"Pending"}</NativeSelectOption>
                                        <NativeSelectOption value="no">{"Not obtained"}</NativeSelectOption>
                                    </NativeSelect>
                                </Field>
                                <Field>
                                    <FieldLabel htmlFor="doc">{"Documentation completeness (%)"}</FieldLabel>
                                    <Input id="doc" type="number" min="0" max="100" className="h-11 tabular-nums" value={documentation} onChange={lambda (e: ChangeEvent) { documentation = e.target.value; }} />
                                    <FieldDescription>{"Office notes, test results and referrals on file."}</FieldDescription>
                                </Field>
                                <Field>
                                    <FieldLabel htmlFor="filed">{"Has the claim been filed?"}</FieldLabel>
                                    <NativeSelect id="filed" className="h-11 w-full" value={filed} onChange={lambda (e: ChangeEvent) { filed = e.target.value; }}>
                                        <NativeSelectOption value="no">{"Not yet filed"}</NativeSelectOption>
                                        <NativeSelectOption value="yes">{"Already filed"}</NativeSelectOption>
                                    </NativeSelect>
                                </Field>
                            </div>
                        </FieldGroup>
                    </CardContent>
                    <CardFooter className="flex flex-wrap items-center justify-between gap-3">
                        <span className="text-sm text-destructive">{error}</span>
                        <Button type="submit" size="lg" className="h-11 shadow-sm" disabled={busy}>
                            <HugeiconsIcon icon={Analytics01Icon} strokeWidth={2} />
                            {"Checking risk..." if busy else "Check denial risk"}
                        </Button>
                    </CardFooter>
                </Card>
            </form>
            <Card className="h-fit bg-muted/40 shadow-sm">
                <CardHeader>
                    <div className="flex size-10 items-center justify-center rounded-lg bg-primary/10 text-primary">
                        <HugeiconsIcon icon={Shield01Icon} strokeWidth={2} className="size-5" />
                    </div>
                    <CardTitle className="font-serif text-lg">{"How the prediction works"}</CardTitle>
                </CardHeader>
                <CardContent className="flex flex-col gap-3 text-sm leading-relaxed text-muted-foreground">
                    <p>{"Your claim becomes a feature vector: procedure, payer, policy type, network, prior authorization and documentation."}</p>
                    <p>{"We find the most similar historical claims by cosine similarity and weight each by how close it is."}</p>
                    <p>{"You get a risk score, the most likely denial code, and each factor explained in plain language. High-risk claims can be fixed before filing."}</p>
                </CardContent>
            </Card>
        </div>
    </div>;
}
