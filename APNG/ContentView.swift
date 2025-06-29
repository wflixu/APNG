//
//  ContentView.swift
//  APNG
//
//  Created by 李旭 on 2025/6/22.
//

import AppKit
import APNGKit

struct ContentView: View {
    @State private var apngImage: APNGImage? = nil

    var body: some View {
        VStack {
           if let apngImage = apngImage {
                APNGImageView(
                    image: apngImage,
                    staticImage: nil,
                    autoStartAnimationWhenSetImage: true,
                    onOnePlayDone: { loop in
                        print("播放完成 \(loop) 次")
                    },
                    onAllPlaysDone: {
                        print("全部播放完成")
                    },
                    onFrameMissed: { index in
                        print("丢帧: \(index)")
                    }
                )
                .frame(width: 200, height: 200)
            } else {
                Text("加载中...")
            }
        }
        .padding()
        .onAppear {
            // 加载 APNG 文件
            if let url = Bundle.main.url(forResource: "sample", withExtension: "apng") {
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        let image = try await APNGImage(data: data)
                        apngImage = image
                    } catch {
                        print("加载 APNG 失败: \(error)")
                    }
                }
            }
        }
    }

//    private func loadImage() {
//        // 尝试加载图像
//        if let loadedImage = try? APNGImage(named: "an") {
//            self.image = loadedImage
//        } else {
//            print("APNG 图像加载失败")
//        }
//    }
}

// struct APNGImageViewRepresentable: NSViewRepresentable {
//    let apngImage: APNGImage
//
//    func makeNSView(context: Context) -> APNGImageView {
//        let imageView = APNGImageView()
//        imageView.image = apngImage
//        imageView.startAnimating()
//        return imageView
//    }
//
//    func updateNSView(_ nsView: APNGImageView, context: Context) {
//        // 如果 apngImage 发生变化，可以更新 image
//        if nsView.image !== apngImage {
//            nsView.image = apngImage
//            nsView.startAnimating()
//        }
//    }
// }

#Preview {
    ContentView()
}
