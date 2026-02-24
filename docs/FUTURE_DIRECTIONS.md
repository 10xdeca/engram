# Future Directions: AI-Powered Audio & Video for Engram

*2026-02-24 — Research findings and recommendations*

## Overview

Engram's knowledge graph already glows when new concepts are ingested. The next step is to make it glow **in sync with narration** — an AI voice explains concepts while the graph lights up in real-time. This document captures the research into AI audio/video tools and recommends an implementation path.

## The Core Idea

```
Knowledge Graph ──► Claude generates narrated script with [CONCEPT:id] markers
                         │
                         ▼
                    TTS API returns audio + character-level timestamps
                         │
                         ├──► Audio file (MP3/WAV)
                         └──► Concept timestamp map:
                              {concept_id: "neural-networks", start: 2.3, end: 5.1}
                              {concept_id: "backpropagation", start: 5.2, end: 8.7}
                                   │
                                   ▼
                    Flutter audio player ──► currentPosition stream
                                   │
                                   ▼
                    activeConceptsProvider (derived from position + timestamp map)
                                   │
                                   ▼
                    glowNodeIdsProvider ──► GraphPainter renders glow
```

The key insight: **the glow system is already built.** `GraphPainter` renders cyan halos driven by `glowNodeIdsProvider`. We just need a new input source — audio playback position instead of one-shot ingest events.

---

## Text-to-Speech APIs

### Recommendation: ElevenLabs

ElevenLabs is the clear winner for our use case because of its **timestamps endpoint** — a single API call returns both audio and character-level timing data.

```
POST /v1/text-to-speech/{voice_id}/with-timestamps
```

Response includes:
```json
{
  "audio_base64": "...",
  "alignment": {
    "characters": ["N", "e", "u", "r", "a", "l"],
    "character_start_times_seconds": [2.3, 2.35, 2.4, 2.45, 2.5, 2.55],
    "character_end_times_seconds": [2.35, 2.4, 2.45, 2.5, 2.55, 2.7]
  }
}
```

From character-level data, we derive word boundaries (group between spaces), and from our pre-annotated concept markers, we get concept-to-timerange mappings.

### Comparison

| Feature | ElevenLabs | OpenAI TTS | Google Cloud TTS |
|---------|-----------|------------|-----------------|
| Voice quality | Excellent | Very good | Good–excellent |
| Voice cloning | Yes (instant + pro) | No | No |
| Word/char timestamps | Yes (character-level) | **No** | Via SSML marks (manual) |
| Streaming | Yes | Yes | Yes |
| Languages | 32 | ~57 | 75+ |
| Cost | ~$5/mo starter | $15/1M chars | $4–30/1M chars |

**Why not OpenAI TTS?** Cheaper but no timestamp support. You'd need a separate Whisper pass to get word timings, adding latency and complexity.

**Why not Google Cloud TTS?** Timestamps require manually inserting `<mark>` tags in SSML. Functional but tedious compared to ElevenLabs' automatic character alignment.

---

## AI Video Generation Landscape

### Generative Video Models (Not Our Path)

Models like Runway Gen-4, Veo 3.1, Kling 2.6, and Luma Ray3 generate cinematic footage from text prompts. These are impressive but solve a different problem — they generate *footage*, not *data visualizations*. We need deterministic, data-driven animation where specific nodes glow at specific times, not AI hallucinating what a glowing graph might look like.

| Model | Developer | Cost | Strength |
|-------|-----------|------|----------|
| Gen-4 Aleph | Runway | $0.15/sec | Best prompt adherence |
| Veo 3.1 | Google DeepMind | $0.20–0.40/sec | Native audio generation |
| Kling 2.6 | Kuaishou | Free tier | Up to 2-min, good physics |
| Luma Ray3 | Luma AI | From $7.99/mo | 4K HDR |

**Possible use:** B-roll and intro sequences for YouTube/social content, not for the core graph experience.

### Avatar/Talking-Head Video

HeyGen and Synthesia generate AI presenters reading scripts. Could be interesting for an AI tutor presenting alongside the knowledge graph, but not the priority.

| Tool | API? | Cost | Key Feature |
|------|------|------|-------------|
| HeyGen | Yes | From $29/mo | Streaming API, hyper-realistic avatars |
| Synthesia | Yes | Enterprise | SOC 2, 200+ avatars |
| D-ID | Yes | From $5.99/mo | Simple API |

### Programmatic Video (Our Territory)

For rendering animated graphics synced to a timeline, these are the relevant tools:

| Tool | Language | How it works | Best for |
|------|----------|-------------|----------|
| **Remotion** | React/TS | Write React components, render frame-by-frame to MP4 | Shareable video export |
| **Motion Canvas** | TypeScript | Programmatic animation with timeline editor | Math/code explainers (3Blue1Brown style) |
| **Manim** | Python | Mathematical animation engine | Math/graph visualizations |
| **Flutter (us)** | Dart | We already have the renderer | Real-time in-app experience |

---

## Recommended Implementation Path

### Phase 1: Real-Time Audio + Glow Sync (Option A) ← START HERE

Play narrated audio in the app while the knowledge graph glows in real-time. Interactive — user can pause, tap nodes, explore while listening.

**What already exists:**
- `GraphPainter` with glow halos + `glowNodeIdsProvider`
- `ForceDirectedLayout` with pinned nodes and animate-in
- `ExtractionService` with Claude forced tool use
- Visual Lab for testing effects

