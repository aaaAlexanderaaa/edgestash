# Signing, notarization, and Homebrew releases

The release tools are prepared; a signed release and installable Cask are not
published yet. Apple Developer Program membership and a Developer ID
Application certificate are still needed. This guide follows
[`contracts/distribution-and-updates.md`](contracts/distribution-and-updates.md).

Homebrew handles downloading and replacing the app. Developer ID signing gives
successive versions a stable identity. Apple notarization handles Gatekeeper's
distribution checks. Accessibility remains a permission the person grants.
The app itself still makes no network requests.

## Diagnostic test releases

The owner-requested v0.1.8 GitHub prerelease uses the existing ad-hoc package
path, with `./scripts/stage-app.sh Release --diagnostics`. It is a Release
optimized build with bounded local runtime logging enabled. Its notes state
the CLT build evidence, unavailable full Xcode-project check, pending physical
sleep/wake acceptance, and ad-hoc signing. It is not the Developer ID and
notarization workflow below and does not generate an installable Cask.

## One-time signing setup

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/enroll/).
   Apple lists the membership at USD 99 per year, or local currency where
   available. A free Apple developer account cannot supply the Developer ID
   distribution identity this workflow requires.
2. On the release Mac, create a **Developer ID Application** certificate with
   its private key, using Xcode's account certificate management or Keychain
   Access and the developer account. This is not an Apple Development, Mac
   App Distribution, or Developer ID Installer certificate. Follow
   [Apple's certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
3. Confirm that the certificate and private key appear as a valid identity:

   ```bash
   security find-identity -v -p codesigning
   ```

4. Store notarization credentials in Keychain. The command prompts for the
   Apple ID, Team ID, and app-specific password and validates the credentials:

   ```bash
   xcrun notarytool store-credentials edgestash-notary
   ```

   Use an [app-specific password](https://support.apple.com/102654), not the
   Apple account password. Do not put passwords, private keys, or exported
   signing certificates into this repository.

5. Set the release configuration in the shell that runs the tools:

   ```bash
   export EDGESTASH_TEAM_ID='ABCDEFGHIJ'
   export EDGESTASH_SIGNING_IDENTITY='Developer ID Application: Your Name (ABCDEFGHIJ)'
   export EDGESTASH_NOTARY_PROFILE='edgestash-notary'
   ```

   Replace the sample Team ID and identity with the real values. Keep the
   same Team ID and bundle ID (`top.whatif.edgestash`) for future releases.
   Normal certificate renewal within that team does not require pinning the
   old certificate fingerprint. Do not replace the default designated
   requirement with an executable hash.

Xcode Command Line Tools can build the app and provide `notarytool` and
`stapler`. A CLT build does not satisfy the repository's separate Xcode-project
Debug validation gate. Before changing the app target, validate that gate on
a Mac with full Xcode.

After changing release tools, run `python3 scripts/check-distribution-tooling.py`
on macOS. Its ten tests use fake signing/notarization tools, real ZIP/plist
handling, and Apple's requirement parser to check failure isolation and archive
consistency. If Homebrew is installed they also evaluate the generated Cask's
DSL without installing anything. They do not replace a real signed release or
upgrade test.

## Prepare each release

1. Choose a new, unused `vMAJOR.MINOR.PATCH` tag. Increase
   `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Info.plist`,
   and the corresponding `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
   entries in `EdgeStash.xcodeproj/project.pbxproj`. The archive's version
   must match the tag. Do not replace an older release's ZIP with new bytes.
2. Run the expectation check, including the logic suite:

   ```bash
   ./scripts/check-expectations.sh
   ```

   For app-target changes, also run the required Debug build with full Xcode.
3. Stage the distribution package:

   ```bash
   ./scripts/stage-app.sh Release --distribution
   ```

   This builds an arm64 app, signs with Hardened Runtime and a secure
   timestamp, verifies the expected Developer ID team, submits to Apple,
   requires `Accepted`, staples the ticket, and checks both the signature and
   Gatekeeper assessment. It then creates the final ZIP. Credentials are
   read from Keychain. Build and notarization failures leave the previous
   `dist` outputs in place; their old `CURRENT.txt` is not evidence that the
   failed build succeeded.

   The final files are always:

   - `dist/EdgeStash.app`
   - `dist/EdgeStash.zip`
   - `dist/CURRENT.txt`

   `CURRENT.txt` must say `mode: distribution` and record an accepted,
   stapled notarization. Without `--distribution`, the same script produces
   a local ad-hoc build; it is not a formal release.

   If Apple times out or rejects the submission, the error includes the
   submission ID when available. Inspect it with `xcrun notarytool info ID`
   or `xcrun notarytool log ID`, passing `--keychain-profile edgestash-notary`.
   Correct the cause and rerun staging; a submission left processing does
   not make an unstapled package publishable.
4. Quit the running EdgeStash and open `dist/EdgeStash.app` for the release
   smoke test. Confirm existing window behavior and the permission boundary.
   First signed-build migration may require granting Accessibility again.
5. Generate the Cask from the **final ZIP**. For example, after bumping to
   version `0.1.6`:

   ```bash
   mkdir -p tmp/release/Casks
   ./scripts/generate-cask.sh v0.1.6 > tmp/release/Casks/edgestash.rb
   ruby -c tmp/release/Casks/edgestash.rb
   ```

   The generator extracts and verifies the ZIP, checks the version, and
   writes a versioned GitHub release URL and the ZIP's SHA-256. Signing,
   notarization, version, or architecture failure produces no Cask text.
   Shell redirection may still create an empty output file on failure; do
   not publish it. Never use a placeholder checksum, `sha256 :no_check`, a
   mutable `latest` URL, or an unsigned archive.
6. Publish that exact `EdgeStash.zip` under the matching new GitHub release
   tag. Verify the downloaded release asset's SHA-256 against the generated
   Cask. Only then place `edgestash.rb` in a top-level `Casks/` directory
   and publish the Cask change. The tools do not commit, tag, create releases,
   upload assets, or publish a tap for you.

## Homebrew installation after the first signed release

The existing repository can also act as the tap once it contains the generated
`Casks/edgestash.rb`. An explicit clone URL avoids needing a second
`homebrew-edgestash` repository:

```bash
brew tap aaaalexanderaaa/edgestash https://github.com/aaaAlexanderaaa/edgestash
brew install --cask aaaalexanderaaa/edgestash/edgestash
```

These commands become usable after the Cask and its signed asset are published.
No installable Cask is checked in during the tooling-only preparation.

For an existing manual installation, first quit EdgeStash and move the old
`/Applications/EdgeStash.app` to Trash so it does not conflict with the first
Homebrew installation. Keep application preferences and support files. Open
the new `/Applications/EdgeStash.app` and grant Accessibility if needed. If
System Settings retains an unusable entry for the old ad-hoc app, remove that
entry and add the new installed app. This migration can require one last
authorization; signing does not transfer the old grant automatically.

Later updates:

```bash
# First quit EdgeStash from its menu, allowing window restoration to finish.
brew update
brew upgrade --cask aaaalexanderaaa/edgestash/edgestash
open /Applications/EdgeStash.app
```

The unqualified `brew upgrade --cask edgestash` also works when no other tap
defines that name. Homebrew does not make updates automatic; the person runs
the upgrade command. There is no in-app update checker.

## Verify that upgrades retain authorization

On macOS Ventura and later, give the terminal used for Homebrew **App
Management** permission if needed for in-place upgrades. Homebrew documents
that without the required updater permission it can uninstall/reinstall the
app, causing macOS to remove permission metadata. Full Disk Access also
satisfies Homebrew, but is broader than needed; start with App Management.
See [Homebrew's explanation](https://docs.brew.sh/FAQ#why-do-my-cask-apps-lose-their-dock-position--launchpad-position--permission-settings-when-i-run-brew-upgrade).

Before promising update continuity to users, test two actual signed versions:

1. Install signed version A into `/Applications` through the tap. Grant
   Accessibility once, change a preference, and enable launch at login if
   desired for this check.
2. Quit the app, publish signed version B with the same team and bundle ID,
   and update through Homebrew. Keep the same installation path.
3. Reopen it and verify that Accessibility still works, preferences remain,
   and the login-item state is correct. Verify window restoration before
   quitting and window management after reopening.
4. Compare `codesign -d -r- /Applications/EdgeStash.app` across versions; the
   designated requirement should remain stable.

That real upgrade remains an owner-machine acceptance check. Passing build,
logic, signature, or notarization checks alone cannot prove that macOS retained
the person's permission grant.
