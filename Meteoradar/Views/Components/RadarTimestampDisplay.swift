//
//  RadarTimestampDisplay.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 15.09.2025.
//

import SwiftUI

struct RadarTimestampDisplay: View {
    let timestamp: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let timestamp = timestamp {
                Text(timestamp.localTimeString)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                Text("--:--")
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                
                Text("No Data")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        
        VStack(spacing: 20) {
            RadarTimestampDisplay(timestamp: Date())
            RadarTimestampDisplay(timestamp: nil)
        }
    }
}
