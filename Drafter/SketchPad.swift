//
//  SketchPad.swift
//  Drafter
//
//  Created by Alex Veledzimovich on 8/8/19.
//  Copyright © 2019 Alex Veledzimovich. All rights reserved.

import Cocoa

class SketchPad: NSView {
    var parent: NSViewController?
    weak var locationX: NSTextField!
    weak var locationY: NSTextField!

    weak var toolUI: NSStackView!
    weak var frameUI: FrameButtons!
    weak var textUI: TextTool!

    weak var curveWidth: ActionSlider!
    weak var curveShadowRadius: ActionSlider!
    weak var curveShadowOffsetX: ActionSlider!
    weak var curveShadowOffsetY: ActionSlider!

    var alphaSliders: [ActionSlider]!
    var colorPanels: [ColorPanel]!

    var trackArea: NSTrackingArea!
    var rulers: Ruler!

    var sketchDir: URL?
    var sketchName: String?
    var sketchExt: String?

    var sketchPath = NSBezierPath()
    let sketchLayer = CAShapeLayer()
    var editedPath = NSBezierPath()
    let editLayer = CAShapeLayer()
    var curvedPath = NSBezierPath()
    let curveLayer = CAShapeLayer()
    var controlPath = NSBezierPath()
    let controlLayer = CAShapeLayer()

    var movePoint: Dot?
    var controlPoint1: Dot?
    var controlPoint2: Dot?
    var controlPoints: [ControlPoint] = []

    var dotSize: CGFloat = setEditor.dotSize
    var dotRadius: CGFloat = setEditor.dotRadius
    var dotMag: CGFloat = setEditor.dotRadius / 2
    var lineWidth: CGFloat = setEditor.lineWidth
    var lineDashPattern = setEditor.lineDashPattern

    var copiedCurve: Curve?
    var selectedCurve: Curve?
    var curves: [Curve] = []
    var groups: [Curve] = []

    var startPos = CGPoint(x: 0, y: 0)
    var finPos = CGPoint(x: 0, y: 0)

    var editDone: Bool = false
    var closedCurve: Bool = false
    var filledCurve: Bool = true
    var roundedCurve: CGPoint?

    var zoomed: CGFloat = 1.0
    var zoomOrigin = CGPoint(x: setEditor.screenWidth/2,
                             y: setEditor.screenHeight/2)
    
    var tool: Tool = tools[0]

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        Tool.parent = self

        let options: NSTrackingArea.Options = [
            .mouseMoved, .activeInActiveApp, .inVisibleRect]
        self.trackArea = NSTrackingArea(rect: self.bounds,
                                  options: options, owner: self)
        self.addTrackingArea(self.trackArea!)

        self.zoomSketch(value: Double(self.zoomed * 100))

        self.rulers = Ruler(parent: self)

        self.setupLayers()

        // filters
        self.layerUsesCoreImageFilters = true
    }

    override func viewWillDraw() {
        self.updateWithPath(layer: self.editLayer, path: self.editedPath)
        self.updateWithPath(layer: self.curveLayer, path: self.curvedPath)
        self.updateWithPath(layer: self.controlLayer, path: self.controlPath)
        self.updateWithPath(layer: self.sketchLayer, path: self.sketchPath)
        rulers.updateWithPath()
    }

    func setupLayers() {
        self.wantsLayer = true
        let layers = [
            self.editLayer: setEditor.fillColor.cgColor,
            self.curveLayer: setEditor.controlColor.cgColor,
            self.controlLayer: setEditor.fillColor.cgColor,
            self.sketchLayer: setEditor.guiColor.cgColor]

        for (layer, color) in layers {
            layer.strokeColor = color
            layer.fillColor = nil
            layer.lineCap = .butt
            layer.lineJoin = .round
            layer.lineWidth = self.lineWidth
            layer.actions = setEditor.disabledActions
            if layer != self.sketchLayer {
                layer.makeShape(path: NSBezierPath(),
                            strokeColor: setEditor.strokeColor,
                            dashPattern: self.lineDashPattern,
                            lineCap: .butt,
                            lineJoin: .round,
                            actions: setEditor.disabledActions)
            }
        }

        let sketchBorder = NSRect(x: 0, y: 0,
                            width: setEditor.screenWidth,
                            height: setEditor.screenHeight)
        self.sketchPath = NSBezierPath(rect: sketchBorder)
    }

