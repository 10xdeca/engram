# Engram

**ENGRAM Notices Gaps, Recursively Awakens Meaning**

*The curiosity engine that cartographs the topology of your ignorance, prowls the web for what would bridge it, and weaves each discovery into the living graph — until the blank spaces on the map begin to glow.*

---

Engram reads an [Outline](https://www.getoutline.com/) wiki, uses Claude to extract a knowledge graph of concepts and relationships, and teaches it back through FSRS spaced repetition. The knowledge graph is alive — a force-directed network that pulses with mastery, where nodes glow grey through red through amber to green as you learn, and newly ingested concepts settle into position among their neighbors like thoughts finding their place.

But Engram is more than a flashcard app with a pretty graph. It's a system that *notices what you don't know yet* and can tell you *why it matters* in terms of the structure of what you already understand. Two clusters with no bridge between them? The curiosity engine searches your wiki for the document that would create that bridge, predicts the new edges it would form, and offers to ingest it with a single tap. Then it shows you the new nodes glowing cyan as they connect to your existing knowledge — so you can *see* your understanding grow.

The whole thing emerged from a recursive accident: ingesting an Anthropic course on agent skills revealed that the ingestion pipeline itself should be an agent skill, and writing the scheduling constraints for that skill revealed that FSRS could close the loop between extraction and scheduling that SM-2 never could. A system for discovering connections discovered a connection about itself. [The full story](docs/ORIGIN_STORY.md) is worth reading.

## What It Does

- **Knowledge extraction** — Point at an Outline wiki collection. Claude extracts concepts, typed relationships (prerequisite, generalization, composition, enables, analogy, contrast), and quiz items with predicted difficulty scores. The extraction prompt receives past prediction accuracy so it calibrates over time.

- **FSRS spaced repetition** — Not just "review in 3 days." Claude predicts quiz item difficulty at extraction time; FSRS uses that prediction as initial D₀. Per-concept desired retention adapts to graph position — hub concepts get 0.95, leaves get 0.85, guardian-protected clusters get 0.97. The scheduling and extraction aren't just connected, they're *conspiring*.

- **The living graph** — A custom force-directed visualization where existing nodes are pinned as immovable anchors while new nodes animate into position via physics simulation. Mastery colors the nodes. Typed relationships color and shape the edges — dashed lines for analogies, arrowheads for prerequisites. Tap a node to see its mastery state; tap an edge to see its relationship type.

- **The curiosity engine** — `GapAnalyzer` detects four kinds of structural gaps: cluster isolation, structural thinness, relationship type gaps, and critical bottlenecks. `RecommendationService` searches your wiki for documents that would bridge those gaps, scores them with Claude, and predicts what new edges they'd create. One-tap ingest, then "View in Graph" — and you watch new nodes glow cyan as they settle among their neighbors.

- **The cooperative game** — The knowledge graph reimagined as a synaptic web. Team members are neurons; concepts are synapses. Guardians volunteer to protect concept clusters. Team goals create cooperative targets. Entropy storms and relay challenges create shared urgency. When the network is neglected, it doesn't just fade — it fractures through four catastrophe tiers. The drama comes from watching it break; the joy comes from rebuilding it together.

- **Social learning** — Wiki-URL-based friend discovery, challenges (test a friend on your mastered cards), nudges (remind about overdue reviews), and a glory board leaderboard with guardian/mission/goal points.

## Architecture

- **Flutter** + **Riverpod** (manual, no codegen) for state management
- **Firebase Auth** (Google + Apple Sign-In) for authentication
- **Cloud Firestore** for storage (migrating to local-first Drift/SQLite — see `docs/LOCAL_FIRST.md`)
- **Claude API** (`anthropic_sdk_dart`) for extraction, difficulty prediction, gap evaluation, and recommendation scoring
- **Custom `ForceDirectedGraphWidget`** — `CustomPainter` + Fruchterman-Reingold layout with velocity-based physics, viscous edge damping, circle initial placement, centering gravity, and incremental pinned layout
- **FSRS** (`fsrs` package) — pure-function scheduling with extraction-informed difficulty

See `CLAUDE.md` for the full architecture reference.

## Development

```bash
flutter pub get
flutter analyze
flutter test          # 700+ tests
flutter run -d macos
```

## Design Documents

| Document | What it captures |
|----------|-----------------|
| [`ORIGIN_STORY.md`](docs/ORIGIN_STORY.md) | How a routine transcription spiraled into a paradigm shift, and why the blank spaces were never empty |
| [`THROUGH_THE_LOOKING_GLASS.md`](docs/THROUGH_THE_LOOKING_GLASS.md) | The session where ingesting a course about skills created a skill about ingesting courses |
| [`SYNAPTIC_WEB_GAME_DESIGN.md`](docs/SYNAPTIC_WEB_GAME_DESIGN.md) | The cooperative network game — catastrophe tiers, guardians, entropy storms |
| [`FSRS_MIGRATION.md`](docs/FSRS_MIGRATION.md) | Why FSRS closes the extraction-scheduling loop that SM-2 never could |
| [`LOCAL_FIRST.md`](docs/LOCAL_FIRST.md) | Device as source of truth, server as sync peer |
| [`CRDT_SYNC_ARCHITECTURE.md`](docs/CRDT_SYNC_ARCHITECTURE.md) | How knowledge graph operations map to CRDTs |
| [`GRAPH_STATE_MANAGEMENT.md`](docs/GRAPH_STATE_MANAGEMENT.md) | Why Riverpod won, and how to normalize incrementally |

---

*The blank spaces were never empty. They were waiting to glow.*
