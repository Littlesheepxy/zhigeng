# iOS 知更 — 键盘优先原生方案（Session 简报）

给**另一个 Cursor session**用的执行简报。改动均在 `apps/ios`（新目录）+ 少量后端配套；不碰桌面端功能代码。

> 本文件可以随时修改：改完哪节，把对应约束/里程碑同步更新即可；执行 session 以本文件为准。

## Goal

任何 App 里切到知更键盘 → 点麦说话 → 流式上屏 → 松手插入净化后文本。**原生 Swift/SwiftUI**，对标 Typeless / Wispr Flow 的丝滑体验。

## 已定决策（用户已确认，勿再问）

| 决策 | 结论 |
|------|------|
| 产品形态 | **键盘优先**：键盘扩展 + 主 App 双体；主 App = 首页 + 活动 + 懂我 + 我的 |
| 主 App IA | 四 Tab；Onboarding 四段（品牌/试说/键盘/完成）；PC 活动+轨迹合并为「活动」，连接进「我的」 |
| 语音卖点 | 轻声输入（真机验收后主宣）、去口头词、场景整理；结果页只显示真实发生的处理标签 |
| 技术栈 | **原生 Swift/SwiftUI**，不用 HBuilder/uni-app/RN；最低 **iOS 17** |
| 代码位置 | **Fold One monorepo 里新建 `apps/ios`** |
| 键盘页 | Voice + 拼音（**自研 Swift 引擎**，26 键 / 九键两套布局）+ Symbols；不绑 KeyboardKit |
| 开源策略 | Hamster / azooKey **只作样板**；中文底座 **自研 Swift**（词库取万象 RIME-LMDG，CC-BY 4.0）；语音桥参考 Wave/Dictus（MIT） |
| 产品特色 | 语音与拼音共用 `PersonalLexicon`：修正一次 → 拼音候选加权 + ASR hotWords |
| v1 ASR | **iOS 主 App：火山 `SpeechEngineAsrToB`（豆包）**，凭证由 `account-api` `/asr/volc-token` 下发；PC 仍走 `apps/asr-proxy` / Fun-ASR |
| 净化/热词 | 服务端 structure + vocabulary；客户端维护个人词并随 `start.hotWords` 上传 |
| 免切换 | PiP 主实验 + Live Activity 状态入口；不达标则回退显式切主 App |
| 账号 | 复用 `apps/account-api`（邮箱验证码 → `zk_` Bearer）；上架前补 Sign in with Apple |
| 签名 | Team `D4NF2N957K`（本机已有开发证书） |

## 为什么不用 supa-man 的混合壳（背景，不用复述）

supa-man（`~/Desktop/supa-man/apps/mobile`）是 uni-app + HBuilder 离线 SDK。踩过的坑：云打包依赖 GUI、Widget 靠 Ruby 改 pbxproj、WKWebView 缺 `URL`/`URLSearchParams`、流式 ASR 准确率不足最终回退「录完上传」。**可以参考的**：Live Activity/灵动岛与录音联动（`Native/LiveActivity/`）、better-auth Apple 登录流程、后端临时凭证模式。

## 平台硬限制（架构由此而来）

**iOS 键盘扩展拿不到麦克风**（iOS 8 至今，所有竞品同此）。业界标准做法（Wispr Flow / Muesli / Wave 同款）：

```text
键盘扩展（RequestsOpenAccess + App Group）
  ├─ 点麦 → URL scheme 唤起主 App
  ├─ 主 App：录音 → 流式 ASR → 净化 → 写 App Group + Darwin notification
  ├─ 用户返回原 App（v1 手动切回保底；自动返回无公开 API，勿依赖私有 API）
  └─ 键盘轮询 App Group → 插入文本
```

**丝滑关键 = 听写会话时间窗**（对齐 `docs/voice-standby.md` 的会话级待机）：主 App 保持一个「听写会话」（5min/15min/1h 可选），窗口内键盘点麦不再切 App，音频经主 App 后台音频会话直传。

## Global Constraints

- 新代码全部在 `apps/ios/`；后端改动（若有）走独立小 PR
- 键盘扩展内存上限 ~50MB，UI 保持轻量，不进大依赖
- WS 协议以现有实现为规格：`packages/voice/src/aliyun-asr.ts`（客户端行为）+ `apps/asr-proxy/src/session.ts`（服务端）
- 铁律沿用仓库规则：录音数据不得静默丢弃；finish 超时/断线 = incomplete，提示重说，禁止当成功插入
- 每个里程碑留一个可跑验证（真机/模拟器路径写清楚）
- 分支 `feat/ios-keyboard`，按里程碑拆 PR

