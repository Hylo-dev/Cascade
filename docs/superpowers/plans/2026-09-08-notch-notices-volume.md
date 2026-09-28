# Continuous notch, notices and volume

Request approved directly by the user on 8 September: Apple continuous shape,
notices only while closed, two-phase closing of Live Activities, replacement
of the volume HUD with icon/text and a percentage bar beside the notch.

## Decisions

- The outline keeps its attachment to the top edge and adopts the native
  continuous curvature. The shared path drives drawing, mask and hit testing.
- Notices occupy both compact sides. Entering hover removes them and
  opens an available Live Activity or the widgets. Notices that arrive during
  expansion are discarded, and are not shown again later.
- Closing a Live Activity hides its views immediately, reaches the
  base geometry and opens the wings only on the next frame. No fixed-time
  wait: the second phase depends on the springs settling. Reduced motion
  goes straight to the final state.
- Volume uses CoreAudio listeners and selective interception of the volume keys.
  System daemons or HUDs are not disabled globally; without support or
  permissions, the keys keep their native behavior.
- No automatic grant of Accessibility, no change to the real audio
  through verification scripts, no commit of pre-existing changes.

## Execution

- [x] Continuous path: `Extensions/CGPath+Notch.swift` and dedicated geometry tests;
  derive/cache Apple segments, verify symmetry, bounds and small angles.
- [x] Host and controller: restrict the expanded presentation to Live Activities,
  discard notices while opening, suspend the views during the return to the
  base, animate the compact width in points. Host/controller regressions before
  the implementation.
- [x] Volume: new types `Cascade/Integrations/Volume`, `VolumeChangeNotice`,
  wiring into services/menu and a Swift 6 harness for events, capability and cleanup.
- [x] Verify the full suite, signed build, independent review and launch
  of the exact build. Update the contract with these new rules.

The shared contract adds `compactPreferredSideWidth: CGFloat?` (outer width
of each wing, configured default when nil). Volume requests 116pt;
the renderer clamps the values to the display. `makeExpandedView` belongs only to
`NotchLiveActivity`; notices cannot obtain an expanded surface.
