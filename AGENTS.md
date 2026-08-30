# EdgeStash working agreement

This repository is the independent EdgeStash product. These instructions
apply to human contributors and coding agents.

## Read order

1. `docs/contracts/edgestash.md` and `docs/contracts/local-first.md`.
2. `docs/design/logical-display-and-seam-beacon.md` — current surface.
3. `docs/design/glass-signal-and-repeatable-seam.md` — accepted 5pt glass
   chrome. Owner perceptual review is still open.

`docs/plans/2026-08-29-edgestash.md` is historical. It is not current
execution authority.

## Product boundaries

- Keep AppKit-free policy in `Sources/EdgeStashLogic` and live macOS
  behavior in `Sources/EdgeStash`.
- Preserve the local-first and permission boundaries in the product
  contracts.
- Do not import external scaffolding, reference code, or checkers.
- Do not commit unless the owner asks.

## Contract-first

- Do not deliver a material behavior change without a landed current or
  accepted target contract.
- Product intent, perceptual trade-offs, and risk acceptance belong to the
  owner.

## Experiments

The 2026-08-29 WindowServer-clipped slide and the 2026-08-30 present-only
hover path were discarded trials. Do not reintroduce them without a new
owner-accepted contract.

## Verification

```bash
swift run EdgeStashLogicTests
```

A Debug build of `EdgeStash.xcodeproj` is required for app-target changes.
Neither command is owner perceptual review.

## Owner-runnable app

When the owner is asked to run a build, stage it with the same script and
the same three files.

```bash
./scripts/stage-app.sh          # Release (default)
./scripts/stage-app.sh Debug    # Debug; still the same output paths
```

Always tell the owner to quit the running EdgeStash and open
`dist/EdgeStash.app`. The zip is always `dist/EdgeStash.zip`.
`dist/CURRENT.txt` records configuration and build time.
