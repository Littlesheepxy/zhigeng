# iOS 开源依赖审计（知更键盘）

> 每个复制进 `apps/ios` 的文件必须在此登记：来源、commit、许可证、修改范围。
> 审计日期：2026-07-20。商业发行前再跑一次许可证扫描。

## 允许 / 禁止

| 状态 | 项目 | 许可证 | 用途 |
|------|------|--------|------|
| 允许参考 | [Hamster](https://github.com/imfuxiao/Hamster) | MIT（仓库 `LICENSE.txt`） | Rime 集成、候选栏、模式切换、App Group 模式；不整仓 fork |
| 已放弃 | [librime](https://github.com/rime/librime) | BSD-3-Clause | 引擎本身可用，但生态词库全是 GPL/LGPL/无声明，配不到能商用的数据；改为自研 Swift 引擎 + 万象词库，见 `docs/ios-session-plan.md` 的决策修订 |
| 允许参考 | [azooKey](https://github.com/azooKey/azooKey) | MIT | 状态管理 / UI↔引擎解耦；不复制日文转换引擎 |
| 允许参考 | [Wave iOS](https://github.com/madebysan/wave-ios) | MIT | 主 App 录音 + Keyboard Extension + App Group 语音桥 |
| 允许参考 | [Dictus iOS](https://github.com/getdictus/dictus-ios) | MIT | App Group 状态机与扩展隔离 |
| 允许参考 | [Muesli iOS](https://github.com/Muesli-HQ/muesli-ios) | MIT | 听写 handoff / Live Activity 模式 |
| 禁止并入 | KeyboardKit 10+ | Closed Source | 不用作依赖；完整本地化属 Pro |
| 禁止并入 | [Squirrel](https://github.com/rime/squirrel) | GPL-3.0 | 仅可读，不得链接或复制进发行物 |
| 禁止并入 | TypeWhisper / iRime | GPL-3.0 | 不得合并源码 |
| 禁止并入 | GuruIM（Hamster fork） | MIT + Commons Clause | 禁止作为付费产品底座 |

## Hamster 注意事项

- 开源仓库最后活跃约 2025-05；后续商业功能不再开源。只能基于公开 MIT 快照学习。
- README 仍引用「KeyboardKit MIT」——与当前 KeyboardKit 10 闭源不符。**知更不得依赖 KeyboardKit。**
- 依赖列表出现 GPL 的 Squirrel：知更完全不碰 Rime 生态的代码，拼音引擎自研，所以这条已不构成风险。

## 复制登记表

| 路径 | 来源 | Commit | 许可证 | 修改 |
|------|------|--------|--------|------|
| `ZhigengCore/Resources/pinyin.zpd` | [RIME-LMDG 万象](https://github.com/amzxyz/RIME-LMDG) release `dict-nightly` 的 `dicts.zip` | 2026-07-28 取 | **CC-BY 4.0** | 由 `tools/pinyin-dict/build.py` 取 `zi` + `jichu` 两表，去声调、ü→v、按 key 排序后打成二进制；weight ≥ 300 剪枝 |

**CC-BY 4.0 的署名是发行条件，不是可选项。** 已落地：「我的 → 设置与支持 → 开源声明」（`OpenSourceNoticesView`，`ZhigengApp/MeViews.swift`），写明词库来自 amzxyz/RIME-LMDG、CC-BY 4.0、修改范围，并附仓库与协议原文链接。改动词库来源或处理方式时必须同步改这一页。

被许可证挡掉的同类词库，避免以后重复调研：雾凇拼音 / 白霜拼音 / libpinyin / 深蓝词库转换均为 GPL-3.0，rime-essay 与 rime-octagram-data 为 LGPL-3.0，CustomPinyinDictionary 无 LICENSE 文件（默认保留所有权利）。万象是唯一宽松许可且质量达标的。

## Spike 验收清单（真机）

- [ ] 键盘扩展加载 mmap 词库连续输入：常驻内存目标 <40MB，无被杀
- [ ] 微信 / 备忘录连续输入 10 分钟：扩展峰值内存目标 <40MB，无被杀
- [ ] SwiftUI KeyGrid 按键反馈 P95 <50ms；不达标再做 UIKit 对照
- [ ] PiP：按需开麦、来电恢复、审核语义可解释
- [ ] Live Activity：仅状态 / 入口，不承担录音执行
