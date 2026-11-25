// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPet",
    platforms: [.macOS(.v14)],
    targets: [
        // 순수 로직 (Foundation 만)
        .target(name: "MacPetCore"),
        // 실행 파일
        .executableTarget(name: "MacPet", dependencies: ["MacPetCore"]),
        .testTarget(name: "MacPetCoreTests", dependencies: ["MacPetCore"]),
    ]
)
