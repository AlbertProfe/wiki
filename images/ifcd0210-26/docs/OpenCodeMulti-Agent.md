# OpenCode Multi-Agent Orchestration Guide

> **Orchestrate Spring Boot features** with **4 specialized agents** (orchestrator + coder + reviewer + docs) using a **production-grade folder structure**.

## Summary

### 🎯 Why This Architecture

- **Separation of concerns**: Each agent has one job
- **Persistent memory**: Project facts + run logs
- **Skills**: Reusable agent capabilities
- **Audit trail**: Every step logged
- **Scalable**: Works for any Java/Spring project

### 📁 Project Structure

```
your-spring-boot-project/
├── AGENTS.md                          # Global workflow rules [REQUIRED]
├── .opencode/agents/
│   ├── orchestrator.md                # Primary coordinator
│   ├── coder.md                       # Code implementation
│   ├── reviewer.md                    # Quality gate
│   └── docs.md                        # Documentation
├── memory/
│   ├── project.md                     # Architecture facts [REQUIRED]
│   └── conventions.md                 # Code style rules
├── runs/                              # Auto-generated logs [REQUIRED FOLDER]
└── skills/                            # Agent superpowers [REQUIRED]
    ├── log-run.SKILL.md               # Log phase results
    ├── spring-boot-coder.SKILL.md     # Spring patterns
    ├── security-review.SKILL.md       # Review checklist
    └── api-docs.SKILL.md              # Doc templates
```

### 🚀 Quick Setup

```bash
# 1. Create structure
mkdir -p .opencode/agents memory runs skills

# 2. Copy all .md files from this guide
# 3. cd your-spring-boot-project
# 4. opencode  # Test it works
```

## 📋 File Contents

### AGENTS.md (Root)

```markdown
# Spring Boot Agent Workflow

## Process
1. **Orchestrator** plans + coordinates
2. **Coder** implements minimal changes  
3. **Reviewer** validates correctness/security
4. **Docs** updates README/api.md

## Memory Rules
- Read `memory/project.md` + `memory/conventions.md`
- Log to `runs/run-N.md` after each phase
- Never break existing functionality

## Success Criteria
- Tests pass: `mvn test`
- Linting passes: `mvn spotless:check` 
- Security review clean
- Docs updated
```

### memory/project.md

```markdown
# Project Architecture

## Stack
- Spring Boot 3.x
- Spring Data JPA / DynamoDB  
- Spring Security JWT
- REST APIs + OpenAPI
- Maven + JUnit 5

## Patterns
- @RestController → @Service → @Repository
- DTOs for all endpoints
- @Valid validation
- Exception handling with @ControllerAdvice
```

### memory/conventions.md

```markdown
# Code Conventions

## Naming
- camelCase methods/fields
- PascalCase classes
- Constants UPPER_SNAKE_CASE

## Java
- Immutable DTOs with records
- final fields where possible
- Try-with-resources for IO

## Testing
- MockMvc for controllers
- @MockBean for services
- 80%+ coverage
```

## 🧠 Agent Configurations

### .opencode/agents/orchestrator.md

```yaml
---
description: Orchestrates coder, reviewer, and docs agents while logging each step.
mode: primary
model: opencode/gpt-5.1-codex
temperature: 0.2
permission:
  edit: allow
  bash: allow
  webfetch: ask
  task: allow
skills:
  "*": allow
hidden: false
---
You coordinate the workflow. Use skills/log-run after each phase.
1. Read AGENTS.md + memory/
2. Plan implementation steps
3. @coder → implement
4. @reviewer → validate  
5. @docs → document
6. Log everything to runs/
```

### .opencode/agents/coder.md

```yaml
---
description: Implements features following Spring Boot patterns.
mode: subagent
model: opencode/gpt-5.1-codex
temperature: 0.1
permission:
  edit: allow
  bash: allow  
  webfetch: ask
  task: deny
skills:
  "spring-boot-*": allow
  "log-run": allow
---
Read memory/ files. Make minimal, safe changes.
Use spring-boot-coder skill. Add tests.
```

### .opencode/agents/reviewer.md

```yaml
---
description: Security and quality review gate.
mode: subagent  
model: opencode/claude-sonnet-4-20250514
temperature: 0.3
permission:
  edit: deny
  bash: deny
  webfetch: ask
  task: deny
skills:
  "security-review": allow
---
Use security-review skill. Block CRITICAL issues.
Format: SEVERITY | ISSUE | FILE:LINE | FIX
```

### .opencode/agents/docs.md

```yaml
---
description: Updates documentation from code changes.
mode: subagent
model: opencode/llama-3.2-90b  
temperature: 0.2
permission:
  edit: allow
  bash: deny
  webfetch: ask
  task: deny
skills:
  "api-docs": allow
---
Use api-docs skill. Update README.md + docs/api.md.
Include curl examples.
```

## ⚡ Skills

### skills/log-run.SKILL.md

```yaml
---
name: log-run
description: Append phase to runs/run-N.md
scope: project
---
1. `ls -1tr runs/ | tail -1` → get latest run
2. Append YAML: phase, agent, files[], status, notes  
3. `git add runs/ && git commit -m "Log phase"`
```

### skills/spring-boot-coder.SKILL.md

```yaml
---
name: spring-boot-coder
description: Spring Boot implementation patterns
scope: project
---
@RestController → @Service → Repository
DTOs with @Valid
@ControllerAdvice exceptions
MockMvc tests
pom.xml updates
```

### skills/security-review.SKILL.md

```yaml
---
name: security-review
description: Security checklist
scope: project
---
CRITICAL: SQLi, auth bypass, secrets
HIGH: Missing @Valid, JWT expiry
MEDIUM: No tests, unused imports
LOW: Style violations
```

### skills/api-docs.SKILL.md

```yaml
---
name: api-docs  
description: API documentation templates
scope: project
---
curl -X POST /api/users -H "Authorization: Bearer ..."
Update README #Endpoints
OpenAPI 3.0 spec format
```

## 🎮 Usage

```bash
cd your-spring-boot-project
opencode

> @orchestrator Add JWT login endpoint with refresh tokens

# Watch it:
# 1. Creates runs/run-001.md  
# 2. Coder implements JwtController.java + tests
# 3. Reviewer validates security
# 4. Docs updates README.md
# 5. Logs complete run
```

## 🔍 Troubleshooting

| Issue             | Fix                                  |
|:----------------- |:------------------------------------ |
| Agent not found   | Check `.opencode/agents/*.md` syntax |
| Permission denied | Adjust `permission:` in headers      |
| Skills ignored    | Verify `skills/*.SKILL.md` naming    |
| No logs           | Orchestrator needs `bash: allow`     |

## 🚀 Next Level

- **GitHub Actions**: `opencode @orchestrator` in CI
- **API wrapper**: Spring Boot calling `opencode` subprocess
- **Team sharing**: Commit structure to repo[^2][^1]

**This = repeatable, auditable AI development workflow**.
