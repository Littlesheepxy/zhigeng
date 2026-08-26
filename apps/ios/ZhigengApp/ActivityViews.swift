import SwiftUI
import UIKit
import ZhigengCore

struct ActivityView: View {
	@Bindable var store: AppStore
	@State private var query = ""
	@State private var showSearch = false

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					HStack {
						Text("速记")
							.font(.largeTitle.bold())
						Spacer()
						Button {
							withAnimation { showSearch.toggle() }
						} label: {
							Image(systemName: "magnifyingglass")
								.font(.headline)
								.frame(width: 42, height: 42)
								.background(Color(.secondarySystemGroupedBackground), in: Circle())
						}
						.accessibilityLabel("搜索速记")
					}

					if showSearch {
						HStack(spacing: 9) {
							Image(systemName: "magnifyingglass")
								.foregroundStyle(.secondary)
							TextField("搜索留下的内容", text: $query)
							if !query.isEmpty {
								Button {
									query = ""
								} label: {
									Image(systemName: "xmark.circle.fill")
										.foregroundStyle(.secondary)
								}
							}
						}
						.padding(12)
						.background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
						.overlay {
							RoundedRectangle(cornerRadius: 14)
								.stroke(Brand.stroke, lineWidth: 1)
						}
					}

					if filteredKept.isEmpty {
						HStack(spacing: 12) {
							Image(systemName: "bookmark")
								.font(.title3)
								.foregroundStyle(Brand.primary)
								.frame(width: 34)
							VStack(alignment: .leading, spacing: 4) {
								Text(store.history.filter(\.isKept).isEmpty ? "还没有留下的记录" : "没有匹配的内容")
									.font(.headline)
								Text(
									store.history.filter(\.isKept).isEmpty
										? "转写完成后点「留下」，重要的内容就会存在这里"
										: "换个关键词试试"
								)
								.font(.subheadline)
								.foregroundStyle(.secondary)
							}
							Spacer()
						}
						.padding(16)
						.background(Brand.surface)
						.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
						.overlay {
							RoundedRectangle(cornerRadius: 20, style: .continuous)
								.stroke(Brand.stroke, lineWidth: 1)
						}
					} else {
						ForEach(grouped(filteredKept), id: \.title) { section in
							VStack(alignment: .leading, spacing: 8) {
								Text(section.title)
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
									.padding(.leading, 4)
								VStack(spacing: 0) {
									ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
										Button {
											store.editingHistoryItem = item
										} label: {
											historyRow(item)
										}
										.buttonStyle(.plain)
										if index != section.items.count - 1 {
											Divider().padding(.leading, 52)
										}
									}
								}
								.background(Brand.surface)
								.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
								.overlay {
									RoundedRectangle(cornerRadius: 18, style: .continuous)
										.stroke(Brand.stroke, lineWidth: 1)
								}
							}
						}
					}

					NavigationLink {
						RecentTranscriptsView(store: store)
					} label: {
						HStack {
							Text("最近转写（30 天内）")
								.font(.subheadline.weight(.medium))
							Spacer()
							Text("\(store.history.count)")
								.font(.caption)
								.foregroundStyle(.secondary)
							Image(systemName: "chevron.right")
								.font(.caption.bold())
								.foregroundStyle(.tertiary)
						}
						.foregroundStyle(.primary)
						.padding(14)
						.background(Brand.surface)
						.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
						.overlay {
							RoundedRectangle(cornerRadius: 16, style: .continuous)
								.stroke(Brand.stroke, lineWidth: 1)
						}
					}
					.buttonStyle(.plain)
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 16)
			}
			.background(Brand.canvas)
			.toolbar(.hidden, for: .navigationBar)
		}
	}

	private var filteredKept: [DictationHistoryItem] {
		let kept = store.history.filter(\.isKept)
		let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedQuery.isEmpty else { return kept }
		return kept.filter { $0.cleanedText.localizedCaseInsensitiveContains(trimmedQuery) }
	}
}

struct RecentTranscriptsView: View {
	@Bindable var store: AppStore
	@State private var query = ""

	var body: some View {
		List {
			Section {
				ForEach(filtered) { item in
					Button {
						store.editingHistoryItem = item
					} label: {
						historyRow(item)
					}
					.buttonStyle(.plain)
					.swipeActions(edge: .trailing, allowsFullSwipe: true) {
						Button {
							store.toggleKept(id: item.id)
						} label: {
							Label(item.isKept ? "取消留下" : "留下", systemImage: item.isKept ? "bookmark.slash" : "bookmark.fill")
						}
						.tint(item.isKept ? .gray : Brand.primary)
					}
				}
			} footer: {
				Text("未留下的转写只保留 30 天。留下的会一直在「速记」里。")
			}
		}
		.searchable(text: $query, prompt: "搜索转写")
		.navigationTitle("最近转写")
		.navigationBarTitleDisplayMode(.inline)
	}

