//
//  APNGImageTests.swift.swift
//  APNGKit
//
//  Created by 李旭 on 2025/6/28.
//

import Foundation
import XCTest
@testable import APNGKit

class APNGImageTests: XCTestCase {
    func testAPNGCreationFromName() throws {
        let apng = createBallImage()
        _ = try APNGImageRenderer(decoder: apng.decoder)
        XCTAssertEqual(apng.scale, 1)
        XCTAssertEqual(apng.size, .init(width: 100, height: 100))
        
        if case .loadedPartial(let duration) = apng.duration {
            XCTAssertEqual(duration, apng.decoder.frame(at: 0)!.frameControl.duration)
        } else {
            XCTFail("Wrong duration.")
        }
    }
    
}
