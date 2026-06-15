//
//  ContentView.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import SwiftUI
import MapKit
import CoreLocation
import StoreKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationManager = LocationManager()
    @StateObject private var radarManager = RadarImageManager()
    @StateObject private var mapCameraController = MapCameraController()
    @ObservedObject private var settings = SettingsService.shared
    @State private var showSettings = false
    @State private var settingsDetent: PresentationDetent
    @State private var showChangelog = false
    @State private var didCheckChangelog = false
    @State private var showWidgetUsageMessage = false
    @State private var didRecordColdStart = false
    @State private var wasInBackground = false
    @State private var showReviewPrompt = false
    @State private var didProcessPostPermissionPrompts = false
    @ObservedObject private var customMarkerService = CustomMapMarkerService.shared
    @State private var showCreatePinDialog = false
    @State private var pendingPinCoordinate: CLLocationCoordinate2D?
    @State private var editingMarkerID: UUID?
    @State private var newPinDefaultName = "Marker 1"

    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    private enum Layout {
        static let screenSidePadding: CGFloat = 16
        static let headerTopPadding: CGFloat = 8
        static let headerButtonSize: CGFloat = 44
        static let locationButtonSize: CGFloat = 34
        static let locationButtonIconSize: CGFloat = 15
        static let controlButtonSize: CGFloat = 50
        static let controlButtonSpacing: CGFloat = 8
        static let centerLocationButtonGap: CGFloat = 28
        static let controlsProgressBarGap: CGFloat = 16
    }

    init() {
        // Use large detent on iPad, medium on iPhone
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        _settingsDetent = State(initialValue: isIPad ? .large : .medium)
    }

    private var hasLocationAccess: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private var meetsChangelogSessionThreshold: Bool {
        SessionCountStore.sessionCount() > 2
    }

    private func checkWidgetUsageMessage() {
        guard hasLocationAccess else { return }
        guard !showWidgetUsageMessage else { return }
        if WidgetUsageStore.shouldShowUsageMessage() {
            showWidgetUsageMessage = true
        }
    }

    private func checkReviewPrompt() {
        guard hasLocationAccess else { return }
        guard !showReviewPrompt else { return }
        guard !showChangelog && !showWidgetUsageMessage else { return }
        if ReviewPromptStore.shouldPromptReview(sessionCount: SessionCountStore.sessionCount()) {
            showReviewPrompt = true
        }
    }

    private func openReviewFeedbackEmail() {
        let subject = String(localized: "settings.email_subject")
        if let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "mailto:\(Constants.App.supportEmail)?subject=\(encodedSubject)") {
            openURL(url)
        }
    }

    private func handlePostPermissionPrompts() {
        guard hasLocationAccess else { return }
        guard !didProcessPostPermissionPrompts else { return }
        didProcessPostPermissionPrompts = true

        if ChangelogService.shared.shouldShowChangelog && meetsChangelogSessionThreshold {
            showChangelog = true
            ChangelogService.shared.markChangelogShown()
        } else {
            checkWidgetUsageMessage()
            checkReviewPrompt()
        }
    }

    private func prepareNewPin(at coordinate: CLLocationCoordinate2D) {
        pendingPinCoordinate = coordinate
        newPinDefaultName = customMarkerService.nextDefaultMarkerName
        showCreatePinDialog = true
    }

    private func toggleAnimation() {
        if radarManager.radarSequence.isAnimating {
            radarManager.stopAnimation()
        } else {
            radarManager.startAnimation()
        }
    }

    private func centerOnUserLocation() {
        if let location = locationManager.location {
            mapCameraController.center(on: location)
            return
        }

        locationManager.requestLocationUpdate { result in
            guard case .success(let location) = result else { return }
            Task { @MainActor in
                mapCameraController.center(on: location)
            }
        }
    }
    
    
    var body: some View {
        ZStack {
            MapViewWithOverlay(
                cameraController: mapCameraController,
                radarImageManager: radarManager,
                userLocation: locationManager.location,
                userHeading: locationManager.heading,
                customMarkers: customMarkerService.markers,
                onMapLongPress: prepareNewPin(at:),
                onCustomMarkerTap: { markerID in
                    editingMarkerID = markerID
                }
            )
                .ignoresSafeArea()
            
            // Timestamp display in top left corner, settings button in top right
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        RadarTimestampDisplay(
                            timestamp: radarManager.radarSequence.currentTimestamp,
                            isForecast: radarManager.radarSequence.currentImageData?.kind.isForecast ?? false
                        )
                        
                        // Country flag of the currently selected radar product
                        RadarProductPicker()
                    }
                    .padding(.leading, Layout.screenSidePadding)
                    .padding(.top, Layout.headerTopPadding)
                    
                    Spacer()
                    
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: Layout.headerButtonSize, height: Layout.headerButtonSize)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, Layout.screenSidePadding)
                    .padding(.top, Layout.headerTopPadding)
                }
                
                Spacer()
            }
            
            if settings.isLegendEnabled {
                GeometryReader { proxy in
                    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
                    let isLandscape = proxy.size.width > proxy.size.height
                    let legendTopSpacerFactor: CGFloat = isIPad ? (isLandscape ? 0.58 : 0.67) : 0.45

                    VStack {
                        Spacer()
                            .frame(height: proxy.size.height * legendTopSpacerFactor)
                        RadarLegendView()
                            .padding(.leading, isIPad ? 16 : 0)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: Layout.centerLocationButtonGap) {
                        Button(action: centerOnUserLocation) {
                            Image(systemName: "location.fill")
                                .font(.system(size: Layout.locationButtonIconSize, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: Layout.locationButtonSize, height: Layout.locationButtonSize)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                        .disabled(!hasLocationAccess)
                        .accessibilityLabel(Text("map.center_user_location"))

                        VStack(spacing: Layout.controlButtonSpacing) {
                            // Animation toggle button
                            Button(action: toggleAnimation) {
                                Image(systemName: radarManager.radarSequence.isAnimating ? "pause.fill" : "play.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: Layout.controlButtonSize, height: Layout.controlButtonSize)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                            
                            // Refresh button
                            Button(action: {
                                radarManager.refreshRadarImages()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: Layout.controlButtonSize, height: Layout.controlButtonSize)
                                    .background(Color.green)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.trailing, Layout.screenSidePadding)
                    .padding(.bottom, RadarProgressBar.Constants.controlsBottomPadding(gapAboveProgressBar: Layout.controlsProgressBarGap))
                }
            }
            .transition(.opacity)
            
            // Radar Progress Bar at the very bottom (under safe area)
            VStack {
                Spacer()
                RadarProgressBar(radarSequence: radarManager.radarSequence, radarImageManager: radarManager)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .radarKeyboardShortcuts(
            onToggleAnimation: toggleAnimation,
            onRefresh: { radarManager.refreshRadarImages() }
        )
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                if wasInBackground {
                    SessionCountStore.incrementSessionCount()
                    wasInBackground = false
                    checkReviewPrompt()
                }
                radarManager.resumeForForeground()
                locationManager.resumeForForeground()
            case .inactive, .background:
                if phase == .background {
                    wasInBackground = true
                }
                radarManager.pauseForBackground()
                locationManager.pauseForBackground()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium, .large], selection: $settingsDetent)
        }
        .onAppear {
            if !didRecordColdStart {
                SessionCountStore.incrementSessionCount()
                didRecordColdStart = true
            }
            guard !didCheckChangelog else { return }
            didCheckChangelog = true
            handlePostPermissionPrompts()
        }
        .onChange(of: locationManager.authorizationStatus) { status in
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                handlePostPermissionPrompts()
            }
        }
        .onChange(of: showChangelog) { _ in
            if !showChangelog {
                checkReviewPrompt()
            }
        }
        .onChange(of: showWidgetUsageMessage) { _ in
            if !showWidgetUsageMessage {
                checkReviewPrompt()
            }
        }
        .alert("changelog.title", isPresented: $showChangelog) {
            Button("settings.done") {}
        } message: {
            Text("changelog.message")
        }
        .alert("widget.usage_title", isPresented: $showWidgetUsageMessage) {
            Button("settings.done") {
                WidgetUsageStore.markUsageMessageShown()
            }
        } message: {
            Text("widget.usage_message")
        }
        .alert("review.prompt_title", isPresented: $showReviewPrompt) {
            Button("review.prompt_yes") {
                ReviewPromptStore.markCompleted()
                requestReview()
            }
            Button("review.prompt_no") {
                ReviewPromptStore.markCompleted()
                openReviewFeedbackEmail()
            }
        }
        .sheet(isPresented: $showCreatePinDialog) {
            CreatePinSheetView(
                defaultName: newPinDefaultName,
                onCancel: {
                    pendingPinCoordinate = nil
                    showCreatePinDialog = false
                },
                onSave: { name, colorHex, glyph in
                    guard let coordinate = pendingPinCoordinate else { return }
                    customMarkerService.addMarker(
                        name: name,
                        coordinate: coordinate,
                        colorHex: colorHex,
                        glyph: glyph
                    )
                    pendingPinCoordinate = nil
                    showCreatePinDialog = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { editingMarkerID != nil },
            set: { if !$0 { editingMarkerID = nil } }
        )) {
            if let markerID = editingMarkerID,
               let marker = customMarkerService.marker(for: markerID) {
                EditPinSheetView(
                    marker: marker,
                    defaultName: customMarkerService.defaultName(for: markerID),
                    onDelete: {
                        customMarkerService.deleteMarker(id: markerID)
                        editingMarkerID = nil
                    },
                    onSave: { name, colorHex, glyph in
                        customMarkerService.updateMarker(
                            id: markerID,
                            name: name,
                            colorHex: colorHex,
                            glyph: glyph
                        )
                        editingMarkerID = nil
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

#Preview {
    ContentView()
}

private extension View {
    /// Maps the spacebar to play/pause and the R key to refresh on iPad / external keyboards.
    /// No-op on iOS < 17.0; `.onKeyPress` requires iOS 17.0+.
    @ViewBuilder
    func radarKeyboardShortcuts(
        onToggleAnimation: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            modifier(RadarKeyboardShortcutsModifier(
                onToggleAnimation: onToggleAnimation,
                onRefresh: onRefresh
            ))
        } else {
            self
        }
    }
}

@available(iOS 17.0, *)
private struct RadarKeyboardShortcutsModifier: ViewModifier {
    let onToggleAnimation: () -> Void
    let onRefresh: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear { grabFocus() }
            .onChange(of: scenePhase) { _, phase in
                // Re-grab focus when returning from background or when the
                // window becomes key again (relevant on "Designed for iPad" on macOS).
                if phase == .active { grabFocus() }
            }
            .onKeyPress { press in
                switch press.key {
                case .space:
                    runAfterCurrentUpdate(onToggleAnimation)
                    return .handled
                case KeyEquivalent("r"), KeyEquivalent("R"):
                    runAfterCurrentUpdate(onRefresh)
                    return .handled
                default:
                    return .ignored
                }
            }
    }

    /// Defers the focus assignment to the next run loop tick to avoid
    /// "Publishing changes from within view updates is not allowed" warnings
    /// caused by mutating @FocusState during a view update pass.
    private func grabFocus() {
        runAfterCurrentUpdate { isFocused = true }
    }

    /// SwiftUI dispatches `.onKeyPress` actions during a view-update phase, so
    /// mutating `@Published` state from `RadarImageManager` synchronously here
    /// triggers a "Publishing changes from within view updates" warning.
    /// Hopping onto the next main-actor turn breaks that ordering.
    private func runAfterCurrentUpdate(_ action: @escaping () -> Void) {
        Task { @MainActor in
            action()
        }
    }
}