//    MARK: Mouse func
    override func rightMouseDown(with event: NSEvent) {
        let pos = convert(event.locationInWindow, from: nil)
        defer {
            if let curve = self.selectedCurve {
                curve.frameAngle = 0
                curve.controlDot = nil
                self.createControls(curve: curve)
            }
            self.frameUI.updateFrame(view: self, pos: event.locationInWindow)
        }

        if let curve = self.selectedCurve, curve.edit {
            return
        } else if let curve = self.selectedCurve,
            self.groups.count > 1 {
            self.clearControls(curve: curve)
            return
        } else {
            self.setTool(tag: 0)
            self.selectCurve(pos: pos)
        }

    }

    override func scrollWheel(with event: NSEvent) {
        self.clearRulers()

        self.zoomOrigin = CGPoint(
            x: self.zoomOrigin.x + event.deltaX,
            y: self.zoomOrigin.y - event.deltaY)
        self.zoomSketch(value: Double(self.zoomed * 100))
    }

    override func mouseEntered(with event: NSEvent) {
        let pos = convert(event.locationInWindow, from: nil)
        self.showCurvedPath(pos: pos)

        if let curve = self.selectedCurve {
            curve.showControl(pos: pos)
        }
        self.needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        self.closedCurve = false
        if let curve = self.selectedCurve {
            curve.hideControl()
        }
        self.needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let shift: Bool = event.modifierFlags.contains(.shift) ? true : false
        let ctrl: Bool = event.modifierFlags.contains(.control) ? true : false
        self.startPos = convert(event.locationInWindow, from: nil)

        if let curve = self.selectedCurve, curve.edit {
            self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
            for point in curve.points {
                if point.collidedPoint(pos: self.startPos) != nil {
                    self.clearRulers()
                    return
                }
            }

            if curve.path.rectPath(
                curve.path, pad: setEditor.dotRadius).contains(self.startPos),
                let segment = curve.path.findPath(pos: self.startPos) {

                // center
                var mpPoints: [CGPoint] = [
                    curve.boundsPoints(curves: curve.groups)[1]]
                for cp in curve.points {
                    mpPoints.append(cp.mp.position)
                }

                let snap = self.snapToRulers(points: [self.startPos],
                                             curves: [],
                                             curvePoints: mpPoints,
                                             ctrl: ctrl)
                self.startPos.x -= snap.x
                self.startPos.y -= snap.y

                self.curvedPath = curve.path.insertCurve(
                    to: self.startPos, at: segment.index, with: segment.points)
                let size50 = self.dotSize/2
                self.curvedPath.appendOval(in: CGRect(
                    x: self.startPos.x-size50,
                    y: self.startPos.y-size50,
                    width: self.dotSize, height: self.dotSize))

            } else {
                self.clearRulers()
            }
        } else {
            self.tool.move(shift: shift, ctrl: ctrl)
        }
        self.needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let cmd: Bool = event.modifierFlags.contains(.command) ? true : false
        let opt: Bool = event.modifierFlags.contains(.option) ? true : false
        let ctrl: Bool = event.modifierFlags.contains(.control) ? true : false
        let shift: Bool = event.modifierFlags.contains(.shift) ? true : false

        self.finPos = convert(event.locationInWindow, from: nil)

        if let curve = self.selectedCurve, curve.edit {
            self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
            self.clearControls(curve: curve, updatePoints: ())

            // center
            var mpPoints: [CGPoint] = [
                curve.boundsPoints(curves: curve.groups)[1]]
            var mPos = self.startPos
            if let dot = curve.controlDot {
                for cp in curve.points {
                    if cp.mp != dot || cmd {
                        mpPoints.append(cp.mp.position)
                    }
                    if dot.tag != 2 &&
                        (cp.mp == dot || cp.cp1 == dot || cp.cp2 == dot) {
                        mPos = cp.mp.position
                    }
                }
            }

            if shift {
                self.finPos = self.shiftAngle(
                    topLeft: mPos, bottomRight: finPos)
            }

            let snap = self.snapToRulers(points: [self.finPos],
                                         curves: [],
                                         curvePoints: mpPoints,
                                         ctrl: ctrl)
            self.finPos.x -= snap.x
            self.finPos.y -= snap.y

            if shift {
                self.rulers.appendCustomRule(move: mPos, line: self.finPos)
            }
            curve.editPoint(pos: self.finPos, cmd: cmd, opt: opt)
        } else if let curve = self.selectedCurve, let dot = curve.controlDot {
            self.dragFrameControlDots(curve: curve, finPos: self.finPos,
                                      deltaX: event.deltaX,
                                      deltaY: event.deltaY,
                                      dot: dot, shift: shift, ctrl: ctrl)
        } else {
            self.tool.drag(shift: shift, ctrl: ctrl)
            self.tool.create(ctrl: ctrl, shift: shift, opt: opt,
                             event: event)
        }
        self.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        print("down")
        self.startPos = convert(event.locationInWindow, from: nil)
        let shift: Bool = event.modifierFlags.contains(.shift) ? true : false
        let opt: Bool = event.modifierFlags.contains(.option) ? true : false

        let nc = NotificationCenter.default
        nc.post(name: Notification.Name("abortTextFields"), object: nil)

        if let curve = self.selectedCurve, curve.edit {
            self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
            curve.selectPoint(pos: self.startPos)

            var mpPoints: [CGPoint] = [
                curve.boundsPoints(curves: curve.groups)[1]]
            if let dot = curve.controlDot {
                for cp in curve.points where cp.mp != dot {
                    mpPoints.append(cp.mp.position)
                }
            }
            self.snapToRulers(points: [self.startPos], curves: [],
                              curvePoints: mpPoints, ctrl: true)

        } else if let curve = self.selectedCurve,
            let dot = curve.controlFrame?.collideControlDot(pos: self.startPos),
            !curve.lock {
            curve.controlDot = dot
            if dot.tag == 9 {
                curve.gradient = !curve.gradient
            }
        } else if let mp = self.movePoint,
            mp.collide(pos: self.startPos, radius: mp.bounds.width),
            self.controlPoints.count>0 {
            self.filledCurve = false
            self.finalSegment(fin: {mp, cp1, cp2 in
                self.editedPath.move(to: mp.position)
                self.controlPoints.append(
                    ControlPoint(mp: mp, cp1: cp1, cp2: cp2))
            })

        } else if self.movePoint != nil, self.closedCurve {
            self.finalSegment(fin: {mp, cp1, cp2 in
                self.addSegment(mp: mp, cp1: cp1, cp2: cp2)
            })

        } else {
            self.tool.down(shift: shift)
        }

        if opt { self.cloneCurve() }
        self.frameUI.hide()
        self.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        print("up")
        self.tool.up(editDone: self.editDone)

        self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
        for cur in self.groups {
            self.curvedPath.append(cur.path)
        }
        self.clearRulers()

        self.roundedCurve = nil
        self.closedCurve = false
        self.filledCurve = true
        self.editDone = false

        self.updateSliders()
        self.needsDisplay = true
    }

