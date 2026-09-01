# Contributing to HackyKit

Run the repository invariant check, `swift test`, and `git diff --check` before
every commit. Changes to canonical encoding, activation, validation, extraction,
or PDF rendering require regression tests and must remain byte-compatible with
the public Hacky v0.1 contract.

HackyKit owns reusable Swift export and inspection mechanics. It must not
contain app copy, account state, networking policy, product economy, or
user-specific absolute paths. Generated `.build`, `.swiftpm`, Xcode user state,
and DerivedData are never committed.

Hacky v0.1 has exactly four public JSON keys. New writers emit only canonical
`.hacky.json` and `.hacky.pdf`; any historical reader must remain internal,
read-only, explicitly invoked, and unable to leak old names into public API,
documentation, or filenames.

Code contributions use Apache-2.0. Documentation contributions use CC BY 4.0.
