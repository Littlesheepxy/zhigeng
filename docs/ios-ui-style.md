# 知更 iOS UI 风格：雾光效率感

## 一句话

**一只陪你表达的知更鸟，置于清透紫蓝雾光中；界面有亲和力，但文字、交互和状态保持专业克制。**

融合来源：

- 参考 App：只借鉴大面积 Hero 构图、吉祥物作为状态主角、圆弧分区、轻卡片和轻盈导航感；不借用其暖色配色或自绘 Tab Bar。
- 知更 Landing Page：紫蓝雾光、留白、上下文 Compose 卡、胶囊状态、强标题与清晰正文；PC 专属的黑色悬浮语音条不移植。

不是儿童化健康 App，也不是系统设置页；定位是 **有角色感的中文效率产品**。

## 视觉原则

1. **一个页面只有一个视觉主角**：首页是知更鸟与就绪状态，试说页是语音主控件，活动页是结果列表。
2. **吉祥物必须表达状态**：待机、聆听、整理、学会、需要处理，而不是每页重复摆 Logo。
3. **柔和背景，清晰内容**：雾光可以轻，正文必须深；不使用大面积低对比灰字。
4. **品牌色只留在主 App**：紫色用于主 App 按钮、选中和学习；键盘保持黑白中性；录音使用橙色，成功使用绿色。
5. **少卡片、强层级**：首页最多一个 Hero、一个主任务卡、两条轻列表；不把所有内容装进相同白卡。
6. **能力靠结果证明**：显示“去除口头词”“按消息整理”“命中常用词”，不堆 ASR、模型、Prompt 等技术名词。

## Taste Skill 与 Apple HIG 校准

本机的 Anthropic `frontend-design` 和外部 `taste-skill` 都强调先确定设计方向、避免模板化 AI UI；后者明确把原生移动端列为范围外，并要求直接使用 Apple HIG。因此知更只吸收其可迁移原则，不照搬 Web 的字体、GSAP 或高变体布局。

### 三个设计旋钮

- `DESIGN_VARIANCE = 6/10`：Hero 和状态舞台可以有圆弧、错位雾光和 Robin 动作；导航、表单、列表保持 iOS 熟悉结构。
- `MOTION_INTENSITY = 4/10`：只动画状态变化、Robin 和语音波形；不做滚动劫持、持续漂浮和无意义循环。
- `VISUAL_DENSITY = 4/10`：首页偏舒展，活动与设置保持日常工具密度；不做“每屏只有一句话”的空洞画册。

### Anti-slop 规则

- 不使用默认“白底 + 紫色渐变 + 三张相同功能卡”的 AI 模板。
- Hero 必须有真实的 Robin 和产品状态，不能只有渐变色块。
- 卡片只在表达层级时使用；能靠留白、分组和分隔线解决，就不套卡。
- 同一屏不重复相同布局家族；Hero、主任务、轻列表应有明显层级差异。
- 圆角体系固定：Hero 32–40pt、卡片 20–24pt、输入 12–16pt、按钮胶囊。
- 页面品牌已是紫色，可以保留，但必须配合中性色和受控雾光，不能变成通用“AI 紫光”。

### Apple UI 层 / 内容层

- `UI 层`：Tab Bar、Navigation Bar、Sheet、Menu、Search 使用系统组件与系统材质，保证熟悉、可访问和自动适配新 iOS。
- `内容层`：Robin、雾光、Compose 结果卡、个人词学习和品牌文案承载知更识别度。
- 品牌色放在可滚动内容中；固定导航不大面积染紫。
- iOS 26 的 Liquid Glass 交给系统组件；iOS 17–18 使用系统 Material 回退，不手绘仿玻璃。

## 色彩系统

### 基础

- `Ink / #111315`：主标题与正文。
- `Secondary / #626873`：说明文字。
- `Canvas / #F7F8FC`：页面背景。
- `Surface / #FFFFFF`：主要内容面。
- `Stroke / #E5E8EF`：结构分隔，避免重阴影。

### 品牌与状态

