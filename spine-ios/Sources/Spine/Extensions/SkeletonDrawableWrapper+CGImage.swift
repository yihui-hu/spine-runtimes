/******************************************************************************
 * Spine Runtimes License Agreement
 * Last updated April 5, 2025. Replaces all prior versions.
 *
 * Copyright (c) 2013-2025, Esoteric Software LLC
 *
 * Integration of the Spine Runtimes into software or otherwise creating
 * derivative works of the Spine Runtimes is permitted under the terms and
 * conditions of Section 2 of the Spine Editor License Agreement:
 * http://esotericsoftware.com/spine-editor-license
 *
 * Otherwise, it is permitted to integrate the Spine Runtimes into software
 * or otherwise create derivative works of the Spine Runtimes (collectively,
 * "Products"), provided that each user of the Products must obtain their own
 * Spine Editor license and redistribution of the Products in any form must
 * include this license and copyright notice.
 *
 * THE SPINE RUNTIMES ARE PROVIDED BY ESOTERIC SOFTWARE LLC "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL ESOTERIC SOFTWARE LLC BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES,
 * BUSINESS INTERRUPTION, OR LOSS OF USE, DATA, OR PROFITS) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THE SPINE RUNTIMES, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *****************************************************************************/

import Foundation
import UIKit
import CoreGraphics

public extension SkeletonDrawableWrapper {
    
    /// Render the ``Skeleton`` to a `CGImage`
    ///
    /// Parameters:
    ///     - size: The size of the `CGImage` that should be rendered.
    ///     - backgroundColor: the background color of the image
    ///     - scaleFactor: The scale factor. Set this to `UIScreen.main.scale` if you want to show the image in a view
    func renderToImage(size: CGSize, backgroundColor: UIColor, scaleFactor: CGFloat = 1) throws -> CGImage? {
        let spineView = SpineUIView(
            controller: SpineController(disposeDrawableOnDeInit: false), // Doesn't own the drawable
            backgroundColor: backgroundColor
        )
        spineView.frame = CGRect(origin: .zero, size: size)
        spineView.isPaused = false
        spineView.enableSetNeedsDisplay = false
        spineView.framebufferOnly = false
        spineView.contentScaleFactor = scaleFactor
        
        try spineView.load(drawable: self)
        spineView.renderer?.waitUntilCompleted = true
        
        spineView.delegate?.draw(in: spineView)
        
        guard let texture = spineView.currentDrawable?.texture else {
            throw SpineError("Could not read texture.")
        }
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        let data = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: MemoryLayout<UInt8>.alignment)
        defer {
            data.deallocate()
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(data, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
        
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
        ).union(.byteOrder32Little)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
              let cgImage = context.makeImage() else {
                throw SpineError("Could not create image.")
        }
        return cgImage
    }
    
    // AN_FIX - Custom renderToImage for exporting animations
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // The original `renderToImage` function above is not well suited for exporting animations
    // because it creates a new `SpineUIView` for *every* single frame.
    //
    // Instead, we should just set up a singular render context and SpineView to use throughout
    // the exporting session.
    //
    // Please see `extractFramesFromAnimation` in `StickerExportManager` for more info on usage.
    //
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    /// This function is used to set up a singular `SpineUIView`
    /// and `SpineController` to be used throughout the
    /// sticker exporting session.
    ///
    func setupRenderContext(size: CGSize, bounds: RawBounds? = nil) throws -> (
        SpineUIView,
        SpineController
    ) {
        let controller = SpineController(disposeDrawableOnDeInit: false)
        
        var spineView: SpineUIView
        if let bounds = bounds {
            spineView = SpineUIView(
                controller: controller,
                boundsProvider: bounds,
                backgroundColor: .clear
            )
        } else {
            spineView = SpineUIView(
                controller: controller,
                backgroundColor: .clear
            )
        }
        
        spineView.frame = CGRect(origin: .zero, size: size)
        spineView.isPaused = false
        spineView.enableSetNeedsDisplay = false
        spineView.framebufferOnly = false
        
        try spineView.load(drawable: self)
        spineView.renderer?.waitUntilCompleted = true
        
        return (spineView, controller)
    }
    
    /// Renders a frame using a singular `SpineUIView`
    /// that should be set up via `setupRenderContext`.
    ///
    func renderFrameWithContext(
        spineView: SpineUIView
    ) throws -> CGImage? {
        spineView.delegate?.draw(in: spineView)
        
        guard let currentDrawable = spineView.currentDrawable else {
            throw SpineError("Could not get drawable.")
        }
        
        let texture = currentDrawable.texture
        
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        
        return try autoreleasepool {
            let data = UnsafeMutableRawPointer.allocate(
                byteCount: rowBytes * height,
                alignment: MemoryLayout<UInt8>.alignment
            )
            
            defer { data.deallocate() }
            
            let region = MTLRegionMake2D(0, 0, width, height)
            texture.getBytes(data, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
            
            let bitmapInfo = CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
            ).union(.byteOrder32Little)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            
            guard let context = CGContext(
                data: data, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: rowBytes,
                space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
            else {
                throw SpineError("Could not create context.")
            }
            
            guard let cgImage = context.makeImage() else {
                throw SpineError("Could not create image.")
            }
            
            return cgImage
        }
    }
    
    /// Remember to clean up the `SpineUIView`
    /// and `SpineController`.
    ///
    func cleanupRenderContext(
        spineView: SpineUIView,
        controller: SpineController
    ) {
        spineView.delegate = nil
        spineView.renderer = nil
        
        controller.drawable?.disposeForSharedDrawable()
        controller.drawable = nil
    }
    
    func renderToImageForStickerPreview() throws -> CGImage? {
        let spineView = SpineUIView(
            controller: SpineController(disposeDrawableOnDeInit: false), // Doesn't own the drawable
            boundsProvider: RawBounds(
                x: -150, y: -1300, width: 300, height: 1300
            ),
            backgroundColor: .clear
        )
        spineView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: 300, height: 300)
        )
        spineView.isPaused = false
        spineView.enableSetNeedsDisplay = false
        spineView.framebufferOnly = false
        spineView.contentScaleFactor = 1
        
        try spineView.load(drawable: self)
        spineView.renderer?.waitUntilCompleted = true
        
        spineView.delegate?.draw(in: spineView)
        
        guard let texture = spineView.currentDrawable?.texture else {
            throw SpineError("Could not read texture.")
        }
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        let data = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: MemoryLayout<UInt8>.alignment)
        defer {
            data.deallocate()
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(data, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
        
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
        ).union(.byteOrder32Little)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
              let cgImage = context.makeImage() else {
            throw SpineError("Could not create image.")
        }
        return cgImage
    }
    
    // AND_FIX_END - custom renderToImage
}
