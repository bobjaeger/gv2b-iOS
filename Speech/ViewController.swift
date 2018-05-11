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
import NaturalLanguageClassifierV1
import FirebaseDatabase

// prepare Natural Language Classifier
let username = ""
let password = ""
let naturalLanguageClassifier = NaturalLanguageClassifier(username: username, password: password)
let classifierID = "e9d41cx366-nlc-1438"

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
extension Int {
    func commaSeperateFormat() -> String {
        // format current bid to appropriate comma seperation
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = NumberFormatter.Style.decimal
        let formattedNumber = numberFormatter.string(from: NSNumber(value:self))
        return formattedNumber!
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
  var numsMil = Array(stride(from: 50, through: 0, by: -1))
  var nums = Array(stride(from: 999, through: 0, by: -1))
  var numsOnes = Array(stride(from: 995, through: 0, by: -5))
    
  override func viewDidLoad() {
    super.viewDidLoad()
    AudioController.sharedInstance.delegate = self
    
    // instantly hide ui elements
    hideTranscriptArea(duration: 0.0)
    
    // set the firebase reference
    ref = Database.database().reference()
    
    // set property value to 0
    setCurrentBidValue(newBid: 0)
    
    // retrieve current bid snapshot and listen for changes
    databaseHandle = ref?.child("Bids").observe(.childChanged, with: { (snapshot) in
        if snapshot.key == "currentBid" {
            // get current bid value
            let databaseCurrentBid = snapshot.value as! Int
            print( "CB: " + String( databaseCurrentBid ) )
            
            // set current bid to current bid title
            self.currentBid = databaseCurrentBid
            self.currentBidLabel.text = (currentBidLabelPreset + databaseCurrentBid.commaSeperateFormat())
            
            // flash current bid view upon value update
            self.currentBidChanged()
            
            // set bubble to eventlist
            self.addEventBubble(eventText: ("$"+self.currentBid.commaSeperateFormat()), eventType: .bidSubmitted)
        }
    })
    
    // Set dataSource and delegate to this class (self).
    self.pickOne.dataSource = self
    self.pickOne.delegate = self
    
    // set border color
    self.manualPickerContainer.layer.borderWidth = 3
    self.manualPickerContainer.layer.borderColor = currentBidStock.cgColor
    
    //validateTranscriptionNLC(transcriptionText: "i have herp le derp at 1 million baguettes")
    //print(wordsToNumber(transcription: "i have herp le derp at 1 million baguettes") )
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
    
  // double tap gesture to swap sides of heavy to navigate middle picker
  @IBAction func dblTapThou(_ sender: UITapGestureRecognizer) {
    if pickOne.selectedRow(inComponent: 1) > (nums.count/2) {
        pickOne.selectRow(nums[nums.count-1], inComponent: 1, animated: true)
    } else {
        pickOne.selectRow(nums[0], inComponent: 1, animated: true)
    }
  }
    
  // set the new current bid value
  func setCurrentBidValue(newBid: Int) -> Void {
    ref?.child("Bids").updateChildValues(["currentBid": newBid])
  }

  // accept bid
  @IBAction func acceptBid(_ sender: UIButton) {
    let milNum = numsMil[pickOne.selectedRow(inComponent: 0)] * 1000000
    let thoNum = nums[pickOne.selectedRow(inComponent: 1)] * 1000
    let oneNum = numsOnes[pickOne.selectedRow(inComponent: 2)]
    let bidNumber = Int(milNum + thoNum + oneNum)
    
    // if bid is not greater then current bid
    if bidNumber <= currentBid
    {
        addEventBubble(eventText: "Must be greater then current Bid", eventType: .warning)
    }
    else
    {
        // add current bid to database
        setCurrentBidValue(newBid: bidNumber)
    }
    hideManualEntry()
  }
    
  // decline bid
  @IBAction func declineBid(_ sender: UIButton) {
    hideManualEntry()
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
    
    addEventBubble(eventText: "Stream Started", eventType: .streamStarted)
  }

  @IBAction func stopAudio(_ sender: NSObject) {
    _ = AudioController.sharedInstance.stop()
    SpeechRecognitionService.sharedInstance.stopStreaming()
    
    hideManualEntry() // hide manual entry area
    
    hideTranscriptArea(duration: 0.5)    // animate hide transcipt area
    
    micStart.isHidden = false
    micStop.isHidden = true
    
    addEventBubble(eventText: "Stream Stopped", eventType: .streamEnded)
  }
    
    // clear bubble text in event list
    func clearEventList() {
        for view in eventList.subviews{
            view.removeFromSuperview()
        }
    }
    
    // show manual entry view
    func showManualEntry(valueToAccept: Int? = nil) {
        DispatchQueue.main.async {
            // prepare to preset pickers
            var animate: Bool
            var strCB: String
            
            // check if valueToAccept has been set and process accordingly
            if valueToAccept == nil {
                strCB = String(format: "%09d", self.currentBid)
                animate = false
            } else {
                if valueToAccept! > self.currentBid
                {
                    strCB = String(format: "%09d", valueToAccept!)
                    animate = true
                } else {
                    strCB = String(format: "%09d", self.currentBid!)
                    animate = true
                }
            }
            
            // set array for picker populating
            let compOne = Int(strCB[6...8])
            let compTho = Int(strCB[3...5])
            let compMil = Int(strCB[0...2])
            
            // find index for pickers preset
            let milIndex = self.numsMil.index(of: compMil!) as Int? ?? self.numsMil.count-1
            let thoIndex = self.nums.index(of: compTho!) as Int? ?? self.nums.count-1
            let oneIndex = self.numsOnes.index(of: compOne!) as Int? ?? self.numsOnes.count-1
            
            // set pickers to respective rows
            self.pickOne.selectRow(milIndex, inComponent: 0, animated: animate)
            self.pickOne.selectRow(thoIndex, inComponent: 1, animated: animate)
            self.pickOne.selectRow(oneIndex, inComponent: 2, animated: animate)
            self.manualPickerContainer.isHidden = false
            
            // animate manual entry show
            let showMP = CGRect(origin: CGPoint(x: 15, y: 210), size: self.manualPickerContainer.frame.size)
            UIView.animate(withDuration: 0.2, animations: {
                () -> Void in
                self.manualPickerContainer.frame = showMP
            })
        }
    }
    
    func hideManualEntry() {
        // animate manual entry hide
        let hideMP = CGRect(origin: CGPoint(x: 15, y: -100), size: self.manualPickerContainer.frame.size)
        UIView.animate(withDuration: 0.2, animations: {
            () -> Void in
            self.manualPickerContainer.frame = hideMP
        }, completion: { (true) -> Void in
            // after animation completed set isHidden to true
            self.manualPickerContainer.isHidden = true
        })
    }
    
  // show or hide manual entry button
  @IBAction func showHideManualEntry(_ sender: UIButton) {
    if manualPickerContainer.isHidden
    { showManualEntry() }   // show manual entry
    else
    { hideManualEntry() }   // hide manual entry
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
            }, completion: {
                (true) -> Void in
                // re scroll to bottom of event list
                self.eventList.scrollTo(direction: .Bottom, animated: true)
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
    
    // enums for auction events
    enum auctionEvent {
        case streamStarted
        case auctionStart
        case bidSubmitted
        case warning
        case nothing
        case auctionEnd
        case streamEnded
    }
    
    // add event or bubble to final transcription
    func addEventBubble(eventText: String, eventType: auctionEvent) {
        // initialize a view to contain label bubble output
        let addedView = UIView()
        addedView.frame = CGRect(
            origin: CGPoint(x: 0,y : Int(eventList.frame.height) + (50 * uiViewEventArray.count) ),
            size: CGSize(
                width: (self.eventList.frame.width),
                height: 50)
        )
        
        // initialize a label to contain text content
        let transcriptLabel = UILabel()
        transcriptLabel.frame = CGRect(
            origin: CGPoint(x: 15,y : 0),
            size: CGSize(
                width: ((self.eventList.frame.width) - 20),
                height: 40)
        )
        transcriptLabel.center = CGPoint(x: addedView.frame.width/2, y: addedView.frame.height/2) // center label in initialized view
        transcriptLabel.font = UIFont(name:transcriptLabel.font.fontName, size: 18.0)   // set default font size standard
        transcriptLabel.textAlignment = NSTextAlignment.left    // set left align as default
        
        // event type handlimg
        if eventType == .nothing
        {
            // if event triggered is "nothing"
            transcriptLabel.backgroundColor = UIColor(red:1.00, green:1.00, blue:1.00, alpha:1.0)
        }
        else if eventType == .bidSubmitted
        {
            // if event triggered is "bidSubmitted"
            transcriptLabel.backgroundColor = speechOnColor
            transcriptLabel.textAlignment = NSTextAlignment.right
            transcriptLabel.font = UIFont(name:transcriptLabel.font.fontName, size: 20.0)
        } else if eventType == .streamStarted || eventType == .streamEnded
        {
            // if event triggered is "streamEnded"
            transcriptLabel.backgroundColor = UIColor.gray
            transcriptLabel.font = UIFont(name:transcriptLabel.font.fontName, size: 18.0)
        } else if eventType == .warning
        {
            // if event triggered is "warning"
            transcriptLabel.backgroundColor = UIColor.yellow
            transcriptLabel.font = UIFont(name:transcriptLabel.font.fontName, size: 18.0)
        }
        
        transcriptLabel.text = "  "+eventText+"  "
        transcriptLabel.layer.masksToBounds = true
        transcriptLabel.layer.cornerRadius = 20
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

  // convert transcription from words of numbers to numeric
  func wordsToNumber(transcription: String) -> Int {
    // var of words for numbers
    var wordsOfNumber: [String: Int] = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100, "thousand": 1000, "million": 1000000]
    
    // split transcription into words
    let transWords = transcription.components(separatedBy: " ")
    var recompileTranscription: [Int] = []
    
    // find sequence of number then word number
    for i in 0...(transWords.count-1) {
        let lowerWord = transWords[i].lowercased()   // lowercased word
        if let x:Int = Int(lowerWord) {
            if x != nil {
                if let val = wordsOfNumber[transWords[i+1]] {
                    recompileTranscription.append(x)
                    recompileTranscription.append(val)
                    break
                }
            }
        }
    }
    
    // readd number together
    var numberAddition = 0
    if recompileTranscription.count == 2 {
        numberAddition = recompileTranscription[0] * recompileTranscription[1]
    }
    
    if numberAddition > 0 {
        return numberAddition       // number found
    }
    return -1                       // nope
  }
    
  // validate transciption to see if is acknowledged bid
  func validateTranscriptionNLC(transcriptionText: String) {
    // print nlc errors
    let failure = { (error: Error) in print(error) }
    
    // classify transcription
    naturalLanguageClassifier.classify(classifierID: classifierID, text: transcriptionText, failure: failure) {
        classification in
        print(classification)
        // set and get most confident class
        let classArray = classification.classes!
        let firstConfidence = classArray.first!.confidence! as Double
        
        // if most confident class is greater than 66%
        if firstConfidence > 0.66 {
            // if class is an acknowledged bid
            if classification.topClass! == "ackBid" {
                
                // if it is an acknowldeged bid
                let regex = try! NSRegularExpression(pattern: "(\\d+){1}", options: [])
                let matches = regex.matches(in: transcriptionText, options: [], range: NSRange(location: 0, length: transcriptionText.count))
                
                // get bid value from match
                if let match = matches.first {          // get first regex match
                    let range = match.rangeAt(1)
                    if let swiftRange = Range(range, in: transcriptionText) {
                        let bid = transcriptionText[swiftRange]                // get bid from refex match string range
                        self.showManualEntry(valueToAccept: Int(bid)!)         // show manual entry with attempted price
                    }
                }
                
            }
        }
    }
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
                //var finished = false    // flag to identify end of speech recognition result
                
                // if result or google api return is a streaming recognition result
                for result in response.resultsArray! {
                    if let result = result as? StreamingRecognitionResult {
                        var stable = false
                        
                        //print(result)
                        
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
                            //finished = true
                            
                            // print the running transcript
                            if let resultFirstAlt = result.alternativesArray.firstObject as? SpeechRecognitionAlternative {
                                
                                //if let x = self?.wordsToNumber(transcription: resultFirstAlt.transcript) {}
                                
                                // check transcription for classification labels
                                self?.validateTranscriptionNLC(transcriptionText: resultFirstAlt.transcript)
                                
                                // set text view to transcript
                                strongSelf.textView.text = resultFirstAlt.transcript
                                
                                // add event to event list
                                self?.addEventBubble(eventText: resultFirstAlt.transcript, eventType: .nothing)
                                //print(resultFirstAlt.transcript)
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
