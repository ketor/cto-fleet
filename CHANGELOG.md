# Changelog

## [1.6.0] - 2026-03-28

### Added
- **HANDOFF.md** — File-based handoff specification for multi-agent context management. Defines the Write-to-file + SendMessage-path-only pattern that reduces team lead context by 50-60%
- **RFC-2026-001** — Complete RFC document for File-Based Handoff design (`docs/rfc/rfc-2026-001-file-based-handoff.md`, 951 lines)
- **Design review report** — Structured evaluation: Conditionally Approved 7.5/10, 25 challenger challenges, 4 Major improvements integrated (`docs/rfc/design-review-report-20260328-170000.md`)
- `bin/sync-preamble` handoff section sync — detects `<!-- HANDOFF_SECTION_START/END -->` markers, inserts/updates handoff section in SKILL.md files that use TeamCreate

### Changed
- **team-review/SKILL.md** — Pilot: agents write reports to `/tmp/{team-name}/` files, SendMessage sends path + ≤500 char summary, team lead forwards paths not content, ⚡必须Read markers at key decision points
- **team-dev/SKILL.md** — Pilot: architect outputs, group meeting materials, reviewer reports all use file-based handoff with compliance checking
- **team-security/SKILL.md** — Pilot: scanner reports, auditor findings, analyst unified vulnerability list, reporter materials all use file-based handoff
- `bin/sync-preamble` — Extended from preamble-only sync to also handle handoff section synchronization across skills

## [1.5.0] - 2026-03-28

### Changed
- Version bump (preparation for File-Based Handoff implementation)

## [1.4.0] - 2026-03-27

### Security
- Fixed sed command injection in `bin/cto-fleet-config` — replaced `sed -i` with `awk` to safely handle special characters (`/`, `&`) in keys and values
- Fixed file permission hardening: state directory now created with `chmod 700`, config/cache files with `chmod 600`
- Fixed concurrent file race conditions in `bin/cto-fleet-update-check` — all cache writes now use atomic `mktemp` + `mv` operations
- Fixed marker file read-delete race condition with atomic delete pattern
- Fixed curl network error handling — failures no longer cache a false "up to date" result
- Fixed version regex to strict SemVer (`^[0-9]+\.[0-9]+\.[0-9]+$`) to reject malformed versions

### Added
- `tests/test_config.sh` — 11 unit tests for `cto-fleet-config` (set/get, special chars, permissions)
- `tests/test_update_check.sh` — 9 unit tests for `cto-fleet-update-check` (marker flow, cache, disabled check)
- `bin/sync-preamble` — synchronize preamble across all SKILL.md files; supports `--check`, `--fix`, `--dry-run`, `--verbose`, `--skills=` options
- `docs/PARAMETER-SPEC.md` — canonical parameter naming spec: standard params (`--auto`/`--once`/`--lang`) + domain param conventions
- `docs/SKILL-DEVELOPMENT-GUIDE.md` — guide for creating new skills: structure, patterns, checklist
- `SKILL-TEMPLATE.md` — ready-to-use template for new skill development

## [1.3.0] - 2026-03-26

### Changed
- Router (team/) synced with all 43 skills
- README updated with current skill list
- Various skill deepening improvements

## [1.2.0] - 2026-03-20

### Changed
- Quality consistency improvements across all skills

## [1.1.0] - 2026-03-15

### Added
- 11 new team skills (team-dora, team-feature-flag, team-schema, team-chaos, team-accessibility, team-contract-test, team-i18n, team-threat-model, team-governance, team-cicd, team-cto-briefing)
- Auto-update detection and upgrade prompting preamble for all skills

## [1.0.0] - 2026-03-10

### Added
- Initial release: 32 Claude Code multi-agent team skills
