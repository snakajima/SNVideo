//
//  ViewController.swift
//  NSVideo
//
//  Created by satoshi on 9/20/16.
//  Copyright © 2016 Satoshi Nakajima. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    @IBOutlet var viewMain : UIView!
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
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if session.canSetSessionPreset(AVCaptureSessionPreset1280x720) {
            session.sessionPreset = AVCaptureSessionPreset1280x720
        }

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
        var metalTexture:Unmanaged<CVMetalTextureRef>?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .BGRA8Unorm, width, height, 0, &metalTexture)
        if let metalTexture = metalTexture?.takeUnretainedValue() where status == kCVReturnSuccess {
            let texture = CVMetalTextureGetTexture(metalTexture)
            print("buffer")
        } else {
            print("failed", status)
        }
        metalTexture?.release()
    }
}

