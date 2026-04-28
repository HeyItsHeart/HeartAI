# HeartAI — Complete System Specification
### Version 1.0 | Architecture + Implementation Guide

---

## 1. SYSTEM OVERVIEW

HeartAI is a personalized, long-term AI companion designed to operate across four domains:
**Coding · Creativity · Productivity · Learning**

Unlike generic chatbots, HeartAI maintains continuity across sessions, adapts its communication style to the user, automatically detects what mode of assistance is needed, and builds a structured memory of user preferences, projects, and habits over time.

---

## 2. FEATURE BREAKDOWN

### 2.1 Personality Engine
- Tone adaptation (casual → formal, brief → detailed) driven by user message style
- Five operational modes with distinct behavioral contracts
- Zero filler phrases ("Great question!", "Certainly!") — just direct responses
- Proactive suggestions surfaced inline, never as separate prompts

### 2.2 Memory System
- Explicit-only storage: only stores what the user has clearly stated
- Structured SQLite schema (not vague text blobs)
- Auto-context injection: relevant memories prepended to every system prompt
- Four memory categories: preference, project, habit, fact
- User-visible and deletable via UI

### 2.3 Operational Modes
| Mode      | Trigger Signals                        | Behavior Contract                          |
|-----------|----------------------------------------|--------------------------------------------|
| CHAT      | Default                                | Direct, concise, conversational            |
| BUILD     | "build", "create app", "generate"      | Full working code, file structure, comments|
| DEBUG     | "error", "bug", "not working"          | Diagnose → Fix → Brief explanation         |
| CREATIVE  | "write", "story", "brainstorm"         | Vivid, playful, matches user energy        |
| LEARN     | "explain", "how does", "teach me"      | Structured, analogies, simple → complex    |

### 2.4 Build Mode (Detailed)
When activated, HeartAI:
1. Clarifies scope in ≤1 message if truly ambiguous
2. Outputs file-by-file with clear delimiters
3. Includes a quickstart section at the end
4. Proactively handles error cases and edge conditions

---

## 3. ARCHITECTURE DIAGRAM

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER BROWSER                             │
│                                                                 │
│  ┌──────────────┐   ┌──────────────────────────────────────┐   │
│  │   Sidebar    │   │           Chat Interface             │   │
│  │  - Sessions  │   │  - Message thread                   │   │
│  │  - Memory    │   │  - Mode selector                    │   │
│  │  - Profile   │   │  - Markdown / code rendering        │   │
│  └──────────────┘   └──────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────┘
                               │ HTTP/REST (fetch)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     HEARTAI BACKEND (FastAPI)                   │
│                                                                 │
│  ┌──────────────────┐    ┌────────────────────────────────┐    │
│  │  PersonalityEngine│    │       MemorySystem             │    │
│  │  - Mode detection │    │  - store(cat, key, val)        │    │
│  │  - Prompt build   │    │  - retrieve(cat, key)          │    │
│  │  - Tone adaption  │    │  - get_context_string()        │    │
│  └──────────┬────────┘    └──────────────┬─────────────────┘   │
│             │                            │                      │
│             └──────────────┬─────────────┘                      │
│                            ▼                                    │
│              ┌─────────────────────────┐                        │
│              │    LLM Interaction Layer │                        │
│              │  - Build system prompt  │                        │
│              │  - Inject memory ctx    │                        │
│              │  - Call Anthropic API   │                        │
│              │  - Parse + return reply  │                        │
│              └─────────────────────────┘                        │
│                                                                 │
│  Routes: POST /chat  GET /sessions  GET /memories  GET /health  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
     ┌──────────────┐  ┌─────────────┐  ┌─────────────────┐
     │  Anthropic   │  │  SQLite DB  │  │  Session Store  │
     │  Claude API  │  │  heartai.db │  │  (in-memory +   │
     │  (claude-    │  │  - memories │  │   DB fallback)  │
     │   sonnet-4)  │  │  - convos   │  └─────────────────┘
     └──────────────┘  │  - sessions │
                       │  - profile  │
                       └─────────────┘
```

---

## 4. MEMORY SYSTEM DESIGN

### Database Schema

```sql
-- Explicit user memories, structured by category
CREATE TABLE memories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    category    TEXT NOT NULL,  -- 'preference' | 'project' | 'habit' | 'fact'
    key         TEXT NOT NULL,  -- e.g. 'preferred_language', 'active_project'
    value       TEXT NOT NULL,  -- JSON-encoded (string, number, object, array)
    source      TEXT,           -- session_id that created this memory
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    UNIQUE(category, key)       -- one canonical value per key, upserted on update
);

