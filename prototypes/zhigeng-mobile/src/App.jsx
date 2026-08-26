import { useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowRight,
  CaretRight,
  ChatCenteredText,
  ChatCircle,
  CheckCircle,
  ClockCounterClockwise,
  Copy,
  Desktop,
  House,
  Keyboard,
  Lightning,
  MagnifyingGlass,
  Microphone,
  Plus,
  ShareNetwork,
  ShieldCheck,
  Sparkle,
  Trash,
  UserCircle,
  Waveform,
} from "@phosphor-icons/react";

const STEPS = ["brand", "try", "keyboard", "ready"];

export function App() {
  const [step, setStep] = useState(0);
  const [unlocked, setUnlocked] = useState(0);
  const [phase, setPhase] = useState("idle");
  const [elapsed, setElapsed] = useState(0);
  const [home, setHome] = useState(false);
  const [learnedTerm, setLearnedTerm] = useState(null); // null | "小杨" | false(skipped)
  const [keyboardReady, setKeyboardReady] = useState(false);
  const timerRef = useRef(null);
  const touchX = useRef(null);

  useEffect(() => {
    if (phase !== "listening") return undefined;
    timerRef.current = window.setInterval(() => setElapsed((v) => v + 1), 1000);
    return () => window.clearInterval(timerRef.current);
  }, [phase]);

  const canGo = (index) => index <= unlocked;

  const goTo = (index) => {
    if (!canGo(index)) return;
    setStep(index);
  };

  const unlockAndGo = (index) => {
    setUnlocked((u) => Math.max(u, index));
    setStep(index);
  };

  const onTouchStart = (e) => {
    touchX.current = e.changedTouches[0].clientX;
  };

  const onTouchEnd = (e) => {
    if (touchX.current == null) return;
    const dx = e.changedTouches[0].clientX - touchX.current;
    touchX.current = null;
    if (Math.abs(dx) < 48) return;
    if (dx < 0) {
      const next = Math.min(step + 1, STEPS.length - 1);
      if (canGo(next)) setStep(next);
    } else {
      setStep(Math.max(step - 1, 0));
    }
  };

  const toggleMic = () => {
    if (phase === "idle") {
      setElapsed(0);
      setPhase("listening");
      return;
    }
    if (phase === "listening") {
      setPhase("processing");
      window.setTimeout(() => {
        setPhase("done");
        setUnlocked((u) => Math.max(u, 2));
      }, 1200);
    }
  };

  if (home) {
    return (
      <div className="stage">
        <HomeShell
          learnedTerm={learnedTerm}
          keyboardReady={keyboardReady}
          onReplay={() => {
            setHome(false);
            setStep(0);
            setUnlocked(0);
            setPhase("idle");
            setElapsed(0);
            setLearnedTerm(null);
            setKeyboardReady(false);
          }}
        />
      </div>
    );
  }

  return (
    <div className="stage">
      <div className="mobile-prototype" onTouchStart={onTouchStart} onTouchEnd={onTouchEnd}>
        <div className="status-bar" aria-hidden="true">
          <span>9:41</span>
          <span className="icons">●●● ▮</span>
        </div>
        <ProgressDots index={step} unlocked={unlocked} onSelect={goTo} />

        <div
          className="pager"
          style={{ transform: `translateX(-${step * 100}%)` }}
        >
          <section className="page">
            <BrandPage onNext={() => unlockAndGo(1)} onSkip={() => setHome(true)} />
          </section>
          <section className="page">
            <TryPage
              phase={phase}
              elapsed={elapsed}
              learnedTerm={learnedTerm}
              onMic={toggleMic}
              onLearn={(term) => setLearnedTerm(term)}
              onContinue={() => unlockAndGo(2)}
              onRetry={() => {
                setPhase("idle");
                setElapsed(0);
                setLearnedTerm(null);
              }}
            />
          </section>
          <section className="page">
            <KeyboardPage
              onNext={() => {
                setKeyboardReady(true);
                unlockAndGo(3);
              }}
              onSkip={() => {
                setKeyboardReady(false);
                unlockAndGo(3);
              }}
            />
          </section>
          <section className="page">
            <ReadyPage
              learnedTerm={learnedTerm}
              keyboardReady={keyboardReady}
              onStart={() => setHome(true)}
            />
          </section>
        </div>
      </div>
    </div>
  );
}

