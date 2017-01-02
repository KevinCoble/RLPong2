//
//  ViewController.swift
//  RLPong2
//
//  Created by Kevin Coble on 12/11/16.
//  Copyright © 2016 Kevin Coble. All rights reserved.
//

import Cocoa
import AIToolbox

enum Opponent {
    case none
    case random
    case medium
    case hard
}

struct GameParameters {
    var pixelsWide : Int
    var pixelsHigh : Int
    var paddleHeight : Int      //  Should only be odd
    var onlyHorizontal : Bool   //  If true, ball only moves horizontally
    var opponent : Opponent
    
    var numPixels : Int {
        get { return pixelsWide * pixelsHigh }
    }
}

enum Action : Int {
    case Down = 0
    case Up
    case Stay
}

class ViewController: NSViewController {
    
    @IBOutlet weak var pixelView: PGPixelView!
    @IBOutlet weak var wonField: NSTextField!
    @IBOutlet weak var lostField: NSTextField!
    @IBOutlet weak var initButton: NSButton!
    @IBOutlet weak var runButton: NSButton!
    @IBOutlet weak var gameSelection: NSPopUpButton!
    @IBOutlet weak var hiddenNodesField: NSTextField!
    @IBOutlet weak var hiddenNodesStepper: NSStepper!
    @IBOutlet weak var stayActionCheckbox: NSButton!
    
    var network : NeuralNetwork!
    
    let parameterSets = [GameParameters(pixelsWide: 2, pixelsHigh: 2, paddleHeight: 1, onlyHorizontal: true, opponent: .none),        //  2x2, horz, no opp.
                         GameParameters(pixelsWide: 3, pixelsHigh: 3, paddleHeight: 1, onlyHorizontal: true, opponent: .none),        //  3x3, horz, no opp.
                         GameParameters(pixelsWide: 5, pixelsHigh: 5, paddleHeight: 1, onlyHorizontal: false, opponent: .none),       //  5x5, angles, no opp.
                         GameParameters(pixelsWide: 11, pixelsHigh: 11, paddleHeight: 3, onlyHorizontal: false, opponent: .random),   //  11x11, angles, easy opp.
                         GameParameters(pixelsWide: 21, pixelsHigh: 21, paddleHeight: 5, onlyHorizontal: false, opponent: .medium)]   //  21x21, angles, medium opp.
    
    var parameters : GameParameters!
    var gameBoard : [Double] = []
    
    var RLPaddlePosition = 0
    var opponentPaddlePosition = 0
    var ballPosX = 0
    var ballXVelocity = 1
    var ballPosY = 0
    var ballFloatPosY = 0.0
    var ballYVelocity = 0.0
    var wonLastGame = false
    var wonCount = 0
    var lostCount = 0
    
    var discountFactor = 0.98
    var trainingRate = 0.2
    var weightDecay = 1.0
    var greedyAction = 0.99
    
    var numActions : UInt32 = 2
    var halfPaddleHeight = 0
    var topPixel = 2.0
    
    var running = false         //  running games in the background
    var stopping = false        //  in the process of stopping
    var training = true         //  training the network on each game run
    var viewing = true//  If true, the gameboard updates on the display, slowing down training
    var scoreUpdate = 100       //  Game iterations before updating - updated from board size
    var minimumFrameTime = 0.05
    var lastFrameTime = Date()

