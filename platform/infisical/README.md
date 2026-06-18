# Infisical

> 📚 Architecture, the secrets-flow, and the `init` vs `standard` agent model live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)** and **[Bootstrapping a Host from Scratch — Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd)**. This file covers only `stack.infra/infisical`: how to run it and its quirks.

## Startup
By default, the compose profile is set to only start the Infisical app, not the agent. Agent is meant to be run separately so it can restart separately from the app. To run the agent, check the compose file for the correct profile to use in your compose command.