- `Robin Purple / #675CF1`：主品牌色。
- `Robin Purple Dark / #4D46C8`：文字型品牌强调。
- `Mist Blue / #EDF4FF`：主任务卡。
- `Mist Lavender / #F1EFFF`：学习、个人词库。
- `Ice Blue / #EAF4FF`：Hero 冷色雾光。
- `Mist Cyan / #DFF7F2`：处理完成、记忆形成的局部雾光。
- `Soft Coral / #FFB39A`：仅作 4%–7% 的局部气氛光，不作为页面底色。
- `Cloud White / #FBFCFF`：Hero 高光与圆弧过渡。
- `Recording / #FF7E4E`：正在听。
- `Success / #286F45`，背景 `#E8F5EE`。
- `Error / #C43D3D`，背景 `#FDECEC`。

背景组合：

- 页面底色为 `Canvas`。
- 首页 Hero 使用 `Mist Lavender → Ice Blue → Cloud White` 的清透冷色渐变。
- 局部叠加 Landing Page 同类的多色径向雾光：
  - 紫色 10%–14%：品牌锚点。
  - 蓝色 8%–12%：智能、上下文与处理中。
  - 青色 6%–9%：完成、学会与同步。
  - 珊瑚色 4%–7%：只靠近 Robin 鸟喙、麦克风或录音区域。
- Robin 自身橙色鸟喙与录音状态提供暖色点缀；页面整体仍是冷白紫蓝，不变成暖色主题。
- 不在每张卡片使用渐变。

## 多色雾光系统

多色不是给每个模块分配一种颜色，而是作为环境光表现状态。每个页面最多出现 2–3 个雾光色，且必须围绕一个主视觉中心。

### 状态映射

- `idle / ready`：紫 + 冰蓝。
- `recording`：紫 + 局部珊瑚/橙，不染满整页。
- `processing`：蓝 + 青，缓慢流动。
- `learned / success`：紫 + 青。
- `error`：保持中性背景，仅在错误组件使用系统红，不做红色雾化大背景。

### 使用位置

- Onboarding 品牌页与完成页。
- 首页 `RobinHeroStage`。
- 全屏试说的录音/处理中舞台。
- “懂我”首次形成新记忆的成功反馈。

### 禁止位置

- 活动列表。
- 我的/设置列表。
- 普通按钮、每张小卡和键盘按键。
- 同一屏多个互相竞争的渐变卡片。

## 字体与层级

系统字体优先：`SF Pro` + `PingFang SC`。

- Hero 标题：32–36pt，Bold，行高约 1.12。
- 页面标题：28–32pt，Bold。
- 卡片标题：18–20pt，Semibold。
- 正文：16–17pt，Regular。
- 辅助文字：13–14pt，Medium/Regular，颜色不得浅于 `Secondary`。
- 标签：12–13pt，Semibold。

文案规则：

- 标题描述结果：“说完，就是能直接发送的文字”。
- 按钮描述动作：“开始免切换会话”，不用“下一步”。
- 错误描述原因与解决方式，不只写“失败”。

## 形状与空间

- Hero 底部圆弧/圆角：32–40pt。
- 主卡：24pt。
- 普通卡：18–22pt。
- 主按钮和语音条：胶囊形。
- Tab Bar：使用原生 `TabView`；在支持的新系统自然呈现悬浮/玻璃效果，旧系统使用标准 Tab Bar，不手绘仿制。
- 页面水平边距：20pt。
- 卡片内边距：18–20pt。
- 页面区块间距：18–24pt。

阴影只用于两处：

- 原生 Tab Bar：由系统材质提供非常轻的高度感。
- 语音主控件：仅在脱离键盘按键时给轻微高度感。

普通卡片优先用白色面和细描边，不使用重阴影。

## 核心组件

### 1. `RobinHeroStage`

- 页面上方约占首屏 38%–45%。
- 淡紫到冰蓝雾光背景，底部白色/页面色圆弧过渡。
- 透明背景 Robin 置中；使用 `zhigeng-robin-dock.png`，不要使用带白底的 `zhigeng-robin-normalized.png`。
- Robin 下方只显示一个主状态：
  - “知更已就绪”
  - “正在听”
  - “正在整理”
  - “今天学会了 2 个词”
