#! /usr/bin/env python3

// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors

/*
Generates a tags file, using the POSIX ctags syntax, for navigation while
editing.  The tags file provides "jump to definition" information about DocC
links to headings and syntactic categories in the formal grammar.

To use these tags, configure your editor to include a-z, A-Z, pound (#),
hyphen (-), and colon (:), as valid characters in a tag.
*/

import Foundation

let chapterRegex = try Regex("^# (.*)")
let headingRegex = try Regex("^#+ ")
let grammarRegex = try Regex(#"^> \*[a-z-]*\* → "#)

var chapter: String? = nil
var tags: [String] = []

let basePath = "TSPL.docc/"
let fileManager = FileManager()
let fileEnumerator = fileManager.enumerator(atPath: basePath)!
for case let path as String in fileEnumerator {
    guard path.hasSuffix(".md") else { continue }
    guard path != "ReferenceManual/SummaryOfTheGrammar.md" else { continue }
    print(path)

    let fileContents = try String(contentsOfFile: basePath + path, encoding: .utf8)
    chapter = nil
    for line in fileContents.split(separator: "\n") {
        if let match = line.firstMatch(of: chapterRegex) {
            let chapter = match.0
            let tag = "doc:" + chapter
            let search =  "/^" + line.replacingOccurances(of: "/", with: "\\/") + "/"
            tags.append(tag + "\t" + path + "\t" + search + "\n")
        } else if let match = line.firstMatch(of: headingRegex) {

        } else if let match = line.firstMatch(of: grammarRegex) {

        }
    }
}

print(tags)
