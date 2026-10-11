//
//  ArknightsToolBoxApp.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI
import Firebase   // 新增：导入 Firebase

@main
struct ArknightsToolBoxApp: App {
    
    init() {
        // 初始化 Firebase
        FirebaseApp.configure()
        
        // 修改 SegmentedPicker 样式：未选中白色，选中黑色
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.black
        ]
        UISegmentedControl.appearance().setTitleTextAttributes(normalAttrs, for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(selectedAttrs, for: .selected)
    }
    
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
