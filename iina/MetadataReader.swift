//
//  ID3TagReader.swift
//  iina
//
//  Created by LEoREo2247 on 2019/01/08.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation

enum MetadataType {
  case id3v2
  case id3v3
  case id3v4
  case unknown
}

class MetadataReader {
  
  typealias Byte = UInt8
  
  private var data: Data?
  
  func readMetadata(from filePath: String) -> Metadata? {
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: filePath))
    } catch {
      
    }
    let length = data?.count
    if length == nil {
      return nil
    }
    
    let metadataType = determineType()
    if metadataType != .unknown {
      return readID3Tag(from: data!, type: metadataType)
    }
    return nil
  }
  
  private func determineType() -> MetadataType {
    // Look for the ID3 header
    if let id3Header = data?.range(of: Data(bytes: "ID3", count: 3), options: [], in: 0..<(data?.count)!) {
      // Check if its a valid ID3 header. If yes, then check the version
      let headerData = data?.subdata(in: id3Header)
      let headerString = String(data: headerData!, encoding: .utf8)
      
      if headerString == "ID3" {
        // Only supporting ID3v2.x for now.
        // .id3v2 == ID3v2.2, .id3v3 == ID3v2.3, .id3v4 == ID3v2.4
        let id3Version = [Byte](data!)[3]
        switch id3Version {
        case 2:
          return .id3v2
        case 3:
          return .id3v3
        case 4:
          return .id3v4
        default:
          return .unknown
        }
      }
    }
    
    return .unknown
  }
  
  private func readID3Tag(from data: Data, type: MetadataType) -> Metadata? {
    if data.count < 5 {
      
    }
    let tagHeaderSize = 10
    let tagSizeOffset = 6
    
    let tagHeader = [Byte](data.subdata(in: 0..<5))
    let tagHeaders: [MetadataType : [Byte]] = [
      .id3v2 : [Byte]("ID3".utf8) + [0x02, 0x00],
      .id3v3 : [Byte]("ID3".utf8) + [0x03, 0x00],
      .id3v4 : [Byte]("ID3".utf8) + [0x04, 0x00]
    ]
    let isTagPresent = tagHeader.elementsEqual(tagHeaders[type]!)
    if isTagPresent {
      let nsData = data as NSData
      
      let tagSize = (nsData.bytes + tagSizeOffset).assumingMemoryBound(to: UInt32.self).pointee.bigEndian
      let decodedTagSize = decodeSynchsafe(integer: tagSize)
      
      let metadata = Metadata(type: type)
      
      var framePos = tagHeaderSize
      while framePos < decodedTagSize {
        let frame = getID3Frame(from: nsData, framePos: framePos, type: type)
        parseID3Frame(from: frame, type: type, metadata: metadata)
        framePos += frame.count
      }
      return metadata
    }
    return nil
  }
  
  private func getID3Frame(from data: NSData, framePos: Int, type: MetadataType) -> Data {
    let frameSizeOffset: [MetadataType : Int] = [
      .id3v2 : 2,
      .id3v3 : 4,
      .id3v4 : 4
    ]
    let frameSizeMask: [MetadataType : UInt32] = [
      .id3v2 : 0x00FFFFFF,
      .id3v3 : 0xFFFFFFFF,
      .id3v4 : 0xFFFFFFFF
    ]
    let frameHeaderSizes: [MetadataType : Int] = [
      .id3v2 : 6,
      .id3v3 : 10,
      .id3v4 : 10,
    ]
    
    let frameSizePosition = framePos + frameSizeOffset[type]!
    var frameSize: UInt32 = 0
    data.getBytes(&frameSize, range: NSMakeRange(frameSizePosition, 4))
    frameSize = frameSize.bigEndian & frameSizeMask[type]!
    if type == .id3v4 {
      frameSize = decodeSynchsafe(integer: frameSize)
    }
    let finalFrameSize = Int(frameSize) + frameHeaderSizes[type]!
    
    let frame = data.subdata(with: NSMakeRange(framePos, finalFrameSize))
    return frame
  }
  
  private func parseID3Frame(from data: Data, type: MetadataType, metadata: Metadata) -> [Any]? {
    let frameHeaderSizes: [MetadataType : Int] = [
      .id3v2 : 6,
      .id3v3 : 10,
      .id3v4 : 10,
    ]
    let encodingSize = 1
    let encodingPositions: [MetadataType : Int] = [
      .id3v2 : 6,
      .id3v3 : 10,
      .id3v4 : 10
    ]
    let encodings: [MetadataType : [UInt8 : String.Encoding]] = [
      .id3v2 : [
        0x00 : .isoLatin1,
        0x01 : .utf16
      ],
      .id3v3 : [
        0x00 : .isoLatin1,
        0x01 : .utf16,
      ],
      .id3v4 : [
        0x00 : .isoLatin1,
        0x01 : .utf16,
        0x03 : .utf8
      ]
    ]
    
    let frameIdSizes: [MetadataType : Int] = [
      .id3v2 : 3,
      .id3v3 : 4,
      .id3v4 : 4
    ]
    
    let frameIdData = [UInt8](data.subdata(in: Range(0...frameIdSizes[type]! - 1)))
    let frameId = frameIdData.reduce("") { (convertedString, byte) -> String in
      convertedString + String(Character(UnicodeScalar(byte)))
    }
    
    if frameId.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).isEmpty {
      return nil
    }
    
    if frameId == "APIC" {
      let jpeg: Data = Data(bytes: [0xFF, 0xD8, 0xFF, 0xE0])
      let png: Data =  Data(bytes: [0x89, 0x50, 0x4E, 0x47])
      if let magicNumberRange = data.range(of: jpeg) {
        return [frameId, NSImage(data: data.subdata(in: magicNumberRange.lowerBound..<data.count))]
      }
      if let magicNumberRange = data.range(of: png) {
        return [frameId, NSImage(data: data.subdata(in: magicNumberRange.lowerBound..<data.count))]
      }
    } else {
      let frameContentRangeStart = frameHeaderSizes[type]! + encodingSize
      let frameContent = data.subdata(in: frameContentRangeStart..<data.count)
      let encoding = data[encodingPositions[type]!]
      let frameEncoding = encodings[type]![encoding]
      if let frameString = String(data: frameContent, encoding: frameEncoding ?? .isoLatin1) {
        let trimmedString = frameString.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        return [frameId, trimmedString]
      }
    }
    
    /*
    let encoding = stringEncodingDetector.detect(frame: data, version: version)
    if let frameContentAsString = String(data: frameContent, encoding: encoding) {
      return paddingRemover.removeFrom(string: frameContentAsString)
    } else {
      return nil
    }*/
    return nil
  }
  
  private func decodeSynchsafe(integer: UInt32) -> UInt32 {
    var decodedInteger: UInt32 = 0
    var mask: UInt32 = 0x7F000000
    
    while (mask != 0) {
      decodedInteger = decodedInteger >> 1
      decodedInteger = decodedInteger | integer & mask
      mask >>= 8
    }
    
    return decodedInteger
  }
  
}
