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
import FirebaseDatabase

let currentBidLabelPreset = "CURRENT BID: $"

// set data base reference on load
var ref: DatabaseReference!

let SAMPLE_RATE = 16000

// scroll functionality for UIScrollView EventList
enum ScrollDirection {
    case Top
    case Right
    case Bottom
    case Left
    
    func contentOffsetWith(scrollView: UIScrollView) -> CGPoint {
        var contentOffset = CGPoint.zero
        switch self {
        case .Top:
            contentOffset = CGPoint(x: 0, y: -scrollView.contentInset.top)
        case .Right:
            contentOffset = CGPoint(x: scrollView.contentSize.width - scrollView.bounds.size.width, y: 0)
        case .Bottom:
            contentOffset = CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.bounds.size.height)
        case .Left:
            contentOffset = CGPoint(x: -scrollView.contentInset.left, y: 0)
        }
        return contentOffset
    }
}
extension UIScrollView {
    func scrollTo(direction: ScrollDirection, animated: Bool = true) {
        self.setContentOffset(direction.contentOffsetWith(scrollView: self), animated: animated)
    }
}
/*
 myScrollView.scrollTo(.Top/.Right/.Bottom/.Left)    // Animation is enabled by default
 myScrollView.scrollTo(.Top/.Right/.Bottom/.Left, animated: false)  // Without animation
 */

extension String {
    subscript (bounds: CountableClosedRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start...end])
    }
    
    subscript (bounds: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start..<end])
    }
}

