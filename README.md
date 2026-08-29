# EdgeStash

EdgeStash is an independent, local-first macOS menu-bar app for stashing and
restoring application windows at logical display edges.

- Bundle identifier: `top.whatif.edgestash`
- Minimum system: macOS 12
- Product contract: `docs/contracts/edgestash.md`
- Implementation plan: `docs/plans/2026-08-29-edgestash.md`

## Build and verify

```bash
swift run EdgeStashLogicTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project EdgeStash.xcodeproj -scheme EdgeStash -configuration Debug build
```

EdgeStash requires Accessibility permission only for controlling other
applications' windows. Without that permission, Settings remains available and
the live window engine stays stopped. The app does not capture the screen or
make network requests.

Settings opens automatically only when Accessibility is unavailable. After
that, use the menu-bar item or reopen EdgeStash from Finder.
