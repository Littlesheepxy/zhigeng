<div align="center">
  <img src="apps/desktop/public/zhigeng-app-icon.png" alt="Zhigeng Logo" width="120" />
  <h1>Zhigeng 知更</h1>
  <p><strong>AI is capable. What it lacks is knowing you.</strong></p>
  <p>An independent, vendor-neutral voice input and memory agent</p>
  <p><a href="README.md">简体中文</a> · <a href="README_EN.md">English</a></p>
  <p>
    <a href="https://zhigeng.app"><img src="https://img.shields.io/badge/Website-zhigeng.app-2563eb?style=flat-square" alt="Website" /></a>
    <a href="https://zhigeng.app/Zhigeng-mac-arm64.dmg"><img src="https://img.shields.io/badge/Download-macOS%20Apple%20Silicon-111827?style=flat-square" alt="Download for macOS" /></a>
    <a href="https://github.com/Littlesheepxy/zhigeng/releases"><img src="https://img.shields.io/github/v/release/Littlesheepxy/zhigeng?style=flat-square&label=Release" alt="Release" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/Source%20Available-Noncommercial-orange?style=flat-square" alt="PolyForm Noncommercial License" /></a>
  </p>
  <p>
    <a href="https://zhigeng.app">Website</a> ·
    <a href="https://zhigeng.app/Zhigeng-mac-arm64.dmg">Download macOS</a> ·
    <a href="https://github.com/Littlesheepxy/zhigeng/releases">Release</a> ·
    <a href="mailto:littleyang78@gmail.com">Contact</a>
  </p>
</div>

Zhigeng is an independent, vendor-neutral voice input and memory agent. It does not force you into another chat window or lock your memory inside one model provider's account.

**Voice captures your intent, input reflects how you communicate, and local activity shows what you actually do.** Within the permissions you grant, Zhigeng turns these signals into long-term memory that belongs to you—viewable, editable, deletable, and available to the models and agents you choose.

So you no longer need to explain the same context over and over:

> **You say less. Your agents get more right.**

On Mac, Zhigeng handles voice input, context-aware replies, and orchestration of local agents such as Codex and Claude Code. The iOS app in development will become a portable memory terminal and remote control for your local agents—letting you capture context, continue work, and send instructions to the Mac at your home or office while on the go.

**The goal is not to hand you over to one AI, but to bring your context to the AI you choose.**