//    MARK: Control func
    func initCurve(path: NSBezierPath,
                   fill: Bool, rounded: CGPoint?,
                   angle: CGFloat, lineWidth: CGFloat,
                   cap: Int, join: Int, dash: [NSNumber],
                   alpha: [CGFloat], shadow: [CGFloat],
                   gradientDirection: [CGPoint],
                   gradientLocation: [NSNumber],
                   colors: [NSColor], blur: Double,
                   points: [ControlPoint]) -> Curve {

        let curve = Curve.init(parent: self, path: path,
                               fill: fill, rounded: rounded)
        curve.angle = angle
        curve.lineWidth =  lineWidth
        curve.setLineCap(value: cap)
        curve.setLineJoin(value: join)
        curve.setDash(dash: dash)
        curve.alpha = alpha
        curve.shadow = shadow
        curve.gradientDirection = gradientDirection
        curve.gradientLocation = gradientLocation
        curve.colors = colors
        curve.blur = blur
        curve.setPoints(points: points)
        return curve
    }

    func newCurve() {
        guard let path = self.editedPath.copy() as? NSBezierPath,
            path.elementCount > 0 else { return }

        let shadowValues: [CGFloat] = [
            CGFloat(self.curveShadowRadius.doubleValue),
            CGFloat(self.curveShadowOffsetX.doubleValue),
            CGFloat(self.curveShadowOffsetY.doubleValue)]

        let lineWidth = !self.filledCurve && self.curveWidth.doubleValue == 0
            ? 1 : self.curveWidth.doubleValue

        var alpha: [CGFloat] = self.alphaSliders.map {CGFloat($0.doubleValue)}
        alpha[1] = self.filledCurve ? alpha[1] : 0
        alpha[0] = (alpha[0] == 0 && alpha[1] == 0) ? 1 : alpha[0]

        let colors: [NSColor] = self.colorPanels.map {$0.fillColor}

        let curve = self.initCurve(path: path,
            fill: self.filledCurve, rounded: self.roundedCurve,
            angle: 0,
            lineWidth: CGFloat(lineWidth),
            cap: setCurve.lineCap, join: setCurve.lineJoin,
            dash: setCurve.lineDashPattern,
            alpha: alpha, shadow: shadowValues,
            gradientDirection: setCurve.gradientDirection,
            gradientLocation: setCurve.gradientLocation,
            colors: colors,
            blur: setCurve.minBlur,
            points: self.controlPoints)

        let name = filledCurve
            ? self.tool.name
            : "line"
        curve.setName(name: name, curves: self.curves)
        self.layer?.addSublayer(curve.canvas)
        self.addCurve(curve: curve)
    }

    func addCurve(curve: Curve) {
        self.curves.append(curve)
        self.setTool(tag: 0)
        self.groups = []
        self.selectedCurve = curve
    }

    func deselectCurve(curve: Curve) {
        self.clearControls(curve: curve)
        self.frameUI.hide()
        self.clearRulers()
        self.selectedCurve = nil
    }

    func selectCurve(pos: CGPoint, shift: Bool = false) {
        if let curve = self.selectedCurve {
            self.deselectCurve(curve: curve)
        }

        var locked: Curve?
        for curve in self.curves {
            if curve.groupRect(curves: curve.groups).contains(pos) &&
                !curve.canvas.isHidden {
                if !curve.lock {
                    self.selectedCurve = curve
                } else {
                    locked = curve
                }
            }
        }

        if let lockedCurve = locked, self.selectedCurve == nil {
            self.selectedCurve = lockedCurve
        }

        if let curve = self.selectedCurve, curve.groups.count==1, shift {
            if self.groups.contains(curve) {
                if let index = self.groups.firstIndex(of: curve) {
                    self.groups.remove(at: index)
                }
            } else {
                self.groups.append(curve)
            }
        } else if let curve = self.selectedCurve,
            self.groups.contains(curve), self.groups.count>1 {
            if curve.groupRect(curves: self.groups).contains(pos) &&
                !curve.canvas.isHidden {
                self.selectedCurve = curve
            }
        } else {
            self.groups.removeAll()
        }

        for cur in self.groups {
            self.curvedPath.append(cur.path)
        }

        if let curve = self.selectedCurve {
            let groups = self.groups.count>1 ? self.groups : curve.groups
            self.snapToRulers(points: curve.boundsPoints(curves: groups),
                              curves: self.curves,
                              exclude: groups, ctrl: true)
        }
    }

    func dragCurve(deltaX: CGFloat, deltaY: CGFloat, ctrl: Bool = false) {
        if let curve = self.selectedCurve, !curve.lock {
            let groups = self.groups.count>1
                ? self.groups
                : curve.groups
            let snap = self.snapToRulers(
                points: curve.boundsPoints(curves: groups),
                curves: self.curves, exclude: groups, ctrl: ctrl)

            let deltaX = (deltaX - snap.x) / self.zoomed
            let deltaY = (deltaY + snap.y) / self.zoomed
            let move = AffineTransform.init(
                translationByX: deltaX,
                byY: -deltaY)

            for cur in groups {
                cur.path.transform(using: move)
                self.clearControls(curve: cur, updatePoints: (
                   cur.updatePoints(deltaX: deltaX, deltaY: deltaY)
                ))
            }
            self.updateSliders()
        }
    }

    func createControls(curve: Curve) {
        if !curve.edit {
            curve.createControlFrame()
        }
        self.needsDisplay = true
    }

    func clearControls(curve: Curve,
                       updatePoints: @autoclosure () -> Void = ()) {
        if !curve.edit {
            curve.clearControlFrame()
        }
        updatePoints()
        self.needsDisplay = true
    }

//    MARK: Sliders
    func updateSliders() {
        let nc = NotificationCenter.default
        nc.post(name: Notification.Name("updateSliders"), object: nil)
    }

    func updateStack() {
        let nc = NotificationCenter.default
        nc.post(name: Notification.Name("updateStack"), object: nil)
    }

//    MARK: Rulers
    @discardableResult func snapToRulers(
        points: [CGPoint], curves: [Curve],
        curvePoints: [CGPoint] = [],
        exclude: [Curve] = [],
        ctrl: Bool = false) -> CGPoint {

        self.locationX.isHidden = true
        self.locationY.isHidden = true

        let snap = rulers.createRulers(points: points,
            curves: curves, curvePoints: curvePoints,
            exclude: exclude, ctrl: ctrl)
        let pad = self.dotRadius
        let width = self.locationX.frame.width
        let height = self.locationX.frame.height
        for (key, pnt) in snap.pnt {
            if let pos = pnt.pos {
                let x = (pos.x-self.bounds.minX) * self.zoomed
                let y = (pos.y-self.bounds.minY) * self.zoomed

                guard pnt.dist >= setEditor.rulersDelta || ctrl else {
                    break
                }
                if key == "x" {
                    self.locationX.doubleValue = Double(pnt.dist)
                    self.locationX.frame = CGRect(
                        x: x - width - pad, y: y - height - pad,
                        width: width, height: height)
                    self.locationX.isHidden = false
                } else {
                    self.locationY.doubleValue = Double(pnt.dist)
                    self.locationY.frame = CGRect(
                        x: x + pad, y: y + pad,
                        width: width,
                        height: height)
                    self.locationY.isHidden = false
                }
            }
        }
        return snap.delta
    }

    func clearRulers() {
        self.rulers.clearRulers()
        self.locationX.isHidden = true
        self.locationY.isHidden = true
    }

//    MARK: Zoom func
    func zoomSketch(value: Double) {
        let delta = value / 100

        self.bounds = self.frame
        self.zoomed = CGFloat(delta)
        let originX = self.zoomOrigin.x
        let originY = self.zoomOrigin.y
        self.translateOrigin(to: CGPoint(x: self.frame.midX,
                                         y: self.frame.midY))
        self.scaleUnitSquare(to: NSSize(width: delta,
                                        height: delta))

        self.translateOrigin(to: CGPoint(x: -originX,
                                         y: -originY))

        self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
        self.dotSize = setEditor.dotSize/self.zoomed
        self.dotRadius = self.dotSize/2
        self.dotMag = self.dotRadius/2
        self.lineWidth = setEditor.lineWidth/self.zoomed

        let dash = Double(
            truncating: setEditor.lineDashPattern[0])/Double(self.zoomed)
        let gap = Double(
            truncating: setEditor.lineDashPattern[1])/Double(self.zoomed)

        self.lineDashPattern[0] = NSNumber(value: dash)
        self.lineDashPattern[1] = NSNumber(value: gap)

        if let curve = self.selectedCurve {
            self.clearControls(curve: curve)
            self.createControls(curve: curve)
            if curve.edit {
                curve.clearPoints()
                curve.createPoints()
            }
        }
        self.updateControlSize()
        self.needsDisplay = true
    }

