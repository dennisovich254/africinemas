# JI-056: A client build whose compiler kernel is killed says only "died with signal 9", in the browser alone

- **Version:** jaclang 0.38.0, `jac run --dev main.jac`
- **Found:** 2026-10-24, P14.5a (testing in the browser)
- **Status:** open, cause unconfirmed (most likely out of memory)

## What we saw
After `core/tenancy/tenant_api.jac` gained an import of a large server module, the dev page showed only this overlay:

```text
[plugin:jac] E7005: Client build failed: KernelCompileError: the native compiler kernel could not compile /home/amon/africinemas/main.jac: the kernel jc_compile died with signal 9
core/tenancy/tenant_api.jac
```

The server's terminal printed nothing about it.

The machine has 3.3 GB of memory and 2 cores, with VS Code running, and about 850 MB was free. Signal 9 is SIGKILL, which on Linux usually means the out-of-memory killer, but the journal showed no record of a kill.

## Expected
- **Say why:** signal 9 from the kernel is very likely memory, so say "probably out of memory", with how much the kernel was using.
- **Log it:** write the failure to the server's terminal as well as the browser overlay.
- **Point to a fix:** a smaller compile, fewer parallel workers, or a setting to lower the kernel's memory.

## Workaround (in place)
The module stopped importing the large one: the value it needed (a cinema's verification date) is now kept on the `Tenant` node (`verified_at`). Closing other programs also frees memory for the build.
