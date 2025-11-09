//
//  ContentView.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraCaptureView()
    }
}

#Preview {
    // Use a simple preview that doesn't require camera access
    VStack {
        Text("MuseLens")
            .font(.system(size: 36, weight: .bold))
        Text("拍一眼，就懂艺术")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.secondary)
    }
    .padding()
}
