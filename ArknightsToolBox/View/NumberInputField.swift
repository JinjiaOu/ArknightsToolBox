//
//  NumberInputField.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/22/25.
//

import SwiftUI

struct NumberInputField: View {
    let title: String
    @Binding var number: Int
    var placeholder: String = ""

    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: Binding(
            get: {
                if inputText.isEmpty {
                    return number == 0 ? "" : "\(number)"
                } else {
                    return inputText
                }
            },
            set: {
                inputText = $0
                if let value = Int($0), value >= 0 {
                    number = value
                } else if $0.isEmpty {
                    number = 0
                }
            }
        ))
        .keyboardType(.numberPad)
        .focused($isFocused) //  绑定焦点
        .foregroundColor(.white)
        .padding(10)
        .background(Color(hex: "#1E1E1E"))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            inputText = number == 0 ? "" : "\(number)"
        }
        .onChange(of: number) { newValue in
            inputText = newValue == 0 ? "" : "\(newValue)"
        }
    }
}