## 里程碑

### M0 — 工程骨架
- `apps/ios` Xcode 工程：主 App（SwiftUI）+ `ZhigengKeyboard` 键盘扩展 + Live Activity
- App Group：`group.app.zhigeng.ios`；URL scheme：`zhigeng://`
- Core 包：`AppGroupBridge` + `PersonalLexicon`（`swift test` 可跑，不依赖模拟器）
- 品牌资源复用 `apps/desktop/public/zhigeng-*`
- 验证：`cd apps/ios && xcodegen generate && swift test`；真机装上后键盘能在设置里启用、能打开主 App
- 状态（2026-07-20）：骨架已生成，`swift test` 20/20 通过；generic iOS Simulator **BUILD SUCCEEDED**；主 App 已替换占位 List，落地 Onboarding 四段 + 四 Tab（首页/活动/懂我/我的）；真机 App Group / Full Access 待做；ASR 真机流式待接通（试说暂为标注示例整理）

### 决策修订：中文底座不用 librime，改为自研 Swift（2026-07-28）

原计划的 BSD librime 三条都不成立：

1. **内存**。键盘扩展只有 ~50MB 就会被杀，librime 的 Rime 引擎加上编译期词典要在这个预算里腾挪，属于把最紧张的资源交给一个我们改不动的 C++ 依赖。
2. **许可证**。librime 本体是 BSD，但生态里能用的词库几乎都不是——rime-ice 是 GPL-3.0，其余多为 LGPL 或干脆无声明，跟闭源上架冲突。BSD 的引擎配不到能商用的数据，等于没有底座。
3. **桥接成本**。Swift ↔ C++ 的构建、签名和崩溃排查开销，在一个纯查表 + Viterbi 的问题上不划算。

现方案：`PinyinSegmenter`（音节切分成格）+ `PinyinComposer`（Viterbi 解码）+
`PinyinFileDictionary`（mmap 二进制表）+ `PinyinSession`（编码缓冲状态机），
全部在 `ZhigengCore`，可用 `swift test` 覆盖。词库由 `tools/pinyin-dict/build.py`
从万象 RIME-LMDG 产出，`min-weight=300` 剪到 25MB（gzip 10MB），实测探针
准确率 100%。mmap 让常驻内存只等于真正查过的页，这是能塞进扩展预算的原因。

万象是 **CC-BY 4.0，必须署名**，见 `docs/ios-open-source-audit.md`。

### M0.5 — 主 App UI（当前）
- Onboarding：品牌能力 → 试说学习 → 键盘验证 → 准备完成
- Tab：首页 / 活动 / 懂我 / 我的；首页仅 ReadyCard + 最近听写 + 最近学会
- 键盘扩展写入 `KeyboardHeartbeat`；主 App 不臆测 Full Access
- 验证：Xcode 真机安装 → 走完引导 → 四 Tab 可点 →「我的 → 重新运行引导」可重进

### M1 — 主 App 内听写端到端（先不做键盘）
- AVAudioEngine 采 16k PCM → **豆包流式 ASR**（`SpeechEngineAsrToB` + account-api `/asr/volc-token`）
- 流式 partial 实时上屏；松手 finish → 识别结果（structure 净化二期）
- 结果页：复制 / 分享
- 验证：真机登录 account-api → 对着 `docs/agent-stress-checklist.md` 的 V1–V8 说一遍；未配 `VOLC_ASR_*` 时应看到明确错误

### M2 — 键盘扩展 + 切换回插
- 键盘 UI：麦按钮 + 最近结果 + 地球键切回系统键盘
- 点麦 → `zhigeng://dictate` 唤起主 App → 录 → App Group 写结果 → 键盘插入
- 听写会话时间窗（会话内免切换直录）
- 验证：在微信/备忘录里完整走一遍「切键盘 → 说 → 插入」

