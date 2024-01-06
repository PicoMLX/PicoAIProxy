//
//  File.swift
//  
//
//  Created by Ronald Mannak on 1/2/24.
//

import Foundation
import Hummingbird

struct AttestationResponse: HBResponseCodable {
    let id: UUID
    let challengeID: String
    let response: String
}