    override func viewDidLoad() {
        super.viewDidLoad()

        //  Set the default parameters
        setParameters(parameters: parameterSets[0])
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    @IBAction func onGameChanged(_ sender: NSPopUpButton) {
        let index = gameSelection.selectedTag()
        if (index >= 0) {
            setParameters(parameters: parameterSets[index])
        }
    }
    
    @IBAction func onHiddenNodesFieldChanged(_ sender: NSTextField) {
        hiddenNodesStepper.integerValue = hiddenNodesField.integerValue
        createNetwork()
    }
    
    @IBAction func onHiddenNodesStepperChanged(_ sender: NSStepper) {
        hiddenNodesField.integerValue = hiddenNodesStepper.integerValue
        createNetwork()
    }
    
    @IBAction func onStayActionChanged(_ sender: NSButton) {
        numActions = 2
        if (stayActionCheckbox.state == NSOnState) { numActions = 3 }
        createNetwork()
    }
    
    @IBAction func onGreedyActionChanged(_ sender: NSTextField) {
        greedyAction = sender.doubleValue
    }
    
    func setControlStates(enable: Bool) {
        if (enable) {
            gameSelection.isEnabled = true
            hiddenNodesField.isEnabled = true
            hiddenNodesStepper.isEnabled = true
            stayActionCheckbox.isEnabled = true
        }
        else {
            gameSelection.isEnabled = false
            hiddenNodesField.isEnabled = false
            hiddenNodesStepper.isEnabled = false
            stayActionCheckbox.isEnabled = false
        }
    }
    
    func setParameters(parameters: GameParameters) {
        self.parameters = parameters
        gameBoard = [Double](repeating: 0.0, count: parameters.numPixels)
        pixelView.setData(data: gameBoard)
        pixelView.setParameters(parameters: parameters)
        halfPaddleHeight = parameters.paddleHeight / 2
        RLPaddlePosition = parameters.pixelsHigh / 2
        opponentPaddlePosition = parameters.pixelsHigh / 2
        topPixel = Double(parameters.pixelsHigh - 1)
        
        //  Determine an approximate score update frequency
        scoreUpdate = 200 / parameters.pixelsHigh
        
        //  Determine frame time - across screen in 1 second
        minimumFrameTime = 1.0 / Double(parameters.pixelsWide)
        
        //  Create a NeuralNetwork to run the policyGradient
        createNetwork()
    }
    
    func createNetwork() {
        //  Get the number of hidden nodes
        let numHiddenNodes = hiddenNodesField.integerValue
        
        //  Get the number of output nodes
        let numOutputNodes = (stayActionCheckbox.state == NSOnState) ? 3 : 1
        
        //  Get the layer definitions
        var networkLayers : [(layerType: NeuronLayerType, numNodes: Int, activation: NeuralActivationFunction, auxiliaryData: AnyObject?)] = []
        if (numHiddenNodes != 0) {
            networkLayers.append((layerType: .simpleFeedForward, numNodes: numHiddenNodes, activation: .sigmoid, auxiliaryData: nil))
        }
        networkLayers.append((layerType: .simpleFeedForward, numNodes: numOutputNodes, activation: .sigmoid, auxiliaryData: nil))
        
        network = NeuralNetwork(numInputs: parameters.numPixels, layerDefinitions: networkLayers)
        
        //  Initialize
        onInit(initButton)
    }

    @IBAction func onTrainChanged(_ sender: NSButton) {
        training = (sender.state == NSOnState)
    }
    
    @IBAction func onViewChanged(_ sender: NSButton) {
        viewing = (sender.state == NSOnState)
    }
    
    @IBAction func onInit(_ sender: NSButton) {
        //  Initialize the network
        network.initializeWeights(nil)
        
        //  Reset the score
        onReset(sender)
    }
    
    @IBAction func onRun(_ sender: NSButton) {
        //  If in the process of stopping, do nothing
        if (stopping) { return }
        
        //  If running, just set the stop flag
        if (running) {
            stopping = true
            runButton.title = "Stopping"
            return
        }
        
        //  Start episodes playing in the background
        setControlStates(enable: false)
        stopping = false
        runButton.title = "Stop"
        let tQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.default)
        tQueue.async {
            self.play()
        }
    }
    
    func play() {
        running = true
        var gameCount = 0
        
        //  Loop[ until we are told to stop
        while (!stopping) {
            //  Create an episode
            let episode = generateEpisode()
            
            //  See if we lost or won
            if (episode.finalReward > 0.0) {
                wonCount += 1
            }
            else {
                lostCount += 1
            }
            
            //  If we are training on this, do so
            if (training) {
                //  Discount the reward
                episode.discountRewards(discountFactor: discountFactor)
                
                //  Train the network
                episode.trainPolicyNetwork(network : network, trainingRate : trainingRate, weightDecay : weightDecay)
            }
            
            //  See if it is time to update the score
            gameCount += 1
            if (viewing || gameCount >= scoreUpdate) {
                gameCount = 0
                DispatchQueue.main.sync {
                    wonField.integerValue = wonCount
                    lostField.integerValue = lostCount
                }
            }
        }
        
        //  Set mode to 'stopped'
        running = false
        DispatchQueue.main.sync {
            runButton.title = "Run"
            setControlStates(enable: true)
        }
        stopping = false
    }
    
