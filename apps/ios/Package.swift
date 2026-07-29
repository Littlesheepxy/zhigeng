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
		// The pinyin table is deliberately not a package resource: SPM embeds a resource
		// bundle into every target that links the package, which shipped the 26MB file
		// twice. It is attached to the app target in project.yml instead, and the
		// keyboard extension reads it out of the containing app bundle.
		.target(
			name: "ZhigengCore",
			path: "ZhigengCore"
		),
		.testTarget(
			name: "ZhigengCoreTests",
			dependencies: ["ZhigengCore"],
			path: "ZhigengCoreTests"
		),
	]
)