- 可带一个小型胶囊提示，不叠加多段说明。

### 2. `VoiceControl`

保留 PC 端“状态集中在一个语音控件中”的机制，不复制黑色悬浮外观：

- 主 App idle：Robin Purple 圆形麦克风或紫色胶囊“点一下开始”。
- 键盘 idle：黑色麦克风主键，与系统黑白键位体系融合，不使用紫色。
- recording：控件切为 Recording Orange，显示实时波形与计时；不是整块黑底。
- processing：回到紫色，保留最后文字，波形变为轻量进度。
- PiP/Live Activity 使用系统材质和状态色，不创造第三套黑色 Overlay。

### 3. `ContextComposeCard`

继承 Landing Page 的 Compose 演示：

- 顶部一行场景：`消息 · 通用模式`、`邮件 · 已按邮件整理`。
- 中间显示最终文本。
- 底部最多三个真实处理标签。
- App 无法可靠判断时写“通用模式”，不虚构宿主 App。

### 4. `TaskCard`

- 主任务卡使用 `Mist Blue`，承载“开始免切换会话”。
- 左侧标题、状态、额度；右侧小型场景图或 Robin 局部动作。
- 其余活动使用白色轻列表，不复制同样的大卡。

### 5. `NativeTabBar`

- 四项：`首页 / 活动 / 懂我 / 我的`，使用原生 `TabView`。
- 选中项使用系统 tint 和填充图标，未选中使用线性图标；不只依赖颜色表达选中。
- 不自绘参考图里的悬浮白色胶囊，让系统在不同 iOS 版本自动选择标准或 Liquid Glass 表现。
- Robin 不作为第五个 Tab，避免把品牌角色与导航目的地混为一谈。

## 页面应用

### Onboarding

整体形态：左右滑分页（`TabView` page style）+ 顶部 4 点进度；不是整页 push/替换。当前点为紫色短胶囊，其余为描边圆点。可随时滑回已访问页；前进受解锁门槛约束（试说完成一次、键盘已检测或跳过）。

#### 品牌页

- 上半部是完整 `RobinHeroStage`：冷白底上叠紫、蓝、少量珊瑚径向雾光，视觉中心始终是 Robin。
- 品牌句：“知你所言，更懂你意。”
- 副句：“说得更自然，写得更清楚，越用越像你。”
- 三项能力改为一条可横滑的能力轨道，不再垂直堆三张大白卡：
  - 知更输入
  - 知更代回
  - 知更执行
- 底部固定主按钮“先试一句”（或右滑进入试说）；次按钮“稍后设置”直接进首页。

#### 试说页

- 去掉当前大段说明和多层白卡。
- 顶部小标题 + 场景示例。
- 中央以 `VoiceControl` 为唯一视觉主角。
- idle 使用紫蓝雾光；recording 只在麦克风周围增加橙色光晕；processing 转为蓝青雾光。
- 完成后原地展开 `ContextComposeCard`，展示整理结果和真实标签。
- 学习确认使用底部 Sheet，不再额外堆一张大卡。

#### 键盘设置页

- 保持系统可信感，不做过度装饰。
- 顶部小 Robin 指路插图。
- 三步纵向时间线，当前步骤紫色，完成步骤绿色。
- 验证区使用一个清晰输入面，不再嵌套多层卡片。

### 首页

首屏结构固定：

1. 顶部轻导航：头像 / 就绪胶囊 / 账户入口。
2. `RobinHeroStage`：Robin + 当前状态；雾光颜色随 ready / recording / processing / learned 改变。
3. `TaskCard`：开始或管理免切换会话。
4. 两条轻列表：
   - 最近听写
   - 最近学会
5. 原生 `NativeTabBar`。

首页不出现权限四行表、统计大盘和多张同形白卡。

### 活动

- 背景保持干净，弱化吉祥物。
- 每条活动使用图标 + 两行文字 + 状态，不套大卡。
- 详情页用 `ContextComposeCard` 展示最终结果与处理标签。

