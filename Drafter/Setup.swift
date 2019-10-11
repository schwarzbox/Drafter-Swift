//
//  Setup.swift
//  Drafter
//
//  Created by Alex Veledzimovich on 9/10/19.
//  Copyright © 2019 Alex Veledzimovich. All rights reserved.
//

import Cocoa

struct Setup {
    let minZoom: Double = 20
    let maxZoom: Double = 400
    let reduceZoom: CGFloat = 40

    let screenWidth: Double = 800
    let screenHeight: Double = 600
    let maxScreenWidth: Double = 1600
    let maxScreenHeight: Double = 1200
    let minResize: Double = 0.1
    let minRotate = -Double.pi
    let maxRotate = Double.pi
    let alpha: [CGFloat] = [1.0, 1.0]
    let lineWidth: CGFloat = 1.0
    let lineCap = 0
    let lineJoin = 0
    let lineDashPattern: [NSNumber] = [0, 0, 0, 0]
    let maxLineWidth: CGFloat = 64
    let minBlur: Double = 0
    let maxBlur: Double = 64
    let minDash: Double = 0
    let maxDash: Double = 32
    let strokeColor = NSColor.white.sRGB()
    let fillColor = NSColor.systemBlue.sRGB()
    let guiColor = NSColor.unemphasizedSelectedContentBackgroundColor.sRGB()
    let controlColor = NSColor.green.sRGB()

    let shadow: [CGFloat] = [2.0, 0.5, 8.0, 8.0]
    let shadowColor =  NSColor.black
    let maxShadowRadius: Double = 32
    let maxShadowOffsetX: Double = 256
    let maxShadowOffsetY: Double = 256
    let gradientDirection = [CGPoint(x: 0.0, y: 0.0),
                             CGPoint(x: 1.0, y: 0.0)]
    let gradientColor = [NSColor.systemPink,
                         NSColor.systemBlue,
                         NSColor.systemPurple]
    let gradientLocation: [NSNumber] = [0.0, 0.50, 1.0]
    let gradientOpacity: [CGFloat] = [0.0, 0.0, 0.0]

    let dotSize: CGFloat =  8
    let dotRadius: CGFloat = 4
    let crossSize: CGFloat = 2

    let rulersDelta: CGFloat = 2
    let rulersDashPattern: [NSNumber] = [2, 2, 0, 0]

    let fontFamily: String = "Helvetica"
    let fontType: String = "Regular"
    let fontSize: CGFloat = 18

    let filename: String = "untitled"
    let fileTypes: [String] = ["png", "svg"]
}

var setup = Setup()
