# EdgeStash

EdgeStash is an independent, local-first macOS menu-bar app for stashing and
restoring application windows at logical display edges.

- Bundle identifier: `top.whatif.edgestash`
- Minimum system: macOS 12
- Product contract: `docs/contracts/edgestash.md`
- Current surface: `docs/design/logical-display-and-seam-beacon.md`
- Glass chrome: `docs/design/glass-signal-and-repeatable-seam.md`

## Build and verify

```bash
swift run EdgeStashLogicTests
./scripts/stage-app.sh
```

Open `dist/EdgeStash.app`. The zip is `dist/EdgeStash.zip`. Debug uses the
same paths: `./scripts/stage-app.sh Debug`.

EdgeStash requires Accessibility permission only for controlling other
applications' windows. Without that permission, Settings remains available and
the live window engine stays stopped. The app does not capture the screen or
make network requests.

Settings opens automatically only when Accessibility is unavailable. After
that, use the menu-bar item or reopen EdgeStash from Finder.