**What to build:**
1. ElevenLabs API client (REST, similar to `OutlineClient`)
2. Script generation: Claude produces narrated text with `[CONCEPT:id]` markers
3. TTS with timestamps: single API call returns audio + timing
4. Timestamp-to-concept mapper: parse markers, build timerange map
5. Flutter audio player (e.g., `just_audio` package)
6. Playback sync provider: `audioPosition` → `activeConceptsProvider` → `glowNodeIdsProvider`
7. Sustained glow mode: hold glow while concept is active, fade when topic moves on
8. Highlight propagation: BFS from active node, connected nodes get softer glow

### Phase 2: Screen-Record Export (Option D)

Simplest path to shareable video:
1. Play audio + glow in the Flutter app
2. Screen-record with macOS screen capture or `flutter_screen_recording`
3. Post-process in Descript/FFmpeg if needed

No duplicate rendering code. Quick path from interactive experience to distributable content.

### Phase 3: NotebookLM-Style Podcast Generation

Generate two-host conversational podcasts from the knowledge graph:
1. Claude generates a dialogue script from concepts + relationships
2. Synthesize with two different ElevenLabs voices
3. Interleave audio clips with pauses
4. Same timestamp → glow sync pipeline

**Alternative:** Google's NotebookLM Enterprise Podcast API is available (allowlisted for GCP customers). Open-source alternatives include Podcastfy (Python, supports 100+ LLMs + multiple TTS backends) and Open NotebookLM (Llama + MeloTTS, fully self-hosted).

### Phase 4: Remotion Video Export (Option B)

For polished, shareable explainer videos:
1. Rebuild graph renderer in React (Remotion is React-based)
2. `useCurrentFrame()` drives glow state at each frame
3. Perfect frame-accurate sync (deterministic, no runtime jitter)
4. Output: MP4 videos for YouTube, social media

**Trade-off:** Duplicates the Flutter renderer in React. Worth it only when there's demand for standalone video content. Consider sharing the data model (concepts, relationships, timestamps) between Flutter and Remotion via JSON.

### Phase 5: Motion Canvas Exploration

**Motion Canvas** (https://motioncanvas.io/) is a TypeScript-based programmatic animation tool designed for educational content — essentially "3Blue1Brown's tool but in TypeScript." Worth exploring for:
- Standalone educational videos about learning science concepts
- Animated explainers of how FSRS scheduling works
- Knowledge graph visualization tutorials
- Content that lives outside the app (YouTube, course material)

Unlike Remotion (which renders React components to video), Motion Canvas has a dedicated timeline editor and animation primitives purpose-built for math/code/diagram explanations. It could complement the in-app experience by producing polished educational content.

---

## Architecture Fit

The audio-sync feature slots into engram's existing layered architecture:

| Layer | New Components |
|-------|---------------|
| **Models** | `NarrationScript` (concept-annotated text), `TimestampedConcept` (concept ID + start/end time), `NarrationSession` (script + audio ref + timestamp map) |
| **Services** | `ElevenLabsClient` (TTS API), extend `ExtractionService` for script generation |
| **Providers** | `audioPlaybackProvider` (position stream), `activeConceptsProvider` (derived), `highlightPropagationProvider` (BFS decay) — all wired into existing `glowNodeIdsProvider` |
| **UI/Graph** | Extend `GraphPainter` for sustained glow mode, add audio player widget, new `NarrationScreen` or embed in Dashboard |
| **Engine** | Optionally extend `ForceDirectedLayout` to apply gentle attractive forces toward active nodes during playback |

The key Riverpod chain:

```
audioPositionProvider (stream from audio player)
    │
    ▼
timestampMapProvider (loaded from narration session)
    │
    ▼
activeConceptsProvider = derived(audioPosition + timestampMap)
    │
    ▼
highlightPropagationProvider = derived(activeConcepts + graphStructure)
    │                          BFS with decaying intensity
    ▼
glowNodeIdsProvider (ALREADY EXISTS — just wire it up)
    │
    ▼
GraphPainter renders glow (ALREADY EXISTS — extend for sustained mode)
```

---

## Cost Estimates

| Tool | Cost | Usage |
|------|------|-------|
| ElevenLabs Starter | $5/mo | 30K characters (~20 min of narration) |
| Claude API (script gen) | ~$0.05/script | Already using for extraction |
| Total Phase 1 | ~$5/mo | Negligible incremental cost |

---

## References

- [ElevenLabs TTS with Timestamps](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps)
- [ElevenLabs Timestamps Blog](https://elevenlabs.io/blog/new-text-to-speech-endpoints-with-timestamps)
- [Remotion](https://www.remotion.dev/)
- [Motion Canvas](https://motioncanvas.io/)
- [Podcastfy](https://github.com/souzatharsis/podcastfy) — open-source podcast generation
- [NotebookLM Enterprise Podcast API](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/podcast-api)
- [Runway API](https://docs.dev.runwayml.com/)
- [Mayer's Signaling Principle](https://en.wikipedia.org/wiki/Multimedia_learning) — g=0.38–0.53 for visual cues
- [Temporal Contiguity Effect](https://en.wikipedia.org/wiki/Multimedia_learning) — d=1.22 for synced audio+visual
- Engram Issue #74 — Video-synchronized knowledge graph highlighting
