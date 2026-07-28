import Foundation

/// One syllable (or, at the tail, one incomplete syllable) found in a key sequence.
public struct PinyinSpan: Equatable, Sendable {
	public let start: Int
	public let length: Int
	/// Canonical spelling with `ü` restored; for a partial span, the letters as typed.
	public let syllable: String
	public let isPartial: Bool

	public init(start: Int, length: Int, syllable: String, isPartial: Bool) {
		self.start = start
		self.length = length
		self.syllable = syllable
		self.isPartial = isPartial
	}
}

/// A key sequence to segment. Nine-key and the full keyboard differ only in how many
/// letters a single key can stand for, so both funnel into the same lattice.
public struct PinyinInput: Sendable {
	public let keys: [Set<Character>]
	/// Key indices where a syllable is forced to start (typed apostrophes).
	public let boundaries: Set<Int>

	public init(keys: [Set<Character>], boundaries: Set<Int> = []) {
		self.keys = keys
		self.boundaries = boundaries
	}

	public static func full(_ text: String) -> PinyinInput {
		var keys: [Set<Character>] = []
		var boundaries: Set<Int> = []
		for character in text.lowercased() {
			if character == "'" || character == "\u{2019}" {
				boundaries.insert(keys.count)
			} else if character.isASCII, character.isLetter {
				keys.append([character])
			}
		}
		return PinyinInput(keys: keys, boundaries: boundaries)
	}

	public static func nineKey(_ digits: String) -> PinyinInput {
		var keys: [Set<Character>] = []
		var boundaries: Set<Int> = []
		for character in digits {
			if character == "'" {
				boundaries.insert(keys.count)
			} else if let letters = PinyinSyllableTable.nineKeyLetters[character] {
				keys.append(letters)
			}
		}
		return PinyinInput(keys: keys, boundaries: boundaries)
	}
}

public enum PinyinSegmenter {
	/// Every syllable that can start at every position — the lattice the language model scores.
	/// Incomplete syllables are only reported at the tail, where they are what the user is still typing.
	public static func spans(_ input: PinyinInput) -> [PinyinSpan] {
		let keys = input.keys
		guard !keys.isEmpty else { return [] }

		var result: [PinyinSpan] = []
		for start in keys.indices {
			var frontier: Set<String> = [""]
			var index = start
			while index < keys.count {
				if index > start, input.boundaries.contains(index) { break }
				var next: Set<String> = []
				for prefix in frontier {
					for letter in keys[index] {
						let candidate = prefix + String(letter)
						if PinyinSyllableTable.prefixes.contains(candidate) {
							next.insert(candidate)
						}
					}
				}
				if next.isEmpty { break }
				frontier = next
				index += 1

				let atTail = index == keys.count
				for typed in frontier {
					if let canonical = PinyinSyllableTable.canonical[typed] {
						result.append(
							PinyinSpan(start: start, length: index - start, syllable: canonical, isPartial: false)
						)
					} else if atTail {
						result.append(
							PinyinSpan(start: start, length: index - start, syllable: typed, isPartial: true)
						)
					}
				}
			}
		}
		return result
	}
}

public enum PinyinSyllableTable {
	public static let nineKeyLetters: [Character: Set<Character>] = [
		"2": ["a", "b", "c"],
		"3": ["d", "e", "f"],
		"4": ["g", "h", "i"],
		"5": ["j", "k", "l"],
		"6": ["m", "n", "o"],
		"7": ["p", "q", "r", "s"],
		"8": ["t", "u", "v"],
		"9": ["w", "x", "y", "z"],
	]

	/// Typed letters -> canonical syllable. `ü` is typed as `v`, and after j/q/x/y as `u`.
	public static let canonical: [String: String] = buildCanonical()

	/// Every prefix of every typed form, so the walk can stop as soon as a path dies.
	public static let prefixes: Set<String> = {
		var all: Set<String> = []
		for typed in canonical.keys {
			var prefix = ""
			for letter in typed {
				prefix.append(letter)
				all.insert(prefix)
			}
		}
		return all
	}()

	private static func buildCanonical() -> [String: String] {
		var table: [String: String] = [:]
		for syllable in standard {
			table[syllable] = syllable
			// `lü` / `nüe` are typed with `v`, which is otherwise unused in pinyin.
			if syllable.contains("ü") {
				table[syllable.replacingOccurrences(of: "ü", with: "v")] = syllable
				table[syllable.replacingOccurrences(of: "ü", with: "u")] = syllable
			}
		}
		// After j/q/x/y the `ü` sound is spelled `u`; tolerate the `v` habit from other IMEs.
		for syllable in standard where "jqxy".contains(syllable.first ?? " ") && syllable.dropFirst().hasPrefix("u") {
			table[syllable.prefix(1) + "v" + syllable.dropFirst(2)] = syllable
		}
		return table
	}

