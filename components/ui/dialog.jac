import from "radix-ui" { Dialog as DialogPrimitive }
import from ...lib.utils { cn }
import from .button { Button }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Cancel01Icon }

# A window over the page: centred from `sm` up, a sheet from the bottom on a phone.

def:pub Dialog(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as sheet.jac
    <DialogPrimitive.Root data-slot="dialog" {**props}/>
}

def:pub DialogClose(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as sheet.jac
    <DialogPrimitive.Close data-slot="dialog-close" {**props}/>
}

def:pub DialogContent(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as sheet.jac
    <DialogPrimitive.Portal data-slot="dialog-portal">
        <DialogPrimitive.Overlay
            data-slot="dialog-overlay"
            className="fixed inset-0 z-50 bg-black/50 duration-100 data-open:animate-in data-open:fade-in-0 data-closed:animate-out data-closed:fade-out-0"
        />
        <DialogPrimitive.Content
            {**props}
            data-slot="dialog-content"
            className={cn(
                "bg-popover text-popover-foreground fixed inset-x-0 bottom-0 z-50 flex max-h-[90svh] flex-col gap-4 overflow-y-auto rounded-t-xl border-t p-4 text-sm shadow-lg duration-200 sm:inset-x-auto sm:bottom-auto sm:top-1/2 sm:left-1/2 sm:w-[min(48rem,calc(100vw-2rem))] sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-xl sm:border data-open:animate-in data-open:fade-in-0 data-closed:animate-out data-closed:fade-out-0",
                props["className"]
            )}
        >
            {props["children"]}
            <DialogPrimitive.Close data-slot="dialog-close" asChild={True}>
                <Button
                    variant="ghost"
                    className="absolute top-3 right-3"
                    size="icon-sm"
                >
                    <HugeiconsIcon icon={Cancel01Icon} strokeWidth={2}/>
                    <span className="sr-only">Close</span>
                </Button>
            </DialogPrimitive.Close>
        </DialogPrimitive.Content>
    </DialogPrimitive.Portal>
}

def:pub DialogHeader(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as sheet.jac
    attrs: dict[str, any] = {** props};  # jac:ignore[W1037]
    <div
        {**attrs}
        data-slot="dialog-header"
        className={cn("flex flex-col gap-0.5 pr-10", props["className"])}
    />
}

def:pub DialogTitle(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as sheet.jac
    <DialogPrimitive.Title
        {**props}
        data-slot="dialog-title"
        className={cn("text-foreground text-lg font-semibold", props["className"])}
    />
}

def:pub DialogDescription(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as sheet.jac
    <DialogPrimitive.Description
        {**props}
        data-slot="dialog-description"
        className={cn("text-muted-foreground text-sm", props["className"])}
    />
}
