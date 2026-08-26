import { ArrowLeft, BriefcaseBusiness, UserRound, Users } from "lucide-react";
import { useEffect, useState } from "react";
import type {
	EpisodeSummary,
	HomeSnapshot,
	MemoryEntityRecord,
	PersonMemoryValue,
	ProjectMemoryValue,
	UserProfileData,
} from "../types.js";
import { formatTime } from "../components/FormFields.js";
import { ProfileImportModal } from "./ProfileImportModal.js";
import { dedupeFollowUpIntents } from "../lib/follow-up.js";

type Habit = { label: string; count: number; example?: string };

const HABIT_CLUSTERS = [
	{ id: "voice-structure", label: "语音转写整理", pattern: /^转写：|voice\.structure|整理|润色|口述/i },
	{ id: "voice-reply", label: "代回与聊天回复", pattern: /^代回：|voice\.reply|回复|微信|飞书|slack/i },
	{ id: "mail", label: "邮件与收件箱", pattern: /mail|邮件|gmail|邮箱|未读|收件/i },
	{ id: "files", label: "文件与报价整理", pattern: /报价|pdf|下载|整理|发给|jason/i },
	{ id: "browser", label: "浏览器与网页", pattern: /chrome|网页|浏览|打开.*网|标签页/i },
	{ id: "screen", label: "屏幕读取", pattern: /屏幕|截图|ocr|界面/i },
] as const;

const FOLLOW_UP_PATTERN = /待办|提醒|跟进|答应|截止|之前|发给|回复|提交/i;

function personInitial(name: string): string {
	const c = name.trim().charAt(0);
	return c ? c.toUpperCase() : "?";
}

function isPersonEntity(
	e: MemoryEntityRecord,
): e is MemoryEntityRecord & { type: "entity.person"; value: PersonMemoryValue } {
	return e.type === "entity.person";
}

function isProjectEntity(
	e: MemoryEntityRecord,
): e is MemoryEntityRecord & { type: "entity.project"; value: ProjectMemoryValue } {
	return e.type === "entity.project";
}

function clusterHabits(episodes: EpisodeSummary[], limit = 5): Habit[] {
	const clusters = new Map<string, Habit>();
	const singles = new Map<string, number>();

	for (const ep of episodes) {
		const intent = ep.intent.trim();
		if (!intent) continue;

		const cluster = HABIT_CLUSTERS.find((c) => c.pattern.test(intent));
		if (cluster) {
			const existing = clusters.get(cluster.id) ?? { label: cluster.label, count: 0 };
			existing.count += 1;
			if (!existing.example) existing.example = intent;
			clusters.set(cluster.id, existing);
			continue;
		}

		singles.set(intent, (singles.get(intent) ?? 0) + 1);
	}

	return [
		...clusters.values(),
		...[...singles.entries()].map(([label, count]) => ({ label, count })),
	]
		.sort((a, b) => b.count - a.count)
		.slice(0, limit);
}

function inferTopics(habits: Habit[]): string[] {
	const text = habits.map((h) => `${h.label} ${h.example ?? ""}`).join(" ");
	const topics: string[] = [];
	if (/mail|邮件|gmail|邮箱|收件/i.test(text)) topics.push("邮件");
	if (/转写|口述|润色|整理/i.test(text)) topics.push("转写");
	if (/代回|回复|聊天/i.test(text)) topics.push("代回");
	if (/pdf|报价|下载|文件|整理/i.test(text)) topics.push("文档");
	if (/chrome|网页|浏览/i.test(text)) topics.push("浏览器");
	if (/屏幕|截图|ocr/i.test(text)) topics.push("屏幕");
	return topics;
}

function buildProfileLine(
	episodes: EpisodeSummary[],
	habits: Habit[],
	stored?: UserProfileData | null,
): string {
	if (stored?.summary?.trim()) return stored.summary.trim();
	if (stored?.role?.trim()) {
		const domains = stored.domains?.length ? `，主要处理${stored.domains.join("、")}` : "";
		return `你是${stored.role}${domains}。`;
	}
	if (episodes.length === 0) {
		return "开始使用 知更 后，这里会根据你的任务记录逐步形成个人画像。";
	}
	const topics = inferTopics(habits);
	if (topics.length > 0) {
		return `你主要用 知更 处理${topics.join("、")}相关事务，习惯通过语音快速下达指令。`;
	}
	return `你已执行 ${episodes.length} 次任务，知更 会持续从你的使用习惯中学习偏好。`;
}

