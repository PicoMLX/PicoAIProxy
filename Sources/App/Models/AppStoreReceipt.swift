//
//  File.swift
//  
//
//  Created by Ronald Mannak on 1/9/24.
//

import Foundation
import Hummingbird
import HummingbirdAuth

class AppStoreReceipt: HBAuthenticatable { // HBResponseCodable
    let name: String
    let date: Date
    
    init() {
        name = "receipt"
        date = Date()
    }
}
