//
//  ContentView.swift
//  Meteoradar
//
//  Created by Daniel Suchý on 14.09.2025.
//

import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationManager = LocationManager()
    @StateObject private var radarManager = RadarImageManager()
    @State private var region: MKCoordinateRegion
    @State private var showSettings = false
    @State private var settingsDetent: PresentationDetent
    @State private var showChangelog = false
    @State private var didCheckChangelog = false
    
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
                radarManager.resumeForForeground()
                locationManager.resumeForForeground()
            case .inactive, .background:
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
            guard !didCheckChangelog else { return }
            didCheckChangelog = true
            
            if ChangelogService.shared.shouldShowChangelog {
                showChangelog = true
                ChangelogService.shared.markChangelogShown()
            }
        }
        .alert("changelog.title", isPresented: $showChangelog) {
            Button("settings.done") {}
        } message: {
            Text("changelog.message")
        }
    }
}

#Preview {
    ContentView()
}
