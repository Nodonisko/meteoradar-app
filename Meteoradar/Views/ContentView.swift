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
    @StateObject private var locationManager = LocationManager()
    @StateObject private var radarManager = RadarImageManager()
    @State private var region = Constants.Radar.defaultRegion
    
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
            MapViewWithOverlay(region: $region, radarImageManager: radarManager, userLocation: locationManager.location)
                .ignoresSafeArea()
            
            // Timestamp display in top left corner
            VStack {
                HStack {
                    RadarTimestampDisplay(timestamp: radarManager.radarSequence.currentTimestamp)
                        .padding(.leading, 16)
                        .padding(.top, 8)
                    
                    Spacer()
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
                                .background(radarManager.isLoading ? Color.gray : Color.green)
                                .clipShape(Circle())
                        }
                        .disabled(radarManager.isLoading)
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
    }
}

#Preview {
    ContentView()
}
