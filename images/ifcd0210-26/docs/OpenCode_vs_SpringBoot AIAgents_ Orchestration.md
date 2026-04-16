# OpenCode vs Spring Boot AI Agents

## Summary

### Introduction: OpenCode CLI vs Spring Boot AI Agents

**Which orchestrates your Spring Boot AI coding workflow better?**

Two powerful approaches compete to deliver **coder + reviewer + docs** automation:

**OpenCode CLI**: Zero-code, markdown-driven agents with native file editing and bash integration. Your existing `AGENTS.md`, `memory/`, `skills/` structure works immediately.

**Spring Boot AI**: Production-grade REST API using Spring AI's TaskExecutor, ChatMemory, and FileSystemTools. Enterprise deployment with monitoring and scaling.

This comparison analyzes **16 key criteria** to determine the best fit for your **Spring Boot multi-agent orchestration** needs - from personal prototyping to team production systems.

### References

- Main references:
  
  - [Agents_Companion_v2 (3).pdf - Google Drive](https://drive.google.com/file/d/1GVPdwEh48bErTNdhxD0vqxPAifSx1I6Y/view)
  - [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)

- <mark>Embabel</mark>:
  
  - [GitHub - embabel/embabel-agent: Agent framework for the JVM. Pronounced Em-BAY-bel /ɛmˈbeɪbəl/ · GitHub](https://github.com/embabel/embabel-agent)
  - [Embabel Agent Framework User Guide](https://docs.embabel.com/embabel-agent/guide/0.1.3/)
  - [Embabel Agent Documentation](https://docs.embabel.com/embabel-agent/api-docs/0.1.3/index.html)

- [Spring AI Community · GitHub](https://github.com/spring-ai-community)

- Spring AI
  
  - [Building Effective Agents :: Spring AI Reference](https://docs.spring.io/spring-ai/reference/api/effective-agents.html)
  - [Build a Coding Agent Like Claude Code with Spring AI - YouTube](https://www.youtube.com/watch?v=P8s65qu-LZI)
    - [GitHub - danvega/codingagent · GitHub](https://github.com/danvega/codingagent)
    - [GitHub - spring-ai-community/spring-ai-agent-utils: A Spring AI library that brings Claude Code-inspired tools and agent skills to your AI applications. · GitHub](https://github.com/spring-ai-community/spring-ai-agent-utils)
  
  - [Building AI Agents in Java with Embabel (Getting Started) - YouTube](https://www.youtube.com/watch?v=G5VDQCZu6t0)
    
    - [blog-agent](https://github.com/danvega/blog-agent)
    - [Embabel · GitHub](https://github.com/embabel)

## Spring AI Architecture

```json
Spring Boot Orchestrator → Local LLM (Ollama)
     ↓
Loads: AGENTS.md, memory/*.md, skills/*.md as prompts
```

**Orchestrator delegates** to 3 worker agents via **Task tool** (Spring AI 1.0.2+).

<mark>Complete Setup:</mark>

### 1. pom.xml

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.ai</groupId>
        <artifactId>spring-ai-ollama-spring-boot-starter</artifactId>
        <version>1.0.2</version>
    </dependency>
</dependencies>
```

### 2. application.yml

```yaml
spring:
  ai:
    ollama:
      base-url: http://localhost:11434
      chat:
        options:
          model: llama3.2:8b
    agent:
      orchestrator:
        chat-model: ollama
      coder:
        chat-model: ollama
        system-prompt-file: classpath:agents/coder.md
      reviewer:
        chat-model: ollama  
        system-prompt-file: classpath:agents/reviewer.md
      docs:
        chat-model: ollama
        system-prompt-file: classpath:agents/docs.md
```

### 3. OrchestratorAgent.java

```java
@Component
@Agent("orchestrator")
public class OrchestratorAgent {

    private final TaskExecutor taskExecutor;

    public OrchestratorAgent(AgentRegistry registry) {
        this.taskExecutor = new TaskExecutor(registry);
    }

    @AgentTask
    public String orchestrate(@Input String featureRequest) {
        // Read AGENTS.md + memory/project.md as context
        String context = loadFiles("AGENTS.md", "memory/project.md");

        // Delegate via Task tool
        String codeResult = taskExecutor.delegate("coder", 
            "Implement: " + featureRequest + "\nContext: " + context);

        String reviewResult = taskExecutor.delegate("reviewer", codeResult);
        String docsResult = taskExecutor.delegate("docs", codeResult);

        // Log run
        saveRunLog(featureRequest, codeResult, reviewResult, docsResult);

        return "Complete";
    }
}
```

### 4. Keep Your .md Files

```
src/main/resources/
├── AGENTS.md                 # Global rules
├── agents/
│   ├── orchestrator.md       # Orchestrator prompt
│   ├── coder.md             # Coder system prompt
│   ├── reviewer.md          # Reviewer system prompt
│   └── docs.md              # Docs system prompt
├── memory/
│   └── project.md
└── skills/                  # Optional prompt snippets
```

### 5. REST Controller

```java
@RestController
public class OrchestratorController {

    private final OrchestratorAgent orchestrator;

    @PostMapping("/feature")
    public String addFeature(@RequestBody String featureRequest) {
        return orchestrator.orchestrate(featureRequest);
    }
}
```

## Operations & Setting up

### Local LLM Setup

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull models
ollama pull llama3.2:8b      # Orchestrator/Coder
ollama pull mistral:7b       # Reviewer
ollama pull phi3:14b         # Docs

ollama serve
```

### File Loading

Spring Boot loads `.md` files as **system prompts** automatically via `system-prompt-file`.

**AGENTS.md** becomes orchestrator's base context

### Run It

1. `mvn spring-boot:run`
2. `curl -X POST http://localhost:8080/feature -d "Add JWT login"`

## Comparison

| **Criteria**          | **OpenCode CLI Agents**      | **Spring Boot AI Agents**                   |
|:--------------------- |:---------------------------- |:------------------------------------------- |
| **Deployment**        | Terminal only, single user   | REST API, Docker, Kubernetes, load-balanced |
| **File Editing**      | Native (edit, bash, git)     | FileSystemTools + ShellTools required       |
| **Multi-Agent**       | Manual `@agent` coordination | Native TaskExecutor, parallel execution     |
| **Memory/State**      | Session-based, manual files  | ChatMemory + Redis + database persistent    |
| **Local LLM**         | Mixed cloud/local            | 100% local (Ollama/LM Studio)               |
| **Monitoring**        | Terminal logs                | Actuator, Micrometer, tracing               |
| **Scalability**       | Single process               | Horizontal scaling, clustering              |
| **Development Speed** | 5 minutes setup              | 2+ hours Spring Boot config                 |
| **Team Sharing**      | Folder structure in git      | JAR deployment + config management          |
| **CI/CD Integration** | `opencode` in GitHub Actions | Full Spring Boot pipeline                   |
| **Your .md Files**    | Native discovery             | Manual resource loading                     |
| **Skills/Tools**      | Native SKILL.md files        | Spring AI tool annotations                  |
| **Production Use**    | Prototyping, personal        | Enterprise, teams, services                 |
| **Learning Curve**    | Low (CLI + markdown)         | High (Spring AI ecosystem)                  |
| **Cost**              | Free (OpenCode)              | Free (open source)                          |
| **Debugging**         | Session transcripts          | Logs + debug endpoints                      |
| **Customization**     | Agent prompts + skills       | Java code + annotations                     |

## 🏆 Winner by Use Case

| **Use OpenCode if** | **Use Spring Boot if**               |
|:------------------- |:------------------------------------ |
| Personal projects   | <mark>Team/production systems</mark> |
| Quick prototyping   | REST API needed                      |
| Terminal workflow   | <mark>Database integration</mark>    |
| Learning AI agents  | <mark>Enterprise deployment</mark>   |
| Git-only sharing    | Monitoring required                  |

## 🎯 Recommendation

**Start with OpenCode** for your Spring Boot project:

- ✅ Zero Java coding
- ✅ Uses your exact folder structure
- ✅ Native file editing
- ✅ Works today

**Migrate to Spring Boot** when you need:

- Team API access
- Production monitoring
- Database run history
- Horizontal scaling
