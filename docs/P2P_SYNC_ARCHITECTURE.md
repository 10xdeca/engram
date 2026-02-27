# Phase 7: Peer-to-Peer Sync

> Decision: **Pending.** Add optional peer-to-peer sync as an alternative transport alongside Firestore, enabling device-to-device changeset exchange without server mediation. Requires changes to tombstone lifecycle, peer discovery, and the sync transport abstraction.

## Motivation

### Data Sovereignty

Phases 1–6 establish local-first storage (Drift/SQLite is source of truth) and make Firestore optional for personal features. But "optional server" is not the same as "no server in the data path." Even with Phase 6 complete, multi-device sync still routes through Firestore:

```
Phone ─── changeset ──→ Firestore ─── changeset ──→ Laptop
```

Every review, every quiz answer, every concept extraction transits Google's infrastructure. For users, institutions, or jurisdictions that require data to remain on-premises or on-device, this is a non-starter.

P2P sync removes the server from the personal data path entirely:

```
Phone ←── changeset ──→ Laptop     (LAN / Bluetooth / WiFi Direct)
                  ↕
             Firestore              (opt-in, social features only)
```

### Key Questions for Data Sovereignty Review

1. **Jurisdiction**: Can we guarantee that personal learning data (quiz history, scheduling state, knowledge graph) never leaves the user's devices without explicit consent?
2. **Transit encryption**: What transport-layer encryption is required for LAN/Bluetooth sync? (TLS for mDNS, Bluetooth encryption profile, etc.)
3. **Social features**: Cooperative game data (challenges, nudges, glory board) inherently requires a shared state. Can a self-hosted relay replace Firestore for orgs that need on-prem?
4. **Audit trail**: Does P2P sync need to log which devices synced what data, when? CRDT HLCs provide causal ordering but not access-control audit.
5. **Right to deletion**: Tombstone purge across a P2P mesh is harder than star topology (see below). Can we guarantee deletion propagation?

## Architecture: Hybrid Star + P2P

Phase 7 does not replace the Firestore transport — it adds a second transport. The `CrdtSyncNotifier` already operates on a `SyncTransport` abstraction. P2P adds a `LocalNetworkSyncTransport` that implements the same interface.

```
┌─────────────────────────────────────────────────────────┐
│  CrdtSyncNotifier                                       │
│  ┌────────────────────┐  ┌────────────────────────────┐ │
│  │ FirestoreSyncTrans │  │ LocalNetworkSyncTransport  │ │
│  │ (cloud, social)    │  │ (LAN, Bluetooth)           │ │
│  └────────┬───────────┘  └────────────┬───────────────┘ │
└───────────┼───────────────────────────┼─────────────────┘
            │                           │
            ↓                           ↓
    ┌───────────────┐          ┌─────────────────┐
    │   Firestore   │          │  Peer device(s)  │
    │   sync_log    │          │  on local network │
    └───────────────┘          └─────────────────┘
```

**Sync priority**: P2P first (lower latency, no server cost), Firestore as fallback for cross-network sync and social features. If both transports deliver the same changeset, CRDT merge is idempotent — no conflict.

## What Changes from Star Topology

### 1. Tombstone Lifecycle (Critical)

**Current (star):** After syncing with Firestore, tombstones older than the pull bookmark are purged. Safe because Firestore is the single hub — if the hub has seen the deletion, all future peers will learn about it from the hub.

**P2P problem:** Device C might be offline for weeks. When it syncs directly with Device A (which already purged its tombstones), Device C never learns about deletions. Deleted concepts resurrect.

**Solutions (choose one):**

| Strategy | Pros | Cons |
|----------|------|------|
| **Per-peer version vectors** | Precise — purge only when all known peers have advanced past the tombstone | Requires tracking peer set + per-peer HLC watermarks. Peer set grows with device additions. |
| **Time-based retention** | Simple — keep tombstones for N days (e.g., 90), purge after | Devices offline longer than N days can resurrect ghosts. Bounded storage growth. |
| **Hub-mediated purge** | Keep current behavior — only purge after hub confirms all registered devices have synced | Requires the hub to know the device set. Breaks if hub is offline. Doesn't work for hub-less deployments. |
| **Never purge** | Simplest. Guaranteed correctness. | Unbounded storage growth. Mitigated by the fact that deletions are rare in Engram's additive graph model. |

