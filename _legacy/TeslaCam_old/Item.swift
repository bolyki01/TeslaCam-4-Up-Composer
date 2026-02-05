//
//  Item.swift
//  TeslaCam
//
//  Created by Bolyki György on 05/02/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
