# Navigate Berkeley

Plan your whole day in one sentence. You type your stops and constraints ("gym, dinner at Clark Kerr, USPS before 4:45, end at Moffitt"); the app returns 3 ranked multimodal plans (walk, bus, later scooter/BART) with a timeline and map, then keeps you on track live.

**Current goal:** a working web app that Ryan and ~10 friends use on real days. The test question: *do these plans beat what you'd have done with Google Maps?*

---

## How we work

- **Architect chat** (claude.ai): owns the big picture, makes decisions, picks the next step, reviews results. No code there.
- **Build sessions** (Claude Code, in this repo): one fresh session per roadmap step. Start in plan mode with: *"Read PROJECT.md and do step N."*
- **This file** is the shared memory. After each step, report back to the architect chat, then update **Status** and the **Decision log** below.

**Rules for build sessions**
1. Follow this spec. Don't change the architecture, stack, or contracts. If you think they should change, stop and write it under **Open questions**.
2. Do only the current step. Don't build ahead.
3. A step is done only when its **Done when** check passes, tested for real.
4. End every session with a short report: what works, what doesn't, what surprised you, what the next step needs to know.

---

## Scope for the friends test

**In:** text → stop read-back → 3 plans (walk + AC Transit bus) with timeline and map → live trip with "Re-plan from here". Berkeley-anchored trips. Starting point from GPS, the prompt, or by asking.