//    MARK: Path func
    func updateWithPath(layer: CAShapeLayer, path: NSBezierPath) {
        layer.removeFromSuperlayer()
        layer.lineWidth = self.lineWidth
        if path.elementCount>0 {
            layer.path = path.cgPath
            layer.bounds = path.bounds
            layer.position = CGPoint(x: path.bounds.midX,
                                    y: path.bounds.midY)
            if let dashLayer = layer.sublayers?.first as? CAShapeLayer {
                dashLayer.path = layer.path
                dashLayer.lineWidth = self.lineWidth
                dashLayer.lineDashPattern = lineDashPattern
            }
            self.layer?.addSublayer(layer)
        }
    }

    func clearPathLayer(layer: CAShapeLayer, path: NSBezierPath) {
        layer.removeFromSuperlayer()
        path.removeAllPoints()
    }

    func addSegment(mp: Dot, cp1: Dot, cp2: Dot) {
        let cPnt = self.curvedPath.findPoint(1)
        self.editedPath.curve(to: cPnt[2],
                              controlPoint1: cPnt[0],
                              controlPoint2: cPnt[1])

        self.controlPoints.append(ControlPoint(mp: mp, cp1: cp1, cp2: cp2))
    }

    func finalSegment(fin: (_ mp: Dot, _ cp1: Dot, _ cp2: Dot) -> Void ) {
        if let mp = self.movePoint,
            let cp1 = self.controlPoint1,
            let cp2 = self.controlPoint2 {

            fin(mp, cp1, cp2)

            if self.filledCurve {
                self.editedPath.close()
            }

            self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
            self.clearPathLayer(layer: self.controlLayer,
                                path: self.controlPath)
            self.editDone = true
        }
    }

    func updateControlSize() {
        if let mp = self.movePoint {
            mp.updateSize(width: self.dotSize, height: self.dotSize,
                          lineWidth: self.lineWidth)
        }
        if let cp1 = self.controlPoint1,
            let cp2 = self.controlPoint2 {
            cp1.updateSize(width: self.dotSize, height: self.dotSize,
                           lineWidth: self.lineWidth)
            cp2.updateSize(width: self.dotSize, height: self.dotSize,
                           lineWidth: self.lineWidth)
        }

        if self.tool is Vector {
            for point in self.controlPoints {
                point.clearDots()
                for dot in point.dots {
                    dot.updateSize(width: self.dotSize, height: self.dotSize,
                                   lineWidth: self.lineWidth)
                    self.layer?.addSublayer(dot)
                }
            }
        }
    }

    func dragCurvedPath(topLeft: CGPoint, bottomRight: CGPoint,
                        opt: Bool = false) {
        self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
        self.clearPathLayer(layer: self.controlLayer, path: self.controlPath)

        if let mp = self.movePoint, let cp1 = self.controlPoint1,
            let cp2 = self.controlPoint2 {
            let finPos = CGPoint(
                x: mp.position.x - (bottomRight.x - topLeft.x),
                y: mp.position.y - (bottomRight.y - topLeft.y))

            cp1.position = CGPoint(x: bottomRight.x, y: bottomRight.y)
            if !opt {
                cp2.position = CGPoint(x: finPos.x, y: finPos.y)
            }
            if self.editedPath.elementCount>1 {
                let index = self.editedPath.elementCount-1
                let count = self.controlPoints.count
                let last = self.controlPoints[count-1].cp1
                var cPnt = [last.position, cp2.position, topLeft]
                self.editedPath.setAssociatedPoints(&cPnt, at: index)
            }
            self.controlPath.move(to: cp1.position)
            self.controlPath.line(to: mp.position)
            self.controlPath.line(to: cp2.position)
        }
    }

    func showCurvedPath(pos: CGPoint) {
        if editedPath.elementCount>0 {
            for point in controlPoints {
                if let mp = self.movePoint, let cp1 = self.controlPoint1 {
                    if point.collideDot(pos: pos,
                                        dot: point.mp) {
                        self.moveCurvedPath(move: mp.position,
                                            to: point.mp.position,
                                            cp1: cp1.position,
                                            cp2: point.cp2.position)
                        self.closedCurve = true
                        return
                    }
                }
            }
        }
    }

    func moveCurvedPath(move: CGPoint, to: CGPoint,
                        cp1: CGPoint, cp2: CGPoint) {
        if self.closedCurve {
            return
        }
        self.clearPathLayer(layer: self.curveLayer,
                            path: self.curvedPath)
        self.curvedPath.move(to: move)
        self.curvedPath.curve(to: to,
                              controlPoint1: cp1,
                              controlPoint2: cp2)
    }

    func clearCurvedPath() {
        self.clearPathLayer(layer: self.editLayer, path: self.editedPath)
        self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
        self.clearPathLayer(layer: self.controlLayer, path: self.controlPath)

        for point in self.controlPoints {
            point.mp.removeFromSuperlayer()
            point.cp1.removeFromSuperlayer()
            point.cp2.removeFromSuperlayer()
        }
        self.controlPoints = []

        if let mp = self.movePoint,
            let cp1 = self.controlPoint1,
            let cp2 = self.controlPoint2 {
            self.movePoint = nil
            mp.removeFromSuperlayer()
            self.controlPoint1 = nil
            cp1.removeFromSuperlayer()
            self.controlPoint2 = nil
            cp2.removeFromSuperlayer()
        }

    }

