# iOS Bluetooth Mesh Chat App Plan

This document translates your idea into an implementable iOS architecture: a chat app that works **without internet, SMS, or cellular**, by relaying messages device-to-device over local wireless links.

## 1) Product idea in one line
Build an **offline, peer-to-peer mesh messenger** where nearby phones relay messages hop-by-hop until they reach more distant users.

## 2) Important iOS reality check (very important)
On iOS, pure “always-on Bluetooth mesh like background infrastructure” is constrained by platform rules. A practical approach is:

- Use **Multipeer Connectivity (MPC)** as the main transport layer (it uses Bluetooth + peer-to-peer Wi-Fi + local network automatically).
- Optionally add **CoreBluetooth** only when you specifically need BLE custom control.
- Design for **foreground and near-foreground reliability** first.

This still matches your core goal: messages can move locally between nearby users without internet.

## 3) How message relay works
Example with 10 users in a line:

1. User A creates a message `M` for User J.
2. A broadcasts `M` to nearby peers (B/C).
3. B stores `M` and forwards to its peers (C/D).
4. Each phone repeats this process while preventing duplicates.
5. J eventually receives `M` once any relay path reaches J.

That is a **store-and-forward mesh**.

## 4) Core architecture

## 4.1 App layers
- **UI Layer (SwiftUI)**
  - Chat list, conversation view, nearby status, delivery indicators.
- **Messaging Core**
  - Message model, deduplication, routing metadata, retry policy.
- **Mesh Transport Layer**
  - `MultipeerConnectivity` session management.
  - Peer discovery + secure handshake.
- **Persistence Layer**
  - Local DB (Core Data/SQLite) for messages, peers, and relay state.

## 4.2 Data model (minimum)
```swift
struct MeshMessage: Codable {
    let id: UUID
    let senderID: String
    let recipientID: String? // nil for group channel
    let timestamp: Date
    let bodyCiphertext: Data
    let hopCount: Int
    let ttl: Int
    let signature: Data
}
```

- `id`: global dedup key.
- `ttl`: limits endless looping.
- `hopCount`: telemetry + routing heuristics.

## 4.3 Relay algorithm
For each incoming message:

1. Validate signature/decrypt envelope.
2. If `id` already seen → drop.
3. Save locally and mark delivered if intended recipient.
4. If `ttl > 0`, decrement and forward to eligible peers.
5. Record forwarding outcome for analytics/debug.

## 5) Security model (must-have)
- End-to-end encryption (recipient public key).
- Per-device keypair generated on first launch.
- Signed envelopes to prevent spoofing.
- Optional safety number / key verification UI.
- Local DB encrypted at rest.

## 6) UX expectations you should set early
- “Works best when people periodically open the app and are near others.”
- Delivery may be delayed when mesh is sparse.
- Show status like:
  - Sent to mesh
  - Relayed by N peers
  - Delivered
  - Expired (TTL reached)

## 7) MVP scope (recommended)
Phase 1 should avoid over-complexity:

- 1:1 chat only (no groups yet).
- Foreground relaying.
- Nearby peer discovery.
- Dedup + TTL forwarding.
- Basic E2E encryption.
- Conversation history stored locally.

## 8) Implementation roadmap

### Phase 0 — Technical spike (1–2 weeks)
- Validate MPC peer discovery/connectivity across devices.
- Test relay chain with 3–5 phones.
- Measure latency and packet loss.

### Phase 1 — MVP (3–6 weeks)
- Identity + keys.
- 1:1 encrypted messaging.
- Mesh relay with dedup/TTL.
- Basic chat UI + delivery states.

### Phase 2 — Reliability
- Retry/backoff strategy.
- Better peer scoring (avoid noisy peers).
- Message chunking for larger payloads.

### Phase 3 — Product polish
- Group chat.
- Attachments.
- Better diagnostics and onboarding.

## 9) Testing strategy
- Simulator is limited for Bluetooth behavior; test mostly on physical iPhones.
- Build an internal test matrix:
  - 2, 3, 5, 10 devices.
  - Users walking apart/together.
  - App foreground/background transitions.
- Add deterministic unit tests for:
  - Deduplication logic
  - TTL expiry
  - Serialization and signature checks

## 10) Risks and mitigations
- **iOS background limitations** → design expectations and optimize for foreground relay windows.
- **Battery use** → adaptive scanning intervals.
- **Duplicate storms** → message ID cache + TTL + forwarding cooldown.
- **Trust/safety concerns** → signatures, key verification, abuse controls.

## 11) Suggested Swift package/module split
- `MeshCore` (models, relay logic, crypto adapters)
- `MeshTransport` (MPC wrappers, peer state machine)
- `MeshStorage` (message/peer persistence)
- `MeshUI` (SwiftUI screens and view models)

## 12) First engineering tasks to start tomorrow
1. Create a new iOS app target `MeshChat`.
2. Build `PeerService` around `MCNearbyServiceAdvertiser`, `MCNearbyServiceBrowser`, and `MCSession`.
3. Send/receive a signed `MeshMessage` JSON payload between two devices.
4. Add local “seen message IDs” cache and drop duplicates.
5. Add relay forward method with `ttl - 1`.
6. Display live console-style events in-app for debugging (peer joined, message relayed, delivered).

---

If you want, the next step is I can generate a concrete Swift skeleton (protocols, classes, and starter code) for `PeerService`, `MeshRouter`, `CryptoService`, and a basic `ChatViewModel` so your team can start coding immediately.
