//
//  ArknightsToolBoxApp.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI

@main
struct ArknightsToolBoxApp: App {
    
    init() {
        // 修改 SegmentedPicker 的未选中文字颜色为白色，选中为黑色
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