    @IBAction func onReset(_ sender: NSButton) {
        wonCount = 0
        wonField.integerValue = wonCount
        lostCount = 0
        lostField.integerValue = lostCount
    }
    
    func generateEpisode() -> PGEpisode
    {
        let episode = PGEpisode()
        
        //  Start with the serve
        serve()
        if (viewing) {
            drawFrame()
        }
        
        //  Add frames until we are done
        while (true) {
            var action = getActionFromNetwork()
            let nonGreedy = Double(arc4random()) / Double(UInt32.max)
            if (nonGreedy > greedyAction) {     //  Time to explore instead of exploit!
                action = getRandomAction()
            }
            let gradient = network.getLastClassificationGradient(resultUsed: action.rawValue)
            let result = doOneFrame(action: action)     //  Do the actions to find reward, but don't update the game board - we need the original as inputs for the step
            episode.addStep(newStep: PGStep(state: gameBoard, gradient: gradient, reward: result.reward))
            //  Get the board image for the next frame
            updateGameBoard()
            if (viewing) {
                drawFrame()
            }
            if (result.terminalState) { break }
        }
        
        return episode
    }
    
    func drawFrame() {
        //  Make sure the previous frame has been up long enough
        let currentTime = Date()
        let interval = currentTime.timeIntervalSince(lastFrameTime)
        if (interval < minimumFrameTime) {
            Thread.sleep(forTimeInterval: minimumFrameTime - interval)
        }
        lastFrameTime = Date()
        
        //  Draw the frame
        DispatchQueue.main.sync {
            pixelView.setData(data: gameBoard)
            pixelView.setNeedsDisplay(pixelView.bounds)
        }
    }
    
    func serve()
    {
        //  Start on the left or right side, depending on who won the last game
        if (wonLastGame) {
            ballPosX = parameters.pixelsWide - 1
            ballXVelocity = -1
        }
        else {
            ballPosX = 0
            ballXVelocity = 1
        }
        
        if (parameters.onlyHorizontal) {
            //  Pick a row to start in
            ballPosY = Int(arc4random_uniform(UInt32(parameters.pixelsHigh)))
            ballFloatPosY = Double(ballPosY)
            ballYVelocity = 0.0
        }
        else {
            //  Start in the center
            ballPosY = parameters.pixelsHigh / 2
            ballFloatPosY = Double(ballPosY)
            ballYVelocity = Double(arc4random()) / Double(UInt32.max) - 0.5
        }
        
        //  Get the board image
        updateGameBoard()
    }
    