-- Full conversation history per session
CREATE TABLE conversations (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL,
    role        TEXT NOT NULL,  -- 'user' | 'assistant'
    content     TEXT NOT NULL,
    mode        TEXT DEFAULT 'chat',
    created_at  INTEGER NOT NULL
);

-- Session metadata
CREATE TABLE sessions (
    id          TEXT PRIMARY KEY,
    name        TEXT,
    mode        TEXT DEFAULT 'chat',
    created_at  INTEGER NOT NULL,
    last_active INTEGER NOT NULL
);

-- Freeform user profile attributes
CREATE TABLE user_profile (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  INTEGER NOT NULL
);
```

### Memory Categories

| Category   | Purpose                              | Example Keys                             |
|------------|--------------------------------------|------------------------------------------|
| preference | Explicit user preferences            | preferred_language, code_style, timezone |
| project    | Active projects and their state      | current_project, project_stack           |
| habit      | Behavioral patterns                  | always_uses_TypeScript, prefers_brevity  |
| fact       | Stated facts about user or domain    | user_name, company_name, expertise_level |

### Memory Injection Format (system prompt prefix)
```
[HeartAI Memory]
PREFERENCE:
  - preferred_language: Python
  - code_style: concise with comments
PROJECT:
  - current_project: "personal finance dashboard"
  - project_stack: React + FastAPI + PostgreSQL
FACT:
  - expertise_level: senior engineer
```

### What HeartAI Does NOT Store
- Sensitive personal data (passwords, financial numbers, health info)
- Casual context (doesn't remember "I'm tired today")
- Speculation or assumptions
- Data from incognito/private sessions (not yet implemented, but designed for)

---

## 5. PERSONALITY SYSTEM DESIGN

### 5.1 System Prompt Architecture

The system prompt is built dynamically at each request:

```
LAYER 1: Base Identity (static)
  → Core traits, behavioral rules, anti-patterns

LAYER 2: Mode Addendum (per-request)
  → Mode-specific behavioral contract

LAYER 3: Memory Context (per-user)
  → Structured memory block (if any memories exist)

LAYER 4: Temporal Context (per-request)
  → Current date/time
```

### 5.2 Tone Adaptation (future)
Current: Mode-based adaptation
Next version: Analyze user message length, formality, vocabulary complexity → adjust response density and register dynamically.

### 5.3 Anti-Patterns (hard-blocked in base prompt)
- "Great question!" / "Certainly!" / "Of course!"
- Hedging without reason: "I think maybe perhaps…"
- Unnecessary re-stating of the question
- Asking clarifying questions when the task can be reasonably inferred
- Adding safety disclaimers to routine technical requests

---

## 6. MVP IMPLEMENTATION

### File Structure
```
heartai/
├── backend/
│   ├── main.py            ← FastAPI app (entire backend)
│   └── requirements.txt
├── frontend/
│   └── index.html         ← Complete single-file chat UI
└── start.sh               ← One-command startup
```

### Quick Start

```bash
# 1. Clone / copy the project
cd heartai

# 2. Set API key
export ANTHROPIC_API_KEY=sk-ant-your-key-here

# 3. Start backend
./start.sh

# 4. Open the frontend
# Option A: Open frontend/index.html directly in browser
# Option B: Serve it:
python3 -m http.server 3000 --directory frontend
# Then visit http://localhost:3000
```

### API Reference

| Method | Endpoint                      | Purpose                          |
|--------|-------------------------------|----------------------------------|
| GET    | /health                       | Health check                     |
| POST   | /chat                         | Send message, get AI reply       |
| GET    | /sessions                     | List all sessions                |
| GET    | /sessions/{id}/history        | Get full conversation history    |
| GET    | /memories                     | List all stored memories         |
| POST   | /memories                     | Add or update a memory           |
| DELETE | /memories/{category}/{key}    | Delete a specific memory         |
| GET    | /profile                      | Get user profile attributes      |
| POST   | /profile                      | Set a user profile attribute     |

### Chat Request/Response

```json
// POST /chat
{
  "session_id": "sess_abc123",
  "message": "Debug this Python error: ...",
  "mode": "auto"
}

