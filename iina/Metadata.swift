//
//  Metadata.swift
//  iina
//
//  Created by Soma Yamamoto on 2019/01/08.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation

class Metadata {
  class Date {
    
  }
  
  var type: MetadataType?
  
  var title: String?
  var artist: String?
  var album: String?
  var albumArtist: String?
  var genre: String?
  var date: Date?
  var track: String?
  var disc: String?
  var description: String?
  var language: String?
  var copyright: String?
  var publisher: String?
  var encoder: String?
  var image: NSImage?
  
  init(type: MetadataType) {
    self.type = type
  }
}

