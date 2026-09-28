# REQUIRES resolution

Cascade resolves addon requirements as bounded data before it launches any provider. Resolution does not install software, open an application, ask for a permission, or execute addon code.

Requirements at the manifest root decide whether the addon can be admitted. Requirements attached to a feature decide only whether that feature is enabled. An absent source application can therefore block an `openInSourceApp` feature while an autonomous timer from the same addon remains available. `installed` means that the host catalog can verify the application is present; `running` additionally requires a live application. Neither state authenticates an addon.

Service versions describe the contract offered by a `PROVIDES` entry. They are resolved independently of the addon's package version. A requirement such as `>=1.0.0 <2.0.0` accepts compatible service releases even when the package itself has a different version.

Provider selection is deterministic. An explicit binding is considered first, then a still-valid persisted binding, then a matching host service, and finally installed providers in stable identity, version, and digest order. A persisted binding remains valid only while its consumer, provider, verified publisher identity, service version, and artifact digest still match. A bundle identifier from a manifest is never treated as proof of signed identity.

Bindings created for feature requirements include the feature ID. This permits two features in one addon to bind different compatible major versions or providers of the same service. Root requirements use a `nil` feature ID. When selecting for a feature, an exact feature-scoped explicit or prior binding is preferred; a valid root-scoped binding is a fallback. The resulting feature binding remains explicitly scoped and the broker must use that scope when issuing tokens in P2.

Disabled providers and providers lacking declared permission grants are unavailable. Cycles block the affected dependency closure with a readable reason. The v1 policy admits at most 32 addons per dependency closure, 128 dependency edges, and dependency depth 8; the installed catalog has a separate defensive bound of 1024 entries. A shared deterministic work budget counts both `anyOf` alternatives and attempted provider branches. Its count remains monotonic across failed branches and feature rollback; exceeding it returns `resolutionTooComplex` instead of continuing an unbounded search.

A service provider signed by a different publisher is denied unless the trusted host environment contains an exact grant for the consumer, requirement, and verified provider identity. Explicit provider selection and consent are separate: an explicit binding cannot grant data access. The manifest cannot grant this access to itself. The broker must revalidate the grant when a service is invoked.

Startup order is topological: a selected provider precedes its consumers. Reverse dependency edges let the runtime later re-evaluate only consumers affected by a provider being disabled, removed, or revoked.

Repeated service requirements within the same root or feature scope share one binding. Every active conjunctive version constraint must accept that binding; disjoint ranges block the scope. The bounded search can reconsider providers and `anyOf` branches when later conjuncts conflict. Distinct feature scopes remain independent.

Admission and choice rollback restore statuses, failures, startup state, bindings, and edges together. Only consumed search work survives rollback. The work ceiling is 256 provider/host attempts and `anyOf` alternatives. Policy inputs can tighten, but cannot raise, the host ceilings. Dependency depth counts edges (depth 8 permits a chain of 9 addons); the 32-addon closure includes its consumer. Each proposed edge validates the resulting graph, including cached provider chains and every affected ancestor when a feature adds dependencies.
