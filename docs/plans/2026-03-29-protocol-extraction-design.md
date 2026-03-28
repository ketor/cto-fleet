# Protocol Extraction Design: sync-protocols

> Date: 2026-03-29
> Status: Approved
> Scope: Extract shared behavioral protocols from 42 team SKILL.md files into canonical source files, managed by a generalized sync engine.

## Problem

cto-fleet's 42 team skills share ~2000+ lines of verbatim-identical protocol text (handoff rules, consensus calculation, error handling, preamble). This duplication was introduced through batch copy-paste and has already caused drift issues:

- team-deps and team-cost have **two** consensus blocks (domain-specific + generic, the latter a batch-rollout artifact)
- team-review, team-dev, team-security, team-refactor have a **duplicate handoff section** (old manual version after the synced marker version)
- The existing `bin/sync-preamble` manages 2 protocols with hard-coded logic, cannot scale to more

### What NOT to extract

Research showed that teammate **roles** (scanner, analyzer, reviewer, etc.) share only 10-20% generic structure — 80-90% is domain-specific instructions. Extracting roles into shared agents would increase complexity without meaningful deduplication. **The right unit of extraction is protocols, not roles.**

## Research Findings

### Protocol duplication quantified (across 42 team skills)

| Protocol Block | Coverage | Verbatim % | Lines/copy | Total duplicated |
|---|---|---|---|---|
| Handoff (交接规范) | 42/42 | 100% | 34 | ~1400 |
| Preamble (更新检查) | 42/42 | 100% | 7 | ~294 |
| Generic consensus (共识度) | ~20/42 | 100% | 16 | ~320 |
| Error handling / circuit breaker | 42/42 | ~90% | 10-15 | ~500 |
| **Total** | | | | **~2500** |

### Not extracted (insufficient dedup ROI)

| Protocol Block | Reason |
|---|---|
| Mode behavior table (--auto/--once) | ~60% identical; 2nd column (confirmation items) varies per skill |
| Self-check checklist (fixer/coder) | Only ~15 skills; each has additional domain-specific items |
| Scoring/deduction tables | Fully domain-specific (different dimensions, weights, scales) |

### Role similarity analysis

7 functional archetypes across 192 role slots (scanner, dual-analyst, merger, output-generator, implementer, quality-gate, adversarial-challenger), but domain instructions are 80-90% of each role definition. Shared parts (lifecycle, handoff compliance) are already covered by protocol extraction.

## Solution: Generalized Protocol Sync Engine

### Approach

Extend the existing build-time sync pattern (proven by preamble + handoff) into a **registry-driven, multi-protocol sync engine**.

**Why build-time sync, not runtime Read:**
- Each SKILL.md remains self-contained — Claude loads one file, gets complete instructions
- No runtime overhead (no extra Read calls, no context growth)
- Consistent with the existing proven pattern
- Failures are caught at sync time, not at runtime when a team is mid-execution

### Directory structure

```
cto-fleet/
├── protocols/
│   ├── registry.conf             # Protocol registry
│   ├── preamble.md               # <!-- PREAMBLE_SECTION_START/END -->
│   ├── consensus.md              # <!-- CONSENSUS_SECTION_START/END -->
│   └── error-handling.md         # <!-- ERROR_HANDLING_SECTION_START/END -->
├── HANDOFF.md                    # <!-- HANDOFF_SECTION_START/END --> (unchanged location)
├── PREAMBLE.md                   # Documentation only (no longer sync source)
├── bin/
│   ├── sync-protocols            # New: generalized engine
│   └── sync-preamble             # Symlink → sync-protocols (backward compat)
```

### registry.conf format

