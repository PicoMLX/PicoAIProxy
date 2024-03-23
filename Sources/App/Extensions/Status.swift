//
//  File.swift
//  
//
//  Created by Ronald Mannak on 3/23/24.
//

import Foundation
import AppStoreServerLibrary

extension AppStoreServerLibrary.Status: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .active:
            return "active"
        case .expired:
            return "expired"
        case .billingRetry:
            return "billing retry"
        case .billingGracePeriod:
            return "billing grace period"
        case .revoked:
            return "revoked"
        }
    }
}