    func doOneFrame(action: Action) -> (reward: Double, terminalState: Bool)
    {
        //  Move the paddle
        if (action == .Down) {
            if (RLPaddlePosition > halfPaddleHeight) { RLPaddlePosition -= 1 }
        }
        else if (action == .Up) {
            if (RLPaddlePosition < parameters.pixelsHigh - (1+halfPaddleHeight)) { RLPaddlePosition += 1 }
        }
        
        //  Move the ball forward
        ballPosX += ballXVelocity
        
        //  Deal with Y movement
        if (!parameters.onlyHorizontal) {
            ballFloatPosY += ballYVelocity
            if (ballFloatPosY < 0.0) {
                ballFloatPosY *= -1.0
                ballYVelocity *= -1.0
            }
            if (ballFloatPosY > topPixel) {
                ballFloatPosY = topPixel - (ballFloatPosY - topPixel)
                ballYVelocity *= -1.0
            }
            ballPosY = Int(ballFloatPosY + 0.5)
        }
        
        //  Move the opponent paddle, if there is one
        if (parameters.opponent != .none) {
            //  Get a random move
            var opponentAction = getRandomAction()
            let diceRoll = arc4random()
            if ((parameters.opponent == .medium && diceRoll < (UInt32.max / 4)) ||
                (parameters.opponent == .hard && diceRoll < (UInt32.max / 2))) {
                //  Track the ball
                if (ballPosY > opponentPaddlePosition) { opponentAction = .Up }
                if (ballPosY < opponentPaddlePosition) { opponentAction = .Down }
            }
            if (opponentAction == .Down) {
                if (opponentPaddlePosition > halfPaddleHeight) { opponentPaddlePosition -= 1 }
            }
            else if (opponentAction == .Up) {
                if (opponentPaddlePosition < parameters.pixelsHigh - (1+halfPaddleHeight)) { opponentPaddlePosition += 1 }
            }
        }
        
        var reward = 0.0
        var terminal = false
        //  Hit right side
        if (ballPosX >= (parameters.pixelsWide-1)) {
            if (ballPosY >= (RLPaddlePosition - halfPaddleHeight) && ballPosY <= (RLPaddlePosition + halfPaddleHeight)) {       //  On the paddle
                if (parameters.opponent == .none) {     //  No opponent, so done
                    terminal = true
                    reward = 1.0
                }
                else {
                    //  Bounce
                    ballXVelocity *= -1
                    ballPosX = parameters.pixelsWide-2
                    if (halfPaddleHeight > 0) {
                        let distanceFromCenter = ballFloatPosY - Double(RLPaddlePosition)
                        ballYVelocity = 1.0 * distanceFromCenter / Double(halfPaddleHeight)
                    }
                }
            }
            else {      //  Not on paddle
                terminal = true
                wonLastGame = false
                reward = -1.0
            }
        }
        
        //  Hit left side
        if (ballPosX <= 0) {
            if (ballPosY >= (opponentPaddlePosition - halfPaddleHeight) && ballPosY <= (opponentPaddlePosition + halfPaddleHeight)) {       //  On the paddle
                //  Bounce
                ballXVelocity *= -1
                ballPosX = 1
                if (halfPaddleHeight > 0) {
                    let distanceFromCenter = ballFloatPosY - Double(opponentPaddlePosition)
                    ballYVelocity = 1.0 * distanceFromCenter / Double(halfPaddleHeight)
                }
            }
            else {
                terminal = true
                wonLastGame = true
                reward = 1.0
            }
        }
        
        return (reward: reward, terminalState: terminal)
    }

    func updateGameBoard()
    {
        //  Clear the board
        gameBoard = [Double](repeating: 0.0, count: parameters.numPixels)
        
        //  Add the ball
        gameBoard[ballPosY * parameters.pixelsWide + ballPosX] = 1.0
        
        //  Add the computer's paddle to the last column
        let paddleCenter = (RLPaddlePosition * parameters.pixelsWide) + parameters.pixelsWide - 1
        gameBoard[paddleCenter] = 1.0
        if (halfPaddleHeight > 0) {
            for index in 0..<halfPaddleHeight {
                let offset = (index + 1) * parameters.pixelsWide
                gameBoard[paddleCenter + offset] = 1.0
                gameBoard[paddleCenter - offset] = 1.0
            }
        }
        
        //  If there is an opponent, draw the paddle for them
        if (parameters.opponent != .none) {
            let paddleCenter = (opponentPaddlePosition * parameters.pixelsWide)
            gameBoard[paddleCenter] = 1.0
            if (halfPaddleHeight > 0) {
                for index in 0..<halfPaddleHeight {
                    let offset = (index + 1) * parameters.pixelsWide
                    gameBoard[paddleCenter + offset] = 1.0
                    gameBoard[paddleCenter - offset] = 1.0
                }
            }
        }
    }
    
    func getActionFromNetwork() -> Action {
        let result = network.classifyOne(gameBoard)
        if let action = Action(rawValue: result) {
            return action
        }
        return Action.Stay
    }
    
    func getRandomAction() -> Action {
        
        let actionIndex = Int(arc4random_uniform(UInt32(numActions)))
        return Action(rawValue: actionIndex)!
    }
}