	private var filtered: [DictationHistoryItem] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return store.history }
		return store.history.filter { $0.cleanedText.localizedCaseInsensitiveContains(trimmed) }
	}
}

private func historyRow(_ item: DictationHistoryItem) -> some View {
	HStack(alignment: .top, spacing: 12) {
		Image(systemName: item.isKept ? "bookmark.fill" : (item.source == .keyboard ? "keyboard" : "waveform"))
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(Brand.primary)
			.frame(width: 32, height: 32)
		VStack(alignment: .leading, spacing: 4) {
			Text(item.cleanedText)
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.primary)
				.lineLimit(3)
			Text(meta(item))
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		Spacer()
		Text(timeLabel(item))
			.font(.caption2)
			.foregroundStyle(.secondary)
	}
	.padding(12)
}

private func timeLabel(_ item: DictationHistoryItem) -> String {
	let formatter = DateFormatter()
	formatter.locale = Locale(identifier: "zh_CN")
	formatter.dateFormat = Calendar.current.isDateInToday(Date(timeIntervalSince1970: item.createdAt))
		? "HH:mm"
		: "M月d日"
	return formatter.string(from: Date(timeIntervalSince1970: item.createdAt))
}

private func grouped(_ items: [DictationHistoryItem]) -> [(title: String, items: [DictationHistoryItem])] {
	let cal = Calendar.current
	var today: [DictationHistoryItem] = []
	var yesterday: [DictationHistoryItem] = []
	var earlier: [DictationHistoryItem] = []
	for item in items {
		let date = Date(timeIntervalSince1970: item.createdAt)
		if cal.isDateInToday(date) {
			today.append(item)
		} else if cal.isDateInYesterday(date) {
			yesterday.append(item)
		} else {
			earlier.append(item)
		}
	}
	var out: [(String, [DictationHistoryItem])] = []
	if !today.isEmpty { out.append(("今天", today)) }
	if !yesterday.isEmpty { out.append(("昨天", yesterday)) }
	if !earlier.isEmpty { out.append(("更早", earlier)) }
	return out
}

private func meta(_ item: DictationHistoryItem) -> String {
	let status = item.status == .ready
		? (item.directStructured ? "已整理" : "原始")
		: (item.status == .incomplete ? "未完整" : item.status.rawValue)
	let source = item.source == .keyboard ? "键盘" : item.source == .demo ? "示例" : "主 App"
	let kept = item.isKept ? "已留下 · " : ""
	return "\(kept)\(status) · \(source)"
}

struct DictationDetailView: View {
	@Bindable var store: AppStore
	let item: DictationHistoryItem
	@Environment(\.dismiss) private var dismiss
	@State private var draft = ""
	@State private var learnedTerm: String?
	@State private var learnedTermId: String?

	private var liveItem: DictationHistoryItem {
		store.history.first { $0.id == item.id } ?? item
	}

	var body: some View {
		List {
			Section {
				TextEditor(text: $draft)
					.frame(minHeight: 120)
					.font(.body)
			} header: {
				Text("内容")
			} footer: {
				Text("改错词后点保存，知更会记住正确写法。")
			}

			if let learnedTerm {
				Section {
					HStack {
						Text("已记住「\(learnedTerm)」")
							.foregroundStyle(Brand.success)
						Spacer()
						Button("撤销") {
							if let id = learnedTermId {
								store.forgetTerm(id: id)
							}
							self.learnedTerm = nil
							self.learnedTermId = nil
						}
						.font(.subheadline)
					}
				}
			}

			if !liveItem.processingTags.isEmpty {
				Section("整理了什么") {
					ForEach(liveItem.processingTags, id: \.self) { tag in
						Text(tag)
					}
				}
			}

			Section {
				Button("保存修改") { saveEdits() }
					.disabled(draft == liveItem.cleanedText)
				Button(liveItem.isKept ? "取消留下" : "留下") {
					store.toggleKept(id: liveItem.id)
					store.editingHistoryItem = store.history.first { $0.id == liveItem.id }
				}
				Button("删除", role: .destructive) {
					store.deleteHistory(id: liveItem.id)
					dismiss()
				}
			}
		}
		.navigationTitle("详情")
		.onAppear {
			if draft.isEmpty { draft = item.cleanedText }
		}
	}

	private func saveEdits() {
		let original = liveItem.cleanedText
		let edited = draft
		store.updateHistoryText(id: liveItem.id, cleanedText: edited)
		let pairs = TextEditDiff.replacements(original: original, edited: edited)
		for (from, to) in pairs {
			if let term = store.learnCorrection(original: from, replacement: to, requestId: liveItem.id) {
				learnedTerm = term.text
				learnedTermId = term.id
			}
		}
		store.editingHistoryItem = store.history.first { $0.id == liveItem.id }
	}
}
