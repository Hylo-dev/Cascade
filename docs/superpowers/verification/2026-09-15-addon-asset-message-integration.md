> Current continuation: [Codex verification of 18 September](2026-09-18-addon-asset-message-integration.md). The routing and budget constraints reported below are historical.

# Asset message wiring and SDK client

Historical status as of 15 September: implementation in progress, no delivery verified at that time. [Plan](../plans/2026-09-15-addon-asset-message-integration.md).

Baseline verified before the change:795 tests/80 suites,400 identical app/test inputs,55 paths in the reviewed cumulative manifest. The last signed build and the relaunch PID28937 concern the previous component. The official main quota is61% used as of15 September2026,10:31:09UTC; ceiling65% to keep at least35%.

The increment connects the frames to the authenticated runtime, to its shared slots, to the quotas and to the canonical aliases, and adds a concrete SDK client to import/share/release images through an injected message channel. Negotiation1.2 is cumulative: the host enables it only with storage and asset support; the asset operations do not require the storage.own permission.

The end-to-end test will use a test-only bridge to the real runtime, codec, assembler, ImageIO and AssetState. It does not constitute a production IPC adapter or a qualification of the native launcher. No C0d gate is opened.

Pending as of 15 September (now completed in the verification of 18 September): implementation, targeted RED/GREEN, independent review, full suite on the frozen code, signed build, Applications update and verified relaunch.
