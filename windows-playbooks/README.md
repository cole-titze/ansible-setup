# Windows setup
Full automation isn't worth the time here. The two services that I run on my windows machine for the homelab is steam for remote play and ollama for the code-server LLM.
## Static ip steps
1. Go to settings -> Network & internet
2. Select properties for connected network
3. Change IP to manual and fill in the fields (currently using 10.0.0.80)

## Ollama setup
+ Go to ollama download site
+ Pull some models
```
ollama pull deepseek-code-v2
```

## Steam
+ Download steam off the internet
+ Remote play should work straight away