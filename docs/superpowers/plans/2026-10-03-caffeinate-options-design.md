# Caffeinate options design

The user requested a native redesign of Caffeinate's additional controls, `chevron.left` for Back, and no selectable outline on Back or Settings.

## Design read

Reading this as a preserved native macOS utility for users working in another app, with Cascade's discreet notch language. Impeccable's product register and Taste's preserve mode apply; the existing SF font, dark surface and cup amber take precedence over marketing presets. Dials: `DESIGN_VARIANCE: 3`, `MOTION_INTENSITY: 3`, `VISUAL_DENSITY: 5`.

The previous page treated the seven duration actions as loose text links, gave the display toggle no visible state, and lacked hierarchy between session information and infrequent actions. The redesign uses a session header, equally sized duration segments, a display row with an explicit switch, and a quiet footer for Stop and credits. Credits disclose inline. Errors replace the secondary status line rather than adding another row. Busy states retain geometry and remove action authority.

## Constraints

- Keep the shared 220-point options content height and standard notch width.
- Reuse the existing plugin nodes, native controls and shared page transition; add no SDK primitives, dependencies, timers or per-frame state.
- Use the existing cup amber only for active state and the selected duration. Use readable white and neutral secondary text on the notch surface.
- Back and Settings retain click/AX actions, refuse first responder and disable focus rings. A separate invisible responder preserves Escape without selecting navigation chrome.
- Preserve duration actions, native deadlines, display behavior, stale-action rejection and provenance text.

## Verification

The native keyboard-target regression must fail on the previous focus behavior and pass after the change. Render the actual plugin components at the host's content width with normal, busy, credits and error states; verify that their fitting heights stay within 220 points. Run affected tests and the signed application build, then relaunch that exact build. Record any live UI or performance qualification that the available environment cannot provide separately from component rendering.