### M3 — 账号 / 热词 / 权益
- 邮箱验证码登录（`apps/account-api`）
- ⚠️ 已知不一致：account-api 发 `zk_` 前缀 token，asr-proxy/gateway 注释偏 `tm_`——对接前先核对齐
- 热词：onboarding 采集（对齐桌面 know-you 步骤）→ 服务端 vocabulary 下发
- Free/Pro 档位 + voice-usage 上报
- 验证：热词导入前后同一句话的专名命中对比

### M4 — 丝滑打磨
- 灵动岛 / Live Activity 录音态（参考 supa-man `SupamindLiveActivity`）
- Action Button / 锁屏 Widget 直达听写
- 触觉反馈、上屏动效、断网降级文案

### 配套（不在 apps/ios，但发内测前必须）
- **asr-proxy 公网部署**：现在只有本机 dev；真机离开局域网就没 ASR。托管方案另定（ECS / 云函数均可）
- TestFlight 分发（Developer 账号已就绪）

## 2026-07-21 TODO

1. **把今日验证过的原型同步到原生 iOS**
   - 以 `prototypes/zhigeng-mobile` 为已确认交互规格，不再把原生 SwiftUI 页面停留在功能占位态
   - 完整同步 Onboarding、首页、活动、懂我、我的视觉层级、文案、点击跳转和状态变化
   - 同步轻声/气声试说、免切换开关、账户叠卡、活动语义色和 Mac 远程入口
   - 每个页面同步后必须在真机逐页对照原型验收，不能只以模拟器 Build 通过作为完成

2. **移动端主 App UI 收口**
   - 统一首页、活动、Mac 任务、懂我、我的视觉层级与空/加载/错误态
   - 重做 Mac 任务消息气泡、执行步骤、完成结果和审批卡，不直接暴露桌面 Overlay 的技术字段
   - 修复远程结果中的 `page/bbox`、Markdown 图片占位等技术噪声；先在共享结果边界清理，避免只补 iOS 展示
   - 真机检查安全区、键盘顶起、长文本、深浅色与动态字体

3. **语音键盘产品与 UI 设计**
   - 闭合最小循环：切到知更键盘 → 点麦 → 说话 → 整理 → 插入 → 可撤销
   - 明确首次唤起主 App、免切换会话、后台失效、断网和未开 Full Access 的状态机
   - 设计单手可用的黑白键盘；录音态仅使用状态强调色，不复制桌面黑色语音胶囊
   - 覆盖普通听写、轻声/气声、去语气词、按当前 App 修正格式、个人词命中

4. **语音键盘首版原型**
   - 先做可点击 SwiftUI/键盘扩展状态原型，再接真实 ASR
   - 在微信与备忘录真机验证「说完可插入」，记录切换次数、首字延迟和失败恢复

5. **远程链路补验**
   - 补完 iPhone HITL 审批、设备撤销、网络断开重连和任务中途重连

## 关键风险

| 风险 | 应对 |
|------|------|
| 键盘→主 App→返回原 App 无公开自动返回 API | **省电待命（PiP）/ 长时间待命（后台音频）**：首次激活后窗口内免跳转；失活后再走 `zhigeng://activate`；iOS 26.4+ 可能需手动滑回 |
| asr-proxy 无公网部署 | iOS 主路径已切豆包 `/asr/volc-token`；PC 仍 Fun-ASR |
| 键盘扩展 50MB 内存上限 | 扩展内零重依赖，逻辑全在主 App |
| 火山/豆包流式（product.md §5.4 方向）与 v1 复用 DashScope 冲突 | `AsrProvider` 协议隔离，二期实测延迟后再切，不阻塞 v1 |

## 参考路径

- 协议规格：`packages/voice/src/aliyun-asr.ts`、`apps/asr-proxy/src/session.ts`、`apps/asr-proxy/src/vocabulary.ts`
- 决策文档：`docs/product.md` §5.4（iOS 流式 ASR 决策）、`docs/voice-standby.md`（会话级待机）、`docs/plan-tiers.md`
- 账号/权益：`apps/account-api/src/`、`apps/asr-proxy/src/entitlements.ts`
- supa-man 参考（只抄模式不抄壳）：`~/Desktop/supa-man/apps/mobile/ios-native`

## 开 session 时的用户提示词（可复制）

```text
按 docs/ios-session-plan.md 执行 iOS 版开发，从 M0 开始，按里程碑拆 PR（分支 feat/ios-keyboard）。
决策已定勿再问形态/技术栈；每个里程碑完成后给我真机验证步骤再继续。
```
