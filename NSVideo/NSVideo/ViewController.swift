//
//  ViewController.swift
//  NSVideo
//
//  Created by satoshi on 9/20/16.
//  Copyright © 2016 Satoshi Nakajima. All rights reserved.
//

import UIKit
import AVFoundation
import Metal
import MetalKit

class ViewController: UIViewController {
    @IBOutlet var viewMain : UIView!
    @IBOutlet var viewSub : MTKView!
    var playerLayer : CALayer?
    let outputQueue = DispatchQueue(label: "VideoOutputQueue", attributes: [])

    static let device = MTLCreateSystemDefaultDevice()!
    static let queue = ViewController.device.makeCommandQueue()
    static let psMask:MTLComputePipelineState? = {
        if let function = ViewController.device.newDefaultLibrary()?.makeFunction(name: "SNTrimMask") {
            let ps = try! ViewController.device.makeComputePipelineState(function: function)
            print("max =", ps.maxTotalThreadsPerThreadgroup)
            print("width = ", ps.threadExecutionWidth)
            return ps
        }
        return nil
    }()

    lazy var textureCache:CVMetalTextureCache = {
        var cache:CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(nil, nil, ViewController.device, nil, &cache)
        print("textureCache success=", status == kCVReturnSuccess)
        return cache!
    }()
    let session = AVCaptureSession()
    var backCamera : AVCaptureDevice? = {
        for device in AVCaptureDevice.devices() as! [AVCaptureDevice] {
            if device.hasMediaType(AVMediaTypeVideo) {
                if device.position == AVCaptureDevicePosition.back {
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
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable:Int(kCVPixelFormatType_32BGRA)]
        output.alwaysDiscardsLateVideoFrames = true
        return output
    }()
    lazy var videoConnection:AVCaptureConnection? = {
        for connection in self.videoOutput?.connections as! [AVCaptureConnection] {
            for port in connection.inputPorts {
                if (port as AnyObject).mediaType == AVMediaTypeVideo {
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

        if let input = cameraInput , session.canAddInput(input) {
            session.beginConfiguration()
            session.addInput(input)
            if let output = videoOutput , session.canAddOutput(output) {
                session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: outputQueue)
            }
            session.commitConfiguration()

            session.startRunning()
            playerLayer = AVCaptureVideoPreviewLayer(session: session)
            playerLayer?.frame = viewMain.bounds
            viewMain.layer.insertSublayer(playerLayer!, at:0)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

// http://flexmonkey.blogspot.co.uk/2015/07/generating-filtering-metal-textures.html

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("no pixelBuffer")
            return
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var metalTexture:CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &metalTexture)
        let texture = CVMetalTextureGetTexture(metalTexture!)
        guard let drawable = viewSub.currentDrawable else {
            print("failed 2", status)
            return
        }
        guard let psMask = ViewController.psMask else {
            print("failed 3")
            return
        }
        let cmdBuffer:MTLCommandBuffer = {
            let cmdBuffer = ViewController.queue.makeCommandBuffer()
            let encoder = cmdBuffer.makeComputeCommandEncoder(); defer { encoder.endEncoding() }
            encoder.setTexture(texture, at: 0)
            encoder.setTexture(drawable.texture, at: 1)
            encoder.setComputePipelineState(psMask)
            let threadsCount = MTLSize(width: 16, height: min(16, psMask.maxTotalThreadsPerThreadgroup/16), depth: 1)
            let groupsCount = MTLSize(width: width / threadsCount.width, height: height/threadsCount.height, depth: 1)
            encoder.dispatchThreadgroups(groupsCount, threadsPerThreadgroup: threadsCount)
            return cmdBuffer
        }()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        drawable.present()
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didDrop sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        print("didDropSampleBuffer")
    }
}

