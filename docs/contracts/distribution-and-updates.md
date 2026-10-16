---
doc_type: contract
status: target
authority: normative
implementation: in_progress
verification_status: partial
last_reconciled: 2026-10-15
---

# Distribution and updates

## Owner request and scope

On 2026-10-15 the owner requested Homebrew package management and signing to
reduce the repeated download, developer-trust, and Accessibility authorization
work during updates. The owner has no Apple Developer Program membership yet
and authorized preparing the release tooling first.

This contract covers release tools and installation documentation. It does not
add networking, an update feed, an updater, or a new permission prompt to the
EdgeStash process. The capability boundary in `local-first.md` still applies.
Build, notarization, download, and package-manager networking happen outside
the app.

## Required behavior

- `./scripts/stage-app.sh [Release|Debug]` remains the local development path.
  Its ad-hoc signature is not a distribution identity and does not promise
  Accessibility continuity between builds.
- `./scripts/stage-app.sh Release --distribution` is the explicit distribution
  path. It requires a Developer ID Application identity, an expected Apple
  Team ID, and a named notarytool Keychain profile. Missing prerequisites or
  failed signing/notarization/verification stop the command; there is no
  fallback to ad-hoc signing.
- Both paths produce exactly `dist/EdgeStash.app`, `dist/EdgeStash.zip`, and
  `dist/CURRENT.txt`. Build and verification finish before replacing those
  outputs. `CURRENT.txt` distinguishes development from distribution and
  records signing and notarization status.
- Distribution is Apple Silicon only, as the current README promises. Its
  identity remains `top.whatif.edgestash`. Releases retain the same Apple
  team and default Developer ID designated requirement; do not bind the
  requirement to a particular executable hash or certificate fingerprint.
- Distribution signing enables Hardened Runtime and a secure timestamp.
  The sole entitlement is Apple Events automation, to preserve the existing
  user-invoked macOS 12 login-item fallback. It grants no Accessibility
  access, enables no App Sandbox, and adds no new runtime operation.
- Apple must accept the notarization submission. Staple and validate the
  ticket on the app, verify the signature and Gatekeeper assessment, and
  only then create the final ZIP. The ZIP must contain that stapled app.
- The Cask generator reads and verifies the app extracted from the final
  ZIP, checks its version against the release tag, and pins that ZIP's
  SHA-256 and versioned release URL. It refuses development packages.
  Do not publish an installable Cask with placeholder values or an unsigned
  release URL. Every published update increments the app version and build;
  already published archives are not replaced in place.
- The Cask installs `EdgeStash.app`. It neither re-signs the app nor removes
  quarantine, resets TCC, grants permissions, or deletes preferences. The
  user quits EdgeStash before updating so normal window restoration can
  complete. Updates are user-initiated through Homebrew.

## Permission continuity and limits

Developer ID signing establishes a stable code identity; notarization allows
Gatekeeper to assess the published package. Neither grants Accessibility.
The first installation still requires the person's explicit authorization.
Migration from an ad-hoc build may require authorization once more.

Stable identity alone is not an end-to-end permission-continuity test.
Homebrew documents that uninstall/reinstall upgrades can discard macOS
permission metadata. On macOS Ventura and later, its in-place replacement
strategy requires the terminal performing the upgrade to have App Management
or Full Disk Access. Installation guidance recommends the narrower App
Management permission when needed; no tool changes these settings.

## Acceptance evidence

| Outcome | Evidence required | Status |
|---|---|---|
| Local build still stages the same three outputs | CLT Release stage; extracted ZIP matches the app's files and passes native signature integrity verification | passed 2026-10-15 |
| Missing distribution credentials fail without replacing existing outputs | native missing-credential and absent-identity checks against the real staged output | passed 2026-10-15 |
| Cask cannot advertise a development archive | native codesign rejects the extracted ad-hoc package; generator emits no Cask text | passed 2026-10-15 |
| Failure isolation and Cask consistency | seven tests in `scripts/check-distribution-tooling.py`; fake Apple tools, native requirement parser and ZIP handling, Ruby syntax and installed Homebrew DSL evaluation | passed 2026-10-15; orchestration evidence only |
| Formal package has the intended identity, runtime protections, and ticket | real Developer ID signing, notarization, stapler, codesign, and Gatekeeper verification | blocked on owner membership and credentials |
| Updates preserve permissions and settings | authorize signed version A once, install signed version B through Homebrew at the same path, verify Accessibility, settings, and login-item state | owner machine review pending |
| Window behavior stays within the declared grammar | `./scripts/check-expectations.sh`: 12 structural anchors and logic suite; cardinality coverage remains one executable and eleven structural-only | passed 2026-10-15 |

The formal-release path and signed A-to-B upgrade are not proved by mocked
tools, an ad-hoc build, the logic suite, or an Xcode build.

## Primary references

- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Code designated requirement](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS40007919-CH1-TNTAG300)
- [Apple: Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- [Homebrew: Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
- [Homebrew: permission settings during upgrades](https://docs.brew.sh/FAQ#why-do-my-cask-apps-lose-their-dock-position--launchpad-position--permission-settings-when-i-run-brew-upgrade)
