# APNGKit

APNG 是一个用于 macOS 的 APNG（Animated PNG）图片格式解码、显示与编码的项目。支持 APNG 动画图片的解析、渲染和生成，适用于需要高质量动画图片支持的 macOS 应用。

## 功能特性

- 支持 APNG 格式图片的解码与显示
- 支持 APNG 格式图片的编码与导出
- 提供 Swift API，易于集成到 macOS 项目
- 包含单元测试与 UI 测试

## 目录结构

- `APNG/`：主应用代码（SwiftUI）
- `APNGKit/`：APNG 解码、编码核心库（Swift Package）
- `APNGTests/`：单元测试
- `APNGUITests/`：UI 测试

## 快速开始

### 依赖

- macOS 12.0 及以上
- Xcode 14 及以上
- Swift 5.7 及以上

### 编译与运行

1. 克隆代码库
    ```sh
    git clone https://github.com/yourname/APNG.git
    cd APNG
    ```
2. 用 Xcode 打开 `APNG.xcodeproj`
3. 选择目标并运行

### 使用 APNGKit

在你的 Swift 代码中：

```swift
import APNGKit

// 加载 APNG 图片
if let url = Bundle.main.url(forResource: "sample", withExtension: "apng"),
   let apngImage = APNGImage(contentsOf: url) {
    // 显示或处理 apngImage
}
```

## 贡献

欢迎提交 issue 和 PR 改进本项目。

## 许可证

MIT License

---

> 本项目仅用于学习与研究 APNG 格式相关技