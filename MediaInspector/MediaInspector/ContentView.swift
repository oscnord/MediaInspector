//
//  ContentView.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-02-15.
//

import SwiftUI
import Charts
import AVFoundation
import UniformTypeIdentifiers
import AppKit
import CoreMedia

struct MediaInspector: View {
    @State private var times: [Double] = []
    @State private var bitrates: [Double] = []
    @State private var extendedInfo: ExtendedVideoInfo?
    @State private var effectiveFPS: Double?
    @State private var minInterval: Double?
    @State private var maxInterval: Double?
    @State private var currentData: (time: Double, bitrate: Double)?
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        Button("Load file") {
                            self.loadAsset()
                        }
                        .padding(15)
                        
                        if !bitrates.isEmpty {
                            Chart {
                                ForEach(Array(zip(times, bitrates)), id: \.0) { (time, bitrate) in
                                    LineMark(
                                        x: .value("Time (s)", time),
                                        y: .value("Bitrate (kbps)", bitrate / 1000)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(
                                        Color(.red)
                                    )
                                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                                }
                            }
                            .chartXAxisLabel("Time (s)")
                            .chartYAxisLabel("Bitrate (kbps)")
                            .frame(maxWidth: .infinity)
                            .frame(height: geometry.size.height * 0.6)
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    let location = value.location
                                                    if let time: Double = proxy.value(atX: location.x) {
                                                        if let index = times.enumerated().min(by: { abs($0.element - time) < abs($1.element - time) })?.offset {
                                                            currentData = (time: times[index], bitrate: bitrates[index])
                                                        }
                                                    }
                                                }
                                                .onEnded { _ in
                                                    currentData = nil
                                                }
                                        )
                                }
                            }
                            .overlay {
                                if let data = currentData {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Time: \(data.time, specifier: "%.2f") s")
                                        Text("Bitrate: \(data.bitrate / 1000, specifier: "%.0f") kb/s")
                                    }
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                                    .shadow(radius: 5)
                                    .padding(.top, 20)
                                    .padding(.leading, 20)
                                    .transition(.opacity)
                                }
                            }
                            .padding(.horizontal, 15)
                        }
                        Spacer()
                    }
                    .frame(width: geometry.size.width * 0.60)
                    .background(.background)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.bar, lineWidth: 1)
                    )
                    .padding(.horizontal, 15)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let info = extendedInfo {
                            Group {
                                Text("File: \(info.fileName)").fontWeight(.bold)
                                Text("Size: \(info.fileSize)")
                                Text("Overall Bitrate: \(info.overallBitrate)")
                                Text("Duration: \(info.duration)")
                                Text("Resolution: \(info.resolution)")
                                Text("Nominal Frame Rate: \(info.frameRate)")
                                Text("Codec: \(info.codec)")
                            }
                            Group {
                                if let effectiveFPS = effectiveFPS {
                                    Text(String(format: "Effective Frame Rate: %.2f FPS", effectiveFPS))
                                }
                                if let minInterval = minInterval, let maxInterval = maxInterval {
                                    Text(String(format: "Frame Interval: min %.3f s, max %.3f s", minInterval, maxInterval))
                                }
                            }
                            Group {
                                if let cp = info.colorPrimaries {
                                    Text("Color Primaries: \(cp)")
                                }
                                if let tf = info.transferFunction {
                                    Text("Transfer Function: \(tf)")
                                }
                                if let mc = info.matrixCoefficients {
                                    Text("Matrix Coeffs: \(mc)")
                                }
                                if let range = info.colorRange {
                                    Text("Color Range: \(range)")
                                }
                                if let depth = info.bitDepth {
                                    Text("Bit Depth: \(depth)")
                                }
                                if let size = info.av1CSize {
                                    Text("av1C Box Size: \(size) bytes")
                                }
                            }
                        } else {
                            Text("No asset loaded")
                                .padding(.vertical, 15)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 25)
                    .frame(width: geometry.size.width * 0.35)
                    .background(.background)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.bar, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.top, 5)
        .padding(.bottom, 20)
        .padding(.leading, 5)
    }
    
    private func loadAsset() {
        openFileDialog { path in
            guard let path = path else { return }
            let url = URL(fileURLWithPath: path)
            let asset = AVURLAsset(url: url)
            
            Task {
                let info = await getExtendedInfo(url: url, asset: asset)
                self.extendedInfo = info
            }
            
            extractFrames(asset: asset) { extractedTimes, extractedBitrates in
                DispatchQueue.main.async {
                    self.times = extractedTimes
                    self.bitrates = extractedBitrates
                    if let stats = frameRateStats(from: extractedTimes) {
                        self.effectiveFPS = stats.averageFPS
                        self.minInterval = stats.minInterval
                        self.maxInterval = stats.maxInterval
                    }
                }
            }
        }
    }
}