**Recommendation for Phase 7a:** Start with **time-based retention (90 days)** as the default. Add a `tombstone_retention_days` config for orgs that need longer. For data sovereignty deployments that require guaranteed deletion propagation, offer **per-peer version vectors** as an opt-in mode.

**Right-to-deletion guarantee:** For GDPR/privacy compliance, the "never purge" strategy is actually *helpful* — tombstones propagate forever, ensuring deletion reaches all peers eventually. The risk is *premature* purge, not retention.

### 2. Peer Discovery

Devices need to find each other on the local network without a central registry.

| Protocol | Platform Support | Range | Notes |
|----------|-----------------|-------|-------|
| **mDNS/Bonjour** (`package:nsd`)| iOS, macOS, Android, Linux | LAN | Native, zero-config. Broadcast `_engram-sync._tcp` service. |
| **Bluetooth LE** (`flutter_blue_plus`) | iOS, Android, macOS | ~10m | Works without WiFi. Lower bandwidth (~1 Mbps). |
| **WiFi Direct** | Android, some Linux | ~100m | No router needed. Not supported on iOS. |
| **QR code pairing** | All platforms | Visual range | One-time setup. Exchange device IDs + shared secret for encryption. |

**Recommendation:** mDNS for LAN discovery (primary), QR code for initial pairing (trust establishment). Bluetooth as a stretch goal for true offline-offline sync.

### 3. Transport Protocol

Changesets are already serialized as JSON (table name → list of column maps). The P2P transport wraps this in a simple request/response protocol:

```
1. Discovery: mDNS announces _engram-sync._tcp with TXT record {nodeId, hlcWatermark}
2. Handshake: TLS connection, exchange node IDs, verify pairing (shared secret or cert)
3. Push: POST /changeset {changeset JSON, senderNodeId}
4. Pull: GET /changeset?since={hlc}&excludeNode={localNodeId}
5. Ack: 200 OK {highestMergedHlc}
```

The HTTP semantics match `FirestoreSyncTransport.pushChangeset()` / `pullChangesets()` exactly, so the `SyncTransport` interface doesn't need to change — only the implementation differs.

### 4. Conflict-Free Guarantee

P2P doesn't change CRDT merge semantics — the same G-Set union and LWW-Register rules apply regardless of transport. Two devices that sync via P2P produce the same merged state as if they'd both synced through Firestore. This is the core CRDT guarantee: **merge is commutative, associative, and idempotent.**

The only difference is that P2P sync may deliver changesets in a different order than Firestore-mediated sync. CRDTs handle this by design — order doesn't matter for convergence.

### 5. Social Features: What Stays Server-Mediated

| Feature | P2P Possible? | Reason |
|---------|--------------|--------|
| Personal quiz review | Yes | Single-user, single-device-set |
| Knowledge graph edits | Yes | CRDT merge, no central authority needed |
| Friend discovery | No | Requires central index of wiki URL hashes |
| Challenges / nudges | Partially | Could P2P between co-located friends, but cross-network needs relay |
| Glory board rankings | No | Global aggregation requires central compute |
| Guardian assignments | No | Cluster-level arbitration needs single authority |
| Team goals | Partially | Contributions are G-Counters (P2P-safe), but goal creation/status needs coordinator |

**Principle:** Personal learning is fully P2P-capable. Social features degrade gracefully — work locally when co-located, fall back to server for cross-network coordination.

## Data Sovereignty Deployment Model

For organizations that need full control:

```
┌──────────────────────────────────────────────┐
│  Organization Network (on-prem / VPC)        │
│                                              │
│  ┌──────────┐  P2P   ┌──────────┐           │
│  │ Device A │←──────→│ Device B │           │
│  └────┬─────┘        └────┬─────┘           │
│       │                   │                  │
│       └───────┬───────────┘                  │
│               ↓                              │
│  ┌────────────────────────┐                  │
│  │  Self-hosted relay     │  (replaces       │
│  │  (optional)            │   Firestore)     │
│  └────────────────────────┘                  │
│                                              │
│  No data leaves this boundary.               │
└──────────────────────────────────────────────┘
```

