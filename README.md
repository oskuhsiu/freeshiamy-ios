# FreeShiamy iOS improvement plan

This branch starts from `master` at `2d449c3ce19b5faaa0704d4c67a69a4e75f0736f`. The items below are source-backed observations, not claims that the app has been fixed or tested. An item is complete only after its behavior passes native checks and independent review. The simulator unit tests exercise production keyboard classes with a fake text proxy; they do not prove behavior inside every third-party host app.

| ID | Status | Evidence at baseline | Acceptance evidence needed |
| --- | --- | --- | --- |
| F01 | Under test | Delete touch-down and touch-up both delete in `FSHKeyboardView.m`/`InputViewController.m` | Tap once, hold after delay, no composition-to-host crossover |
| F02 | Under test | Raw deletion and reverse checks use UTF-16 units | Emoji, combining mark, ZWJ and supplementary-character tests |
| F03 | Under test | Repeat timer has no disappearance teardown | Cancel, drag exit, rebuild, focus change, disappearance tests |
| F04 | Under test | Sensitive guard only covers ordinary key press | Secure-field delete, raw and candidate paths cannot write |
| F05 | Open | Globe is hard-disabled in `InputViewController.m` | System switch key and picker work in all modes/layouts |
| F06 | Under test | Emoji rows omit Delete | Delete works without leaving emoji mode |
| F07 | Under test | Symbol rows omit !, ?, double quote, backtick | All four directly reachable without losing existing symbols |
| F08 | Open | QAZ/Del setting shifts Q/A but not Z and narrows Delete | Q/A/Z/Delete geometry checked at four widths |
| F09 | Under test | Original layout changes row gap after calculating row height | Last row reaches bottom for both Original layouts |
| F10 | Open | Narrow key gaps and 32×28 More control | Non-overlapping hit-map checks for Delete/More/Return |
| F11 | Open | Shift/Caps/symbol states share appearance | Distinct visual and accessibility states, sequence tests |
| F12 | Open | Emoji/Settings require hidden long presses | Discoverable, named and accessible actions |
| F13 | Open | Return substitutes dismissal/tab for host actions | Trait labels and host behavior matrix, with integration limits stated |
| F14 | Under test | Hidden More reserves trailing space | One/ten/eleven-candidate width tests |
| F15 | Under test | Candidate scroll stays at prior offset across queries | New-query reset and same-data relayout tests |
| F16 | Under test | Candidate buttons recreated on every layout | Stable view identities and bounded allocations |
| F17 | Open | Settings setters each rebuild all keys | One rebuild for one combined settings snapshot |
| F18 | Open | Candidates expose value only | Code/exactness/shortcut semantics match current digit mapping |
| F19 | Open | Fixed key/candidate fonts and settings row heights | Dynamic Type visual/accessibility checks |
| F20 | Under test | Spell data comment appears in candidate value | `j03 腕 # non official` parses to `腕`; literal # value retained |
| F21 | Under test | Engine reports ready after parse failures | Atomic missing/unreadable/empty-dictionary failure and visible error |
| F22 | Under test | Background load mutates live engine | Publish completed engine on main, reject stale result |
| F23 | Under test | Homophone index keeps first pronunciation only | All known readings for 行/樂 with stable deduped order |
| F24 | Under test | Duplicate comma/period entries in main dictionary | Exact duplicates removed, alternate codes retained |
| F25 | Under test | Host app lacks character-to-all-codes search | Offline lookup: 行→MV/MIRI, 中→CI/CJ/CJV |
| F26 | Under test | Settings accept arbitrary numbers/strings | Range/enum sanitation and legacy fixture tests |
| F27 | Open | Sensitive setting label overstates implemented trait guard | UI wording matches actual password/OTP trait behavior |
| F28 | Open | Host controls anchored below keyboard | Reachable focused inputs in portrait/landscape/iPad |
| F29 | Open | Keyboard height ignores available landscape/floating space | No negative frames/constraint breaks with expanded candidates |
| F30 | Open | Leading [ and ] roots are absent from letter keyboard | Both root candidates compose; symbols still insert literal brackets |

## Verification

The branch adds a shared Xcode scheme, hosted XCTest cases and a macOS simulator workflow. CI uses Xcode 26.2 and a simulator created for that job, saves logs and an `.xcresult`, and does not alter production signing or entitlements. A passing simulator suite establishes only the behaviors it asserts. Extension-host integration, accessibility appearance, App Group access, screenshots and performance measurements need separate evidence before their corresponding items can close.

Numeric settings accept stored NSNumbers containing finite whole values. Values below or above the supported range clamp to its boundary, including zero and negative values; missing, wrongly typed, fractional, or non-finite values use the documented default. Keyboard layouts accept only the three current values and the two known legacy values until host-app migration consumes them. Both reads and writes apply the same limits.

### CI decision record, 2026-10-14

The [third simulator run](https://github.com/oskuhsiu/freeshiamy-ios/actions/runs/38594545189) at `0862d34` executed 32 tests and reported three assertions: the host code-search test checked its navigation child window before UIKit finished attaching it, and two sensitive-field assertions expected absolute switch/dismiss counts of one despite earlier host callbacks. Diagnostic artifact `11909971249` has SHA-256 `723b44eb4027f7c2b52c9bc413513c5737014772d8b107a155881026d3f06706`. The follow-up change waits for the actual scene-backed view/window and nonempty geometry, checks manual switch/dismiss deltas, and separately tests that a connected secure-field transition advances and dismisses once. The next CI run should use the unchanged Xcode 26.2, iOS 26.2 arm64 simulator environment; acceptance requires both scene-backed attachment predicates and the exactly-once/delta assertions to pass. No production-code defect was established by the prior three assertions. The code-search image attachments show the app window; the keyboard-layout-guide assertion, rather than the window-only screenshot, establishes keyboard occlusion. These corrections still require a new simulator run before the items can be marked complete.

The [fourth simulator run](https://github.com/oskuhsiu/freeshiamy-ios/actions/runs/38597645705) at `312cef2` passed the prior scene-backed and sensitive-transition assertions but executed 38 tests with eight geometry assertions across three tests. Artifact `11913256978` has SHA-256 `29d4f8f438ec0e41a26d16f6b4db0affa66129064c077ddaac5bdf7dace8db53`. The emoji Delete and original-row sweeps set frames on a controller-owned keyboard still governed by Auto Layout; these assertions saw effectively zero-sized frames, so those sweeps now use standalone, explicitly sized keyboards. The candidate-width test used a standalone bar but compared scroll widths across states where the raw button's width could redistribute. It now pins the bar to a sized host and checks the same exact 0/36-point reserved-width geometry within the candidate area. This follow-up changes test fixtures and measurement only; no production layout fix is inferred from those assertions. Separately, screenshots showed short raw text occupying 35% of the bar, which remains a product-polish candidate requiring its own review and evidence. The next run should keep Xcode 26.2 and the iOS 26.2 arm64 simulator, pass the numeric geometry assertions, and retain the already-passing scene-backed production-keyboard checks.
