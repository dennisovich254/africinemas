import from "clsx" { clsx }
import from "tailwind-merge" { twMerge }  # jac:ignore[W1102] untyped npm library

def:pub cn(*inputs: any) -> str {  # jac:ignore[W1037] class names of any kind, as clsx takes them
    return twMerge(clsx(inputs));
}