function ProgressDots({ index, unlocked, onSelect }) {
  return (
    <div className="progress" aria-label="引导进度">
      {STEPS.map((_, i) => (
        <button
          key={STEPS[i]}
          type="button"
          className={`dot ${i === index ? "active" : ""} ${i <= unlocked ? "open" : "locked"}`}
          aria-current={i === index ? "step" : undefined}
          aria-label={`第 ${i + 1} 步`}
          onClick={() => onSelect(i)}
        />
      ))}
    </div>
  );
}

function BrandPage({ onNext, onSkip }) {
  const [activeAbility, setActiveAbility] = useState(0);
  const abilities = [
    {
      title: "输入",
      icon: Waveform,
      scene: "消息 · 通用模式",
      before: "嗯，帮我跟小杨说一下，就是 ARR 的表我今晚改完……",
      after: "帮我跟小杨说一下，ARR 的表我今晚改完，明早发给他。",
      tags: ["轻声识别", "去除口头词", "按消息整理"],
    },
    {
      title: "代回",
      icon: ChatCenteredText,
      scene: "选中文字 · 知更代回",
      before: "对方问：明早能发我吗？",
      after: "可以，我今晚整理好 ARR 表，明早发给你。",
      tags: ["理解上下文", "保持你的语气"],
    },
    {
      title: "执行",
      icon: Lightning,
      scene: "iPhone 发起 · Mac 执行",
      before: "把刚才的内容整理成待办，明早提醒我。",
      after: "已生成待办，等待你确认后交给在线 Mac。",
      tags: ["先确认", "跨设备接续"],
    },
  ];
  const active = abilities[activeAbility];

  return (
    <div className="page-inner brand">
      <div className="brand-hero">
        <img className="brand-mist" src="/brand-mist.png" alt="" />
        <img className="robin-hero" src="/robin.png" alt="知更" />
        <div className="brand-glow" aria-hidden="true" />
      </div>

      <div className="brand-copy">
        <h1>知你所言，更懂你意</h1>
        <p className="sub">说得更自然，写得更清楚，越用越像你。</p>
      </div>

      <div className="brand-showcase">
        <div className="ability-tabs" role="tablist" aria-label="知更能力">
          {abilities.map((item, index) => {
            const Icon = item.icon;
            return (
              <button
                key={item.title}
                type="button"
                role="tab"
                aria-selected={index === activeAbility}
                className={index === activeAbility ? "active" : ""}
                onClick={() => setActiveAbility(index)}
              >
                <Icon size={17} weight={index === activeAbility ? "fill" : "regular"} />
                <span>知更{item.title}</span>
              </button>
            );
          })}
        </div>

        <article className="proof-card" key={active.title}>
          <div className="proof-scene">
            <span className="live-dot" />
            {active.scene}
          </div>
          <p className="proof-before">{active.before}</p>
          <div className="proof-flow" aria-hidden="true">
            <span>知更理解后</span>
            <ArrowRight size={14} weight="bold" />
          </div>
          <p className="proof-after">{active.after}</p>
          <div className="proof-tags">
            {active.tags.map((tag) => (
              <span key={tag}>
                <CheckCircle size={12} weight="fill" />
                {tag}
              </span>
            ))}
          </div>
        </article>
      </div>

      <div className="footer-actions brand-footer">
        <button className="primary" type="button" onClick={onNext}>先试一句</button>
        <button className="ghost" type="button" onClick={onSkip}>稍后设置</button>
      </div>
    </div>
  );
}