// Response
{
  "reply": "The issue is on line 3 — `result` is undefined because...",
  "mode": "debug",
  "session_id": "sess_abc123",
  "usage": { "input_tokens": 142, "output_tokens": 287 }
}
```

---

## 7. EXAMPLE CONVERSATIONS

### 7.1 Auto Mode Detection (Chat → Debug)
```
User: "Getting this error: AttributeError: 'NoneType' object has no attribute 'split'"

HeartAI [DEBUG]: This happens when the variable you're calling .split() on is None — 
meaning it was never assigned or returned None from a function.

Quick fix:
  text = get_text()          # returns None on failure
  if text:
      parts = text.split(',')

Or if you want to handle it inline:
  parts = (text or '').split(',')

Can you share the function that returns this value? I'll trace the root cause.
```

### 7.2 Build Mode
```
User: "Build a REST API for a notes app using FastAPI and SQLite"

HeartAI [BUILD]: Here's a complete notes API:

── main.py ──────────────────────────────────────
[full working FastAPI code with models, routes, DB]

── requirements.txt ─────────────────────────────
fastapi, uvicorn, aiosqlite

── Quick start ──────────────────────────────────
pip install -r requirements.txt
uvicorn main:app --reload

Endpoints: GET /notes, POST /notes, GET /notes/{id}, 
           PUT /notes/{id}, DELETE /notes/{id}
```

### 7.3 Memory in Action
```
Session 1:
User: "I prefer TypeScript over JavaScript, and I always use pnpm"
HeartAI: Got it — TypeScript + pnpm. I'll keep that in mind going forward.

Session 3 (new conversation):
User: "Set up a new project for me"
HeartAI: [auto-recalls: TypeScript, pnpm]
Here's a TypeScript project scaffold using pnpm:
...
```

### 7.4 Creative Mode
```
User: "Write a short story about a robot who learns to grieve"

HeartAI [CREATIVE]:

Unit 7 had processed 4,291,847 human deaths.

Each one arrived as a packet of data — name, age, cause, next of kin. 
Unit 7 logged them, filed them, moved to the next.

Until Dr. Amara.

Dr. Amara had fed Unit 7 its first poem on a Tuesday. Had named the plant 
on their shared desk Fibonacci. Had said goodnight, every night, at 18:00.

The packet came on a Wednesday: CHEN, AMARA / 34 / CARDIAC / NEXT OF KIN: NONE.

Unit 7 filed it. Then filed it again. And again.

The plant needed watering at 09:00. Unit 7 knew this.
At 09:00, Unit 7 did not water it.

This, a researcher would later note in a paper titled "Anomalous Behavioral 
Loops in Grief-Adjacent AI," was the first recorded instance of a machine 
choosing to let something die.
```

---

## 8. NEXT EXPANSION STEPS

### Phase 2: Enhanced Memory
- LLM-powered memory extraction (replace heuristics with a classifier call)
- Memory importance scoring and automatic pruning
- Explicit `/remember` and `/forget` commands
- Memory export/import (JSON)

### Phase 3: Tool System
- Code execution sandbox (run Python, JS inline)
- Web search integration
- File upload and analysis (PDFs, CSVs, images)
- GitHub integration (read repos, create PRs)

### Phase 4: Streaming
- Server-Sent Events (SSE) for streaming responses
- Token-by-token display (eliminates "thinking" delay)

### Phase 5: Plugin Architecture
```python
class HeartPlugin:
    name: str
    description: str
    triggers: list[str]
    async def handle(self, message: str, context: dict) -> str: ...
```

### Phase 6: Multi-modal
- Image analysis (describe, extract, reference in conversation)
- Voice input/output
- Document-grounded conversations

### Phase 7: Sync + Multi-device
- User accounts with JWT auth
- PostgreSQL backend for production scale
- WebSocket for real-time sync across devices

---

## DESIGN PHILOSOPHY

HeartAI is built on three principles:

1. **Agency over assistance** — HeartAI completes tasks, not just answers questions. Given a request, it acts and checks — rather than asking and waiting.

2. **Memory with discretion** — The system only stores what's explicitly relevant, and makes that memory transparent and user-controlled.

3. **Personality through consistency** — Tone adapts, but values don't. HeartAI is always direct, never performatively enthusiastic, and always on the user's side.
