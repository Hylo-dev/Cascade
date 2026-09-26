//
//  CGPath+SoftwareNotchDroplet.swift
//  CascadeKit
//

import CoreGraphics

extension CGPath {

    /// softwareNotchDroplet keeps the small edge bump visible while a rounded
    /// body descends beneath it. The body keeps its full resolved content height;
    /// the controller reserves the extra bump and neck depth in its canvas.
    static func softwareNotchDroplet(
        resting          : CGPath,
        bodyGeometry     : NotchGeometry,
        centerX          : CGFloat,
        topY             : CGFloat,
        expansionProgress: CGFloat,
        metrics          : SoftwareNotchMetrics
    ) -> CGPath {
        let progress = expansionProgress.isFinite
            ? min(1, max(0, expansionProgress))
            : 0
        guard progress > 0 else { return resting }

        let drop = (metrics.restingSize.height + metrics.bodyOffset) * progress
        let bodyHeight = max(0, bodyGeometry.height)
        guard bodyGeometry.width > 0, bodyHeight > 0 else { return resting }

        let body = CGRect(
            x     : centerX - bodyGeometry.leftExtent,
            y     : topY - drop - bodyHeight,
            width : bodyGeometry.width,
            height: bodyHeight
        )
        let radius = max(0, min(
            bodyGeometry.bottomCornerRadius,
            body.width / 2,
            body.height / 2
        ))
        let bodyPath = CGPath(
            roundedRect : body,
            cornerWidth : radius,
            cornerHeight: radius,
            transform   : nil
        )

        let restingBottom = topY - metrics.restingSize.height
        guard body.maxY < restingBottom else {
            return resting.union(bodyPath)
        }

        let gap = restingBottom - body.maxY
        let neckHalfWidth = min(body.width / 2, max(0, metrics.neckWidth / 2))
        let flare = min(
            gap,
            max(0, min(metrics.restingSize.width / 2, body.width / 2) - neckHalfWidth)
        )
        let joinHalfWidth = neckHalfWidth + flare
        let middleY = body.maxY + gap / 2
        let bumpRadius = min(metrics.restingSize.height / 2, metrics.restingSize.width / 2)
        let bumpRight = centerX + metrics.restingSize.width / 2 - bumpRadius
        let bumpLeft = centerX - metrics.restingSize.width / 2 + bumpRadius
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bumpLeft - bumpRadius, y: topY))
        path.addLine(to: CGPoint(x: bumpRight + bumpRadius, y: topY))
        ContinuousNotchCorner.append(
            to       : path,
            transform: CGAffineTransform(
                a : 0,
                b : -bumpRadius,
                c : bumpRadius,
                d : 0,
                tx: bumpRight,
                ty: topY
            )
        )
        path.addLine(to: CGPoint(x: bumpRight, y: restingBottom + bumpRadius))
        ContinuousNotchCorner.append(
            to       : path,
            transform: CGAffineTransform(
                a : -bumpRadius,
                b : 0,
                c : 0,
                d : bumpRadius,
                tx: bumpRight,
                ty: restingBottom
            )
        )
        path.addLine(to: CGPoint(x: centerX + joinHalfWidth, y: restingBottom))
        path.addCurve(
            to      : CGPoint(x: centerX + neckHalfWidth, y: middleY),
            control1: CGPoint(x: centerX + neckHalfWidth, y: restingBottom),
            control2: CGPoint(x: centerX + neckHalfWidth, y: middleY + gap * 0.15)
        )
        path.addCurve(
            to      : CGPoint(x: centerX + joinHalfWidth, y: body.maxY),
            control1: CGPoint(x: centerX + neckHalfWidth, y: middleY - gap * 0.15),
            control2: CGPoint(x: centerX + neckHalfWidth, y: body.maxY)
        )
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.maxY))
        path.addArc(
            center    : CGPoint(x: body.maxX - radius, y: body.maxY - radius),
            radius    : radius,
            startAngle: .pi / 2,
            endAngle  : 0,
            clockwise : true
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.minY + radius))
        path.addArc(
            center    : CGPoint(x: body.maxX - radius, y: body.minY + radius),
            radius    : radius,
            startAngle: 0,
            endAngle  : -.pi / 2,
            clockwise : true
        )
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addArc(
            center    : CGPoint(x: body.minX + radius, y: body.minY + radius),
            radius    : radius,
            startAngle: -.pi / 2,
            endAngle  : -.pi,
            clockwise : true
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.maxY - radius))
        path.addArc(
            center    : CGPoint(x: body.minX + radius, y: body.maxY - radius),
            radius    : radius,
            startAngle: .pi,
            endAngle  : .pi / 2,
            clockwise : true
        )
        path.addLine(to: CGPoint(x: centerX - joinHalfWidth, y: body.maxY))
        path.addCurve(
            to      : CGPoint(x: centerX - neckHalfWidth, y: middleY),
            control1: CGPoint(x: centerX - neckHalfWidth, y: body.maxY),
            control2: CGPoint(x: centerX - neckHalfWidth, y: middleY - gap * 0.15)
        )
        path.addCurve(
            to      : CGPoint(x: centerX - joinHalfWidth, y: restingBottom),
            control1: CGPoint(x: centerX - neckHalfWidth, y: middleY + gap * 0.15),
            control2: CGPoint(x: centerX - neckHalfWidth, y: restingBottom)
        )
        path.addLine(to: CGPoint(x: bumpLeft + bumpRadius, y: restingBottom))
        ContinuousNotchCorner.append(
            to       : path,
            transform: CGAffineTransform(
                a : 0,
                b : bumpRadius,
                c : bumpRadius,
                d : 0,
                tx: bumpLeft,
                ty: restingBottom
            )
        )
        path.addLine(to: CGPoint(x: bumpLeft, y: topY - bumpRadius))
        ContinuousNotchCorner.append(
            to       : path,
            transform: CGAffineTransform(
                a : -bumpRadius,
                b : 0,
                c : 0,
                d : -bumpRadius,
                tx: bumpLeft,
                ty: topY
            )
        )
        path.closeSubpath()
        return path
    }
}