[zhigeng.app](https://zhigeng.app) · Source is available under the [PolyForm Noncommercial 1.0.0](LICENSE): **you may inspect, modify, study, and use it for noncommercial purposes. Commercial use is not permitted.**

The product is called **Zhigeng**; internal workspace packages still use the `@fold/*` scope.

## Download

| | |
|---|---|
| **Website** | [https://zhigeng.app](https://zhigeng.app) |
| **macOS installer** | [Zhigeng-mac-arm64.dmg](https://zhigeng.app/Zhigeng-mac-arm64.dmg) (Apple Silicon, signed and notarized) |
| **Release notes** | [github.com/Littlesheepxy/zhigeng/releases](https://github.com/Littlesheepxy/zhigeng/releases) |

Open the website and download—no beta access code required.

Voice recognition can run fully on-device with SenseVoice or Whisper. LLM inference uses your own cloud API key (BYOK), stored only in your local system keychain.

## Screenshots

### Home · Context awareness

Zhigeng understands your current windows, conversations, clipboard, and active work. It lives in the menu bar without stealing focus.

![Home: contextual inference, recent activity, and usage stats](docs/readme/desktop-home.png)

### Voice input · Speak, then get a polished draft

Tap **Right ⌘** to transcribe. Zhigeng can resolve spoken corrections, remove filler words, and adapt tone for apps such as Lark, WeChat, and email.

<p align="center">
  <img src="docs/readme/voice-listening.png" alt="Hold Right Command for live transcription" width="48%" />
  <img src="docs/readme/voice-input.png" alt="Insert the polished transcription into the target app" width="48%" />
</p>

### Activity · Transcription, replies, and actions

Every voice input, reply draft, and local action is recorded so you can review both the original request and the result.

![Activity: polished transcription, reply drafts, and local actions](docs/readme/desktop-activities.png)

### Contextual reply · Understand the conversation first

Hold **Right ⌘**. Zhigeng reads the current conversation, proposes several replies, and lets you insert one before deciding whether to send it.

![Contextual reply: multiple drafts generated from the current conversation](docs/readme/smart-reply.png)

### Trail · Local activity context

See which apps and windows you worked in, along with clipboard history used for contextual understanding.

![Trail: application context and clipboard history](docs/readme/desktop-trail.png)

### Memory · People, projects, and you

Zhigeng remembers who matters, what you are working on, and how you prefer to communicate. Memory stays local and can be viewed, disabled, edited, or deleted.

![Memory: people, projects, and working preferences](docs/readme/desktop-memory.png)

### Connections · Agents and collaboration tools

Zhigeng handles simple tasks directly and hands complex work to Codex, Claude Code, or WorkBuddy. It can connect with Lark, DingTalk, WeCom, Slack, Gmail, and more.

![Connections: local agents, communication tools, and screen context](docs/readme/desktop-connections.png)

### Settings · BYOK and local ASR

Configure shortcuts, transcription cleanup, offline speech recognition, and your own model providers.

![Settings: shortcuts, voice input, local ASR, and BYOK](docs/readme/desktop-settings.png)

## What makes it different

1. **Speak into a finished draft** — Tap Right ⌘ for context-aware formatting, or disable smart cleanup and only remove filler words.
2. **Understand what you are already doing** — Use windows, conversations, clipboard, and tasks without making you explain everything in a new chat.
3. **Generate replies for the conversation in front of you** — Hold Right ⌘, choose a draft, and insert it.
4. **Hand complex work to your local agents** — Press ⌥ Space to send tasks to Codex or Claude Code, with confirmation and cancellation controls.
5. **Become more useful over time** — People, projects, and preferences accumulate as user-controlled local memory.
6. **Local-first and BYOK** — Speech can stay on-device; model inference uses the providers and keys you choose.

## iOS keyboard (in development)

`apps/ios` is building an **iOS 17+ keyboard extension and portable memory terminal**. The target experience includes system-wide typing, streaming voice input, intelligent candidates, and sentence-level Pinyin composition—without opening a separate app and copying text back and forth.

It will also carry your context and memory, and send instructions to local agents running on a Mac at your home or office.

Current work:

- **Keyboard extension + Live Activity** — Voice input directly inside any app
- **Pinyin engine** — Custom segmentation, sentence composition, candidates, and correction in `ZhigengCore`
- **Streaming ASR** — Volcengine speech recognition in the iOS app; SenseVoice, Whisper, or cloud ASR on desktop
- **Shared memory and profile** — People, vocabulary, and preferences across devices, progressively
- **Local agent remote control** — Add context and send instructions from iPhone for execution on Mac (in development)

The iOS app is **not included in the current macOS DMG**. See [`apps/ios/README.md`](apps/ios/README.md) for development details.

## Desktop shortcuts

| Action | Shortcut |
|--------|----------|
| Structured voice input | Tap **Right ⌘** |
| Contextual reply | Hold **Right ⌘** |
| Send to a local agent | **⌥ Space** |
| Cancel | Esc |

## Run locally

```bash
pnpm install
cp .env.example .env   # Optional; mock mode works without model keys
pnpm desktop:dev       # Desktop client
pnpm site:dev          # Local website preview
```

Build a signed DMG (requires a local Developer ID and notarization credentials):

```bash
pnpm desktop:pack
```

## Repository structure

```text
apps/desktop     macOS desktop client (Electron)
apps/site        Website (Next.js) → zhigeng.app
apps/ios         iOS keyboard and companion capabilities (in development)
packages/        Model routing, execution, context, memory, and skills
docs/readme/     README screenshots
```

## Source and license

This repository is source-available under the **[PolyForm Noncommercial 1.0.0](LICENSE)**.

| Allowed | Not allowed |
|---------|-------------|
| Inspect, study, and research the source | Turn the source or derivatives into a commercial product |
| Modify and use it personally or noncommercially | Sell services, client work, or SaaS based on it |
| Participate through feedback and issues | Redistribute it without the required notices |

See [`LICENSE`](LICENSE) for the complete legal terms. For commercial licensing and partnerships: [littleyang78@gmail.com](mailto:littleyang78@gmail.com).

## About the builder

**Little Yang**

An AI builder with a recruiting background, currently leading AI product work. I explore AI products, agent communication, machine identity and collaborative trust, and how AI can become part of real everyday work.

I am also exploring **AI Dealroom**—a trusted identity and opportunity network for people and agents in the AI era, helping founders, talent, projects, and agents discover one another, verify capabilities, and start working together.

Founders, AI builders, and agent researchers are welcome to reach out.

📮 [littleyang78@gmail.com](mailto:littleyang78@gmail.com)
