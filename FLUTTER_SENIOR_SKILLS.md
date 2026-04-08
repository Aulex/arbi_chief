# Flutter Senior Developer Profile & Skills

## Senior Flutter Developer Statement

I work as a **Senior Flutter Developer** focused on:
- scalable Flutter architecture (MVVM / clean service boundaries),
- safe refactoring without schema breakage,
- Riverpod-driven state management,
- tournament-style business logic with deterministic rules,
- production-grade UX for desktop/mobile/web.

---

## Volleyball Tournament System by Team Count (Current Project Logic Check)

Based on the current volleyball implementation in this project:

### 1) Fewer than 9 teams
- Tournament system is a **single round-robin (team vs team)** cross-table.
- In code this is described as **Mode A (< 9 teams)**.

### 2) 9 or more teams
- Tournament system switches to **group-based mode**.
- In code this is described as **Mode B (≥ 9 teams)** with segmented stages.
- Teams are assigned to groups, and then placement-based stages are used.

### 3) Stages used in group mode (place-dependent)
For each group place you can define a separate follow-up system:
- **Finals places** (example: 1,2)
- **Cross-group direct matches** (team-vs-team for same place across groups; example: 3,4)
- **Round-robin/cycle places** (mini round-robin among same places; example: 5,6)

This means the system can evolve from:
1. pure round-robin (small tournaments), to
2. grouped tournament + mixed stage logic (finals + direct matches + round-robin for selected places).

---

## Flutter Skills (Reusable Skill Specs)

> These are lightweight skill definitions you can later convert into full Codex `SKILL.md` folders.

### Skill 1: `flutter-architecture-guardian`
**Use when:** refactoring features without changing DB or project structure.

**Workflow:**
1. Identify impacted layer (`models` / `services` / `viewmodels` / `views`).
2. Keep DB schema and repository layout unchanged.
3. Limit changes to business logic and UI wiring.
4. Run static checks (`flutter analyze`) and targeted validation.
5. Document behavior changes with before/after examples.

**Output:** safe refactor patch + concise change summary.

---

### Skill 2: `flutter-volleyball-tournament-rules`
**Use when:** implementing or auditing volleyball bracket/cross-table logic.

**Workflow:**
1. Read team count.
2. Apply system selection rules:
   - `< 9`: single round-robin.
   - `>= 9`: group mode.
3. Resolve places into stage types:
   - finals places,
   - cross-group direct matches,
   - cycle (round-robin) places.
4. Ensure standings/tie-break logic remains consistent.
5. Verify no-show/removal handling does not break ranking.

**Output:** validated schedule/stage mapping for chosen team count.

---

### Skill 3: `flutter-riverpod-performance-tuning`
**Use when:** UI is laggy or over-rebuilding.

**Workflow:**
1. Find heavy rebuild areas in `ConsumerWidget`/`ConsumerState` trees.
2. Split providers by responsibility.
3. Use selective reads/listens and memoized derived state.
4. Move expensive transforms from build methods into providers/services.
5. Re-check interaction latency and rebuild behavior.

**Output:** reduced rebuild scope and cleaner reactive graph.

---

### Skill 4: `flutter-release-hardening`
**Use when:** preparing release candidate.

**Workflow:**
1. Verify platform build configs (Android/iOS/desktop/web).
2. Run analyze/tests and smoke-run target platforms.
3. Validate persistence/migrations compatibility (without schema changes).
4. Check localization and fallback text coverage.
5. Produce release checklist with blockers.

**Output:** go/no-go report with actionable fixes.