class ViewController : UIViewController, AudioControllerDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    
  @IBOutlet weak var textView: UITextView!
  @IBOutlet weak var micStart: UIButton!
  @IBOutlet weak var micStop: UIButton!
  @IBOutlet weak var transcriptSpace: UIView!
  @IBOutlet weak var eventList: UIScrollView!
  @IBOutlet weak var currentBidView: UIView!
  @IBOutlet weak var currentBidLabel: UILabel!
  @IBOutlet weak var menuView: UIView!
  @IBOutlet weak var manualEnter: UIButton!
  @IBOutlet weak var manualPickerContainer: UIView!
    
  @IBOutlet weak var pickOne: UIPickerView!
    
  var audioData: NSMutableData!
    
  var uiViewEventArray: [UIView] = []
    
  // color presets for programmatical changes
  let speechOnColor = UIColor(red:0.00, green:0.83, blue:0.78, alpha:1.0)
  let speechOffColor = UIColor(red:0.15, green:0.15, blue:0.15, alpha:1.0)
  let currentBidStock = UIColor(red:0.30, green:0.30, blue:0.31, alpha:1.0)
    
  var currentBid: Int! = 0      // variable for the current standing bid
  var tempResult : StreamingRecognitionResult!     // create variable to store Streaming Recognition Result for comparison

  // variable to set database reference on load
  var ref: DatabaseReference!
  var databaseHandle: DatabaseHandle?
    
  // populate pickers with numbers
  var numsMil = Array(stride(from: 20, through: 0, by: -1))
  var nums = Array(stride(from: 999, through: 0, by: -1))
  var numsOnes = Array(stride(from: 900, through: 0, by: -100))
    
  override func viewDidLoad() {
    super.viewDidLoad()
    AudioController.sharedInstance.delegate = self
    
    // set menu color to off
    //menuView.backgroundColor = speechOffColor
    
    // instantly hide ui elements
    hideTranscriptArea(duration: 0.0)
    
    // set the firebase reference
    ref = Database.database().reference()
    
    // retrieve current bid snapshot and listen for changes
    databaseHandle = ref?.child("Bids").observe(.childChanged, with: { (snapshot) in
        if snapshot.key == "currentBid" {
            // get current bid value
            let databaseCurrentBid = snapshot.value as! Int
            print(databaseCurrentBid)
            
            // format current bid to appropriate comma seperation
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = NumberFormatter.Style.decimal
            let formattedNumber = numberFormatter.string(from: NSNumber(value:databaseCurrentBid))
            
            // set current bid to current bid title
            self.currentBid = databaseCurrentBid
            self.currentBidLabel.text = (currentBidLabelPreset + formattedNumber!)
            
            // flash current bid view upon value update
            self.currentBidChanged()
        }
    })
    
    // Set dataSource and delegate to this class (self).
    self.pickOne.dataSource = self
    self.pickOne.delegate = self
    
    // set border color
    self.manualPickerContainer.layer.borderWidth = 3
    self.manualPickerContainer.layer.borderColor = currentBidStock.cgColor
  }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        // Column count: use one column.
        return 3
    }
    func pickerView(_ pickerView: UIPickerView,
                    numberOfRowsInComponent component: Int) -> Int {
        // Row count: rows equals array length.
        if component == 0
        { return numsMil.count }
        else if component == 2
        { return numsOnes.count }
        
        return nums.count
    }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        // Return a string from the array for this row.
        if component == 0
        { return String(numsMil[row]) }
        else if component == 2
        { return String(numsOnes[row]) }
        
        return String(nums[row])
    }
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        let attributedString = NSAttributedString(string: String(format: "%03d", nums[row]), attributes: [NSForegroundColorAttributeName : UIColor.white])
        
        if component == 0
        { return NSAttributedString(string: String(numsMil[row]), attributes: [NSForegroundColorAttributeName : UIColor.white]) }
        else if component == 2
        { return NSAttributedString(string: String(format: "%03d", numsOnes[row]), attributes: [NSForegroundColorAttributeName : UIColor.white]) }
        
        return attributedString
    }

  // flash color change upon current bid value update
  func currentBidChanged() {
    UIView.animate(withDuration: 0.2, animations: { () -> Void in
        // color
        self.currentBidView.backgroundColor = self.speechOnColor
    }, completion: {
        (true) -> Void in
        UIView.animate(withDuration: 0.2, animations: { () -> Void in
            // uncolor
            self.currentBidView.backgroundColor = self.currentBidStock
        })
    })
  }

  // set the new current bid value
  func setCurrentBidValue(currentBid: Int) -> Void {
    ref?.child("Bids").updateChildValues(["currentBid": currentBid])
  }

  // accept bid
  @IBAction func acceptBid(_ sender: UIButton) {
    let milNum = numsMil[pickOne.selectedRow(inComponent: 0)] * 1000000
    let thoNum = nums[pickOne.selectedRow(inComponent: 1)] * 1000
    let oneNum = numsOnes[pickOne.selectedRow(inComponent: 2)]
    let bidNumber = Int(milNum + thoNum + oneNum)
    
    // if bid is not greater then current bid
    if bidNumber <= currentBid
    { showHideManualEntry(sender) }
    else
    {
        // add current bid to database
        setCurrentBidValue(currentBid: bidNumber)
        showHideManualEntry(sender)
    }
  }
    
  // decline bid
  @IBAction func declineBid(_ sender: UIButton) {
    showHideManualEntry(sender)
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

    showTranscriptArea(duration: 0.5)    // animate show transcript area
    
    micStart.isHidden = true
    micStop.isHidden = false
    
    // Scroll to bottom of scroll view
    eventList.scrollTo(direction: .Bottom, animated: true)
  }

  @IBAction func stopAudio(_ sender: NSObject) {
    _ = AudioController.sharedInstance.stop()
    SpeechRecognitionService.sharedInstance.stopStreaming()
    
    hideManualEntry() // hide manual entry area
    
    hideTranscriptArea(duration: 0.5)    // animate hide transcipt area
    
    micStart.isHidden = false
    micStop.isHidden = true
    
    // Scroll to bottom of scroll view
    eventList.scrollTo(direction: .Bottom, animated: true)
  }
    
    // show manual entry view
    func showManualEntry() {
        // prepare to preset pickers
        let strCB = String(format: "%09d", currentBid)
        let compOne = Int(strCB[6...8])
        let compTho = Int(strCB[3...5])
        let compMil = Int(strCB[0...2])
        
        // find index for pickers preset
        let milIndex = numsMil.index(of: compMil!) as Int! ?? numsMil.count-1
        let thoIndex = nums.index(of: compTho!) as Int! ?? nums.count-1
        let oneIndex = numsOnes.index(of: compOne!) as Int! ?? numsOnes.count-1
        
        // set pickers to respective rows
        pickOne.selectRow(milIndex, inComponent: 0, animated: false)
        pickOne.selectRow(thoIndex, inComponent: 1, animated: false)
        pickOne.selectRow(oneIndex, inComponent: 2, animated: false)
        manualPickerContainer.isHidden = false
        
        // animate manual entry show
        let showMP = CGRect(origin: CGPoint(x: 15, y: 210), size: self.manualPickerContainer.frame.size)
        UIView.animate(withDuration: 0.2, animations: {
            () -> Void in
            self.manualPickerContainer.frame = showMP
        })
    }
    
    func hideManualEntry() {
        // animate manual entry hide
        let hideMP = CGRect(origin: CGPoint(x: 15, y: -100), size: self.manualPickerContainer.frame.size)
        UIView.animate(withDuration: 0.2, animations: {
            () -> Void in
            self.manualPickerContainer.frame = hideMP
        }, completion: { (true) -> Void in
            self.manualPickerContainer.isHidden = true
        })
    }
    
  // show or hide manual entry
  @IBAction func showHideManualEntry(_ sender: UIButton) {
    if manualPickerContainer.isHidden
    {
        showManualEntry()
    }
    else
    {
        hideManualEntry()
    }
  }
    
    // function to HIDE transcript area and text view with animation
    func hideTranscriptArea(duration: TimeInterval) {
        // animate the visibility of transcript text view to hide
        UIView.animate(withDuration: duration*2, animations: {
            () -> Void in
            self.menuView.backgroundColor = self.speechOffColor // set menu color to off
            self.textView.alpha = 0 // fade out transcribe area
            self.manualEnter.alpha = 0 // fade out manual entry button
        }, completion: {
            // animate transcript area hiding
            (true) -> Void in
            self.textView.isHidden = true
            self.manualEnter.isHidden = true    // unhide manual entry button
            UIView.animate(withDuration: duration, animations: { () -> Void in
                // move top part of Transcript Space to hide the prior text view space
                let transcriptSpaceFrame = CGRect(origin: CGPoint(x: 0,y : self.view.frame.maxY - 77), size: CGSize(width: self.view.frame.width, height: 450))
                self.transcriptSpace.frame = transcriptSpaceFrame
                
                // hide current bid view
                let currentBidViewFrame = CGRect(
                    origin: CGPoint(x: 0,y : self.menuView.frame.minY),
                    size: CGSize(
                        width: self.view.frame.width,
                        height: self.currentBidView.frame.height)
                )
                self.currentBidView.frame = currentBidViewFrame
                
                // move bottom part of event list View
                let eventListViewFrame = CGRect(
                    origin: CGPoint(x: 16,y : self.currentBidView.frame.maxY + 16),
                    size: CGSize(
                        width: self.eventList.frame.width,
                        height: (transcriptSpaceFrame.minY - 43 + self.currentBidView.frame.height - self.eventList.frame.minY))
                )
                self.eventList.frame = eventListViewFrame
            })
        })
    }
    
    // function to SHOW transcript area and text view with animation
    func showTranscriptArea(duration: TimeInterval) {
        // animate transcript area showing
        UIView.animate(withDuration: duration, animations: {
            () -> Void in
            // move top part of Transcript Space to open for text view
            let transcriptSpaceFrame = CGRect(origin: CGPoint(x: 0,y :self.textView.frame.minY - 15), size: CGSize(width: self.view.frame.width, height: 450))
            self.transcriptSpace.frame = transcriptSpaceFrame
            
            // show current bid view
            let currentBidViewFrame = CGRect(
                origin: CGPoint(x: 0,y : self.menuView.frame.maxY),
                size: CGSize(
                    width: self.view.frame.width,
                    height: self.currentBidView.frame.height)
            )
            self.currentBidView.frame = currentBidViewFrame
            
            // move bottom part of event list View
            let eventListViewFrame = CGRect(
                origin: CGPoint(x: 16,y : self.currentBidView.frame.maxY + 16),
                size: CGSize(
                    width: self.eventList.frame.width,
                    height: (transcriptSpaceFrame.minY - 15 - self.currentBidView.frame.height - self.eventList.frame.minY))
            )
            self.eventList.frame = eventListViewFrame
        }, completion: {
            // on completion of transcript area showing
            //      animate the visibility of transcript text view
            (true) -> Void in
            self.textView.isHidden = false
            self.manualEnter.isHidden = false // hide manual entry button
            UIView.animate(withDuration: duration*2, animations: { () -> Void in
                self.menuView.backgroundColor = self.speechOnColor // set menu color to on
                self.textView.alpha = 1
                self.manualEnter.alpha = 1 // fade in manual entry button
            })
        })
    }
    
    // add event or bubble to final transcription
    func addFinalTranscription(transcription: String) {
        let addedView = UIView()
        addedView.frame = CGRect(
            origin: CGPoint(x: 0,y : Int(eventList.frame.height) + (50 * uiViewEventArray.count) ),
            size: CGSize(
                width: (self.eventList.frame.width),
                height: 50)
        )
        let transcriptLabel = UILabel()
        transcriptLabel.frame = CGRect(
            origin: CGPoint(x: 15,y : 0),
            size: CGSize(
                width: ((self.eventList.frame.width) - 20),
                height: 40)
        )
        transcriptLabel.center = CGPoint(x: addedView.frame.width/2, y: addedView.frame.height/2)
        transcriptLabel.font.withSize(6.0)
        transcriptLabel.backgroundColor = UIColor(red:1.00, green:1.00, blue:1.00, alpha:1.0)
        transcriptLabel.layer.masksToBounds = true
        transcriptLabel.layer.cornerRadius = 20
        transcriptLabel.text = transcription
        transcriptLabel.textAlignment = NSTextAlignment.right
        addedView.addSubview(transcriptLabel)
        
        // add to uiViewArray
        uiViewEventArray.append(addedView)
        eventList.contentSize = CGSize(
            width: eventList.frame.width,
            height: (
                CGFloat(
                    Float(eventList.frame.height) + (50.0 * Float(uiViewEventArray.count) )
                )
            )
        )
        self.eventList.addSubview(addedView)
        
        // Scroll to bottom of scroll view
        eventList.scrollTo(direction: .Bottom, animated: true)
        
        // set transcription field to empty string
        textView.text = String()
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
                            strongSelf.textView.text = String()
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
                                strongSelf.textView.text = resultFirstAlt.transcript
                                
                                // add event to event list
                                self?.addFinalTranscription(transcription: resultFirstAlt.transcript)
                                print(resultFirstAlt.transcript)
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