**Out (later):** calendar, iPhone widget, reflection screen, preferences editor (hard-code Ryan's), scooters/bikes, BART/SF/airport trips, full recalibration chat, App Store, push notifications.

---

## Architecture

```
 phone (web app) ──text──▶ [1] Intent ──ParsedPlan──▶ [3] Planner ──3 plans──▶ phone
                                                           │
                                                           ▼
                                                 [2] Travel times (OTP)
                                                           ▲
                         511.org GTFS + GTFS-RT ──────────┘   (one central poller, cached)
                         OpenStreetMap (East Bay)
```

**Layers stay separate.** Every future feature should slot into exactly one of them.

1. **Intent:** text → `ParsedPlan` (schema below). An LLM fills the schema. Places resolve against `places.json` (a hand-made list of Berkeley places) first, with a general geocoder only as fallback. The app shows the read-back so the user can fix mistakes before routing.
2. **Travel times:** OpenTripPlanner 2 (Docker) loaded with AC Transit GTFS + OSM. A real-time updater polls 511 GTFS-Realtime. Answers "A → B departing at T: duration and legs."
3. **Planner:** two separate steps.
   - **Build the time table:** query OTP for every pair of stops at the relevant departure times.
   - **Search orderings:** brute-force every order (≤6 stops), enforcing time windows, deadlines, the fixed start and end, and time spent at each stop. Score with the cost function and return the top 3 *different* plans.

**Stack**
- `otp/`: OTP 2 config, data download scripts
- `planner/`: Python 3.11+, FastAPI, pydantic
- `web/`: Next.js (React) as an installable web app, MapLibre GL for maps
- LLM: one call per request, structured JSON output
- Hosting: one small server (OTP + planner), web on a static host

**Pattern: poll the live feed once, centrally.** One server job fetches 511 every 30–60 s and caches it. Requests read the cache. Phones never call 511 directly.

**Pattern: log from day one.** Store every plan served, plus predicted vs. actual bus arrivals. This is the raw data for reliability scoring later.

---

## Contracts (drafts — make them final in step 2.1 and step 3.1)

```python
class Stop(BaseModel):
    place_id: str            # key in places.json, or "geo:<lat>,<lon>"
    name: str
    kind: Literal["start", "flexible", "deadline", "window", "anchored", "end"]
    window_start: time | None
    window_end: time | None  # deadline = window_end only
    dwell_min: int = 0       # time spent at the stop

class ParsedPlan(BaseModel):
    start: Stop
    stops: list[Stop]        # unordered except anchored ones
    end: Stop | None         # None = end at last stop
    depart_after: datetime
    raw_text: str

class Leg(BaseModel):
    mode: Literal["walk", "bus", "scooter", "bart"]
    minutes: int
    route: str | None        # "51B"
    board_at: str | None     # stop name
    depart: datetime

class PlanStop(BaseModel):
    stop: Stop
    arrive: datetime
    leave: datetime

class Plan(BaseModel):
    label: str               # "Fastest", "Walk + bus", "Package first"
    total_travel_min: int
    walk_min: int
    finish: datetime
    tradeoff: str            # ≤4 words: "free", "scooter ~$4"
    timeline: list[PlanStop | Leg]

class PlanResponse(BaseModel):
    plans: list[Plan]        # exactly 3 when possible, ranked
```

---

## Roadmap

### Week 1: Data and routing engine
- **1.1** Get a 511.org API token. Write `otp/fetch_data.sh` to download Bay Area GTFS (AC Transit at minimum) and an East Bay OSM extract.
  *Done when:* files download from one command.
- **1.2** Run OTP 2 in Docker with that data. Query one trip by API.
  *Done when:* Blackwell Hall → Moffitt returns a sensible walk/bus plan, and Ryan has checked it by actually doing the trip.
- **1.3** Turn on the GTFS-Realtime updater in OTP (central polling). Add a logger that stores predicted vs. actual arrivals.
  *Done when:* a plan's bus time changes when the live feed changes, and the log is filling.

### Week 2: Planner
- **2.1** Finalize the `ParsedPlan` / `PlanResponse` contracts in `planner/models.py`.
- **2.2** Build the travel-time table between all stops, calling OTP.
- **2.3** Search all orderings with constraints. Score with: total time + walk penalty + transfer penalty + deadline slack (hard-code Ryan's preferences). Pick the top 3 different plans.
  *Done when:* Ryan's sample day (RSF, USPS before 4:45, Clark Kerr dinner, end at Moffitt) returns 3 valid plans through `POST /plan`, with unit tests for each constraint type.

### Week 3: Intent and app
- **3.1** `places.json` with ~40 Berkeley places (name, aliases, coordinates). Intent endpoint: text → `ParsedPlan`, schema-validated, with geocoder fallback.
  *Done when:* 15 test prompts parse correctly, including vague ones ("gym", "Crossroads", "sometime before 4").
- **3.2** `web/`: build the approved screens (Welcome → Your plan read-back → Routing → Pick a plan → Live trip), first against fake responses, then the real API. Use the browser for location.
  *Done when:* the full flow works on Ryan's phone against the real backend.

### Week 4: Live updates and friends
- **4.1** Live trip: the phone sends its location every 30–60 s. The server checks the next leg against the live feed and offers to re-plan if a connection is missed. "Re-plan from here" button.
- **4.2** Deploy (HTTPS). Feedback button. Log every plan and whether it was followed.
  *Done when:* 5+ friends have used it on a real day and logged feedback.

---

## Status

| Step | State | Notes |
|---|---|---|
| Design mockups | ✅ done | Canvas: Navigate Berkeley (9 phone screens + web) |
| 1.1 | ✅ done | `./otp/fetch_data.sh` → `otp/data/ac-gtfs.zip` (feed valid 2026-08-09 → 2027-04-03) + `east-bay.osm.pbf` (34 MB). Needs `osmium-tool`. |
| 1.2 | ⏭ next | |

---

## Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-10-17 | Web app first; App Store only when live alerts need it | Ship and fix fast, no review process |
| 2026-10-17 | 511.org for GTFS + GTFS-RT; OTP 2 for routing | Free, covers AC Transit/BART/Muni; OTP handles multimodal + real-time |
| 2026-10-17 | Planner = time table + brute-force search, kept separate | ≤6 stops is small; better data and better search can change independently |
| 2026-10-17 | LLM only parses intent, never routes | Routing must be correct and explainable |
| 2026-10-17 | Berkeley `places.json` before any geocoder | Fixes the address problems other apps have |
| 2026-10-17 | Always 3 plans, each showing total time, walk minutes, finish time, one tradeoff; no risk tag | Ryan's call |
| 2026-10-17 | Preferences are soft scoring penalties, ≤10-word labels | Nudges, not hard rules |
| 2026-10-17 | Scope: trips that start or end in Berkeley (SF/airports later via BART) | Built for Berkeley students |
| 2026-10-17 | Design: Geist + Geist Mono, near-white, black accents, color only for modes | Clean, demo-ready look |
| 2026-10-17 | OSM = Geofabrik NorCal clipped with osmium to bbox -122.42,37.70,-122.10,38.02 (Richmond–San Leandro, shore–Orinda) | No ready-made East Bay extract; clipped file is small (34 MB) |

---

## Open questions
- Does Bear Transit publish a GTFS feed? (Ask Berkeley Parking & Transportation.)
- ~~What are 511's rate limits per token?~~ Confirmed: `RateLimit-Limit: 60` (per hour, per token). Polling every 30–60 s for step 1.3 would use it all or exceed it. Before 1.3: ask 511 for a higher limit, or poll only TripUpdates every 90–120 s?
- How much memory does OTP need for the East Bay extract? (Guess: 2–4 GB; extract is only 34 MB, so likely ~2 GB.) This decides hosting.
- Which LLM provider and model for intent parsing, and the cost per request?
