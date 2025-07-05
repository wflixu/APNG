//
//  APNGDemo.swift
//  APNGKit
//
//  Created by 李旭 on 2025/7/3.
//

import SwiftUI
import APNGKit // 导入你的库

@main
struct APNGDemoApp: App {
    var body: some Scene {
        WindowGroup {
            APNGImageView()
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                   
                    
                }
        }
    }
}


