
// 仅支持 SwiftUI，macOS 15+，Swift 6 并发安全环境
import Foundation
import SwiftUI
import CoreGraphics

// 测试 组件是否可以被引用，先写一个简单的 View，显示 resources 中的png 图片
public struct PNGImageView: View {
    @State var imageUrl: URL?

    public init() {}

    public var body: some View {
        VStack {
            Text("load png image").font(.title)
            Image("sample", bundle: .module)
                               .renderingMode(.original)
        }.onAppear {
            loadImage();
        }
    }

    // loadImage
    public func loadImage() {
        guard let lsimageURL = Bundle.module.url(
            forResource: "sample",
            withExtension: "png",
            subdirectory: "Images"
        ) else {
            print("Image not found")
            return
        }
        print(lsimageURL.path);
    }
}

