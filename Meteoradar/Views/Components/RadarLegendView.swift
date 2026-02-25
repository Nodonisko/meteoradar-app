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
        static let colorWidth: CGFloat = 30
        static let rowHeight: CGFloat = 16
        static let labelSpacing: CGFloat = 6
        static let mmhColumnMinWidth: CGFloat = 24
        static let cornerRadius: CGFloat = 8
        static let firstSwatchCornerRadius: CGFloat = 4
        static let padding: CGFloat = 8
        static let phoneBottomPadding: CGFloat = 5
        static let trailingPadding: CGFloat = 8
        static let backgroundOpacity: CGFloat = 0.7
        static let strokeOpacity: CGFloat = 0.15

        static let dbzFont = Font.system(size: 11, weight: .semibold, design: .monospaced)
        static let mmhFont = Font.system(size: 10, weight: .semibold, design: .monospaced)
        static let unitFont = Font.system(size: 9, weight: .medium)
    }

    private let dbzValues = [60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12, 8, 4]
    private let colorSteps = [
        "#FCFCFC",
        "#A40003",
        "#FE0100",
        "#FF5400",
        "#F78600",
        "#FBB200",
        "#E0DC01",
        "#9CDD07",
        "#36D700",
        "#00BB03",
        "#00A400",
        "#076CBC",
        "#0200FB",
        "#3001A9",
        "#390071"
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
                ForEach(Array(legendSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: Constants.labelSpacing) {
                        if index == 0 && !isIPad {
                            RoundedCornerShape(radius: Constants.firstSwatchCornerRadius, corners: [.topRight])
                                .fill(step.color)
                                .frame(width: Constants.colorWidth, height: Constants.rowHeight)
                                .overlay(
                                    Text("\(step.dbz)")
                                        .font(Constants.dbzFont)
                                        .foregroundColor(step.dbz >= 60 ? .black : .white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                )
                                .overlay(
                                    RoundedCornerShape(radius: Constants.firstSwatchCornerRadius, corners: [.topRight])
                                        .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                )
                        } else {
                            Rectangle()
                                .fill(step.color)
                                .frame(width: Constants.colorWidth, height: Constants.rowHeight)
                                .overlay(
                                    Text("\(step.dbz)")
                                        .font(Constants.dbzFont)
                                        .foregroundColor(step.dbz >= 60 ? .black : .white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                )
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                )
                        }

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
                    .frame(width: Constants.colorWidth, alignment: .center)

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
        .padding(.leading, isIPad ? Constants.padding : 0)
        .padding(.top, isIPad ? Constants.padding : 0)
        .padding(.bottom, isIPad ? Constants.padding : Constants.phoneBottomPadding)
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
