# Installed keyboard adaptive-layout verification

The hosted XCTest geometry fixtures cannot establish the size assigned to a real
keyboard extension by iOS. Run this pass with the app and keyboard extension
installed, enabled and selected in the test panel's text fields. Do not use a
standalone `FSHKeyboardView` as evidence for scene or floating-keyboard behavior.

1. On an iPhone simulator, test portrait, landscape, then portrait again with
   keyboard height settings 90%, 100% and 220%. Repeat with More collapsed and
   expanded. Use a composition and enough candidates to scroll past the first
   page. Keep the same saved percentage across each rotation.
2. Repeat on an iPad simulator in full-screen and split/floating configurations
   that actually permit the extension. Check both light and dark appearance,
   default and Accessibility XXXL text sizes, and widths around 320, 375, 393,
   768 and 1024 points when that host configuration genuinely supplies them.
3. Save a screenshot for each distinct geometry, especially narrow landscape
   with More open, restored portrait, compact Globe when iOS requires a switch
   key, and the host Settings and test panel at Accessibility XXXL. Verify keys
   and candidate controls are legible, reachable, and have no overlapping glyphs.
4. In the Xcode extension console, retain the `DEBUG` `[AdaptiveKeyboard]` lines
   around each geometry change. They log only root, window and scene dimensions,
   capped requested height, saved percentage, content-size category, and
   expansion/compact state. Confirm scene dimensions change with orientation,
   the same percentage remains saved, and the requested height rises again when
   the scene grows. A smaller assigned root can still reduce the actual keys or
   candidate viewport; that is expected and must be checked in the screenshot.
5. With More open in a constrained host, scroll to an offscreen candidate and
   select it, then reopen and collapse with More. Hold Delete just before opening
   compact More and verify repeat stops. Check the compact Globe's picker event
   when `needsInputModeSwitchKey` is true and its absence when false. A host too
   short for the top bar plus one candidate row cannot expose a complete row.

Keep the console excerpt and image attachments with the simulator run record.
Do not include typed private text or candidate content in diagnostic logs.
