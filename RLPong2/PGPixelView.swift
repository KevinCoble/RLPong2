//
//  PGPixelView.swift
//  RLPong2
//
//  Created by Kevin Coble on 12/13/16.
//  Copyright © 2016 Kevin Coble. All rights reserved.
//

import Cocoa

class PGPixelView: NSView {
    var parameters : GameParameters?
    var stepData : [Double]?
    let zeroColor = NSColor.white
    let oneColor = NSColor.darkGray
    
    func setParameters(parameters: GameParameters)
    {
        self.parameters = parameters
    }
    
    func setData(data: [Double])
    {
        self.stepData = data
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        //  Ignore if we don't have data
        if let parameters = parameters {
            if let data = stepData {
                //  Verify the data matches the parameters
                if (data.count != parameters.pixelsWide * parameters.pixelsHigh) { return }
                
                //  Get the size of each 'pixel'
                var pixelWidth = bounds.width / CGFloat(parameters.pixelsWide)
                var pixelHeight = bounds.height / CGFloat(parameters.pixelsHigh)
                
                //  Make them square, and find the offset for each
                var xOffset : CGFloat = 0.0
                var yOffset : CGFloat = 0.0
                if (pixelWidth > pixelHeight) {
                    pixelWidth = pixelHeight
                    xOffset = (bounds.width - (pixelWidth * CGFloat(parameters.pixelsWide))) * 0.5
                }
                else {
                    pixelHeight = pixelWidth
                    yOffset = (bounds.height - (pixelHeight * CGFloat(parameters.pixelsHigh))) * 0.5
                }
                
                //  Draw the 'off' pixels as the whole used area
                var rect = NSMakeRect(xOffset, yOffset, pixelWidth * CGFloat(parameters.pixelsWide), pixelHeight * CGFloat(parameters.pixelsHigh))
                zeroColor.set()
                NSRectFill(rect)
                
                //  Draw each 'on' pixel
                oneColor.set()
                rect = NSMakeRect(xOffset, yOffset, pixelWidth, pixelHeight)
                var offset = 0
                for row in 0..<parameters.pixelsHigh {       //  Each row
                    for column in 0..<parameters.pixelsWide {    //  each column
                        if (data[offset] != 0.0) {
                            rect.origin.x = xOffset + (CGFloat(column) * pixelWidth)
                            rect.origin.y = yOffset + (CGFloat(row) * pixelHeight)
                            NSRectFill(rect)
                        }
                        offset += 1
                    }
                }
            }
        }
    }
    
}
