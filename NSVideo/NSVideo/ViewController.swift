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
    lazy var imageOutput:AVCaptureStillImageOutput? = {
        let output = AVCaptureStillImageOutput()
        output.outputSettings = [ AVVideoCodecKey : AVVideoCodecJPEG ]
        return output
    }()
    lazy var videoConnection:AVCaptureConnection? = {
        for connection in self.imageOutput!.connections as! [AVCaptureConnection] {
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
                if let output = imageOutput {
                    if session.canAddOutput(output) {
                        session.addOutput(output)
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

