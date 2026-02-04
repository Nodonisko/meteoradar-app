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
    @State private var region: MKCoordinateRegion
    @State private var showSettings = false
    @State private var settingsDetent: PresentationDetent
    @State private var showChangelog = false
    @State private var didCheckChangelog = false
    @State private var showWidgetUsageMessage = false
    @State private var didRecordColdStart = false
    @State private var wasInBackground = false
    @State private var showReviewPrompt = false
    @State private var didProcessPostPermissionPrompts = false

    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    
    init() {
        // Initialize region from saved state, or use default if no saved state exists
        let savedRegion = MapStateService.shared.loadRegion()
        _region = State(initialValue: savedRegion ?? Constants.Radar.defaultRegion)
        
        // Use large detent on iPad, medium on iPhone
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        _settingsDetent = State(initialValue: isIPad ? .large : .medium)
    }
    
    // Helper function to detect if running in simulator
    private var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
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
    
    
    var body: some View {
        ZStack {
            MapViewWithOverlay(region: $region, radarImageManager: radarManager, userLocation: locationManager.location, userHeading: locationManager.heading)
                .ignoresSafeArea()
            
            // Timestamp display in top left corner, settings button in top right
            VStack {
                HStack {
                    RadarTimestampDisplay(
                        timestamp: radarManager.radarSequence.currentTimestamp,
                        isForecast: radarManager.radarSequence.currentImageData?.kind.isForecast ?? false
                    )
                        .padding(.leading, 16)
                        .padding(.top, 8)
                    
                    Spacer()
                    
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                
                Spacer()
            }
            
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        // Animation toggle button
                        Button(action: {
                            if radarManager.radarSequence.isAnimating {
                                radarManager.stopAnimation()
                            } else {
                                radarManager.startAnimation()
                            }
                        }) {
                            Image(systemName: radarManager.radarSequence.isAnimating ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
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
                                .frame(width: 50, height: 50)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.trailing, 20)                    .padding(.bottom, RadarProgressBar.Constants.controlsBottomPadding(gapAboveProgressBar: 16))
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
        .onReceive(locationManager.$location) { location in
            // Only update location if not running in simulator
            if let location = location, !isRunningInSimulator {
                region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: Constants.Location.userLocationSpan
                )
            }
        }
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
    }
}

#Preview {
    ContentView()
}
