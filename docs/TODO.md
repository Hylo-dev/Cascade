# Addon TODO

## ADDON-NOTCH-OPTIONS: contextual options inside the notch

- [ ] Qualify the implemented shared addon/SDK options route in the production
  runtime transport, including manifest/admission/broker/resource authorization.
- [ ] Complete native input and multiple-display acceptance for the shared container:
  Back, Escape, withdrawal/disable, termination and restoration of the underlying
  arrangement, ordinary page and contextual slot.
- [x] Connect Caffeinate's text/disclosure hit area to the shared host container, with duration,
  keep-display-awake, stop and credits controls. Keep the cup as a separate toggle.
  At the icon-only size, expose options through the common widget context action while the cup
  continues toggling the session.

The shared addon contract, runtime validation and native options container exist.
The builtin PluginHost compatibility bridge now uses that container through
`PluginSurfaceHosting`, with a bounded options tree sharing the ordinary document's
authorization table and budgets. Caffeinate's cup remains independent, and its
title/disclosure and common widget context action open the same page after broker
acceptance. It does not use `NotchEngine.setContextualPage` or a detached options window.

The checked item records implemented wiring and automated coverage. Real native
input acceptance and performance measurements remain separate qualification;
an inaccessible AX tree or failed screen capture does not count as a UI pass.
External native launcher qualification remains on hold. See
[`widget-options.md`](addons/widget-options.md) for the contract and Caffeinate usage.
