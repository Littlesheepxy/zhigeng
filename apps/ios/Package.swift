// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "ZhigengCore",
	platforms: [
		.iOS(.v17),
		.macOS(.v14),
	],
	products: [
		.library(name: "ZhigengCore", targets: ["ZhigengCore"]),
	],
	targets: [
		.target(
			name: "ZhigengCore",
			path: "ZhigengCore",
			resources: [.copy("Resources/pinyin.zpd")]
		),
		.testTarget(
			name: "ZhigengCoreTests",
			dependencies: ["ZhigengCore"],
			path: "ZhigengCoreTests"
		),
	]
)
