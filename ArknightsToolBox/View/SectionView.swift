//
//  SectionView.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI

struct SectionView: View {
    let title: String
    let items: [String]
    let colorMapping: [Color]? // Optional for sections without color mapping
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button(action: {
                        print("\(item) clicked")
                    }) {
                        Text(item)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(colorMapping?[safe: index] ?? Color.gray)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}


#Preview {
    SectionView(title: "aa", items: [""], colorMapping: [.red])
}
