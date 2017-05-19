# VKClient

This simple app captures input from the microphone, opens a socket connection and streams audio data. It is intended to be used with the wav_classifier project running in server mode. In response, the server will respond with a classification value. Further, the app will search for a Simblee BLE device and send a control signal to the device based on the classification signal.

## Requirements

The app is written in Swift 3.0 and is known to work with Xcode 8.3.2.