function taskStats(episodes: EpisodeSummary[]) {
	let success = 0;
	let partial = 0;
	let recovered = 0;
	for (const ep of episodes) {
		const s = ep.status.toLowerCase();
		if (s === "success") success += 1;
		else if (s === "recovered") recovered += 1;
		else if (s === "partial") partial += 1;
	}
	return { total: episodes.length, success, recovered, partial };
}

function statusLabel(status: string) {
	const s = status.toLowerCase();
	if (s === "success") return "成功";
	if (s === "recovered") return "恢复完成";
	if (s === "partial") return "需要继续";
	return status;
}

export function ProfileSection({
	snapshot,
	active,
	onNavigate,
}: {
	snapshot: HomeSnapshot;
	active: boolean;
	onNavigate: (section: "tasks" | "work", taskId?: string) => void;
}) {
	const [episodes, setEpisodes] = useState<EpisodeSummary[]>([]);
	const [storedProfile, setStoredProfile] = useState<UserProfileData | null>(null);
	const [loading, setLoading] = useState(true);
	const [importOpen, setImportOpen] = useState(false);
	const [memoryView, setMemoryView] = useState<"overview" | "people" | "things" | "me">("overview");
	const [memoryEntities, setMemoryEntities] = useState<MemoryEntityRecord[]>([]);

	function reloadProfile() {
		void window.fold.profileGet().then((p) => setStoredProfile((p as UserProfileData | null) ?? null));
	}

	useEffect(() => {
		if (!active) return;
		let mounted = true;
		setLoading(true);
		void Promise.all([
			window.fold.listEpisodes(),
			window.fold.profileGet(),
			window.fold.listMemoryEntities(),
		])
			.then(([items, profile, entities]) => {
				if (!mounted) return;
				setEpisodes(items);
				setStoredProfile((profile as UserProfileData | null) ?? null);
				setMemoryEntities((entities as MemoryEntityRecord[]) ?? []);
			})
			.finally(() => {
				if (mounted) setLoading(false);
			});
		return () => {
			mounted = false;
		};
	}, [active]);

	const habits = clusterHabits(episodes);
	const stats = taskStats(episodes);
	const topics = [
		...new Set([...inferTopics(habits), ...(storedProfile?.domains ?? [])]),
	];
	const recent = episodes[0];
	const profileTags = [
		...(storedProfile?.preferredTools ?? []),
		...(storedProfile?.workPatterns ?? []),
	].slice(0, 6);
	const followUps = dedupeFollowUpIntents(episodes
		.filter((episode) => {
			// 已完成的任务不需要跟进；空口令（如「代回：.」）没有可跟进的内容
			if (["success", "recovered"].includes(episode.status.toLowerCase())) return false;
			if (episode.intent.replace(/^(代回|转写)：/, "").replace(/[\s.。，,、…]+/g, "").length < 2) return false;
			return FOLLOW_UP_PATTERN.test(`${episode.intent} ${episode.summary}`);
		}));

	const peopleEntities = memoryEntities.filter(isPersonEntity);
	const projectEntities = memoryEntities.filter(isProjectEntity);

	if (memoryView === "people") {
		return (
			<div className="fold-memory-page">
				<div className="fold-memory-subpage-heading">
					<button type="button" className="fold-memory-back" onClick={() => setMemoryView("overview")}>
						<ArrowLeft size={15} /> 返回记忆
					</button>
					<h2>人</h2>
					<p>人物关系来自导入画像和后续互动。</p>
				</div>

				<section className="fold-memory-subpage">
					{peopleEntities.length > 0 ? (
						<ul className="fold-memory-people-list">
							{peopleEntities.map((entity) => (
								<li key={entity.key} className="fold-memory-person-card">
									<span className="fold-memory-person-avatar" aria-hidden="true">
										{personInitial(entity.value.name)}
									</span>
									<div>
										<strong>{entity.value.name}</strong>
										{entity.value.role && <small>{entity.value.role}</small>}
										{entity.value.commitment && <em>{entity.value.commitment}</em>}
										<small className="fold-memory-person-date">最近 · {entity.value.lastSeenDate}</small>
									</div>
									<button
										type="button"
										className="fold-memory-forget-btn"
										title="忘掉此人"
										onClick={() => {
											void window.fold.deactivateMemory(entity.id).then((r) => {
												if (r.ok) {
													setMemoryEntities((prev) => prev.filter((e) => e.id !== entity.id));
												}
											});
										}}
									>
										忘掉
									</button>
								</li>
							))}
						</ul>
					) : (
						<p className="fold-memory-empty">目前还没有可展示的人物关系记录。导入画像或继续互动后，每日整固会逐步形成记忆。</p>
					)}
					{storedProfile?.migrationArchive?.trim() ? (
						<div className="fold-memory-archive-block">
							<h3>本地档案</h3>
							<pre className="fold-memory-archive">{storedProfile.migrationArchive}</pre>
						</div>
					) : null}
				</section>
			</div>
		);
	}

	if (memoryView === "things") {
		return (
			<div className="fold-memory-page">
				<div className="fold-memory-subpage-heading">
					<button type="button" className="fold-memory-back" onClick={() => setMemoryView("overview")}>
						<ArrowLeft size={15} /> 返回记忆
					</button>
					<h2>事</h2>
					<p>正在推进的项目、待跟进事项和近期经历。</p>
				</div>

				<section className="fold-memory-subpage">
					<h3>项目与事项</h3>
					{projectEntities.length > 0 ? (
						<div className="fold-memory-project-list">
							{projectEntities.map((entity) => (
								<article key={entity.key} className="fold-memory-project-card">
									<strong>{entity.value.name}</strong>
									{entity.value.status && <span>状态 · {entity.value.status}</span>}
									{entity.value.nextStep && <p>{entity.value.nextStep}</p>}
									{entity.value.filePaths?.[0] && (
										<small title={entity.value.filePaths[0]}>{entity.value.filePaths[0]}</small>
									)}
									<small>活跃 · {entity.value.lastActiveDate}</small>
									<button
										type="button"
										className="fold-memory-forget-btn"
										title="忘掉此项目"
										onClick={() => {
											void window.fold.deactivateMemory(entity.id).then((r) => {
												if (r.ok) {
													setMemoryEntities((prev) => prev.filter((e) => e.id !== entity.id));
												}
											});
										}}
									>
										忘掉
									</button>
								</article>
							))}
						</div>
					) : (
						<p className="fold-memory-empty">整固后会把高频文件与任务归纳成项目记忆。</p>
					)}
				</section>

				<section className="fold-memory-subpage">
					<h3>行动习惯</h3>
					{loading ? (
						<p className="fold-memory-empty">正在整理…</p>
					) : habits.length > 0 ? (
						<div className="fold-memory-detail-list">
							{habits.map((habit) => (
								<div key={habit.label}>
									<strong>{habit.label}</strong><span>{habit.count} 次</span>
									{habit.example && habit.example !== habit.label && <p>例：{habit.example}</p>}
								</div>
							))}
						</div>
					) : <p className="fold-memory-empty">完成任务后，这里会归纳你常做的事。</p>}
				</section>

				<section className="fold-memory-subpage">
					<h3>需要跟进</h3>
					{followUps.length > 0 ? (
						<div className="fold-memory-followup-list">
							{followUps.map((episode) => (
								<button type="button" key={episode.id} onClick={() => onNavigate("tasks", episode.id)}>
									<span>{episode.intent}</span>
									<small>{formatTime(episode.timestamp)} · {statusLabel(episode.status)}</small>
								</button>
							))}
						</div>
					) : <p className="fold-memory-empty">近期记录中没有识别到需要跟进的事项。</p>}
				</section>

				<section className="fold-memory-subpage">
					<h3>近期经历</h3>
					{episodes.length > 0 ? (
						<div className="fold-memory-detail-list">
							{episodes.slice(0, 5).map((episode) => (
								<div key={episode.id}>
									<strong>{episode.intent}</strong><span>{formatTime(episode.timestamp)}</span>
									{episode.summary && <p>{episode.summary}</p>}
								</div>
							))}
						</div>
					) : <p className="fold-memory-empty">还没有任务记录。</p>}
				</section>
			</div>
		);
	}

	if (memoryView === "me") {
		return (
			<div className="fold-memory-page">
				<div className="fold-memory-subpage-heading">
					<button type="button" className="fold-memory-back" onClick={() => setMemoryView("overview")}>
						<ArrowLeft size={15} /> 返回记忆
					</button>
					<h2>我</h2>
					<p>根据导入画像和真实任务记录形成的个人偏好。</p>
				</div>

				<section className="fold-memory-subpage">
					<p className="fold-memory-detail-summary">{buildProfileLine(episodes, habits, storedProfile)}</p>
					<div className="fold-memory-profile-details">
						{storedProfile?.role && <div><strong>角色</strong><span>{storedProfile.role}</span></div>}
						{topics.length > 0 && <div><strong>关注领域</strong><span>{topics.join("、")}</span></div>}
						{storedProfile?.preferredTools?.length ? <div><strong>常用工具</strong><span>{storedProfile.preferredTools.join("、")}</span></div> : null}
						{storedProfile?.workPatterns?.length ? <div><strong>工作方式</strong><span>{storedProfile.workPatterns.join("、")}</span></div> : null}
						{storedProfile?.communicationStyle && <div><strong>沟通风格</strong><span>{storedProfile.communicationStyle}</span></div>}
						{storedProfile?.constraints?.length ? (
							<div>
								<strong>边界与约束</strong>
								<ul className="fold-memory-constraint-list">
									{storedProfile.constraints.map((c) => (
										<li key={c}>
											<span>{c}</span>
											<button
												type="button"
												className="fold-memory-forget-btn"
												onClick={() => {
													void window.fold.removeProfileConstraint(c).then((r) => {
														if (r.ok) reloadProfile();
													});
												}}
											>
												忘掉
											</button>
										</li>
									))}
								</ul>
							</div>
						) : null}
						<div>
							<strong>任务记录</strong>
							<span>{stats.total} 次，{stats.success} 次成功{stats.recovered > 0 ? `，${stats.recovered} 次恢复完成` : ""}{stats.partial > 0 ? `，${stats.partial} 次部分完成` : ""}</span>
						</div>
					</div>
					<button type="button" className="fold-profile-action-btn primary" onClick={() => setImportOpen(true)}>
						从 AI 助手导入
					</button>
				</section>

				{importOpen && (
					<ProfileImportModal onClose={() => setImportOpen(false)} onSaved={reloadProfile} />
				)}
			</div>
		);
	}

	return (
		<div className="fold-memory-page">
			<div className="fold-memory-heading">
				<div>
					<h2>记忆</h2>
					<p>知更从你的画像与互动中，持续记住重要的人、事和偏好。</p>
				</div>
				<button type="button" className="fold-profile-action-btn primary" onClick={() => setImportOpen(true)}>
					从 AI 助手导入
				</button>
			</div>

			<div className="fold-memory-grid">
				<button type="button" className="fold-memory-card fold-memory-card--people" onClick={() => setMemoryView("people")}>
					<div className="fold-memory-card-head">
						<div className="fold-memory-card-title">
							<span className="fold-memory-icon"><Users size={20} /></span>
							<div><span>人</span><small>关系记忆</small></div>
						</div>
					</div>
					<div className="fold-memory-avatars" aria-hidden="true">
						{peopleEntities.length > 0
							? peopleEntities.slice(0, 3).map((e) => (
									<span key={e.key}>{personInitial(e.value.name)}</span>
								))
							: (
								<>
									<span>人</span><span>人</span><span>人</span>
								</>
							)}
					</div>
					<p className="fold-memory-summary">
						{peopleEntities.length > 0
							? `已记住 ${peopleEntities.length} 位相关人物。`
							: "人物关系会从导入画像和后续互动中逐步形成。"}
					</p>
					<p className="fold-memory-summary">
						{storedProfile?.migrationArchive?.trim() ? "已保存一份本地导入档案。" : "每日空闲时会整固轨迹与任务。"}
					</p>
					<span className="fold-memory-card-link">进入人物记忆 →</span>
				</button>

				<button type="button" className="fold-memory-card fold-memory-card--things" onClick={() => setMemoryView("things")}>
					<div className="fold-memory-card-head">
						<div className="fold-memory-card-title">
							<span className="fold-memory-icon"><BriefcaseBusiness size={20} /></span>
							<div><span>事</span><small>项目与跟进</small></div>
						</div>
					</div>
					<p className="fold-memory-kicker">
						{loading
							? "正在整理…"
							: projectEntities.length > 0
								? `${projectEntities.length} 个活跃项目`
								: followUps.length > 0
									? `${followUps.length} 项待跟进`
									: habits.length > 0
										? `已归纳 ${habits.length} 类习惯`
										: "尚未形成项目记录"}
					</p>
					<p className="fold-memory-summary">
						{followUps.length > 0
							? `${followUps.length} 项近期记录需要跟进。`
							: "近期没有识别到待跟进事项。"}
					</p>
					<p className="fold-memory-summary">
						{habits.length > 0
							? `已归纳 ${habits.length} 类习惯`
							: recent
								? `最近：${recent.intent}`
								: "完成任务后，这里会归纳你常做的事。"}
					</p>
					<span className="fold-memory-card-link">查看事项与项目 →</span>
				</button>

				<button type="button" className="fold-memory-card fold-memory-card--me" onClick={() => setMemoryView("me")}>
					<div className="fold-memory-card-head">
						<div className="fold-memory-card-title">
							<span className="fold-memory-icon"><UserRound size={20} /></span>
							<div><span>我</span><small>画像与偏好</small></div>
						</div>
					</div>
					<p className="fold-memory-summary">{loading ? "加载中…" : buildProfileLine(episodes, habits, storedProfile)}</p>
					<p className="fold-memory-summary">
						{profileTags.length > 0 ? `偏好：${profileTags.slice(0, 3).join("、")}` : "导入画像或继续使用后，这里会形成更具体的偏好。"}
					</p>
					{storedProfile?.updatedAt && <p className="fold-memory-updated">更新于 {formatTime(storedProfile.updatedAt)}</p>}
					<span className="fold-memory-card-link">查看我的画像 →</span>
				</button>
			</div>

			<section className="fold-memory-followups">
				<div className="fold-memory-followups-head">
					<div>
						<h3>最近需要跟进</h3>
						<p>从近期记录中识别出的提醒与承诺</p>
					</div>
					<button type="button" onClick={() => onNavigate("tasks")} className="fold-home-link">查看全部任务 →</button>
				</div>
				{loading ? (
					<p className="fold-memory-empty">加载中…</p>
				) : followUps.length > 0 ? (
					<div className="fold-memory-followup-list">
						{followUps.map((episode) => (
							<button type="button" key={episode.id} onClick={() => onNavigate("tasks", episode.id)}>
								<span>{episode.intent}</span>
								<small>{formatTime(episode.timestamp)} · {statusLabel(episode.status)}</small>
							</button>
						))}
					</div>
				) : (
					<p className="fold-memory-empty">近期记录中没有识别到需要跟进的事项。</p>
				)}
				{snapshot.liveContext.activeApp && (
					<button type="button" onClick={() => onNavigate("work")} className="fold-home-link fold-memory-trail-link">
						当前在 {snapshot.liveContext.activeApp} · 看轨迹 →
					</button>
				)}
			</section>

			{importOpen && (
				<ProfileImportModal onClose={() => setImportOpen(false)} onSaved={reloadProfile} />
			)}
		</div>
	);
}