function TryPage({ phase, elapsed, learnedTerm, onMic, onLearn, onContinue, onRetry }) {
  const [showLearn, setShowLearn] = useState(false);

  const status = useMemo(() => {
    if (phase === "listening") return `轻声识别中 · ${elapsed}s`;
    if (phase === "processing") return "正在理解并整理";
    if (phase === "done") return "轻声也完整听清了";
    return "不用提高音量，轻轻说就好";
  }, [phase, elapsed]);

  useEffect(() => {
    if (phase === "done" && learnedTerm === null) {
      const t = window.setTimeout(() => setShowLearn(true), 450);
      return () => window.clearTimeout(t);
    }
    if (phase !== "done") setShowLearn(false);
    return undefined;
  }, [phase, learnedTerm]);

  const decideLearn = (keep) => {
    onLearn(keep ? "小杨" : false);
    setShowLearn(false);
  };

  return (
    <div className={`page-inner try phase-${phase}`}>
      <img className="robin-sm" src="/robin.png" alt="" />
      <h1>轻声也能听清</h1>
      <p className="sub">{status}</p>

      <div className="voice-stage">
        <img className="mist" src="/voice-mist.png" alt="" />
        <div className="whisper-guide">
          <Waveform size={15} weight="bold" />
          <span>{phase === "listening" ? "保持这个音量就好" : "像在安静办公室里一样说"}</span>
        </div>
        <button
          type="button"
          className={`mic ${phase}`}
          onClick={onMic}
          disabled={phase === "processing" || phase === "done"}
          aria-label={phase === "listening" ? "结束听写" : "开始听写"}
        >
          <Microphone size={36} weight="fill" color="#fff" />
        </button>
      </div>

      {phase === "idle" && (
        <p className="hint">
          <ChatCircle size={16} weight="regular" />
          <span>用气声试试：“嗯，帮我跟小杨说，ARR 的表今晚改完”</span>
        </p>
      )}

      {phase === "done" && (
        <div className="compose">
          <div className="compose-top">消息 · 通用模式</div>
          <p className="compose-body">
            帮我跟小杨说一下，ARR 的表我今晚改完，明早发给他。
          </p>
          <div className="compose-tags">
            {["已识别轻声", "已去除口头词", "已按消息整理"].map((t) => (
              <span key={t} className="tag">
                <CheckCircle size={12} weight="fill" />
                {t}
              </span>
            ))}
          </div>
          {learnedTerm === "小杨" && (
            <p className="learned-note">已记住「小杨」，语音和拼音都会优先使用</p>
          )}
        </div>
      )}

      <div className="footer-actions">
        {phase === "idle" && (
          <button className="primary" type="button" onClick={onMic}>点一下开始</button>
        )}
        {phase === "listening" && (
          <button className="primary recording" type="button" onClick={onMic}>点一下结束</button>
        )}
        {phase === "processing" && (
          <button className="primary" type="button" disabled>正在整理…</button>
        )}
        {phase === "done" && (
          <>
            <button className="primary" type="button" onClick={onContinue}>在其他 App 里使用</button>
            <button className="ghost" type="button" onClick={onRetry}>再试一次</button>
          </>
        )}
      </div>

      {showLearn && (
        <div className="sheet-backdrop" onClick={() => decideLearn(false)}>
          <div
            className="sheet learn-sheet"
            role="dialog"
            aria-modal="true"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sheet-handle" />
            <h2>要记住「小杨」吗？</h2>
            <p>语音和拼音都会优先使用。可随时在「懂我」里撤销。</p>
            <button className="primary" type="button" onClick={() => decideLearn(true)}>记住</button>
            <button className="ghost" type="button" onClick={() => decideLearn(false)}>仅改这次</button>
          </div>
        </div>
      )}
    </div>
  );
}

