# Sandhai: deferred Phase 4.1 TODO

Created: 21 October 2026
Status: Pending — deferred at your request.

These are refinements to the Phase 4.1 audit instructions. They are not recorded as completed implementation or verification.

- [ ] Assign actual file ownership before parallel edits. Geospatial and Security own separate regression tests; Testing focuses on feed lifecycle and integration coverage. Coordinate shared fixtures and application-source changes.
- [ ] Let the main agent control the connected phone, USB forwarding, and shared development emulators. Isolate parallel tests by ports/project IDs or serialize shared-state tests. Preserve fixtures and restore phone settings.
- [ ] Use the working full JDK 21 configuration for Android builds. Document a persistent installation and selection instead of depending on the temporary JDK path.
- [ ] Report local, staging, and production verification separately. Keep cloud index verification blocked until actual queries execute successfully against a configured cloud Firestore instance; index declarations and emulator passes are insufficient.
- [ ] Keep the 100,000-offer benchmark optional for the controlled investor demo. Record measured query/candidate counts and limitations without inferring cloud scalability from emulator timings.
- [ ] Define whether vendor approval revocation hides existing published offers or only blocks further publication before classifying existing behavior as a defect.
- [ ] Keep 5 km explicitly defined as a discovery filter, not a geographic access-control guarantee.
- [ ] Have the main agent integrate findings, resolve conflicts, run final checks, and report which subagents actually ran, their file changes, and independent test results.

## Current planning context

Phase 4 was reported locally verified on Android and Chrome. A completed Phase 4.1 audit report has not been provided in this conversation. Cloud index verification and production validation remain outstanding.

The immediate investor-access task is to prepare a cloud-connected staging build and a remotely accessible HTTPS web preview, with an optional Android build using the same staging backend.
