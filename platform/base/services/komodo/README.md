# komodo
Komodo Docker Container Manager — **Komodo Core + Mongo only** (the control plane, on `littlebuddy`). The per-host Periphery agent now lives in **`stack.node/komodo-periphery`** (one runs on every host).

> 📚 The orchestration model (Komodo Core + Mongo on `littlebuddy`, a per-host Periphery agent on every host, tier-0 bootstrap order) lives in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `stack.infra/komodo`: how to run it and its quirks.
