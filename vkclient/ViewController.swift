//
//  ViewController.swift
//  vkclient
//
//  Created by Thomas Brophy on 16/5/17.
//  Copyright © 2017 DT. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation
import CoreFoundation
import CoreBluetooth

class ViewController: UIViewController, AVCaptureAudioDataOutputSampleBufferDelegate, StreamDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

    let session = AVCaptureSession()
    
    var outputStream: OutputStream?
    var inputStream: InputStream?
    
    var buffer = [UInt8](repeating: 0, count: 1024)

    var manager:CBCentralManager!
    var peripheral:CBPeripheral!

    var receive_characteristic:CBCharacteristic!
    var send_characteristic:CBCharacteristic!

    struct Server {
        static let Address = "<host ip>"
        static let Port    = 80
    }

    struct Device {
        static let SimbleeServiceUUID    = "FE84"
        static let ReceiveCharacteristic = "2D30C082-F39F-4CE6-923F-3484EA480596"
        static let SendCharacteristic    = "2D30C083-F39F-4CE6-923F-3484EA480596"
        static let SignalCharacteristic  = "2D30C084-F39F-4CE6-923F-3484EA480596"
    }

    //
    // outlets

    @IBOutlet weak var outputLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initialiseRecording()
        intialiseSocket()
        initialiseBLE()
    }

    //
    //- Audio recording
    
    func initialiseRecording() {
        
        session.sessionPreset = AVCaptureSessionPresetLow
        session.automaticallyConfiguresApplicationAudioSession = false

        let recordingSession = AVAudioSession.sharedInstance()

        recordingSession.requestRecordPermission { granted in

            if !granted {
                print("Permission not granted")
            } else  {
                print("Permission granted")
            }

         }

        do {
            try recordingSession.setCategory(AVAudioSessionCategoryRecord)
            // try recordingSession.setPreferredInputNumberOfChannels(1) // For some reason, this is crashing the app
            try recordingSession.setPreferredSampleRate(16000)
            try recordingSession.setActive(true)
        } catch {
            print("Error info: \(error)")
            return
        }
        
        let mic = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
        var mic_input: AVCaptureDeviceInput!
        
        let audio_output = AVCaptureAudioDataOutput()
        audio_output.setSampleBufferDelegate(self, queue: DispatchQueue.main )
        
        do {
            mic_input = try AVCaptureDeviceInput(device: mic)
        } catch {
            print("Error info: \(error)")
            return
        }
        
        session.addInput(mic_input)
        session.addOutput(audio_output)
        session.startRunning()
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        
//        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
//        let streamDesctiption = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription!)
//
//        let dec = streamDesctiption?.pointee
        
        let block = CMSampleBufferGetDataBuffer(sampleBuffer)
        var length = 0
        var data: UnsafeMutablePointer<Int8>? = nil

        let status = CMBlockBufferGetDataPointer(block!, 0, nil, &length, &data)

        if status == kCMBlockBufferNoErr && length > 0 {
            self.sendData(data: data!, length: length)
        }
    }

    //
    //- Socket streaming
    
    func intialiseSocket() {
        
        Stream.getStreamsToHost(withName: Server.Address, port: Server.Port, inputStream: &self.inputStream, outputStream: &self.outputStream)
        
        if let outputStream = self.outputStream, let inputStream = self.inputStream {
            
            inputStream.delegate = self
            outputStream.delegate = self
            
            inputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
            outputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)

            inputStream.open()
            outputStream.open()
        }
    }
 
    func stream(_ stream: Stream, handle eventCode: Stream.Event) {

        switch eventCode {
            
        case Stream.Event.hasBytesAvailable:
            receiveData(stream: stream)
            break
        default:
            break
        }
    }
    
    func receiveData(stream: Stream) {

        if stream === self.inputStream {
         
            if let inputStream = self.inputStream {
                var bytes_read = inputStream.read(&self.buffer, maxLength: self.buffer.count)

                let data = Data(bytes: self.buffer)

                data.withUnsafeBytes() { (u8Ptr: UnsafePointer<Float>) in
                    var read_ptr = u8Ptr
                    while bytes_read > 4 {

                        var f:Float = 0.0

                        memcpy(&f, read_ptr, 4)
                        read_ptr = read_ptr + 1

                        bytes_read = bytes_read - 4

                        if f > 0.5 {
                            sendEnableBytes()
                        } else {
                            sendDisableBytes()
                        }

                        self.outputLabel.text = String(f)
                    }
                }

            }
            
        }
    }
    
    func sendData(data: UnsafePointer<Int8>, length: Int) {

        data.withMemoryRebound(to: UInt8.self, capacity: length) { ptr in
            if let outputStream = self.outputStream {
                outputStream.write(ptr, maxLength: length)
            }
        }
    }

    //
    //- BLE

    func initialiseBLE() {

        manager = CBCentralManager(delegate: self, queue: nil)

    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        if central.state == CBManagerState.poweredOn {
            central.scanForPeripherals(withServices: nil)
        } else {
            print("Bluetooth not available.")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {

        print(peripheral.name)

        if peripheral.name == "Simblee" {

            self.manager.stopScan()

            self.peripheral = peripheral
            self.peripheral.delegate = self

            manager.connect(peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {

        peripheral.discoverServices(nil)
    }


    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {

        for service in peripheral.services! {

            let thisService = service as CBService

            if service.uuid == CBUUID(string: Device.SimbleeServiceUUID) {
                peripheral.discoverCharacteristics(nil, for: thisService)
            }

        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        for characteristic in service.characteristics! {

            let thisCharacteristic = characteristic as CBCharacteristic

            print(thisCharacteristic)

            if thisCharacteristic.uuid == CBUUID(string: Device.ReceiveCharacteristic) {

                receive_characteristic = thisCharacteristic
                peripheral.setNotifyValue(true, for: thisCharacteristic)
            }

            if thisCharacteristic.uuid == CBUUID(string: Device.SendCharacteristic) {

                send_characteristic = thisCharacteristic
            }

        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {

        if let dataBytes = characteristic.value {

            if characteristic.uuid == CBUUID(string: Device.ReceiveCharacteristic) {

                dataBytes.withUnsafeBytes { (bytes: UnsafePointer<Float>)->Void in
                    print(bytes.pointee)
                }
            }
        }
    }

    //
    //- Application specific characteristics

    func sendEnableBytes() {

        let enableBytes = Data(repeating: 1, count: 1)

        if let peripheral = self.peripheral, let send = send_characteristic {
            peripheral.writeValue(enableBytes, for: send, type: CBCharacteristicWriteType.withoutResponse)
        }
    }

    func sendDisableBytes() {

        let enableBytes = Data(repeating: 0, count: 1)

        if let peripheral = self.peripheral, let send = send_characteristic {
            peripheral.writeValue(enableBytes, for: send, type: CBCharacteristicWriteType.withoutResponse)
        }
    }
}

