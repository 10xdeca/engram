# The Diamond Age Direction — Engram becomes the Book

**Decision (Nick, 2026-06-11):** flashcards are removed as Engram's learning
surface. Engram becomes the Young Lady's Illustrated Primer: **beautiful
illustrated stories that teach difficult concepts**, with the learner as
protagonist, followed by warm Socratic dialogue instead of quiz items. The
knowledge graph and FSRS remain — as the book's hidden spine, deciding *which
story the book tells today*.

> "Flash cards are shit — the primer is the way to learn things."

## What teaching looks like

1. **The book opens on a story.** A generated, illustrated, narrated story
   that teaches the concepts due for review or sitting in a detected gap.
   The learner is the protagonist; the story is built from what the book
   knows about them.
2. **The margin darkens.** After the story, a short Socratic trial — the
   two-register pattern proven in the CLI primer (`nickmeinhold/primer`):
   a warm teacher voice and a cold-but-fair examiner voice, with the
   kind-challenge rule (the instant the learner wobbles, all sternness
   drops; the arc "I feel dumb → oh, I see it" is the learning event).
3. **The spine updates.** Trial verdicts become FSRS ratings; mastery moves;
   the living graph glows; tomorrow's story is chosen accordingly.

**The story is the review.** Spaced repetition survives — only the *surface*
changes, from cards to narrative + dialogue.

## Why this is mostly an upgrade, not a rebuild

Engram already has the story spine and doesn't know it:

| Already shipped | Becomes |
| --- | --- |
| Narration pipeline (`narration_service.dart`: Claude writes a concept-annotated script → ElevenLabs synthesizes with character timestamps → time-aligned concept markers) | The **storybook engine**. Script generation upgrades from "narrate these concepts" to story-shaped: beats, stakes, protagonist framing. Concept markers already align highlights to audio; **per-beat illustrations swap on the same timestamps.** |
| `QuizItem` per-concept FSRS state | Unchanged — but rated by trial verdicts, not card self-grades (struggled→again, passed→good, final-gate→easy) |
| `GapAnalyzer` + `RecommendationService` | The book's editorial voice: which story needs telling |
| `SessionMode` / quiz session state | A **dialogue session** over the concepts FSRS+gaps selected |
| `extraction_service.dart` (Claude tool-use) | The same pattern drives the two dialogue minds in Dart |
| ElevenLabs client | The book's voices (the CLI primer uses two distinct voices — teacher/examiner — to signal register change; keep that) |

## What's genuinely new

- **Story-shaped script generation.** The craft is already worked out in the
  CLI primer's books — see the `## story` sections in
  `nickmeinhold/primer/books/` and the `.primer.md` authored from
  `ai-mathematician-demo` ("you once tore a theorem out of a textbook on
  purpose…"). Protagonist framing is the active ingredient.
- **Illustrations.** Per-beat image generation. The hard requirement is
  **style consistency across beats** — one visual voice per book, not
  twenty unrelated good images. This is the first design question to
  settle (model choice, style anchoring, character consistency).
- **The dialogue minds in Dart.** Port the *system-prompt craft*, not the
  Python: `primer.py`'s `primer_system`/`kernel_system` templates, the
  SUMMON / TRIAL COMPLETE / NOTE LEARNER / AMEND BOOK token protocol, and
  the kind-challenge rules verbatim. Mic input in Flutter is an open
  question (speech_to_text plugin vs whisper).
- **The learner file.** A living cross-subject profile (which pictures land,
  pace, trip-wires, what restores them) read by both minds and updated from
  margin notes each session — Nell's book knew Nell. Reference
  implementation: `learner.md` + `[NOTE LEARNER: …]` in the CLI primer.

## Relationship to the CLI primer

`nickmeinhold/primer` stays alive as **the pedagogy lab**: prompt-craft
iterates there in minutes (it's ~600 lines of Python over headless Claude)
and proven patterns port into Engram. The data contract between the two —
companion knowledge graphs in Engram's schema and FSRS-ready review events —
is specified in [PRIMER_BRIDGE.md](PRIMER_BRIDGE.md).

## Sequence

1. Ingest the bridge files (graphs + review events) — proves the spine moves
   from external dialogue sessions. ([PRIMER_BRIDGE.md](PRIMER_BRIDGE.md))
2. Story mode v1: story-shaped narration scripts + per-beat illustrations on
   the existing timestamp alignment. No dialogue yet — the book *reads to
   you* beautifully first.
3. Dialogue sessions replace quiz sessions: two minds, trials, verdicts →
   FSRS. Flashcard UI retires.
4. The editorial loop: FSRS + GapAnalyzer choose the day's story; the
   learner file personalizes it.
