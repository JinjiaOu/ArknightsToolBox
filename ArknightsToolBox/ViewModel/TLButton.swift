//
//  TLButton.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI

struct TLButton: View {
    let title: String
    let background: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            action()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(background)
                    .shadow(color: background.opacity(0.5), radius: 5, x: 0, y: 5) // 增加阴影效果
                
                Text(title)
                    .foregroundColor(.white)
                    .bold()
            }
            .frame(height: 50) // 设置固定高度
            .padding(.horizontal, 20) // 增加左右间距
        }
        .scaleEffect(1.0) // 初始状态
        .onTapGesture {
            withAnimation(.easeIn(duration: 0.2)) {
                // 点击缩放效果
            }
        }
    }
}

#Preview {
    TLButton(title: "Save", background: .pink) {}
}

