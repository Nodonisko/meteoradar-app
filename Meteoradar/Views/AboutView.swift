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
                VStack(spacing: 8) {
                    Text("📱❤️⛈️")
                        .font(.title)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(.init(String(localized: "about.description")))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("about.data_source_title")
                        .font(.headline)

                    Text("about.data_source_description")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                Link(destination: URL(string: "https://github.com/Nodonisko/meteoradar-app")!) {
                    HStack {
                        Text("about.github")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Link(destination: URL(string: "https://radar.danielsuchy.cz/privacy.html")!) {
                    HStack {
                        Text("about.privacy_policy")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}

