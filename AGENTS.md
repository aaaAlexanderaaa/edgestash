# EdgeStash working agreement

This repository is the independent EdgeStash product.

1. Read `docs/contracts/edgestash.md` and `docs/plans/2026-08-29-edgestash.md`.
2. Keep AppKit-free policy in `Sources/EdgeStashLogic` and live macOS behavior
   in `Sources/EdgeStash`.
3. Preserve the local-first and permission boundaries in the product contracts.
4. Do not import external scaffolding, reference code, or checkers.
5. Run `swift run EdgeStashLogicTests` for logic verification.
