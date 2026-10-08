# JI-041: Through an npm default import, the checker loses a class's static methods

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-08, P6.4 (the door scanner, `qr-scanner`)
- **Status:** open. **Low:** a false error at check time; the build and the browser run it correctly.

## What happened
`qr-scanner` declares its class and exports it as the default:

```ts
// node_modules/qr-scanner/types/qr-scanner.d.ts
declare class QrScanner {
    static hasCamera(): Promise<boolean>;
    ...
}
export default QrScanner;
```

Imported as the guide describes (`import-anything.md`: "default as Name"):

```jac
import from "qr-scanner" { default as QrScanner }
... QrScanner.hasCamera() ...
```

`jac check` reports `error[E1030]: Type "default" has no attribute "hasCamera"`. The import resolves to a type named `default` rather than the class, so its static members are lost. Before the package was installed, the checker reported "module not found" and nothing else, so the error only appears once the package is installed.

## Expected
`default as QrScanner` binds the default export, here the `QrScanner` class with its static methods, as TypeScript and the bundler do.

## Workaround (in place)
Use the class through an `any`-typed value: `_scanner_class()` in `web/backoffice/ScannerSection.jac` returns `QrScanner` typed `any`, and both `hasCamera()` and `new(...)` go through it.