### 懂我

- 顶部小型淡紫 Hero：“这些词会同时用于语音和拼音”。
- 词条使用 Chip + 轻列表组合。
- “最近学会”可使用 Robin 小动作插图，但不超过 56pt。

### 我的

- 保留 iOS 原生设置结构，顶部增加品牌账户卡。
- 权益、设备、隐私、诊断采用系统分组列表。
- 不强行将所有设置改造成彩色卡片。

### 键盘扩展

键盘追求输入效率，不复制主 App Hero：

- 背景：系统浅灰/深灰。
- 按键：系统白/深灰，文字和图标使用黑色/系统前景色，圆角 8–10pt。
- 主麦克风：浅色模式黑底白图标，深色模式白底黑图标；录音中变 Recording Orange。
- 顶部状态区：44pt，显示 partial、候选或错误；拼音编码时在其上方追加 18pt 码串行，其余状态下这一行不占位。
- 拼音九键：字母是主标签、数字是右上角小上标；左侧常驻 `，。？！` 标点列，右侧 `⌫` + 双高换行。
- 仅使用 18–22pt 黑白单色 Robin mark；不放 3D 大鸟，不出现品牌紫。
- Voice / Pinyin 两个主表面；Symbols 使用标准 `123 / #+= / ABC`。

## 动效语言

- Robin idle：4–6 秒一次轻呼吸，位移不超过 3pt。
- 开始录音：Robin 微微前倾，麦克风胶囊弹入；一次轻触觉。
- 处理中：雾光缓慢移动，不使用无限旋转大 Loading。
- 学会词条：一个紫色小光点进入 Robin/词库，一次成功触觉。
- Reduce Motion：全部退化为颜色、图标和文字状态。

## 禁止项

- 带白色方形背景的 Robin 素材。
- 全屏统一灰底 + 连续白卡。
- 每页大标题、说明、卡片标题重复表达同一件事。
- 过多浅灰文字和低对比度。
- 用积分、签到、连续天数制造虚假活跃。
- 在键盘默认可见层放设置、历史、账户等低频入口（收进 Robin mark 点开的面板可以，且面板内不超过 3 项）。
- 未经真实检测宣传“任何噪声下气声都能识别”。

## 实施顺序

1. 替换透明 Robin 资产，建立颜色、字体、圆角和间距 Token。
2. 重做首页 `RobinHeroStage + TaskCard + NativeTabBar`。
3. 重做 Onboarding 品牌页与试说页。
4. 收敛活动、懂我、我的，减少白卡和重复标题。
5. 最后将同一状态语言同步到键盘扩展。

## 设计检查清单

- 第一眼是否只看到一个主角和一个主动作？
- 去掉颜色后，是否仍能靠大小、位置、字重理解层级？
- 是否出现三张完全相同的功能卡、连续白卡或重复大标题？
- 每个渐变是否对应 Hero/状态，而不是纯装饰？
- UI 层是否使用系统导航，品牌是否主要留在内容层？
- 普通正文对比度是否达到 4.5:1，点击区域是否至少 44pt？
- 最大 Dynamic Type、深色模式、Reduce Motion 和 Reduce Transparency 是否仍可用？
- 动画是否只使用 opacity/transform 等低成本属性，真机滚动是否稳定？

## 参考

- Apple WWDC26：Communicate your brand identity on iOS  
  https://developer.apple.com/videos/play/wwdc2026/251/
- Apple WWDC26：Principles of great design  
  https://developer.apple.com/videos/play/wwdc2026/250/
- Apple WWDC25：Get to know the new design system  
  https://developer.apple.com/videos/play/wwdc2025/356/
- 本机 Anthropic Frontend Design Skill  
  `/Users/littleyang/.claude/plugins/marketplaces/claude-plugins-official/plugins/frontend-design/skills/frontend-design/SKILL.md`
- Taste Skill（Web 反模板原则；原生移动端仍以 Apple HIG 为准）  
  https://github.com/Leonxlnx/taste-skill
