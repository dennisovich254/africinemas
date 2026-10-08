import from "clsx" { clsx }
import from "tailwind-merge" { twMerge }  # jac:ignore[W1102] untyped npm library

def:pub cn(*inputs: any) -> str {
    return twMerge(clsx(inputs));
}
