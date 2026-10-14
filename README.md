# FreeShiamy iOS improvement plan

This branch starts from `master` at `2d449c3ce19b5faaa0704d4c67a69a4e75f0736f`. The items below are source-backed observations, not claims that the app has been fixed or tested. An item is complete only after its behavior passes native checks and independent review. The simulator unit tests exercise production keyboard classes with a fake text proxy; they do not prove behavior inside every third-party host app.

| ID | Status | Evidence at baseline | Acceptance evidence needed |
| --- | --- | --- | --- |
| F01 | Under test | Delete touch-down and touch-up both delete in `FSHKeyboardView.m`/`InputViewController.m` | Tap once, hold after delay, no composition-to-host crossover |
| F02 | Under test | Raw deletion and reverse checks use UTF-16 units | Emoji, combining mark, ZWJ and supplementary-character tests |
| F03 | Under test | Repeat timer has no disappearance teardown | Cancel, drag exit, rebuild, focus change, disappearance tests |
| F04 | Under test | Sensitive guard only covers ordinary key press | Secure-field delete, raw and candidate paths cannot write |
| F05 | Open | Globe is hard-disabled in `InputViewController.m` | System switch key and picker work in all modes/layouts |
| F06 | Open | Emoji rows omit Delete | Delete works without leaving emoji mode |
| F07 | Open | Symbol rows omit !, ?, double quote, backtick | All four directly reachable without losing existing symbols |
| F08 | Open | QAZ/Del setting shifts Q/A but not Z and narrows Delete | Q/A/Z/Delete geometry checked at four widths |
| F09 | Open | Original layout changes row gap after calculating row height | Last row reaches bottom for both Original layouts |
| F10 | Open | Narrow key gaps and 32×28 More control | Non-overlapping hit-map checks for Delete/More/Return |
| F11 | Open | Shift/Caps/symbol states share appearance | Distinct visual and accessibility states, sequence tests |
| F12 | Open | Emoji/Settings require hidden long presses | Discoverable, named and accessible actions |
| F13 | Open | Return substitutes dismissal/tab for host actions | Trait labels and host behavior matrix, with integration limits stated |
| F14 | Open | Hidden More reserves trailing space | One/ten/eleven-candidate width tests |
| F15 | Open | Candidate scroll stays at prior offset across queries | New-query reset and same-data relayout tests |
| F16 | Open | Candidate buttons recreated on every layout | Stable view identities and bounded allocations |
| F17 | Open | Settings setters each rebuild all keys | One rebuild for one combined settings snapshot |
| F18 | Open | Candidates expose value only | Code/exactness/shortcut semantics match current digit mapping |
| F19 | Open | Fixed key/candidate fonts and settings row heights | Dynamic Type visual/accessibility checks |
| F20 | Open | Spell data comment appears in candidate value | `j03 腕 # non official` parses to `腕`; literal # retained |
| F21 | Open | Engine reports ready after parse failures | Atomic missing/unreadable/empty-dictionary failure and visible error |
| F22 | Open | Background load mutates live engine | Publish completed engine on main, reject stale result |
| F23 | Open | Homophone index keeps first pronunciation only | All known readings for 行/樂 with stable deduped order |
| F24 | Open | Duplicate comma/period entries in main dictionary | Exact duplicates removed, alternate codes retained |
| F25 | Open | Host app lacks character-to-all-codes search | Offline lookup: 行→MV/MIRI, 中→CI/CJ/CJV |
| F26 | Open | Settings accept arbitrary numbers/strings | Range/enum sanitation and legacy fixture tests |
| F27 | Open | Sensitive setting label overstates implemented trait guard | UI wording matches actual password/OTP trait behavior |
| F28 | Open | Host controls anchored below keyboard | Reachable focused inputs in portrait/landscape/iPad |
| F29 | Open | Keyboard height ignores available landscape/floating space | No negative frames/constraint breaks with expanded candidates |
| F30 | Open | Leading [ and ] roots are absent from letter keyboard | Both root candidates compose; symbols still insert literal brackets |

## Verification

The branch adds a shared Xcode scheme, hosted XCTest cases and a macOS simulator workflow. CI uses Xcode 26.2 and a simulator created for that job, saves logs and an `.xcresult`, and does not alter production signing or entitlements. A passing simulator suite establishes only the behaviors it asserts. Extension-host integration, accessibility appearance, App Group access, screenshots and performance measurements need separate evidence before their corresponding items can close.