```conf
# Protocol registry — one protocol per line
# Format: SECTION_NAME | source_file | gate_condition | exclude_if | insertion_anchor
#
# gate_condition:
#   *           = all SKILL.md files
#   TeamCreate  = SKILL.md files containing "TeamCreate"
#
# exclude_if:
#   (empty)     = no exclusion
#   KEYWORD     = skip if SKILL.md contains this keyword
#
# insertion_anchor:
#   after_frontmatter  = after YAML frontmatter closing ---
#   after:KEYWORD      = after first line containing KEYWORD
#   end_of_file        = append to end

PREAMBLE_SECTION        | protocols/preamble.md        | *          |             | after_frontmatter
HANDOFF_SECTION         | HANDOFF.md                   | TeamCreate |             | after:TeamCreate
CONSENSUS_SECTION       | protocols/consensus.md       | TeamCreate | 共识发现数  | end_of_file
ERROR_HANDLING_SECTION  | protocols/error-handling.md   | TeamCreate |             | end_of_file
```

### Marker convention

All protocols use HTML comment markers (unified):

```markdown
<!-- {SECTION_NAME}_START -->
... protocol content ...
<!-- {SECTION_NAME}_END -->
```

The preamble's legacy heading+`---` marker pattern is migrated to HTML comments in Phase 2.

### CLI interface

```bash
bin/sync-protocols                                    # check mode (default)
bin/sync-protocols --fix                              # fix mode
bin/sync-protocols --dry-run                          # preview changes
bin/sync-protocols --verbose                          # per-file results
bin/sync-protocols --skills=team-dev,team-perf        # scope to specific skills
bin/sync-protocols --sections=HANDOFF,CONSENSUS       # scope to specific protocols
bin/sync-protocols --remove=CONSENSUS_SECTION         # remove a protocol from all files
bin/sync-protocols --migrate-preamble                 # one-time: convert preamble markers
```

### Core algorithm

```
parse registry.conf → sections[] (ordered by declaration)

for each skill_file:
  for each section in sections (REVERSE order — bottom-up to preserve line numbers):
    1. gate_check(skill_file, gate_condition)
       → skip if not matched
    2. exclude_check(skill_file, exclude_if)
       → skip if matched
    3. extract existing content between <!-- X_START --> and <!-- X_END -->
    4. compare with canonical content from source_file
       → identical: OK
       → different: OUTDATED → head/tail splice replacement
       → missing: MISSING → locate insertion_anchor, insert with blank line padding
```

**Critical: reverse-order processing.** Sections are processed bottom-to-top within each file, so line-number-based splicing of lower sections doesn't invalidate upper section positions.

### Protocol source file contents

**protocols/preamble.md** — existing preamble wrapped in markers:

```markdown
<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

\`\`\`bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
\`\`\`

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.
<!-- PREAMBLE_SECTION_END -->
```

**HANDOFF.md** — unchanged (already has `<!-- HANDOFF_SECTION_START/END -->` markers).

**protocols/consensus.md** — generic five-dimension consensus block:

```markdown
<!-- CONSENSUS_SECTION_START -->
### 共识度计算

team lead 按五维度评估双路分析的共识度：

| 维度 | 权重 |
|------|------|
| 发现一致性（相同问题/结论） | 20% |
| 互补性（独有但不矛盾的发现） | 20% |
| 分歧程度（直接矛盾的结论） | 20% |
| 严重度一致性（同一问题的严重等级差异） | 20% |
| 覆盖完整性（两路合并后的覆盖面） | 20% |

共识度 = 各维度加权得分之和

- **≥ 60%**：自动合并，分歧项由 team lead 裁决
- **50-59%**：合并但标注分歧，收尾时汇总争议点
- **< 50%**：触发熔断，暂停并向用户确认方向
<!-- CONSENSUS_SECTION_END -->
```

Skills with domain-specific consensus formulas (containing `共识发现数`) are excluded via `exclude_if` and retain their inline versions.

**protocols/error-handling.md** — unified error handling and circuit breaker:

