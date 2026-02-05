//
//  RadarLegendView.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 05.02.2026.
//

import SwiftUI
import UIKit

struct RadarLegendView: View {
    private struct LegendStep: Identifiable {
        let id = UUID()
        let dbz: Int
        let color: Color
        let mmhLabel: String?
    }

    private enum Constants {
        static let colorWidth: CGFloat = 16
        static let rowHeight: CGFloat = 12
        static let labelSpacing: CGFloat = 6
        static let dbzColumnMinWidth: CGFloat = 24
        static let mmhColumnMinWidth: CGFloat = 24
        static let cornerRadius: CGFloat = 8
        static let padding: CGFloat = 8
        static let trailingPadding: CGFloat = 8
        static let backgroundOpacity: CGFloat = 0.7
        static let strokeOpacity: CGFloat = 0.15

        static let dbzFont = Font.system(size: 11, weight: .semibold, design: .monospaced)
        static let mmhFont = Font.system(size: 10, weight: .semibold, design: .monospaced)
        static let unitFont = Font.system(size: 9, weight: .medium)
    }

    private let dbzValues = [4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60]
    private let colorSteps = [
        "#390071",
        "#3001A9",
        "#0200FB",
        "#076CBC",
        "#00A400",
        "#00BB03",
        "#36D700",
        "#9CDD07",
        "#E0DC01",
        "#FBB200",
        "#F78600",
        "#FF5400",
        "#FE0100",
        "#A40003",
        "#FCFCFC"
    ]
    private let mmhLabels: [Int: String] = [
        4: "0.1",
        20: "1",
        36: "10",
        52: "100"
    ]

    private var legendSteps: [LegendStep] {
        let count = min(dbzValues.count, colorSteps.count)
        return (0..<count).map { index in
            let dbz = dbzValues[index]
            return LegendStep(
                dbz: dbz,
                color: Color(hex: colorSteps[index]),
                mmhLabel: mmhLabels[dbz]
            )
        }
    }

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(spacing: 0) {
                ForEach(legendSteps) { step in
                    HStack(spacing: Constants.labelSpacing) {
                        Rectangle()
                            .fill(step.color)
                            .frame(width: Constants.colorWidth, height: Constants.rowHeight)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                            )

                        Text("\(step.dbz)")
                            .font(Constants.dbzFont)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .layoutPriority(1)
                            .frame(minWidth: Constants.dbzColumnMinWidth, alignment: .leading)

                        if isIPad {
                            Text(step.mmhLabel ?? "")
                                .font(Constants.mmhFont)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .layoutPriority(1)
                                .frame(minWidth: Constants.mmhColumnMinWidth, alignment: .leading)
                        }
                    }
                }
            }

            HStack(spacing: Constants.labelSpacing) {
                Text("dBZ")
                    .font(Constants.unitFont)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                    .frame(
                        minWidth: Constants.colorWidth + Constants.labelSpacing + Constants.dbzColumnMinWidth,
                        alignment: .leading
                    )

                if isIPad {
                    Text("mm/h")
                        .font(Constants.unitFont)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .frame(minWidth: Constants.mmhColumnMinWidth, alignment: .leading)
                }
            }
        }
        .padding(.leading, Constants.padding)
        .padding(.vertical, Constants.padding)
        .padding(.trailing, isIPad ? Constants.trailingPadding : 0)
        .background {
            if isIPad {
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .fill(Color.black.opacity(Constants.backgroundOpacity))
            } else {
                RoundedCornerShape(radius: Constants.cornerRadius, corners: [.topRight, .bottomRight])
                    .fill(Color.black.opacity(Constants.backgroundOpacity))
            }
        }
        .overlay {
            if isIPad {
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .stroke(Color.white.opacity(Constants.strokeOpacity), lineWidth: 1)
            } else {
                RoundedCornerShape(radius: Constants.cornerRadius, corners: [.topRight, .bottomRight])
                    .stroke(Color.white.opacity(Constants.strokeOpacity), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

private struct RoundedCornerShape: Shape {
    let radius: CGFloat
    let corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        RadarLegendView()
    }
}
