# 知更 iOS（键盘优先）

原生 Swift/SwiftUI，iOS 17+。主 App + 键盘扩展 + Live Activity。

主 App：Onboarding（品牌 → 试说 → 键盘验证 → 完成）+ 四 Tab（首页 / 活动 / 懂我 / 我的）。

## 生成工程

```bash
cd apps/ios
xcodegen generate
pod install
open Zhigeng.xcworkspace   # 必须用 workspace，不要直接开 .xcodeproj
```

CocoaPods 仅链入主 App target（`SpeechEngineAsrToB`），键盘扩展 / Live Activity 不含豆包 SDK。

## 跑 Core 测试（不依赖模拟器）

```bash
cd apps/ios
swift test
```

## 听写 ASR（豆包）

iOS 主 App 听写走火山 `SpeechEngineAsrToB`；PC 桌面仍用 Fun-ASR / `apps/asr-proxy`。

真机听写前需在 account-api 配置：

- `VOLC_ASR_APP_ID`
- `VOLC_ASR_TOKEN`
- `VOLC_ASR_CLUSTER`

App 登录后向 `GET /asr/volc-token`（Bearer `zk_`）拉取短时凭证。未登录或未配 env 会显示明确错误，不会静默回退 Fun-ASR。

## 真机验证（M0.5 UI）

1. Xcode 选真机 Run 安装（workspace scheme `Zhigeng`）
2. 首次打开走完引导；试说需登录 + 豆包凭证
3. 进入四 Tab：首页就绪卡、活动列表、懂我加词、我的诊断
4. 设置里启用知更键盘并开完全访问；在验证区切到知更后，「我的 → 诊断」应出现键盘心跳

## 真机注意

- Team：`D4NF2N957K`
- App Group：`group.app.zhigeng.ios`（需在 Apple Developer 注册）
- URL Scheme：`zhigeng://`
- 键盘扩展需在设置里启用，并打开「允许完全访问」

决策与里程碑见 `docs/ios-session-plan.md`；开源边界见 `docs/ios-open-source-audit.md`。