//    MARK: Buttons func
    func sendCurve(tag: Int) {
        if let curve = self.selectedCurve,
            let index = self.curves.firstIndex(of: curve), !curve.lock {
            var goal = index
            switch tag {
            case 0:
                goal -= goal>0 ? 1 : 0
            case 1:
                goal += goal<curves.count-1 ? 1 : 0
            default:
                break
            }

            if goal != index {
                var delta = 0
                let goalCurve = self.curves[goal]
                if goal < index {
                    for (ind, cur) in self.curves.enumerated() where ind<goal {
                        delta += cur.groups.count-1
                    }

                    for i in stride(from: goalCurve.groups.count-1,
                                    through: 0, by: -1) {
                        for j in 0..<curve.groups.count {
                            self.layer?.sublayers?.swapAt(goal + delta + i + j,
                                                          index + delta + i + j)
                        }
                    }
                } else {
                    for (ind, cur) in self.curves.enumerated() where ind<index {
                        delta += cur.groups.count-1
                    }
                    for j in 0..<goalCurve.groups.count {
                        for i in stride(from: curve.groups.count-1,
                                        through: 0, by: -1) {
                            self.layer?.sublayers?.swapAt(goal + delta + i + j,
                                                          index + delta + i + j)
                        }
                    }
                }
                self.curves.swapAt(goal, index)
                self.updateStack()
            }
        }
    }

    func flipCurve(tag: Int) {
        if let curve = self.selectedCurve, !curve.lock {
            let flip: AffineTransform
            var originX: CGFloat = 0
            var originY: CGFloat = 0
            var scaleX: CGFloat = 1
            var scaleY: CGFloat = 1
            let bounds = self.groups.count>1
                ? curve.groupRect(curves: self.groups)
                : curve.groupRect(curves: curve.groups)

            switch tag {
            case 2:
                scaleX = -1
                originX = bounds.midX
            case 3:
                scaleY = -1
                originY = bounds.midY
            default:
                break
            }
            flip = AffineTransform(scaleByX: scaleX, byY: scaleY)

            let groups = self.groups.count>1 ? self.groups : curve.groups
            for cur in groups {
                cur.applyTransform(oX: originX, oY: originY,
                               transform: {cur.path.transform(using: flip)})

                cur.updatePoints(ox: originX, oy: originY,
                                   scalex: scaleX, scaley: scaleY)
            }
            self.updateStack()
        }
    }

    func editFinished(curve: Curve) {
        curve.edit = false
        curve.clearPoints()
        curve.createControlFrame()
        self.clearRulers()
        self.clearPathLayer(layer: self.curveLayer,
                            path: self.curvedPath)
        self.frameUI.isOn(on: -1)
        self.frameUI.hide()
        self.updateStack()
    }

    func editStarted(curve: Curve) {
        curve.edit = true
        curve.clearControlFrame()
        curve.createPoints()
        self.frameUI.isEnabled(tag: 4)
        self.setTool(tag: 0)
        self.frameUI.hide()
        self.updateStack()
    }

    func editCurve(sender: NSButton) {
        if let curve = self.selectedCurve {
            if sender.state == .off {
                self.editFinished(curve: curve)
            } else {
                self.editStarted(curve: curve)
            }
        }
    }

    func makeGroup() {
        var sortedGroup: [Curve] = []
        for curve in self.curves {
            if self.groups.contains(curve) {
                sortedGroup.append(curve)
            }
        }
        let base = sortedGroup[0]

        for cur in sortedGroup {
            if let curInd = self.curves.firstIndex(of: cur) {
                if cur != base {
                    base.groups.append(cur)
                }
                self.curves.remove(at: curInd)
                cur.canvas.removeFromSuperlayer()
                self.deselectCurve(curve: cur)
            }
        }
        base.setName(name: "group", curves: self.curves)
        self.addCurve(curve: base)

        for cur in sortedGroup {
            self.layer?.addSublayer(cur.canvas)
        }

        self.clearControls(curve: base)
        self.createControls(curve: base)
        self.selectedCurve = base

        self.groups = []

        self.frameUI.hide()
    }

    func groupCurve(sender: Any) {
        if let button  = sender as? NSButton, button.state == .on {
            if self.groups.count > 1 {
                self.makeGroup()
            } else {
                button.state = .off
            }

        } else if let menu = sender as? NSMenuItem, menu.tag == 0 {
            if self.groups.count > 1 {
                self.makeGroup()
            }
        } else {
            if let curve = self.selectedCurve,
                curve.groups.count > 1 {
                self.deselectCurve(curve: curve)

                for (ind, cur) in curve.groups.enumerated() {
                    if ind == 0 {
                        if let curInd = self.curves.firstIndex(of: curve) {
                            self.curves.remove(at: curInd)
                        }
                    }
                    cur.canvas.removeFromSuperlayer()
                    self.layer?.addSublayer(cur.canvas)
                    self.addCurve(curve: cur)
                }
                curve.groups = [curve]

                let name = String(
                    curve.oldName.split(separator: " ")[0])
                curve.setName(name: name, curves: self.curves)
                self.selectedCurve = curve
                self.createControls(curve: curve)
                self.frameUI.hide()
            }
        }
        self.updateStack()
    }

    func setLock(curve: Curve, sender: NSButton) {
        if sender.state == .off {
            sender.image = setEditor.unlockImg
            curve.lock = false
            self.frameUI.hide()
        } else {
            sender.image = setEditor.lockImg
            curve.lock = true
            self.frameUI.hide()
        }
    }

    func lockCurve(sender: NSButton) {
        if sender.alternateTitle.isEmpty {
            let curve = self.curves[sender.tag]
            for cur in curve.groups {
                self.setLock(curve: cur, sender: sender)
            }
        } else {
            if let curve = self.selectedCurve {
                for cur in curve.groups {
                    self.setLock(curve: cur, sender: sender)
                }
            }
        }
        self.updateStack()
    }

//    MARK: SketchUI func
    func selectSketch(tag: Int) {
        if let oldCurve = self.selectedCurve, oldCurve.edit {
            return
        }
        let curve = self.curves[tag]

        if let oldCurve = self.selectedCurve {
            if oldCurve == curve {
                return
            }
            self.deselectCurve(curve: oldCurve)
        }

        if !curve.canvas.isHidden {
            self.selectedCurve = curve
            self.createControls(curve: curve)
            self.updateSliders()
        }
    }

    func visibleSketch(sender: NSButton) {
        let curve = self.curves[sender.tag]
        if curve.edit {
            sender.state = .on
        } else {
            for cur in curve.groups {
                cur.canvas.isHidden = !cur.canvas.isHidden
                if cur.canvas.isHidden {
                    if let oldCurve = self.selectedCurve,
                        cur == oldCurve {
                        self.deselectCurve(curve: cur)
                    }
                }
            }
        }
    }

