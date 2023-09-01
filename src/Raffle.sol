// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {console} from "forge-std/console.sol";

/**
 * @title A sample Raffle Contract
 * @author Patrick Collins
 * @notice This contract is for creating a sample raffle contract
 * @dev This implements the Chainlink VRF Version 2
 */
contract Raffle is VRFConsumerBaseV2 {
    //Use error to revert if not enough ETH is sent (if - revert)
    error Raffle__notEnoughtETHSent();
    error Raffle__TransferFailed();
    error Raffle__NotOpen();
    error Raffle__UpKeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayesr,
        uint256 raffleState
    );

    /** Type declaration */
    enum RaffleState {
        OPEN, //0
        CALCULATING //1
    }

    /** State variable */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 3;

    //Entrance Fee for the raffle
    uint256 private immutable i_entranceFee;
    //@dev duration of lottery in second
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    //Store the players in an array - usa array perchè poi deve estrarre il vincitore e dal mapping non si può
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    //We pass in the entrance fee to the constructor
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator); //Cast type - i_vrfCoordinator èora di tipo VRFCoordinatorV2Interface
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        //Setta il primo timestamp
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        //Minimum fee people needs to pay to enter the raffle
        if (msg.value < i_entranceFee) {
            revert Raffle__notEnoughtETHSent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        //Mette nel nostro array il nuovo giocatore
        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    //When the winner supposed to be picked
    /**
     * @dev This it the function that the Chainlink Automation node will call
     * to see is it is time to pick a winner
     * The following should be true for this to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (aka players have paid the entrance fee)
     * 4. (Implicit) The subscription has been funded with LINK
     */
    //Per ingnorare il paramentro in ingresso uso checkData
    function checkUpKeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory performData) {
        //Check if enought time has passed
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayer = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayer;
        return (upkeepNeeded, "0x0");
    }

    //1. Get a random number
    //2. Use the random number to pick a winner
    //3. Be automaticcaly called

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        //Get a random winner

        //Random number 2 transaction:
        //1) request random number
        //2) get random number

        //We call the requestRandomWords function of the vrfCoordinator contract - l'address del contratto lo passiamo nel costrutore in base alla chain usata
        uint256 requestId = i_vrfCoordinator.requestRandomWords( //COORDINATOR - chainlink VRF coordinator for the request
            i_gasLane, //gas lane (set how much gas I want to spend) - è di tipo bytes32
            i_subscriptionId, //Id che ricarico con i LINK per fare la richiesta
            REQUEST_CONFIRMATIONS, //numero di conferme che voglio. Lo setto costante.
            i_callbackGasLimit, //gas limit
            NUM_WORDS //numero di parole che voglio = numero di random number
        );
        emit RequestedRaffleWinner(requestId);
    }

    //CEI: checks, effects, interactions
    //Ora ci deve essere una funzione che viene chiamata dal coordinatore quando ha generato il numero random
    function fulfillRandomWords(
        uint256 /* _requestId */,
        uint256[] memory randomWords
    ) internal override {
        //Checks
        //require (if --> errors)

        //Effects (our own contract)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        s_recentWinner = s_players[indexOfWinner];
        //Definisco il vincitore come payable address
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        //Reset the players array
        s_players = new address payable[](0);
        //Reset the last timestamp - start the clock over
        s_lastTimeStamp = block.timestamp;

        //L'evento lo emetto prima dell'interazione ad altri contratti
        emit PickedWinner(winner);

        //Interactions (with other contracts)
        //Paga il vincitore
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            //If the transfer fails, revert the transaction
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Function */

    //Returns the entrance fee
    function getEntrancyFee() external view returns (uint256) {
        return i_entranceFee;
    }

    //Returns the raffle state
    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLenghtOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
