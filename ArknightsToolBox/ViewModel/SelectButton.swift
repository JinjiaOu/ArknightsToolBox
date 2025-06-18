//
//  SelectButton.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI

struct SelectButton: View {
    let title: String
    let items: [String]
    @Binding var selectedItems: [String] // Binding to track selected items
    let color: Color = Color(hex: "#FF8C00") // Default color for selection
    var onSelectionChanged: (() -> Void)? // Optional callback for selection changes

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(title)
                .font(.headline)
                .foregroundColor(color)
                .padding(.horizontal)

            // Selectable items in a grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                ForEach(items, id: \.self) { item in
                    ZStack {
                        Capsule()
                            .fill(selectedItems.contains(item) ? color : Color.gray.opacity(0.3))
                            .frame(height: 50)
                            .shadow(color: selectedItems.contains(item) ? color.opacity(0.5) : .clear, radius: 5)

                        Text(item)
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .onTapGesture {
                        if selectedItems.contains(item) {
                            // Deselect item
                            selectedItems.removeAll { $0 == item }
                        } else {
                            // Select item
                            selectedItems.append(item)
                        }
                        // Call the callback after selection changes
                        onSelectionChanged?()
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    @State var selectedItems: [String] = []
    
    return SelectButton(
        title: "星级",
        items: ["全选", "6★", "5★", "4★", "3★", "2★", "1★"],
        selectedItems: $selectedItems,
        onSelectionChanged: nil
    )
}