function KeyboardPage({ onNext, onSkip }) {
  const [done, setDone] = useState([false, false, false]);
  const [sheet, setSheet] = useState(null); // 0 | 1 | null
  const [pulse, setPulse] = useState(null);
  const [verifyFocus, setVerifyFocus] = useState(false);
  const [typed, setTyped] = useState("");
  const verifyRef = useRef(null);

  const current = done.findIndex((v) => !v);
  const allDone = done.every(Boolean) || typed.trim().length >= 2;

  const steps = [
    {
      title: "添加键盘",
      detail: "设置 → 通用 → 键盘 → 添加新键盘 → 知更",
      cta: "去系统设置添加",
    },
    {
      title: "允许完全访问",
      detail: "设置 → 通用 → 键盘 → 知更 → 允许完全访问",
      cta: "去开启完全访问",
    },
    {
      title: "切换到知更",
      detail: "点下方输入框，长按地球键选择知更",
      cta: "去验证输入",
    },
  ];

  const openStep = (index) => {
    if (index > current) return;
    if (index < current) {
      // allow revisit completed steps to re-open guide
    }
    setPulse(index);
    window.setTimeout(() => setPulse(null), 420);

    if (index === 2) {
      setVerifyFocus(true);
      window.setTimeout(() => verifyRef.current?.focus(), 180);
      return;
    }
    setSheet(index);
  };

  const completeFromSheet = () => {
    if (sheet == null) return;
    const i = sheet;
    setSheet(null);
    setDone((d) => d.map((v, idx) => (idx === i ? true : v)));
  };

  const primaryAction = () => {
    if (allDone) {
      onNext();
      return;
    }
    openStep(current === -1 ? 0 : current);
  };

  return (
    <div className="page-inner keyboard">
      <img className="robin-sm" src="/robin.png" alt="" />
      <h1>设置知更键盘</h1>
      <p className="sub">按顺序完成三步，才能在其他 App 里用知更</p>

      <ol className="timeline">
        {steps.map((step, i) => {
          const state = done[i] ? "done" : i === current ? "current" : "todo";
          const locked = i > current && current !== -1;
          return (
            <li
              key={step.title}
              className={`tl-item ${state} ${pulse === i ? "pulse" : ""} ${locked ? "locked" : ""}`}
            >
              <button type="button" disabled={locked} onClick={() => openStep(i)}>
                <span className="tl-index" aria-hidden="true">
                  {done[i] ? <CheckCircle size={18} weight="fill" /> : i + 1}
                </span>
                <span className="tl-copy">
                  <strong>{step.title}</strong>
                  <small>{step.detail}</small>
                </span>
                <span className="tl-action">
                  {done[i] ? "已完成" : i === current ? "去完成" : "等待中"}
                </span>
              </button>
            </li>
          );
        })}
      </ol>

      <label className={`verify ${verifyFocus || current === 2 ? "active" : ""}`}>
        <span>在这里试打几个字验证</span>
        <textarea
          ref={verifyRef}
          rows={3}
          value={typed}
          onChange={(e) => {
            setTyped(e.target.value);
            if (e.target.value.trim().length >= 2 && done[0] && done[1]) {
              setDone((d) => [true, true, true]);
            }
          }}
          onFocus={() => setVerifyFocus(true)}
          placeholder="长按地球键 → 选择知更"
        />
      </label>

      <div className="footer-actions">
        <button className="primary" type="button" onClick={primaryAction}>
          {allDone ? "继续" : current === 2 ? "去验证输入" : steps[Math.max(current, 0)].cta}
        </button>
        <button className="ghost" type="button" onClick={onSkip}>暂时跳过</button>
      </div>

      {sheet != null && (
        <div className="sheet-backdrop" onClick={() => setSheet(null)}>
          <div
            className="sheet"
            role="dialog"
            aria-modal="true"
            aria-labelledby="settings-sheet-title"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="sheet-handle" />
            <h2 id="settings-sheet-title">模拟系统设置</h2>
            <p>真机上会跳转「设置」。原型里点确认即可完成第 {sheet + 1} 步。</p>
            <div className="sheet-path">{steps[sheet].detail}</div>
            <button className="primary" type="button" onClick={completeFromSheet}>
              我已在设置中完成
            </button>
            <button className="ghost" type="button" onClick={() => setSheet(null)}>
              取消
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function ReadyPage({ learnedTerm, keyboardReady, onStart }) {
  const assets = [];
  if (learnedTerm === "小杨") assets.push("已记住「小杨」");
  if (keyboardReady) assets.push("键盘已连接");
  if (assets.length === 0) assets.push("可以随时回来设置");

  return (
    <div className="page-inner ready">
      <div className="brand-hero ready-hero">
        <img className="brand-mist" src="/brand-mist.png" alt="" />
        <img className="robin-hero" src="/robin.png" alt="" />
        <div className="brand-glow ready-glow" aria-hidden="true" />
      </div>
      <div className="brand-copy">
        <p className="brand-kicker">准备就绪</p>
        <h1>你的知更准备好了</h1>
        <p className="sub">从这次开始，它会越来越懂你的词和表达。</p>
      </div>
      <div className="assets">
        {assets.map((a) => (
          <span key={a}>{a}</span>
        ))}
      </div>
      <div className="footer-actions brand-footer">
        <button className="primary" type="button" onClick={onStart}>开始使用</button>
      </div>
    </div>
  );
}

function HomeShell({ learnedTerm, keyboardReady, onReplay }) {
  const [tab, setTab] = useState("home");
  const [sessionActive, setSessionActive] = useState(false);
  const [activityFilter, setActivityFilter] = useState("全部");
  const [selectedActivity, setSelectedActivity] = useState(null);
  const [showAddTerm, setShowAddTerm] = useState(false);
  const [newTerm, setNewTerm] = useState("");
  const [syncOn, setSyncOn] = useState(false);
  const [terms, setTerms] = useState(() => {
    const initial = [
      { text: "ARR", type: "缩写", source: "语音修正" },
      { text: "金秋资本", type: "公司", source: "桌面同步" },
    ];
    if (learnedTerm === "小杨") {
      initial.unshift({ text: "小杨", type: "人名", source: "刚刚学会" });
    }
    return initial;
  });

  const activities = [
    {
      id: 1,
      type: "输入",
      time: "10:24",
      title: "帮我跟小杨说一下，ARR 的表我今晚改完，明早发给他。",
      source: "键盘 · 消息",
      tags: ["去除口头词", "识别专名", "按消息整理"],
    },
    {
      id: 2,
      type: "代回",
      time: "昨天 18:42",
      title: "可以，我今晚整理好 ARR 表，明早发给你。",
      source: "知更代回 · 消息",
      tags: ["理解上下文", "保持语气"],
    },
    {
      id: 3,
      type: "执行",
      time: "昨天 09:16",
      title: "已生成待办：明早 9:00 发送 ARR 表。",
      source: "iPhone 发起 · Mac 待确认",
      tags: ["先确认", "跨设备接续"],
    },
    {
      id: 4,
      type: "输入",
      time: "周五",
      title: "本周投资例会改到周四下午三点。",
      source: "主 App · 通用模式",
      tags: ["时间格式化"],
    },
  ];

  const filteredActivities =
    activityFilter === "全部"
      ? activities
      : activities.filter((item) => item.type === activityFilter);

  const addTerm = () => {
    const text = newTerm.trim();
    if (!text) return;
    setTerms((current) => [
      { text, type: "自定义", source: "手动添加" },
      ...current,
    ]);
    setNewTerm("");
    setShowAddTerm(false);
  };

  return (
    <div className="mobile-prototype home-app">
      <div className="status-bar" aria-hidden="true">
        <span>9:41</span>
        <span className="icons">●●● ▮</span>
      </div>

      {tab === "home" && (
        <div className="app-body home-tab">
          <header className="app-topbar">
            <div>
              <span>今天想说什么？</span>
              <h1>知更</h1>
            </div>
            <button
              type="button"
              className="header-session-control"
              role="switch"
              aria-checked={sessionActive}
              aria-label="免切换会话"
              onClick={() => setSessionActive((active) => !active)}
            >
              <span>免切换</span>
              <i><b /></i>
            </button>
          </header>

          <section className={`home-stage ${sessionActive ? "active" : ""}`}>
            <img className="home-stage-mist" src="/brand-mist.png" alt="" />
            <div className="home-stage-copy">
              <span className="status-pill">
                <i />
                {sessionActive ? "会话进行中" : "随时可以开始"}
              </span>
              <h2>{sessionActive ? "键盘点麦，直接说" : "说完，就是能直接用的文字"}</h2>
              <p>
                {sessionActive
                  ? "知更会在后台保持连接，无需反复切换 App。"
                  : "去口头词、认专名，并按当前场景整理。"}
              </p>
            </div>
            <img className="home-stage-robin" src="/robin.png" alt="" />
          </section>

          <button type="button" className="voice-action">
            <span className="voice-action-icon">
              <Microphone size={19} weight="fill" />
            </span>
            <span>
              <strong>在 App 内听写</strong>
              <small>说完可复制、分享或保存</small>
            </span>
            <CaretRight size={17} weight="bold" />
          </button>

          <div className="section-heading">
            <h2>最近活动</h2>
            <button type="button" onClick={() => setTab("activity")}>
              查看全部
            </button>
          </div>
          <div className="compact-activity-list">
            {activities.slice(0, 2).map((item) => (
              <button
                type="button"
                key={item.id}
                onClick={() => setSelectedActivity(item)}
              >
                <ActivityIcon type={item.type} />
                <span>
                  <strong>{item.title}</strong>
                  <small>{item.source} · {item.time}</small>
                </span>
                <CaretRight size={15} />
              </button>
            ))}
          </div>

          <div className="home-summary-list">
            <button type="button" onClick={() => setTab("lexicon")}>
              <span className="summary-icon learned">
                <Sparkle size={17} weight="fill" />
              </span>
              <span>
                <strong>已认识 {terms.length} 个你的词</strong>
                <small>{terms.slice(0, 3).map((term) => term.text).join(" · ")}</small>
              </span>
              <CaretRight size={16} />
            </button>
            {!keyboardReady && (
              <button type="button" className="warning" onClick={onReplay}>
                <span className="summary-icon">
                  <Keyboard size={17} />
                </span>
                <span>
                  <strong>键盘尚未验证</strong>
                  <small>完成后才能在其他 App 里使用</small>
                </span>
                <CaretRight size={16} />
              </button>
            )}
          </div>
        </div>
      )}

      {tab === "activity" && (
        <div className="app-body activity-tab">
          <header className="page-header">
            <div>
              <span>输入、代回与执行</span>
              <h1>活动</h1>
            </div>
            <button type="button" className="circle-action" aria-label="搜索活动">
              <MagnifyingGlass size={20} />
            </button>
          </header>

          <div className="filter-tabs" role="tablist" aria-label="活动筛选">
            {["全部", "输入", "代回", "执行"].map((filter) => (
              <button
                key={filter}
                type="button"
                role="tab"
                aria-selected={activityFilter === filter}
                className={activityFilter === filter ? "active" : ""}
                onClick={() => setActivityFilter(filter)}
              >
                {filter}
              </button>
            ))}
          </div>

          <section className="activity-section">
            <div className="date-label">最近</div>
            <div className="activity-list">
              {filteredActivities.map((item) => (
                <button
                  type="button"
                  key={item.id}
                  onClick={() => setSelectedActivity(item)}
                >
                  <ActivityIcon type={item.type} />
                  <span className="activity-copy">
                    <strong>{item.title}</strong>
                    <small>{item.source}</small>
                  </span>
                  <span className="activity-time">{item.time}</span>
                </button>
              ))}
            </div>
          </section>
        </div>
      )}

      {tab === "lexicon" && (
        <div className="app-body lexicon-tab">
          <header className="page-header">
            <div>
              <span>语音与拼音共用</span>
              <h1>懂我</h1>
            </div>
            <button type="button" className="circle-action" onClick={() => setShowAddTerm(true)} aria-label="添加词">
              <Plus size={20} weight="bold" />
            </button>
          </header>

          <section className="lexicon-hero">
            <div>
              <span className="status-pill">
                <Sparkle size={12} weight="fill" />
                越用越懂你
              </span>
              <h2>{terms.length} 个词正在共同提升语音与拼音</h2>
              <p>修正一次，下一次优先识别。</p>
            </div>
            <img src="/robin.png" alt="" />
          </section>

          <label className="search-field">
            <MagnifyingGlass size={18} />
            <input type="search" placeholder="搜索人名、公司或术语" />
          </label>

          <div className="section-heading">
            <h2>最近学会</h2>
            <button type="button" onClick={() => setShowAddTerm(true)}>添加</button>
          </div>
          <div className="term-chips">
            {terms.map((term) => <span key={term.text}>{term.text}</span>)}
          </div>

          <div className="term-list">
            {terms.map((term) => (
              <div className="term-row" key={term.text}>
                <span className="term-avatar">{term.text.slice(0, 1)}</span>
                <span>
                  <strong>{term.text}</strong>
                  <small>{term.type} · {term.source}</small>
                </span>
                <button
                  type="button"
                  aria-label={`忘掉${term.text}`}
                  onClick={() => setTerms((current) => current.filter((item) => item.text !== term.text))}
                >
                  <Trash size={16} />
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {tab === "me" && (
        <div className="app-body me-tab">
          <header className="page-header">
            <div>
              <span>账户、设备与隐私</span>
              <h1>我的</h1>
            </div>
          </header>

          <section className="account-stack">
            <div className="account-card">
              <span className="account-avatar">
                <img src="/robin.png" alt="" />
              </span>
              <span>
                <strong>本地用户</strong>
                <small>登录后同步个人词与权益</small>
              </span>
              <button type="button">登录</button>
            </div>

            <div className="plan-card">
              <span>
                <small>当前方案</small>
                <strong>免费版</strong>
              </span>
              <span>
                <small>云端语音</small>
                <strong>体验额度</strong>
              </span>
            </div>
          </section>

          <SettingsGroup title="键盘与语音">
            <SettingsRow
              icon={Keyboard}
              title="知更键盘"
              value={keyboardReady ? "已连接" : "待验证"}
              tone={keyboardReady ? "success" : "warning"}
            />
            <SettingsRow icon={Microphone} title="免切换时长" value="15 分钟" />
          </SettingsGroup>

          <SettingsGroup title="个人词与设备">
            <div className="settings-row">
              <span className="settings-icon"><Sparkle size={18} /></span>
              <span className="settings-copy">
                <strong>同步个人词</strong>
                <small>在 iPhone 与 Mac 保持一致</small>
              </span>
              <button
                type="button"
                className="mini-switch"
                role="switch"
                aria-checked={syncOn}
                onClick={() => setSyncOn((value) => !value)}
              >
                <span />
              </button>
            </div>
            <SettingsRow icon={Desktop} title="Mac" value="未连接" />
          </SettingsGroup>

          <SettingsGroup title="隐私与帮助">
            <SettingsRow icon={ShieldCheck} title="原始音频" value="默认不保存" />
            <button type="button" className="settings-row settings-button" onClick={onReplay}>
              <span className="settings-icon"><ClockCounterClockwise size={18} /></span>
              <span className="settings-copy"><strong>重新运行引导</strong></span>
              <CaretRight size={16} />
            </button>
          </SettingsGroup>
        </div>
      )}

      <nav className="tabbar" aria-label="主导航">
        {[
          ["home", "首页", House],
          ["activity", "活动", ClockCounterClockwise],
          ["lexicon", "懂我", Sparkle],
          ["me", "我的", UserCircle],
        ].map(([id, label, Icon]) => (
          <button
            key={id}
            type="button"
            className={tab === id ? "active" : ""}
            onClick={() => setTab(id)}
          >
            <Icon size={20} weight={tab === id ? "fill" : "regular"} />
            {label}
          </button>
        ))}
      </nav>

      {selectedActivity && (
        <div className="sheet-backdrop" onClick={() => setSelectedActivity(null)}>
          <div className="sheet activity-detail" onClick={(event) => event.stopPropagation()}>
            <div className="sheet-handle" />
            <div className="detail-heading">
              <ActivityIcon type={selectedActivity.type} />
              <span>
                <strong>{selectedActivity.type}</strong>
                <small>{selectedActivity.source} · {selectedActivity.time}</small>
              </span>
            </div>
            <p>{selectedActivity.title}</p>
            <div className="proof-tags">
              {selectedActivity.tags.map((tag) => (
                <span key={tag}><CheckCircle size={12} weight="fill" />{tag}</span>
              ))}
            </div>
            <div className="detail-actions">
              <button type="button"><Copy size={17} />复制</button>
              <button type="button"><ShareNetwork size={17} />分享</button>
            </div>
          </div>
        </div>
      )}

      {showAddTerm && (
        <div className="sheet-backdrop" onClick={() => setShowAddTerm(false)}>
          <div className="sheet add-term-sheet" onClick={(event) => event.stopPropagation()}>
            <div className="sheet-handle" />
            <h2>添加常用词</h2>
            <p>语音热词和拼音候选都会优先使用。</p>
            <input
              autoFocus
              value={newTerm}
              onChange={(event) => setNewTerm(event.target.value)}
              placeholder="人名、公司或术语"
            />
            <button type="button" className="primary" disabled={!newTerm.trim()} onClick={addTerm}>添加</button>
          </div>
        </div>
      )}
    </div>
  );
}

function ActivityIcon({ type }) {
  const map = {
    输入: [Waveform, "voice"],
    代回: [ChatCenteredText, "reply"],
    执行: [Lightning, "execute"],
  };
  const [Icon, tone] = map[type] || map.输入;
  return (
    <span className={`activity-icon ${tone}`}>
      <Icon size={17} weight="fill" />
    </span>
  );
}

function SettingsGroup({ title, children }) {
  return (
    <section className="settings-group">
      <h2>{title}</h2>
      <div>{children}</div>
    </section>
  );
}

function SettingsRow({ icon: Icon, title, value, tone = "" }) {
  return (
    <div className="settings-row">
      <span className="settings-icon"><Icon size={18} /></span>
      <span className="settings-copy"><strong>{title}</strong></span>
      <span className={`settings-value ${tone}`}>{value}</span>
      <CaretRight size={15} />
    </div>
  );
}
