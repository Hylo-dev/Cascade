# Addon TODO

## ADDON-NOTCH-OPTIONS: contextual options inside the notch

- [ ] Add a shared addon/SDK route for a widget to present and dismiss an options
  page inside its owning notch, covering the other widgets temporarily.
- [ ] Authorize this route through the same manifest, admission, broker, revision
  checks and visibility/resource leases used by other addon surfaces.
- [ ] Preserve the underlying arrangement and open page. Restore them on Back,
  Escape, provider withdrawal/disable and termination. Define ownership and
  focus behavior for multiple displays and competing option pages.
- [ ] Connect Caffeinate's text/disclosure hit area to that route, with duration,
  keep-display-awake, stop and credits controls. Keep the cup as a separate toggle.
  At the icon-only size, expose options through the common widget context action while the cup
  continues toggling the session.

The current plugin contract exposes `widget`, `activity` and `notice` surfaces;
`PluginSurfaceHosting` has no contextual-page operation. A legacy host-only
`NotchEngine.setContextualPage` exists, but bypassing the common SDK to call it
from Caffeinate is outside the addon contract. No floating AppKit menu or detached
window should substitute for these options. Caffeinate's details stay passive
until this shared capability exists.
