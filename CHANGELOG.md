# 1.2.0

- Retain address-keyed icon delegates across metadata updates and column moves.
- Preserve wheel/arrow animations across unrelated refreshes and expose backend errors.
- Share direct typed RPC transport, snapshot scheduling and icon lookup across monitors.
- Separate short-lived input-region ownership from state polling; clear on lifecycle changes.
- Replace repeated geometry scans with dependency-driven host measurement.
- Match repeated host widgets by instance and support Omarchy webapp icons generically.
- Preserve visible focus during strip resizing and make focus queuing/busy state explicit.
- Address native snapshots and scrolling adjustments by workspace without changing focus.
- Repair closes under floating focus and across monitors; invalidate stale deferred repairs.
- Add protocol/native capability checks, all-monitor diagnostics and a read-only doctor.
- Consolidate source, installation, backups, migration and regression tests into one repository.
- Preserve the published plugin identity and existing personal alias, including clean Git-managed public updates and identity-aware diagnostics.
