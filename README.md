# 知更

[zhigeng.app](https://zhigeng.app) · 懂你正在做什么的语音输入。

> 知你所言，才更懂你意。你说一句，它写好；说到，也能做到。

面向用户的产品名是 **知更**；本仓库工程包名仍为 `@fold/*`。

源码按 [PolyForm Noncommercial 1.0.0](LICENSE) 公开：可以看、可以自用、不可以商用。

## 下载

官网：[https://zhigeng.app](https://zhigeng.app)

当前提供 **macOS Apple Silicon** 签名公证安装包。打开网站点下载即可，不需要内测码。

大模型不能在本机「下一个 LLM 就能用」。语音可以完全本地（SenseVoice / Whisper）；推理请在设置里填你自己的云端 API Key。

## 它和普通语音输入差在哪

1. **开口即成稿**  
   短按右 ⌘。不是逐字听写：改口会修好，口头禅可以去掉，并按飞书 / 微信 / 邮件调语气。也可以关掉智能整理，只去掉嗯呃。

2. **先懂你正在做什么**  
   看当前窗口、对话、剪贴板和正在推进的事。Menu Bar 常驻，不抢焦点，不用先打开一个聊天窗口解释背景。

3. **读懂对话，给你几条可选用的回复**  
   长按右 ⌘。按对方和应用给出多条草案，你点一条插入真实输入框，再决定发不发。

4. **简单的事先确认再做，复杂的事交给你已经在用的 Agent**  
   ⌥ Space。发消息、整理文件这类事，授权后由知更执行；代码和重活交给本机 Codex、Claude Code 或 WorkBuddy，做完再通知你。取消即停。

5. **越用越懂你的工作方式**  
   记住你在意谁、正在做什么、常用什么口吻。记忆留在本地，可看、可关、可删。

6. **本地优先，钥匙自己拿**  
   语音可走本机 SenseVoice（约 230MB）或 Whisper；云端 ASR 可选。大模型走你自己的 Key（OpenAI / Anthropic / 智谱 / Kimi / OpenRouter / 自定义 Base URL），存在系统钥匙串。

## 桌面快捷键

| 操作 | 快捷键 |
|------|--------|
| 结构化输入 | **右 ⌘** 短按 |
| 情境代回 | **右 ⌘** 长按 |
| 交给本机 Agent | **⌥ Space** |
| 取消 | Esc |

例：下载一份 PDF 到 `~/Downloads`，短按右 ⌘ 说「帮我整理刚下载的报价发给 Jason」。

## 自己跑

```bash
pnpm install
cp .env.example .env   # 可选；不填 Key 也能用 mock 看流程
pnpm desktop:dev       # 桌面客户端
pnpm site:dev          # 官网 https://zhigeng.app 的本地预览
```

打包签名 DMG（需本机 Developer ID 与公证凭据）：

```bash
pnpm desktop:pack
```

## 仓库结构

```
apps/desktop     macOS 客户端（Electron）
apps/site        官网（Next.js）→ zhigeng.app
apps/ios         iOS 输入法与配套能力（开发中，不在当前 DMG 里）
packages/        模型路由、执行器、情境、记忆、技能
```

## 协议

[PolyForm Noncommercial 1.0.0](LICENSE)。个人学习、研究、自用可以；拿去做产品、接客户、卖服务不行。商业合作请联系 [hello@zhigeng.app](mailto:hello@zhigeng.app)。
