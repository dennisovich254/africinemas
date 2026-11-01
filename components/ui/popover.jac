import from "radix-ui" { Popover as PopoverPrimitive }
import from ...lib.utils { cn }

# A panel anchored to its trigger: the notifications bell's list.

def:pub Popover(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as dialog.jac
    <PopoverPrimitive.Root data-slot="popover" {**props}/>
}

def:pub PopoverTrigger(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as dialog.jac
    <PopoverPrimitive.Trigger data-slot="popover-trigger" {**props}/>
}

def:pub PopoverContent(props: any) -> JsxElement {  # jac:ignore[W1037,W1052] a Radix wrapper, as dialog.jac
    <PopoverPrimitive.Portal>
        <PopoverPrimitive.Content
            align="end"
            sideOffset={8}
            {**props}
            data-slot="popover-content"
            className={cn(
                "bg-popover text-popover-foreground z-50 w-[min(24rem,calc(100vw-1rem))] rounded-xl border p-0 text-sm shadow-lg outline-none data-open:animate-in data-open:fade-in-0 data-closed:animate-out data-closed:fade-out-0",
                props["className"]
            )}
        />
    </PopoverPrimitive.Portal>
}
