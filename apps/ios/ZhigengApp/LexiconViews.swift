import SwiftUI
import ZhigengCore

struct LexiconView: View {
	@Bindable var store: AppStore
	@State private var query = ""
	@State private var kindFilter: PersonalTermKind?

	private var termCount: Int { store.lexicon.allTerms.count }
	private var isEmpty: Bool { termCount == 0 }

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					HStack {
						Text("懂我")
							.font(.largeTitle.bold())
						Spacer()
						Button {
							store.showAddTerm = true
						} label: {
							Image(systemName: "plus")
								.font(.headline.bold())
								.frame(width: 42, height: 42)
								.background(Color(.secondarySystemGroupedBackground), in: Circle())
						}
						.accessibilityLabel("添加")
					}

					heroCard

					if !isEmpty {
						HStack(spacing: 9) {
							Image(systemName: "magnifyingglass")
								.foregroundStyle(.secondary)
							TextField("搜索人名、项目或术语", text: $query)
								.textInputAutocapitalization(.never)
								.autocorrectionDisabled()
						}
						.padding(.horizontal, 13)
						.frame(height: 44)
						.background(Brand.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
						.overlay {
							RoundedRectangle(cornerRadius: 15, style: .continuous)
								.stroke(Brand.stroke, lineWidth: 1)
						}

						HStack(spacing: 8) {
							kindChip(nil, label: "全部")
							ForEach(PersonalTermKind.allCases, id: \.self) { kind in
								kindChip(kind, label: kindLabel(kind))
							}
						}

						if filtered.isEmpty {
							Text("没有匹配的内容")
								.font(.subheadline)
								.foregroundStyle(.secondary)
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(.top, 8)
						} else {
							VStack(alignment: .leading, spacing: 10) {
								HStack {
									Text("最近学会")
										.font(.headline)
									Spacer()
									Button("添加") { store.showAddTerm = true }
										.font(.subheadline)
								}
								ScrollView(.horizontal, showsIndicators: false) {
									HStack(spacing: 8) {
										ForEach(filtered.prefix(8)) { term in
											CapabilityChip(text: term.text)
										}
									}
								}
							}

							VStack(spacing: 0) {
								ForEach(Array(filtered.enumerated()), id: \.element.id) { index, term in
									NavigationLink {
										TermDetailView(store: store, term: term)
									} label: {
										termRow(term)
									}
									.buttonStyle(.plain)
									if index != filtered.count - 1 {
										Divider().padding(.leading, 56)
									}
								}
							}
							.background(Brand.surface)
							.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
							.overlay {
								RoundedRectangle(cornerRadius: 18, style: .continuous)
									.stroke(Brand.stroke.opacity(0.7), lineWidth: 1)
							}
						}
					}
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 16)
			}
			.background(Brand.canvas)
			.toolbar(.hidden, for: .navigationBar)
		}
	}

	private var heroCard: some View {
		ZStack(alignment: .bottomTrailing) {
			MistBackdrop()
				.frame(height: 154)
				.clipped()
			Image.robin
				.resizable()
				.scaledToFit()
				.frame(width: 102, height: 102)
				.offset(x: -2, y: 3)
			VStack(alignment: .leading, spacing: 0) {
				StatusPill(text: "越用越懂你")
				if isEmpty {
					Text("从一次纠正开始")
						.font(.system(size: 18, weight: .bold))
						.lineSpacing(2)
						.padding(.top, 12)
					Text("名字、项目和常用词，改一次，下次就记住。")
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
						.padding(.top, 6)
					Button("添加第一个") {
						store.showAddTerm = true
					}
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(Brand.primaryDark)
					.padding(.top, 10)
				} else {
					Text("已记住 \(termCount) 个人、事与词")
						.font(.system(size: 18, weight: .bold))
						.lineSpacing(2)
						.padding(.top, 12)
					Text("语音和拼音会优先识别。")
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
						.padding(.top, 6)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(18)
			.padding(.trailing, 96)
		}
		.frame(height: 154)
		.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
		.clipped()
	}

	private func kindChip(_ kind: PersonalTermKind?, label: String) -> some View {
		let selected = kindFilter == kind
		return Button {
			withAnimation(.snappy(duration: 0.18)) { kindFilter = kind }
		} label: {
			Text(label)
				.font(.subheadline.weight(selected ? .semibold : .regular))
				.foregroundStyle(selected ? .white : .primary)
				.padding(.horizontal, 14)
				.padding(.vertical, 7)
				.background(selected ? Color.primary : Brand.surface, in: Capsule())
				.overlay {
					if !selected {
						Capsule().stroke(Brand.stroke, lineWidth: 1)
					}
				}
		}
		.buttonStyle(.plain)
	}

	private func termRow(_ term: PersonalTerm) -> some View {
		HStack(spacing: 12) {
			Text(String(term.text.prefix(1)))
				.font(.subheadline.bold())
				.foregroundStyle(Brand.primaryDark)
				.frame(width: 34, height: 34)
				.background(Brand.lavender.opacity(0.65), in: Circle())
			VStack(alignment: .leading, spacing: 3) {
				Text(term.text)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
				Text("\(kindLabel(term.kind)) · \(sourceLabel(term.source))")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Image(systemName: "chevron.right")
				.font(.caption.bold())
				.foregroundStyle(.tertiary)
		}
		.padding(12)
	}

	private var filtered: [PersonalTerm] {
		var terms = store.lexicon.allTerms.sorted { $0.lastUsedAt > $1.lastUsedAt }
		if let kindFilter {
			terms = terms.filter { $0.kind == kindFilter }
		}
		let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { return terms }
		return terms.filter { $0.text.localizedCaseInsensitiveContains(q) }
	}

	private func sourceLabel(_ source: PersonalTermSource) -> String {
		switch source {
		case .manual: "手动添加"
		case .pinyinCorrection: "拼音修正"
		case .desktopSync: "桌面同步"
		}
	}
}

func kindLabel(_ kind: PersonalTermKind) -> String {
	switch kind {
	case .person: "人"
	case .project: "事"
	case .word: "词"
	}
}

struct TermDetailView: View {
	@Bindable var store: AppStore
	let term: PersonalTerm
	@Environment(\.dismiss) private var dismiss
	@State private var kind: PersonalTermKind = .word

	var body: some View {
		List {
			Section {
				Text(term.text)
					.font(.title2.bold())
			}
			Section {
				Picker("分类", selection: $kind) {
					ForEach(PersonalTermKind.allCases, id: \.self) { k in
						Text(kindLabel(k)).tag(k)
					}
				}
				.pickerStyle(.segmented)
				.onChange(of: kind) { _, newValue in
					store.setTermKind(id: term.id, kind: newValue)
				}
			} header: {
				Text("分类")
			}
			Section {
				LabeledContent("用于语音热词", value: "开启")
				LabeledContent("提升拼音候选", value: "开启")
				LabeledContent("来源", value: sourceLabel(term.source))
			}
			Section {
				Button("忘掉这个词", role: .destructive) {
					store.forgetTerm(id: term.id)
					dismiss()
				}
			} footer: {
				Text("删除后，语音和拼音都不再优先识别它。")
			}
		}
		.navigationTitle("词条")
		.onAppear { kind = term.kind }
	}

	private func sourceLabel(_ source: PersonalTermSource) -> String {
		switch source {
		case .manual: "手动添加"
		case .pinyinCorrection: "拼音修正"
		case .desktopSync: "桌面同步"
		}
	}
}

struct AddTermSheet: View {
	@Bindable var store: AppStore
	@Environment(\.dismiss) private var dismiss
	@State private var text = ""
	@State private var kind: PersonalTermKind = .word

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("正确写法", text: $text)
						.autocorrectionDisabled()
					Picker("分类", selection: $kind) {
						ForEach(PersonalTermKind.allCases, id: \.self) { k in
							Text(kindLabel(k)).tag(k)
						}
					}
					.pickerStyle(.segmented)
				} footer: {
					Text("添加后，语音热词和拼音候选都会优先使用。")
				}
			}
			.navigationTitle("添加常用词")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("取消") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("添加") {
						_ = store.addTerm(text, kind: kind)
						dismiss()
					}
					.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
			}
		}
	}
}