```markdown
<!-- ERROR_HANDLING_SECTION_START -->
### 错误处理

| 场景 | 处理方式 |
|------|---------|
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从最近的检查点恢复 |
| 某阶段产出质量不达标 | 记录问题，在收尾阶段汇总，不阻塞后续流程（除非是熔断条件） |
| 用户中途修改需求 | 暂停当前阶段，重新评估影响范围，必要时回退到受影响的最早阶段 |

### 熔断机制（不可跳过）

以下条件触发时，**无论 `--auto` 还是 `--once` 模式，都必须暂停并向用户确认**：

- 共识度 < 50%（双路分析严重分歧）
- 迭代超过最大轮数仍未达标
- 关键依赖缺失（无法继续执行的前置条件不满足）

触发熔断时，向用户展示：当前状态、分歧/问题摘要、建议的下一步选项。
<!-- ERROR_HANDLING_SECTION_END -->
```

## Migration Plan

### Phase 1: Infrastructure (no SKILL.md changes)

1. Create `protocols/` directory with `registry.conf`, `preamble.md`, `consensus.md`, `error-handling.md`
2. Implement `bin/sync-protocols` engine
3. Add shell tests in `tests/`
4. Replace `bin/sync-preamble` with symlink → `bin/sync-protocols`
5. Verify: `bin/sync-protocols --check` reports OK for existing SKILL.md files (engine supports legacy preamble markers during this phase)

### Phase 2: Preamble marker migration (42 SKILL.md content-preserving changes)

1. `bin/sync-protocols --migrate-preamble` converts all SKILL.md preambles from heading+`---` to `<!-- PREAMBLE_SECTION_START/END -->`
2. Verify: `bin/sync-protocols --check` all OK
3. Optional: remove legacy marker support from engine

### Phase 3: New protocol injection + cleanup (~35 SKILL.md changes)

1. `bin/sync-protocols --fix` injects `CONSENSUS_SECTION` and `ERROR_HANDLING_SECTION`
2. Cleanup pass:
   - Remove duplicate generic consensus blocks in skills that have domain-specific formulas (team-deps, team-cost, etc.)
   - Remove orphaned manual `## 文件交接规范` after `HANDOFF_SECTION_END` (team-review, team-dev, team-security, team-refactor)
3. Verify: `bin/sync-protocols --check --verbose` all OK
4. Spot-check 3-5 skills manually

### Rollback

Each phase is a separate git commit. `git revert` any phase independently.

## Maintenance SOP

| Task | Steps |
|---|---|
| Modify a protocol | Edit `protocols/*.md` or `HANDOFF.md` → `bin/sync-protocols --fix` |
| Add new protocol | Create source file in `protocols/` → add line to `registry.conf` → `bin/sync-protocols --fix` |
| Add new skill | Create with SKILL-TEMPLATE.md (no markers needed) → `bin/sync-protocols --fix` auto-injects |
| Remove a protocol | `bin/sync-protocols --remove=SECTION_NAME` → delete source file → remove from `registry.conf` |
| Check for drift | `bin/sync-protocols --check` (can add to CI) |

## Testing Plan

Extend `tests/` with:

- registry.conf parsing (valid, malformed, empty, comments)
- Gate conditions (*, TeamCreate, custom keyword)
- Exclude conditions (keyword match, no match, empty)
- Insertion anchors (after_frontmatter, after:KEYWORD, end_of_file)
- Reverse-order processing (multi-section update in one file)
- Preamble migration (heading+--- → HTML markers)
- Duplicate content cleanup
- Edge cases (empty file, missing markers, unpaired markers, multiple marker pairs)
- Backward compatibility (sync-preamble symlink, old CLI flags)

## Future Directions

- **Templated protocols** (v2): For protocols like the mode behavior table where ~60% is shared but some fields vary per skill. Would need a template engine with variable substitution — deferred as YAGNI for now.
- **CI integration**: Add `bin/sync-protocols --check` to CI pipeline to prevent drift.
