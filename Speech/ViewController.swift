//
// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import UIKit
import AVFoundation
import googleapis

let SAMPLE_RATE = 16000

class ViewController : UIViewController, AudioControllerDelegate {
  @IBOutlet weak var textView: UITextView!
  @IBOutlet weak var micStart: UIButton!
  @IBOutlet weak var micStop: UIButton!
  @IBOutlet weak var transcriptSpace: UIView!
  @IBOutlet weak var eventList: UIView!
  @IBOutlet weak var currentBidView: UIView!
    
  var audioData: NSMutableData!
    
  var currentBid: Int!      // variable for the current standing bid
  var tempResult : StreamingRecognitionResult!     // create variable to store Streaming Recognition Result for comparison

  override func viewDidLoad() {
    super.viewDidLoad()
    AudioController.sharedInstance.delegate = self
    
    textView.text = String()    // clear ui text screen
  }

  @IBAction func recordAudio(_ sender: NSObject) {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(AVAudioSessionCategoryRecord)
    } catch {

    }
    audioData = NSMutableData()
    _ = AudioController.sharedInstance.prepare(specifiedSampleRate: SAMPLE_RATE)
    SpeechRecognitionService.sharedInstance.sampleRate = SAMPLE_RATE
    _ = AudioController.sharedInstance.start()
    micStart.isHidden = true
    micStop.isHidden = false
    
    showTranscriptArea()    // animate show transcript area
  }

  @IBAction func stopAudio(_ sender: NSObject) {
    _ = AudioController.sharedInstance.stop()
    SpeechRecognitionService.sharedInstance.stopStreaming()
    micStart.isHidden = false
    micStop.isHidden = true
    
    hideTranscriptArea()    // animate hide transcipt area
  }
    
    // function to HIDE transcript area and text view with animation
    func hideTranscriptArea() {
        // animate the visibility of transcript text view to hide
        UIView.animate(withDuration: 1, animations: {
            () -> Void in
            self.textView.alpha = 0
        }, completion: {
            // animate transcript area hiding
            (true) -> Void in
            self.textView.isHidden = true
            UIView.animate(withDuration: 0.5, animations: { () -> Void in
                // move top part of Transcript Space to hide the prior text view space
                let transcriptSpaceFrame = CGRect(origin: CGPoint(x: 0,y : self.view.frame.maxY - 77), size: CGSize(width: self.view.frame.width, height: 450))
                self.transcriptSpace.frame = transcriptSpaceFrame
                
                // move bottom part of event list View
                let eventListViewFrame = CGRect(
                    origin: CGPoint(x: 16,y : 210),
                    size: CGSize(
                        width: self.eventList.frame.width,
                        height: (transcriptSpaceFrame.minY - 43 - self.eventList.frame.minY))
                )
                self.eventList.frame = eventListViewFrame
            })
        })
    }
    
    // function to SHOW transcript area and text view with animation
    func showTranscriptArea() {
        // animate transcript area showing
        UIView.animate(withDuration: 0.5, animations: {
            () -> Void in
            // move top part of Transcript Space to open for text view
            let transcriptSpaceFrame = CGRect(origin: CGPoint(x: 0,y :self.textView.frame.minY - 15), size: CGSize(width: self.view.frame.width, height: 450))
            self.transcriptSpace.frame = transcriptSpaceFrame
            
            // move bottom part of event list View
            let eventListViewFrame = CGRect(
                origin: CGPoint(x: 16,y : 210),
                size: CGSize(
                    width: self.eventList.frame.width,
                    height: (transcriptSpaceFrame.minY - 15 - self.eventList.frame.minY))
            )
            self.eventList.frame = eventListViewFrame
        }, completion: {
            // on completion of transcript area showing
            //      animate the visibility of transcript text view
            (true) -> Void in
            self.textView.isHidden = false
            UIView.animate(withDuration: 1, animations: { () -> Void in
                self.textView.alpha = 1
            })
        })
    }

  func processSampleData(_ data: Data) -> Void {
    audioData.append(data)

    // We recommend sending samples in 100ms chunks
    let chunkSize : Int /* bytes/chunk */ = Int(0.1 /* seconds/chunk */
      * Double(SAMPLE_RATE) /* samples/second */
      * 2 /* bytes/sample */);

    if (audioData.length > chunkSize) {
      SpeechRecognitionService.sharedInstance.streamAudioData(audioData,
                                                              completion:
        { [weak self] (response, error) in
            guard let strongSelf = self else {
                return
            }
            
            if let error = error {
                strongSelf.textView.text = error.localizedDescription
            } else if let response = response {
                var finished = false    // flag to identify end of speech recognition result
                
                // if result or google api return is a streaming recognition result
                for result in response.resultsArray! {
                    if let result = result as? StreamingRecognitionResult {
                        var stable = false
                        
                        // if there has not been a recognition result yet
                        if self?.tempResult == nil {
                            // set recognition to temporary variable
                            self?.tempResult = result
                            stable = true
                        } else if (self?.tempResult.stability)! <= result.stability {
                            // otherwise if stability of result is equal or better then temporary variable
                            // replace temp variable with more stable option
                            self?.tempResult = result
                            stable = true
                        }
                        
                        // if recognition result is a stable result
                        if stable == true {
                            // print the running transcript
                            if let resultFirstAlt = result.alternativesArray.firstObject as? SpeechRecognitionAlternative {
                                strongSelf.textView.text = resultFirstAlt.transcript  // add transcript to textView
                            }
                        }
                        
                        // check if final result
                        if result.isFinal {
                            finished = true
                            
                            // print the running transcript
                            if let resultFirstAlt = result.alternativesArray.firstObject as? SpeechRecognitionAlternative {
                                strongSelf.textView.text = resultFirstAlt.transcript  // add transcript to textView
                            }
                            
                            // reset temp result
                            self?.tempResult = nil
                        }
                    }
                }
                
                /*if finished {
                    strongSelf.stopAudio(strongSelf)
                } auto stop audio when json return of transcription is finished */
            }
      })
      self.audioData = NSMutableData()
    }
  }
}
