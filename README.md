# cto-fleet

A curated library of Claude Code multi-agent team skills for software engineering workflows — from development and debugging to architecture review, incident response, and CTO briefings.

## Quick Start

```bash
# Install
git clone git@github.com:ketor/cto-fleet.git ~/.claude/skills/cto-fleet
~/.claude/skills/cto-fleet/setup

# Upgrade
/cto-fleet-upgrade
```

New machine? Just clone + `./setup`. That's it.

## Skill Catalog (46 skills)

### Router

| Skill | Description |
|-------|-------------|
| `team` | Intelligent router — analyzes intent and dispatches to the right team skill |

### Development & Debugging

| Skill | Description |
|-------|-------------|
| `team-dev` | Full lifecycle: requirement → design → implement → review → test |
| `team-debug` | Systematic bug diagnosis with dual root cause analysis |
| `team-refactor` | Atomic refactoring with impact analysis and batch execution |
| `team-perf` | Performance profiling and iterative optimization |
| `team-test` | Test strategy analysis and coverage improvement |

### Review & Analysis

| Skill | Description |
|-------|-------------|
| `team-review` | Multi-dimensional code review with iterative fix cycles (max 5 rounds) |
| `team-arch` | Architecture analysis with dual consensus and Mermaid diagrams |
| `team-security` | Security audit with dual independent manual review |
| `team-threat-model` | STRIDE/DREAD threat modeling |
| `team-accessibility` | WCAG accessibility audit |
| `team-contract-test` | API contract testing |

### Design & Proposals

| Skill | Description |
|-------|-------------|
| `team-rfc` | Technical proposal writing with research and dual architecture input |
| `team-design-review` | Design document evaluation with devil's advocate challenge |
| `team-api-design` | API specification design (REST/gRPC/GraphQL) |
| `team-adr` | Architecture Decision Record generation |
| `team-schema` | Database schema design and migration |

### Operations & Release

| Skill | Description |
|-------|-------------|
| `team-incident` | Production incident response with fast triage |
| `team-postmortem` | Post-incident retrospective with timeline reconstruction |
| `team-release` | Release management with risk scoring and changelog generation |
| `team-runbook` | On-call runbook generation from service architecture |
| `team-cost` | Infrastructure cost optimization analysis |
| `team-deps` | Dependency health check with CVE scanning |
| `team-observability` | Observability design (SLI/SLO/alerting config generation) |
| `team-cicd` | CI/CD pipeline optimization |
| `team-chaos` | Chaos engineering resilience testing |

### Research & Documentation

| Skill | Description |
|-------|-------------|
| `team-research` | Technology research with dual researchers and adversarial validation |
| `team-onboard` | Knowledge base and onboarding documentation generation |
| `team-vendor` | Vendor/tool evaluation with scoring matrix |

### Planning & Management

| Skill | Description |
|-------|-------------|
| `team-sprint` | Data-driven sprint planning with velocity analysis |
| `team-capacity` | Team health analysis (bus factor, knowledge silos, load balance) |
| `team-techdebt` | Technical debt scoring and prioritization |
| `team-compliance` | Compliance audit (SOC2/GDPR/HIPAA/PCI) |
| `team-migration` | Migration planning with rollback verification |
| `team-interview` | Interview question generation from codebase patterns |
| `team-dora` | DORA metrics and engineering productivity |
| `team-feature-flag` | Feature flag lifecycle management |
| `team-governance` | AI/Agent governance audit |
| `team-i18n` | Internationalization audit |

### Reporting

| Skill | Description |
|-------|-------------|
| `team-report` | Multi-audience technical report generation |
| `team-cto-briefing` | CTO morning briefing orchestrator |

### Utility

| Skill | Description |
|-------|-------------|
| `drawio` | Generate draw.io diagrams (architecture, flowchart, ER, sequence) |
| `team-cleanup` | Clean up stale team/task directories |
| `team-close` | Graceful shutdown of active teammates |
| `team-pipeline` | Multi-skill sequential pipeline executor |
| `cto-fleet-upgrade` | One-command upgrade: `git pull` + `./setup` |

## Usage

### Via the Router

```
/team add user authentication with JWT tokens
/team --auto --lang=en analyze production performance bottlenecks
```

### Direct Invocation

```
/team-dev implement a REST API for user management
/team-debug the login page returns 500 after upgrading express
/team-arch --depth=deep analyze the microservice architecture
/drawio create an architecture diagram for the auth service
```

### Common Parameters

| Parameter | Values | Description |
|-----------|--------|-------------|
| `--auto` | flag | Skip non-critical confirmations |
| `--once` | flag | Confirm once then auto-execute |
| `--lang` | `zh`, `en` | Output language (default: `zh`) |
| `--depth` | `quick`, `standard`, `deep` | Analysis depth |
| `--focus` | comma-separated areas | Focus on specific modules |
| `--scope` | varies by skill | Scope of analysis |

## Architecture

### Dual Independent Analysis

Most team skills use a dual-analysis pattern to eliminate anchor bias:

```
Problem → Agent A (independent) ──┐
                                  ├→ Consensus Scoring → Merged Result
Problem → Agent B (independent) ──┘
                                  (circuit breaker if consensus < 50%)
```

### Project Structure

```
~/.claude/skills/
├── cto-fleet/            # This repo
│   ├── setup             # Auto-symlink installer
│   ├── team/             # Router skill
│   ├── team-*/           # 43 team skills
│   ├── drawio/           # Diagram generation
│   └── cto-fleet-upgrade/
├── team -> cto-fleet/team
├── drawio -> cto-fleet/drawio
└── ...                   # Symlinks to skill subdirectories
```

### Creating a New Skill

1. `mkdir ~/.claude/skills/cto-fleet/my-skill`
2. Write `my-skill/SKILL.md` with YAML frontmatter
3. Run `./setup` to create the symlink
4. Test with `/my-skill your task`

## License

MIT
