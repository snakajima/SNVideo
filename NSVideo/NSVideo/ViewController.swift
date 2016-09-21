//
//  ViewController.swift
//  NSVideo
//
//  Created by satoshi on 9/20/16.
//  Copyright © 2016 Satoshi Nakajima. All rights reserved.
//

import UIKit
import AVFoundation
import MetalKit

class ViewController: UIViewController {
    @IBOutlet var viewMain : UIView!
    @IBOutlet var viewSub : MTKView!
    var playerLayer : CALayer?

    static let device = MTLCreateSystemDefaultDevice()!
    static let queue = ViewController.device.newCommandQueue()
    static let psMask:MTLComputePipelineState? = {
        if let function = ViewController.device.newDefaultLibrary()?.newFunctionWithName("SNTrimMask") {
            return try! ViewController.device.newComputePipelineStateWithFunction(function)
        }
        return nil
    }()

    lazy var textureCache:CVMetalTextureCache = {
        var cache:Unmanaged<CVMetalTextureCache>?
        let status = CVMetalTextureCacheCreate(nil, nil, ViewController.device, nil, &cache)
        print("textureCache success=", status == kCVReturnSuccess)
        return cache!.takeUnretainedValue()
    }()
    let session = AVCaptureSession()
    var backCamera : AVCaptureDevice? = {
        for device in AVCaptureDevice.devices() as! [AVCaptureDevice] {
            if device.hasMediaType(AVMediaTypeVideo) {
                if device.position == AVCaptureDevicePosition.Back {
                    return device
                }
            }
        }
        return nil
    }()
    lazy var cameraInput:AVCaptureDeviceInput? = {
        return try? AVCaptureDeviceInput(device: self.backCamera)
    }()
    /*
    lazy var imageOutput:AVCaptureStillImageOutput? = {
        let output = AVCaptureStillImageOutput()
        output.outputSettings = [ AVVideoCodecKey : AVVideoCodecJPEG ]
        return output
    }()
    */
    lazy var videoOutput:AVCaptureVideoDataOutput? = {
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey:Int(kCVPixelFormatType_32BGRA)]
        return output
    }()
    lazy var videoConnection:AVCaptureConnection? = {
        for connection in self.videoOutput?.connections as! [AVCaptureConnection] {
            for port in connection.inputPorts {
                if port.mediaType == AVMediaTypeVideo {
                    return connection
                }
            }
        }
        return nil
    }()

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = viewMain.bounds
        viewSub.device = ViewController.device
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if session.canSetSessionPreset(AVCaptureSessionPreset1280x720) {
            session.sessionPreset = AVCaptureSessionPreset1280x720
        }
        viewSub.framebufferOnly = false

        if let input = cameraInput {
            if session.canAddInput(input) {
                session.addInput(input)
                if let output = videoOutput {
                    if session.canAddOutput(output) {
                        session.addOutput(output)
                        output.setSampleBufferDelegate(self, queue: dispatch_get_main_queue())
                        if let _ = videoConnection {
                            session.startRunning()
                            playerLayer = AVCaptureVideoPreviewLayer(session: session)
                            playerLayer?.frame = viewMain.bounds
                            viewMain.layer.insertSublayer(playerLayer!, atIndex:0)
                        }
                    }
                }
            }
        }
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

// http://flexmonkey.blogspot.co.uk/2015/07/generating-filtering-metal-textures.html

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("no pixelBuffer")
            return
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var metalTextureU:Unmanaged<CVMetalTextureRef>?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .BGRA8Unorm, width, height, 0, &metalTextureU)
        defer { metalTextureU?.release() }
        guard let metalTexture = metalTextureU?.takeUnretainedValue() where status == kCVReturnSuccess else {
            print("failed 1", status)
            return
        }
        let texture = CVMetalTextureGetTexture(metalTexture)
        guard let drawable = viewSub.currentDrawable else {
            print("failed 2", status)
            return
        }
        guard let psMask = ViewController.psMask else {
            print("failed 3")
            return
        }
        let cmdBuffer:MTLCommandBuffer = {
            let cmdBuffer = ViewController.queue.commandBuffer()
            let encoder = cmdBuffer.computeCommandEncoder(); defer { encoder.endEncoding() }
            encoder.setTexture(texture, atIndex: 0)
            encoder.setTexture(drawable.texture, atIndex: 1)
            encoder.setComputePipelineState(psMask)
            let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
            let threadgroupsPerGrid = MTLSize(width: width / 8, height: height / 8, depth: 1)
            encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            return cmdBuffer
        }()
        cmdBuffer.addCompletedHandler { (_) in
            drawable.present()
        }
        cmdBuffer.commit()
    }
}

