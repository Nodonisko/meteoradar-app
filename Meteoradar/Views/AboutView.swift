//
//  AboutView.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 10.01.2026.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("about.data_source_title")
                        .font(.headline)
                    
                    Text("about.data_source_description")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                Link(destination: URL(string: "https://radar.danielsuchy.cz/privacy.html")!) {
                    HStack {
                        Text("about.privacy_policy")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}

