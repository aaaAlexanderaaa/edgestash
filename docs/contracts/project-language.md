---
doc_type: contract
status: current
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-11-09
---

# Project language

The owner requested English throughout the project and GitHub releases on
2026-11-09, with `README_cn.md` as the sole Chinese-language exception.

- Application copy, source comments, contracts, design documents, reviews,
  diagnostic tools, release titles, release notes, and release asset descriptions
  use English. `README_cn.md` remains the Chinese introduction.
- The application always uses its English copy catalog. System locale and
  previously saved language selections do not change its interface language.
  The obsolete language selector is removed. Older settings remain readable;
  their legacy language field is preserved without affecting other settings or
  rescue records.
- Historical Chinese quotations are translated into English and identified as
  translations. Translation preserves their meaning and historical scope; it
  does not accept superseded product behavior or promote past verification.
- Existing release text may be translated without replacing published archives,
  moving existing tags, or changing stable versus prerelease status.
- `scripts/check-project-language.py`, invoked by the expectation check, rejects
  Chinese ideographs in project text outside `README_cn.md`. It also checks that
  literal copy identifiers in the app's `text("...")` calls exist in the English
  catalog; this is a static guard rather than general language detection.

The owner request accepts this interface change. Window behavior, permissions,
local-first boundaries, and the behavior grammar retain their existing rules.
