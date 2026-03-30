# Windows setup

Full automation isn't worth the time here. The two services that run on the Windows machine for the homelab are Steam for remote play and Ollama for LLM inference.

## Ollama setup

1. Download from the Ollama website
2. Pull models:
   ```
   ollama pull deepseek-code-v2
   ```
3. Enable "expose over network" in Ollama settings
4. Setup auto-start via Task Scheduler:
   - Create Task, give it a name
   - Check "Run whether logged on or not"
   - Check "Run with highest privileges"
   - Triggers tab: "At startup"
   - Actions tab: run `"C:\Program Files\Ollama\ollama.exe"` with args `run deepseek-coder-v2`
   - Configure Settings tab as desired

## Steam

Download and install — remote play works out of the box.
