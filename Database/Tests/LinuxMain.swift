import XCTest

import DatabaseTests

var tests = [XCTestCaseEntry]()
tests += DatabaseTests.allTests()
XCTMain(tests)
