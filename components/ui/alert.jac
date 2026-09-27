import from "class-variance-authority" { cva }
import from ...lib.utils { cn }

glob _alertVariants: any = cva(
         "grid gap-0.5 rounded-lg border px-2.5 py-2 text-left text-sm has-data-[slot=alert-action]:relative has-data-[slot=alert-action]:pr-18 has-[>svg]:grid-cols-[auto_1fr] has-[>svg]:gap-x-2 *:[svg]:row-span-2 *:[svg]:translate-y-0.5 *:[svg]:text-current *:[svg:not([class*='size-'])]:size-4 w-full relative group/alert",
         {
             "variants": {
                 "variant": {
                     "default": "bg-card text-card-foreground",
                     "destructive": "text-destructive bg-card *:data-[slot=alert-description]:text-destructive/90 *:[svg]:text-current"
                 }
             },
             "defaultVariants": {"variant": "default"}
         }
     );

def:pub Alert(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    variant = props["variant"] or "default";
    variantsFn = _alertVariants;
    computedClass = cn(
        variantsFn.call(None, {"variant": variant, "className": props["className"]})
    );
    return <div {**attrs} data-slot="alert" role="alert" className={computedClass}/>;
}

def:pub AlertTitle(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="alert-title"
            className={cn(
                "font-medium group-has-[>svg]/alert:col-start-2 [&_a]:hover:text-foreground [&_a]:underline [&_a]:underline-offset-3",
                props["className"]
            )}
        />;
}

def:pub AlertDescription(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="alert-description"
            className={cn(
                "text-muted-foreground text-sm text-balance md:text-pretty [&_p:not(:last-child)]:mb-4 [&_a]:hover:text-foreground [&_a]:underline [&_a]:underline-offset-3",
                props["className"]
            )}
        />;
}

def:pub AlertAction(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="alert-action"
            className={cn("absolute top-2 right-2", props["className"])}
        />;
}
