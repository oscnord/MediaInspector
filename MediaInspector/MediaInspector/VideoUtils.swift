//
//  VideoUtils.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-02-15.
//

import Foundation
import AVFoundation

let kCMFormatDescriptionExtension_Range: CFString = "Range" as CFString
let kCMFormatDescriptionExtension_MatrixCoefficients: CFString = "MatrixCoefficients" as CFString

struct ExtendedVideoInfo {
    let fileName: String
    let fileSize: String
    let overallBitrate: String
    let duration: String
    let resolution: String
    let frameRate: String
    let codec: String
    let colorPrimaries: String?
    let transferFunction: String?
    let matrixCoefficients: String?
    let colorRange: String?
    let bitDepth: String?
    let av1CSize: Int?
}

func fourCCToString(_ code: OSType) -> String {
    let bytes: [CChar] = [
        CChar((code >> 24) & 0xFF),
        CChar((code >> 16) & 0xFF),
        CChar((code >> 8) & 0xFF),
        CChar(code & 0xFF),
        0
    ]
    return String(cString: bytes)
}

func getFileSizeString(for url: URL) -> String {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? UInt64 {
            let sizeMB = Double(size) / 1_048_576.0
            return String(format: "%.2f MiB", sizeMB)
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
    return "Unknown"
}

func getOverallBitrateString(asset: AVAsset, fileURL: URL) -> String {
    let durationSec = CMTimeGetSeconds(asset.duration)
    guard durationSec > 0 else { return "Unknown" }
    
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attrs[.size] as? UInt64 {
            let totalBits = Double(size * 8)
            let bitsPerSecond = totalBits / durationSec
            let kbps = bitsPerSecond / 1000
            return String(format: "%.0f kb/s", kbps)
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
    return "Unknown"
}

func getExtendedInfo(url: URL, asset: AVAsset) async -> ExtendedVideoInfo {
    let fileName = url.lastPathComponent
    let fileSize = getFileSizeString(for: url)
    let overallBitrate = getOverallBitrateString(asset: asset, fileURL: url)
    
    var duration = "N/A"
    var resolution = "N/A"
    var frameRate = "N/A"
    var codec = "Unknown"
    
    var colorPrimaries: String? = nil
    var transferFunction: String? = nil
    var matrixCoefficients: String? = nil
    var colorRange: String? = nil
    var bitDepth: String? = nil
    var av1CSize: Int? = nil
    
    let durationSec = CMTimeGetSeconds(asset.duration)
    if durationSec > 0 {
        duration = String(format: "%.2f sec", durationSec)
    }
    
    if let videoTrack = asset.tracks(withMediaType: .video).first {
        do {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let loadedFrameRate = try await videoTrack.load(.nominalFrameRate)
            let w = Int(naturalSize.width)
            let h = Int(naturalSize.height)
            resolution = "\(w)x\(h)"
            frameRate = String(format: "%.2f FPS", loadedFrameRate)
            
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            guard let formatDesc = formatDescriptions.first else {
                fatalError("No format description available")
            }
            let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
            let codecID = fourCCToString(codecType)
            let codecMappings: [String: String] = [
                "avc1": "H.264",
                "hvc1": "HEVC (H.265)",
                "vp09": "VP9",
                "av01": "AV1"
            ]
            codec = codecMappings[codecID] ?? codecID
            
            if let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] {
                colorPrimaries = extDict[kCMFormatDescriptionExtension_ColorPrimaries] as? String
                transferFunction = extDict[kCMFormatDescriptionExtension_TransferFunction] as? String
                matrixCoefficients = extDict[kCMFormatDescriptionExtension_MatrixCoefficients] as? String
                colorRange = extDict[kCMFormatDescriptionExtension_Range] as? String
                if let d = extDict[kCMFormatDescriptionExtension_Depth] as? NSNumber {
                    bitDepth = "\(d.intValue) bits"
                }
                if let atoms = extDict[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [CFString: Any],
                   let av1CData = atoms["av1C" as CFString] as? Data {
                    av1CSize = av1CData.count
                }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
    
    return ExtendedVideoInfo(
        fileName: fileName,
        fileSize: fileSize,
        overallBitrate: overallBitrate,
        duration: duration,
        resolution: resolution,
        frameRate: frameRate,
        codec: codec,
        colorPrimaries: colorPrimaries,
        transferFunction: transferFunction,
        matrixCoefficients: matrixCoefficients,
        colorRange: colorRange,
        bitDepth: bitDepth,
        av1CSize: av1CSize
    )
}

func frameRateStats(from times: [Double]) -> (averageFPS: Double, minInterval: Double, maxInterval: Double)? {
    guard times.count > 1 else { return nil }
    
    var intervals: [Double] = []
    for i in 1..<times.count {
        intervals.append(times[i] - times[i - 1])
    }
    
    let totalDuration = intervals.reduce(0, +)
    let averageInterval = totalDuration / Double(intervals.count)
    let averageFPS = averageInterval > 0 ? 1.0 / averageInterval : 0
    let minInterval = intervals.min() ?? 0
    let maxInterval = intervals.max() ?? 0
    return (averageFPS, minInterval, maxInterval)
}

func extractFrames(asset: AVAsset, completion: @escaping ([Double], [Double]) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async {
                completion([], [])
            }
            return
        }
        
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            if reader.canAdd(output) {
                reader.add(output)
            } else {
                DispatchQueue.main.async {
                    completion([], [])
                }
                return
            }
            
            var times: [Double] = []
            var bitrates: [Double] = []
            var previousTime: Double?
            
            reader.startReading()
            
            while let sampleBuffer = output.copyNextSampleBuffer() {
                let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                let sampleSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)
                
                if let prev = previousTime, currentTime > prev {
                    let frameDuration = currentTime - prev
                    if frameDuration > 0 {
                        let frameBitrate = Double(sampleSize * 8) / frameDuration
                        times.append(currentTime)
                        bitrates.append(frameBitrate)
                    }
                }
                previousTime = currentTime
            }
            
            DispatchQueue.main.async {
                completion(times, bitrates)
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion([], [])
            }
        }
    }
}