	/// Toneless Mandarin syllables. Interjections (`m`, `n`, `ng`, `hm`, `hng`, `ê`) are left out
	/// on purpose: they collide with the prefixes users are mid-way through typing.
	public static let standard: [String] = [
		"a", "ai", "an", "ang", "ao",
		"ba", "bai", "ban", "bang", "bao", "bei", "ben", "beng", "bi", "bian", "biao", "bie", "bin", "bing", "bo", "bu",
		"ca", "cai", "can", "cang", "cao", "ce", "cen", "ceng", "ci", "cong", "cou", "cu", "cuan", "cui", "cun", "cuo",
		"cha", "chai", "chan", "chang", "chao", "che", "chen", "cheng", "chi", "chong", "chou", "chu", "chua",
		"chuai", "chuan", "chuang", "chui", "chun", "chuo",
		"da", "dai", "dan", "dang", "dao", "de", "dei", "den", "deng", "di", "dia", "dian", "diao", "die", "ding",
		"diu", "dong", "dou", "du", "duan", "dui", "dun", "duo",
		"e", "ei", "en", "eng", "er",
		"fa", "fan", "fang", "fei", "fen", "feng", "fo", "fou", "fu",
		"ga", "gai", "gan", "gang", "gao", "ge", "gei", "gen", "geng", "gong", "gou", "gu", "gua", "guai", "guan",
		"guang", "gui", "gun", "guo",
		"ha", "hai", "han", "hang", "hao", "he", "hei", "hen", "heng", "hong", "hou", "hu", "hua", "huai", "huan",
		"huang", "hui", "hun", "huo",
		"ji", "jia", "jian", "jiang", "jiao", "jie", "jin", "jing", "jiong", "jiu", "ju", "juan", "jue", "jun",
		"ka", "kai", "kan", "kang", "kao", "ke", "kei", "ken", "keng", "kong", "kou", "ku", "kua", "kuai", "kuan",
		"kuang", "kui", "kun", "kuo",
		"la", "lai", "lan", "lang", "lao", "le", "lei", "leng", "li", "lia", "lian", "liang", "liao", "lie", "lin",
		"ling", "liu", "lo", "long", "lou", "lu", "luan", "lun", "luo", "lü", "lüe",
		"ma", "mai", "man", "mang", "mao", "me", "mei", "men", "meng", "mi", "mian", "miao", "mie", "min", "ming",
		"miu", "mo", "mou", "mu",
		"na", "nai", "nan", "nang", "nao", "ne", "nei", "nen", "neng", "ni", "nian", "niang", "niao", "nie", "nin",
		"ning", "niu", "nong", "nou", "nu", "nuan", "nun", "nuo", "nü", "nüe",
		"o", "ou",
		"pa", "pai", "pan", "pang", "pao", "pei", "pen", "peng", "pi", "pian", "piao", "pie", "pin", "ping", "po",
		"pou", "pu",
		"qi", "qia", "qian", "qiang", "qiao", "qie", "qin", "qing", "qiong", "qiu", "qu", "quan", "que", "qun",
		"ran", "rang", "rao", "re", "ren", "reng", "ri", "rong", "rou", "ru", "rua", "ruan", "rui", "run", "ruo",
		"sa", "sai", "san", "sang", "sao", "se", "sen", "seng", "si", "song", "sou", "su", "suan", "sui", "sun", "suo",
		"sha", "shai", "shan", "shang", "shao", "she", "shei", "shen", "sheng", "shi", "shou", "shu", "shua",
		"shuai", "shuan", "shuang", "shui", "shun", "shuo",
		"ta", "tai", "tan", "tang", "tao", "te", "tei", "teng", "ti", "tian", "tiao", "tie", "ting", "tong", "tou",
		"tu", "tuan", "tui", "tun", "tuo",
		"wa", "wai", "wan", "wang", "wei", "wen", "weng", "wo", "wu",
		"xi", "xia", "xian", "xiang", "xiao", "xie", "xin", "xing", "xiong", "xiu", "xu", "xuan", "xue", "xun",
		"ya", "yan", "yang", "yao", "ye", "yi", "yin", "ying", "yo", "yong", "you", "yu", "yuan", "yue", "yun",
		"za", "zai", "zan", "zang", "zao", "ze", "zei", "zen", "zeng", "zi", "zong", "zou", "zu", "zuan", "zui",
		"zun", "zuo",
		"zha", "zhai", "zhan", "zhang", "zhao", "zhe", "zhei", "zhen", "zheng", "zhi", "zhong", "zhou", "zhu",
		"zhua", "zhuai", "zhuan", "zhuang", "zhui", "zhun", "zhuo",
	]
}
