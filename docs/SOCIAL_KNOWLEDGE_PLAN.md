# Social Knowledge Building & Competition

> Vision: A federated knowledge graph where each learner has their own evolving
> view. Graphs grow as you learn; you can browse how others structure the same
> concepts, selectively adopt relationships, compete on quiz items, and
> negotiate "ground truth" collaboratively.

## Core Principles

1. **Personal graph is sovereign** — your concepts, relationships, quiz items,
   and FSRS scheduling state belong to you. Your devices sync automatically
   via the CRDT layer (Phase 4, row-level LWW).
2. **Concepts are shared, opinions differ** — a concept like "Docker" exists
   once in a shared pool, but the *relationships* around it ("Docker is
   prerequisite of Kubernetes" vs "Docker is related to Kubernetes") are
   per-user opinions that can diverge intentionally.
3. **Adoption by choice, not automatic merge** — when you see someone's
   different relationship structure, you can inspect it, compare it to yours,
   and adopt it with a tap. This is explicit, not background sync.
4. **Quiz formats evolve** — flash cards are the starting point. The quiz item
   model should be extensible toward multiple-choice, visual quizzes, and
   diagram-based questions without breaking the knowledge graph or FSRS state.

## Data Model Evolution

### Current (Personal Graph)

```
User A's graph:
  concepts: [Docker, Kubernetes, Pods]
  relationships: [K8s --prerequisite--> Docker, Pods --composition--> K8s]
  quizItems: [personal FSRS state per item]
```

### Future (Federated Graph)

```
Shared concept pool:
  concepts: [Docker, Kubernetes, Pods, ...]  (canonical definitions)

User A's view:
  relationships: [K8s --prerequisite--> Docker]  (A's opinion)
  quizItems: [A's FSRS state]
  adoptedFrom: {r42: userB}  (tracking provenance)

User B's view:
  relationships: [K8s --enables--> Docker]  (B's opinion)
  quizItems: [B's FSRS state]
```

### Key Schema Changes

1. **`owner_id`** on relationships, quiz items — distinguishes "mine" from
   "theirs" without separate tables
2. **`provenance`** on adopted relationships — tracks who you adopted from and
   when, enabling "undo adoption" and social credit
3. **`quiz_format`** enum on quiz items — `flashcard | multipleChoice | visual |
   diagramLabel` — extensible without schema migration
4. **`alternatives`** JSON on multiple-choice quiz items — stores distractor
   options alongside the correct answer
5. **Concept deduplication** — shared concept pool uses content-addressable IDs
   (hash of name + source) or server-assigned canonical IDs after merge

## Social Features

### Browse & Compare

- View another user's relationship graph overlaid on yours (different edge
  colors)
- Diff view: "User B has 3 relationships you don't, you have 2 they don't"
- Tap any foreign relationship to preview, then adopt or dismiss

### Selective Adoption

- One-tap adopt: copies a relationship into your graph with provenance metadata
- Batch adopt: "adopt all of User B's relationships for this concept cluster"
- Undo adoption: removes the relationship and its provenance record

### Competition

- Challenge a friend: "quiz me on your mastered concepts" (existing mechanic)
- Leaderboard: who has the most stable (high-retrievability) graph?
- Concept coverage race: who can master a topic cluster first?

### Negotiation

- Propose a relationship change to another user (like a PR)
- Vote on contested relationships within a wiki group
- "Ground truth" emerges from consensus, not authority

## Quiz Format Evolution

### Phase 1: Current (Flash Cards)

```dart
QuizItem(question: 'What is Docker?', answer: 'A container runtime')
```

### Phase 2: Multiple Choice

```dart
QuizItem(
  question: 'What is Docker?',
  answer: 'A container runtime',
  format: QuizFormat.multipleChoice,
  alternatives: ['A programming language', 'An operating system', 'A database'],
)
```

Distractors can be:
- **AI-generated** — Claude generates plausible wrong answers from nearby
  concepts in the graph
- **Graph-derived** — siblings of the correct concept (same parent, same
  relationship type) make natural distractors

### Phase 3: Visual Quizzes

- "Which node in this subgraph represents Docker?" (highlight the correct node)
- "Draw the missing relationship" (given two concepts, name the edge)
- "Label this diagram" (given a subgraph, fill in concept names)

### Phase 4: Concept Splitting Quizzes

- "Docker was split into Docker Images, Docker Containers, and Docker Networks.
  Which sub-concept does this description belong to?"
- Tests understanding at the sub-concept level after a split

## Implementation Phases

### Phase S1: Shared Concept Pool

- Server-side concept deduplication (name + source hash → canonical ID)
- Personal graphs reference shared concept IDs
- No relationship sharing yet — just concepts

### Phase S2: Relationship Browsing

- API to fetch another user's relationships for a given concept cluster
- Overlay UI on the knowledge graph (foreign edges as dashed/colored lines)
- Diff computation (your edges vs theirs)

### Phase S3: Selective Adoption + Provenance

- `adoptRelationship(fromUser, relationshipId)` — copies into personal graph
- Provenance tracking on adopted relationships
- Undo adoption

### Phase S4: Multiple Choice + Visual Quizzes

- `QuizFormat` enum on `QuizItem`
- AI distractor generation during extraction
- Graph-derived distractors from sibling concepts
- New quiz UI widgets per format

### Phase S5: Negotiation + Consensus

- Relationship proposals (like PRs)
- Wiki-group voting on contested edges
- Consensus threshold for "ground truth" relationships

## Dependencies

- **CRDT sync (Phase 4, #41)** — personal graph sync must work first
- **Concept embeddings (#39)** — enables smart deduplication and distractor
  generation
- **Local-first Drift (#40)** — all social features read from local DB, server
  pushes updates via changeset sync

## Open Questions

1. Should concept *definitions* (description field) also be per-user, or is
   the shared pool's definition canonical?
2. How to handle concept splits in a shared pool — does splitting create new
   shared concepts, or personal sub-concepts?
3. Should FSRS state ever be shared (e.g., "this concept is hard for 80% of
   learners")?
4. How to prevent spam in relationship proposals / voting?