**Self-hosted relay** could be a simple Dart server running the same `mergeChangeset()` logic as the client — it's just another CRDT peer. Postgres or SQLite as storage. This replaces Firestore for orgs that can't use Google Cloud.

**Claude API**: Extraction still needs the Anthropic API. For air-gapped deployments, support local LLM inference (Ollama, llama.cpp) as an alternative extraction backend. This is a separate concern from sync architecture.

## Implementation Sub-Phases

### Phase 7a: Transport Abstraction + Tombstone Policy

- Extract `SyncTransport` interface from `FirestoreSyncTransport`
- Add `tombstone_retention_days` config (default 90)
- Replace `purgeTombstones(before: hlc)` with retention-aware purge
- Unit tests for tombstone retention edge cases (offline > retention period)

### Phase 7b: LAN Sync Transport

- `LocalNetworkSyncTransport` using `package:nsd` for mDNS discovery
- TLS-encrypted HTTP server on each device (self-signed certs, pinned at pairing)
- QR code pairing flow (exchange node IDs + shared secret)
- Push/pull changeset exchange over LAN
- Integration tests with two in-memory Drift databases syncing via localhost

### Phase 7c: Multi-Transport Orchestration

- `CrdtSyncNotifier` runs P2P + Firestore transports concurrently
- Deduplication: same changeset from both transports merged idempotently (already guaranteed by CRDT)
- Priority: P2P first (lower latency), Firestore as fallback
- UI: sync status indicator shows transport type (LAN / Cloud / Offline)

### Phase 7d: Self-Hosted Relay (Optional)

- Dart server package (`engram_relay`) with `mergeChangeset()` + REST API
- Docker image for easy deployment
- Config option to replace Firestore URL with self-hosted relay URL
- Social feature support (friend discovery, challenges) on the relay

### Phase 7e: Per-Peer Version Vectors (Optional)

- `PeerRegistry` tracks known peers + their last-seen HLC
- Tombstone purge requires all registered peers to have advanced past the tombstone HLC
- Stale peer detection: peers not seen for > `peer_stale_days` are removed from registry
- For data sovereignty deployments that require guaranteed deletion propagation

## Security Considerations

| Concern | Mitigation |
|---------|-----------|
| **Unauthorized peer** | QR code pairing establishes shared secret. Reject unknown node IDs. |
| **Eavesdropping** | TLS for all P2P connections. Bluetooth encryption profile. |
| **Replay attacks** | HLC monotonicity — replayed changesets have stale HLCs, merge is idempotent. |
| **Malicious peer** | Trust is per-pairing. Revoke by removing peer from `PeerRegistry`. |
| **Data exfiltration** | P2P sync only shares data with explicitly paired devices. No broadcast. |
| **Key management** | Self-signed TLS certs pinned at pairing time. Rotate via re-pairing. |

## Open Questions

1. **Bandwidth**: How large are typical changesets after a week offline? If they exceed Bluetooth LE capacity (~1 Mbps), should we compress or paginate?
2. **Battery**: Does mDNS discovery drain battery on mobile? Should it only run when the app is foregrounded?
3. **Multi-user P2P**: Could two *different* users sync knowledge graphs P2P (e.g., study group sharing concepts)? This crosses the personal/social boundary and needs careful access control.
4. **Conflict UI**: CRDTs guarantee convergence but not user intent. Should we surface "your phone and laptop both reviewed the same card differently" as a notification?

## Dependencies

- **Phase 6 (Firestore Optional)**: Must be complete — P2P assumes personal features work without Firestore
- **`package:nsd`**: mDNS/DNS-SD for Flutter (pub.dev/packages/nsd)
- **`package:shelf`**: Dart HTTP server for P2P transport endpoint
- **Self-signed TLS**: `dart:io` `SecurityContext` for cert pinning

## References

- Ink & Switch: "Local-First Software" — Section 4 (networking)
- Martin Kleppmann: "Making CRDTs Byzantine Fault Tolerant" (2022)
- Automerge: automerge.org — reference CRDT implementation with P2P sync
- Hypercore Protocol: hypercore-protocol.org — P2P data replication
- libp2p: libp2p.io — modular P2P networking stack
- GDPR Article 17: Right to Erasure — tombstone propagation implications
- Hybrid Logical Clocks: "Logical Physical Clocks" (Kulkarni et al., 2014)
