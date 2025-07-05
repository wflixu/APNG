//
//  APNGDemo.swift
//  APNGKit
//
//  Created by 李旭 on 2025/7/3.
//

import APNGKit // 导入你的库
import SwiftUI

@main
struct APNGDemoApp: App {
    @State var imageUrl: URL?
    @State var apngImage: APNGImage? // 假设你有一个 ImageLoader 类来处理图像加载
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                Text("APNG Demo").font(.title)
                if let imageUrl = imageUrl {
                    // 使用 APNGImage 来加载和显示 APNG 图像
                    // 这里假设你有一个 APNGImage 的初始化方法
                    // let apngImage = try? APNGImage(contentsOf: imageUrl)

                    // 使用 APNGImageView 来显示图像
                    // APNGImageView(image: apngImage, staticImage: Image("sample", bundle: .module))

                    // 这里可以使用自定义的 APNGImageView
                    // 需要确保 APNGImageView 已经实现了相关的播放逻辑
                } else {
                    Text("Loading image...")
                }
                // APNGImageView(
                //     image: nil, // 这里可以传入 APNGImage 实例
                //     staticImage: Image("sample", bundle: .module), // 静态图片
                //     autoStartAnimationWhenSetImage: true,
                //     onOnePlayDone: { count in
                //         print("One play done, count: \(count)")
                //     },
                //     onAllPlaysDone: {
                //         print("All plays done")
                //     },
                //     onFrameMissed: { index in
                //         print("Frame missed at index: \(index)")
                //     },
                //     onFallBackToDefaultImage: {
                //         print("Falling back to default image")
                //     },
                //     onFallBackToDefaultImageFailed: { error in
                //         print("Fallback failed with error: \(error)")
                //     },
                //     onDecodingFrameError: { error in
                //         print("Decoding frame error: \(error)")
                //     }
                // )
            }.onAppear {
                loadImage()
            }
        }
    }

    func loadImage() {
        // executableTarget 下 Bundle.module 依然可用，前提是图片已正确声明为资源
        guard let imageUrl = Bundle.module.url(
            forResource: "sample",
            withExtension: "APNG",
            subdirectory: "Images"
        ) else {
            print("Image not found")
            return
        }
        print(imageUrl.path)
        self.imageUrl = imageUrl
        // 根据apng文件的路径加载 APNGImage，需要 try/catch
        do {
            apngImage = try APNGImage(fileURL: imageUrl)
        } catch {
            print("Failed to load APNGImage: \(error)")
            apngImage = nil
        }
    }
}
