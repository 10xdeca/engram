# The Primer Bridge — data contract with `nickmeinhold/primer`

The CLI primer (the pedagogy lab) and Engram (the memory) share **data, not
code**. Two file formats, both produced by the primer today; Engram's side is
ingest (open task). All field names match Engram's own serialization
(`Concept.toJson` / `Relationship.toJson` / FSRS rating vocabulary) so ingest
is parsing, not translation.

## 1. Companion knowledge graphs — `<book>.graph.json`

Emitted by `primer graph` (and automatically by `primer new`) next to each
book. Example: `books/containers-and-comonads.graph.json` in the primer repo
(25 concepts, 36 relationships, generated 2026-06-11).

```json
{
  "concepts": [
    {
      "id": "container",
      "name": "Container",
      "description": "A data structure described by two questions: …",
      "sourceDocumentId": "containers-and-comonads.md",
      "tags": ["waypoint:1"]
    }
  ],
  "relationships": [
    {
      "id": "container--prerequisite--container-morphism",
      "fromConceptId": "container",
      "toConceptId": "container-morphism",
      "label": "must be understood before",
      "type": "prerequisite"
    }
  ]
}
```

- `type` is a `RelationshipType.name` (camelCase): `prerequisite`,
  `generalization`, `composition`, `enables`, `analogy`, `contrast`,
  `relatedTo`. The primer filters anything else out before writing.
- Every concept carries a `waypoint:N` tag binding it to the book's teaching
  road. **The waypoint tag is the whole bridge**: prose pedagogy and graph
  state reference each other through this one string.
- `sourceDocumentId` is the book filename — a book is a document source,
  ingestible the way wiki documents are.

## 2. Review events — `review_events.jsonl`

Appended by the primer's reading loop whenever the examiner mind (the Kernel)
delivers a trial verdict. One JSON object per line:

```json
{"ts": "2026-06-11T13:26:56.621959+00:00",
 "conceptId": "container",
 "rating": "good",
 "source": "primer-trial",
 "book": "Containers, Comonads, and Trust"}
```

- Rating mapping, fixed in the primer:
  - trial verdict `struggled` → `again`
  - trial verdict `passed` → `good`
  - final gate `[KERNEL ACCEPTS]` → `easy` (all waypoints)
- Events fan out to every concept tagged with the waypoints in the trial's
  scope.
- Location: `~/git/individuals/nickmeinhold/primer/review_events.jsonl`
  (gitignored there — it is learner-private state; Engram ingests and owns it).

## Engram-side ingest (to build)

1. Import a `.graph.json` as a document source (the `ingest_document` /
   `ingest_state` models fit): concepts and relationships merge by id —
   the primer's slugs are stable across regenerations of the same book.
2. Apply review events to each concept's `QuizItem` FSRS state in timestamp
   order, using the standard fsrs rating for `again`/`good`/`easy`.
3. Idempotency: `(ts, conceptId)` pairs are unique; keep a high-water mark.

## The return path (later)

Once ingest exists, the primer asks Engram-side state "what is due, what is
weak, where are the gaps" and opens the book at that node — FSRS-scheduled
*conversational* review. In the Diamond Age direction
([DIAMOND_AGE_PRIMER.md](DIAMOND_AGE_PRIMER.md)) the same query chooses
which story the book tells today.