//    MARK: Tools func
    func setTool(tag: Int) {
        var tag = tag
        if let curve = self.selectedCurve {
            if curve.edit {
                tag = 0
            } else {
                self.deselectCurve(curve: curve)
            }
        }

        self.textUI.hide()
        self.clearCurvedPath()

        self.tool = tools[tag]
        self.toolUI?.isOn(on: tag)
    }

    func shiftAngle(topLeft: CGPoint, bottomRight: CGPoint) -> CGPoint {
        var shift = bottomRight
        var angle = shift.atan2Rad(other: topLeft)
        let sign: CGFloat = angle > 0 ? 1 : -1
        angle = abs(angle)
        let pi8 = CGFloat.pi/8
        let pi4 = CGFloat.pi/4
        let pi2 = CGFloat.pi/2
        let pi = CGFloat.pi

        let hyp = hypot(shift.x - topLeft.x,
                        shift.y - topLeft.y)
        switch angle {
        case _ where angle < pi8:
           shift.x = topLeft.x + cos(0) * hyp
           shift.y = topLeft.y + sin(0) * hyp
        case _ where angle > pi8 && angle < pi4 + pi8:
           shift.x = topLeft.x + cos(sign*pi4) * hyp
           shift.y = topLeft.y + sin(sign*pi4) * hyp
        case _ where angle > pi4 + pi8 && angle < pi2 + pi8:
           shift.x = topLeft.x + cos(sign*pi2) * hyp
           shift.y = topLeft.y + sin(sign*pi2) * hyp
        case _ where angle > pi2 + pi8  && angle < pi2 + pi4:
           shift.x = topLeft.x + cos(sign*(pi2+pi4)) * hyp
           shift.y = topLeft.y + sin(sign*(pi2+pi4)) * hyp
        case _ where angle > pi2 + pi4  && angle < pi:
           shift.x = topLeft.x + cos(sign*pi) * hyp
           shift.y = topLeft.y + sin(sign*pi) * hyp
        default:
           break
        }
        return shift
    }

//    MARK: Key func
    func removeCurve(curve: Curve) {
        if let index = self.curves.firstIndex(of: curve) {
            curve.clearPoints()
            curve.delete()

            self.deselectCurve(curve: curve)
            self.curves.remove(at: index)
            self.frameUI.isOn(on: -1)
        }
    }

    func deleteCurve() {
        self.clearCurvedPath()
        self.clearRulers()

        if tool is Vector && self.movePoint != nil {
            return
        }
        if let curve = self.selectedCurve, !curve.lock {
            if curve.edit && curve.points.count > 2 {
                curve.removePoint()
            } else {
                if self.groups.count>1 {
                    for cur in self.groups {
                        self.removeCurve(curve: cur)
                    }
                    self.groups = []
                } else {
                    self.removeCurve(curve: curve)
                }
            }
            self.updateSliders()
        }
    }

    func copyCurve(from: Curve?) {
        if let curve = from, !curve.edit {
            var groups: [Curve] = []
            for cur in curve.groups {
                if let path = cur.path.copy() as? NSBezierPath {
                    var points: [ControlPoint] = []
                    for point in cur.points {
                        if let copyPoint = point.copy() {
                             points.append(copyPoint)
                        }
                    }
                    let clone = self.initCurve(
                        path: path, fill: cur.fill, rounded: cur.rounded,
                        angle: cur.angle,
                        lineWidth: cur.lineWidth,
                        cap: cur.cap, join: cur.join,
                        dash: cur.dash,
                        alpha: cur.alpha,
                        shadow: cur.shadow,
                        gradientDirection: cur.gradientDirection,
                        gradientLocation: cur.gradientLocation,
                        colors: cur.colors,
                        blur: cur.blur,
                        points: points)
                    let name = String(cur.name.split(separator: " ")[0])
                    clone.setName(name: name, curves: self.curves)
                    groups.append(clone)
                }
            }
            groups[0].oldName = curve.oldName
            groups[0].setGroups(curves: Array(groups.dropFirst()))
            self.copiedCurve = groups[0]
        }
    }

    func pasteCurve(to: CGPoint) {
        let edit = self.selectedCurve?.edit ?? false

        if let clone = self.copiedCurve, !edit {
            if let curve = self.selectedCurve {
                self.clearControls(curve: curve)
            }
            for cur in clone.groups {
                self.layer?.addSublayer(cur.canvas)
            }
            self.addCurve(curve: clone)

            self.moveCurve(
                tag: 0, value: Double(to.x))
            self.moveCurve(
                tag: 1, value: Double(to.y))

            self.createControls(curve: clone)
            self.copyCurve(from: self.copiedCurve)
            self.needsDisplay = true
        }
    }

    func cloneCurve() {
        self.copyCurve(from: self.selectedCurve)
        if let curve = self.selectedCurve {
            self.pasteCurve(to: CGPoint(x: curve.path.bounds.midX,
                                        y: curve.path.bounds.midY))
        }
    }

//    MARK: TextTool func
    func glyphsCurve(value: String, sharedFont: NSFont?) {
        self.editedPath = NSBezierPath()
        if value.count > 0 {
            if let font = sharedFont {
                let hei = self.textUI.bounds.height / 2
                let x = (self.textUI.frame.minX) / self.zoomed
                let y = (self.textUI.frame.minY + hei) / self.zoomed

                let pos = CGPoint(x: x + self.bounds.minX,
                                  y: y + self.bounds.minY )
                self.editedPath.move(to: pos)
                for char in value {
                    let glyph = font.glyph(withName: String(char))
                    self.editedPath.append(
                        withCGGlyph: CGGlyph(glyph), in: font)
                }
            }

            if let curve = self.selectedCurve {
                self.clearControls(curve: curve)
            }
            self.newCurve()
            if let curve = self.selectedCurve {
                self.createControls(curve: curve)
            }
            self.updateSliders()
        }
    }

//    MARK: Frame func
    func dragFrameControlDots(curve: Curve, finPos: CGPoint,
                              deltaX: CGFloat, deltaY: CGFloat, dot: Dot,
                              shift: Bool = false, ctrl: Bool = false ) {
        let groups = self.groups.count>1 ? self.groups : curve.groups
        let snap = self.snapToRulers(
            points: curve.boundsPoints(curves: groups),
            curves: self.curves, exclude: groups, ctrl: ctrl)
        let dX = deltaX / self.zoomed
        let dY = deltaY / self.zoomed

        let dXs = (deltaX - snap.x) / self.zoomed
        let dYs = (deltaY + snap.y) / self.zoomed

        let bounds = self.groups.count>1
            ? curve.groupRect(curves: self.groups, includeStroke: false)
            : curve.groupRect(curves: curve.groups, includeStroke: false)

        switch dot.tag! {
        case 0:
            let resize = Double(bounds.height + dYs)
            self.resizeCurve(tag: 1, value: resize, anchor: CGPoint(x: 0, y: 1),
                             ind: dot.tag!, shift: shift)
            fallthrough
        case 1:
            let resize = Double(bounds.width - dXs)
            self.resizeCurve(tag: 0, value: resize, anchor: CGPoint(x: 1, y: 0),
                             ind: dot.tag!, shift: shift)
        case 2:
            let resize = Double(bounds.width - dXs)
            self.resizeCurve(tag: 0, value: resize, anchor: CGPoint(x: 1, y: 0),
                             ind: dot.tag!, shift: shift)
            fallthrough
        case 3:
            let resize = Double(bounds.height - dYs)
            self.resizeCurve(tag: 1, value: resize, ind: dot.tag!, shift: shift)
        case 4:
            let resize = Double(bounds.height - dYs)
            self.resizeCurve(tag: 1, value: resize, ind: dot.tag!, shift: shift)
            fallthrough
        case 5:
            let resize = Double(bounds.width + dXs)
            self.resizeCurve(tag: 0, value: resize, ind: dot.tag!, shift: shift)
        case 6:
            let resize = Double(bounds.width + dXs)
            self.resizeCurve(tag: 0, value: resize, ind: dot.tag!, shift: shift)
            fallthrough
        case 7:
            let resize = Double(bounds.height + dYs)
            self.resizeCurve(tag: 1, value: resize,
                             anchor: CGPoint(x: 0, y: 1),
                             ind: dot.tag!, shift: shift)
        case 8:
            self.rotateByDelta(curve: curve, pos: finPos,
                               dX: dX, dY: dY)
        case 9:
            break
        case 10:
            self.gradientDirectionCurve(
                tag: 0, value: CGPoint(x: dX, y: dY))
        case 11:
            self.gradientDirectionCurve(
                tag: 1, value: CGPoint(x: dX, y: dY))
        case 12:
            self.gradientLocationCurve(tag: 0, value: dX)
        case 13:
            self.gradientLocationCurve(tag: 1, value: dX)
        case 14:
            self.gradientLocationCurve(tag: 2, value: dX)
        case 15:
            self.roundedCornerCurve(tag: 0, value: dX)
        case 16:
            self.roundedCornerCurve(tag: 1, value: dY)
        default:
            break
        }
    }

//    MARK: Action func
    func alignLeftRightCurve(value: Int) {
        if let curve = self.selectedCurve, !curve.lock {
            let bounds = self.groups.count>1
                ? curve.groupRect(curves: self.groups)
                : curve.groupRect(curves: curve.groups)
            let wid50 = bounds.width/2
            let alignLeftRight: [CGFloat] = [
                self.sketchPath.bounds.minX + wid50,
                self.sketchPath.bounds.midX,
                self.sketchPath.bounds.maxX - wid50
            ]
            self.moveCurve(tag: 0, value: Double(alignLeftRight[value]))
        }
    }

    func alignUpDownCurve(value: Int) {
        if let curve = self.selectedCurve, !curve.lock {
            let bounds = self.groups.count>1
                ? curve.groupRect(curves: self.groups)
                : curve.groupRect(curves: curve.groups)
            let hei50 = bounds.height/2
            let alignLeftRight: [CGFloat] = [
                self.sketchPath.bounds.maxY - hei50,
                self.sketchPath.bounds.midY,
                self.sketchPath.bounds.minY + hei50
            ]
            self.moveCurve(tag: 1, value: Double(alignLeftRight[value]))
        }
    }

    func moveCurve(tag: Int, value: Double) {
        var deltax: CGFloat = 0
        var deltay: CGFloat = 0

        if let curve = self.selectedCurve, !curve.lock {
            self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
            let bounds = self.groups.count>1
                ? curve.groupRect(curves: self.groups)
                : curve.groupRect(curves: curve.groups)
            if tag==0 {
                deltax = CGFloat(value) - bounds.midX
            } else {
                deltay = CGFloat(value) - bounds.midY
            }
            let move = AffineTransform(translationByX: deltax, byY: deltay)

            let groups = self.groups.count>1 ? self.groups : curve.groups
            for cur in groups {
                cur.path.transform(using: move)

                self.clearControls(curve: cur, updatePoints: (
                    cur.updatePoints(deltaX: deltax, deltaY: -deltay)
                ))
            }
            self.updateSliders()
        }
    }

    func resizeCurve(tag: Int, value: Double,
                     anchor: CGPoint = CGPoint(x: 0, y: 0),
                     ind: Int? = nil, shift: Bool = false) {
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1

        if let curve = selectedCurve, !curve.lock {
            self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)
            let bounds = self.groups.count>1
                ? curve.groupRect(curves: self.groups, includeStroke: false)
                : curve.groupRect(curves: curve.groups, includeStroke: false)

            if bounds.width == 0 || bounds.height == 0 {
                self.rotateByAngle(curve: curve, angle: 0.001)
                curve.angle = 0
                return
            }

            var anchorX = anchor.x
            var anchorY = anchor.y

            if tag == 0 {
                scaleX = (CGFloat(value) / bounds.width)
                if shift {
                    scaleY = scaleX
                    if ind == 0 {
                        anchorX = 1
                        anchorY = 1
                    } else if ind == 2 {
                        anchorX = 1
                        anchorY = 0
                    } else if ind == 6 { anchorY = 1 }
                }
            } else {
                scaleY = (CGFloat(value) / bounds.height)
                if shift {
                    scaleX = scaleY
                    if ind == 0 {
                        anchorX = 1
                        anchorY = 1
                    } else if ind == 2 {
                        anchorX = 1
                        anchorY = 0
                    } else if ind == 4 { anchorX = 0 }
                }
            }
            let scale = AffineTransform(scaleByX: scaleX, byY: scaleY)
            let originX = bounds.minX + bounds.width * anchorX
            let originY = bounds.minY + bounds.height * anchorY

            let groups = self.groups.count>1 ? self.groups : curve.groups
            for cur in groups {
                cur.applyTransform(
                    oX: originX, oY: originY,
                    transform: {cur.path.transform(using: scale)})

                self.clearControls(curve: cur, updatePoints: (
                    cur.updatePoints(
                        ox: originX, oy: originY,
                        scalex: scaleX, scaley: scaleY)
                ))
            }
        } else {
            if tag == 0 {
                scaleX = CGFloat(value) / self.sketchPath.bounds.width
            } else {
                scaleY = CGFloat(value) / self.sketchPath.bounds.height
            }
            let originX = self.sketchPath.bounds.minX
            let originY = self.sketchPath.bounds.minY

            let origin = AffineTransform.init(
                translationByX: -originX, byY: -originY)
            self.sketchPath.transform(using: origin)
            let scale = AffineTransform(scaleByX: scaleX, byY: scaleY)

            self.sketchPath.transform(using: scale)

            let def = AffineTransform.init(
                translationByX: originX, byY: originY)
            self.sketchPath.transform(using: def)

            self.needsDisplay = true
        }
        self.updateSliders()
    }

    func rotateCurve(angle: Double) {
        if let curve = self.selectedCurve, !curve.lock {
            self.clearPathLayer(layer: self.curveLayer, path: self.curvedPath)

            self.rotateByAngle(curve: curve, angle: angle)
            self.updateSliders()
        }
    }

    func rotateByAngle(curve: Curve, angle: Double) {
        let bounds = self.groups.count>1
            ? curve.groupRect(curves: self.groups, includeStroke: false)
            : curve.groupRect(curves: curve.groups, includeStroke: false)
        let originX = bounds.midX
        let originY = bounds.midY
        let ang = CGFloat(angle)
        let groups = self.groups.count>1 ? self.groups : curve.groups
        for cur in groups {
            let rotate = AffineTransform(rotationByRadians: ang - cur.angle)

            cur.applyTransform(
                oX: originX, oY: originY,
                transform: {
                    cur.path.transform(using: rotate)})

            self.clearControls(curve: cur, updatePoints: (
                cur.updatePoints(angle: ang - cur.angle,
                                 ox: originX, oy: originY)
            ))

            cur.angle = ang
            cur.resetPoints()
            if !cur.edit {
                cur.clearPoints()
            }
        }
    }

    func rotateByDelta(curve: Curve, pos: CGPoint, dX: CGFloat, dY: CGFloat) {
        let rotate = atan2(pos.y+dY-curve.path.bounds.midY,
                           pos.x+dX-curve.path.bounds.midX)
        var dt = CGFloat(rotate)-curve.frameAngle
        dt = abs(dt)>0.2
            ? dt.truncatingRemainder(dividingBy: 0.2)
            : dt
        let minR = setCurve.minRotate
        let maxR = setCurve.maxRotate
        let ang = Double(curve.angle+dt)
        let lim = ang > maxR ? maxR : ang < minR ? minR : ang
        self.rotateCurve(angle: lim)
        curve.frameAngle = rotate
    }

    func lineWidthCurve(value: Double) {
        if let curve = self.selectedCurve, !curve.lock {
            curve.lineWidth = CGFloat(value)
            self.clearControls(curve: curve)
            self.updateSliders()
        }
    }

    func capCurve(value: Int) {
        if let curve = self.selectedCurve, !curve.lock {
            curve.setLineCap(value: value)
            self.needsDisplay = true
        }
    }

    func joinCurve(value: Int) {
        if let curve = self.selectedCurve, !curve.lock {
            curve.setLineJoin(value: value)
            self.needsDisplay = true
        }
    }

    func dashCurve(tag: Int, value: Double) {
        if let curve = self.selectedCurve, !curve.lock {
            var pattern = curve.dash
            pattern[tag] = NSNumber(value: value)
            curve.setDash(dash: pattern)
            self.clearControls(curve: curve)
            self.updateSliders()
        }
    }

    func colorCurve() {
        if let curve = self.selectedCurve, !curve.lock {
            curve.colors = self.colorPanels.map {$0.fillColor}
            self.clearControls(curve: curve)
            self.createControls(curve: curve)
            self.needsDisplay = true
        }
    }

    func alphaCurve(tag: Int, value: Double) {
        if let curve = self.selectedCurve, !curve.lock {
            curve.alpha[tag] = CGFloat(value)
            self.clearControls(curve: curve)
            self.updateSliders()
        }
    }

    func shadowCurve(tag: Int, value: Double) {
        if let curve = self.selectedCurve, !curve.lock {
            var shadow = curve.shadow
            shadow[tag] = CGFloat(value)
            curve.shadow = shadow
            self.clearControls(curve: curve)
            self.updateSliders()
        }
    }

    func gradientDirectionCurve(tag: Int, value: CGPoint) {
        if let curve = self.selectedCurve, !curve.lock {
            let oldpoint = curve.gradientDirection[tag]
            var x = oldpoint.x + value.x / curve.path.bounds.width
            var y = oldpoint.y - value.y / curve.path.bounds.height
            x = x < 0 ? 0 : x > 1 ? 1 : x
            y = y < 0 ? 0 : y > 1 ? 1 : y

            curve.gradientDirection[tag] = CGPoint(x: x, y: y)
            self.clearControls(curve: curve)
        }
    }

    func gradientLocationCurve(tag: Int, value: CGFloat) {
        if let curve = self.selectedCurve, !curve.lock {
            let value =  Double(value / curve.path.bounds.width)
            var location = curve.gradientLocation
            let num = Double(truncating: location[tag]) + value
            location[tag] = num < 0 ? 0 : num > 1 ? 1 : NSNumber(value: num)

            curve.gradientLocation = location
            self.clearControls(curve: curve)
        }
    }

    func blurCurve(value: Double) {
           if let curve = self.selectedCurve, !curve.lock {
               curve.blur = value
               self.clearControls(curve: curve)
               self.updateSliders()
           }
       }

    func roundedCornerCurve(tag: Int, value: CGFloat) {
        if let curve = self.selectedCurve, let rounded = curve.rounded,
            !curve.lock {
            let wid50 = (curve.path.bounds.width)/2
            let hei50 = (curve.path.bounds.height)/2
            let minX = curve.path.bounds.minX
            let minY = curve.path.bounds.minY
            let maxX = curve.path.bounds.maxX
            let maxY = curve.path.bounds.maxY

            if tag==0 {
                var x = rounded.x - value/wid50
                x  = x < 0 ? 0 : x > 1 ? 1 : x
                curve.rounded = CGPoint(x: x, y: rounded.y)
                let offsetXLeft = maxX - x * wid50
                curve.moveControlPoints(index: [4, 7], tags: [0, 1, 2],
                                 offsetX: offsetXLeft)
                let offsetXRight = minX + x * wid50
                curve.moveControlPoints(index: [0, 3], tags: [0, 1, 2],
                                 offsetX: offsetXRight)
            } else if tag==1 {
                var y = rounded.y + value/hei50
                y  = y < 0 ? 0 : y > 1 ? 1 : y
                curve.rounded = CGPoint(x: rounded.x, y: y)
                let offsetYDown = maxY - y * hei50
                curve.moveControlPoints(index: [1], tags: [0, 2],
                                 offsetY: offsetYDown)
                curve.moveControlPoints(index: [6], tags: [1, 2],
                                 offsetY: offsetYDown)
                let offsetYUp = minY + y * hei50
                curve.moveControlPoints(index: [2], tags: [1, 2],
                                 offsetY: offsetYUp)
                curve.moveControlPoints(index: [5], tags: [0, 2],
                                 offsetY: offsetYUp)
            }
            curve.updateLayer()
            self.clearControls(curve: curve)
        }
    }

//    MARK: Support
    func cgImageFrom(ciImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return cgImage
        }
        return nil
    }

    func imageData(
        fileType: NSBitmapImageRep.FileType = .png,
        properties: [NSBitmapImageRep.PropertyKey: Any] = [:]) -> Data? {
        if let imageRep = bitmapImageRepForCachingDisplay(
            in: self.sketchPath.bounds) {
            self.cacheDisplay(in: self.sketchPath.bounds, to: imageRep)
                return imageRep.representation(
                    using: fileType, properties: properties)!
            }
        return nil
    }
}
