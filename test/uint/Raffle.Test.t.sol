// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

//Configuara tutte le reti
contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    //Crea un player per il test
    address public PLAYER = makeAddr("player");
    //Assegna un balance al player
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    /** Events */
    //Nei test devo ridefinire gli eventi perchè non posso importarli dal contratto come le struct e gli enum
    event EnteredRaffle(address indexed player);

    //Creo il deploy del contratto Raffle
    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        //Diamo dei soldi al player
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    ////////
    //Enter Raffle
    ////////
    function testRaffleRevertsWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act - Assert
        vm.expectRevert(Raffle.Raffle__notEnoughtETHSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventsOnEntrance() public {
        vm.prank(PLAYER);
        //Usiamo expectEmits per verificare che vengano emessi gli eventi
        vm.expectEmit(true, false, false, false, address(raffle));
        //Ora dobbiamo emettere l'evento EnteredRaffle a mano
        emit EnteredRaffle(PLAYER);
        //Ora dobbiamo aggiungere la condizione che emette l'evento
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenTheRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //Setta il timestamp in modo che la raffle sia in stato CALCULATING
        vm.warp(block.timestamp + interval + 1);
        //Setta il block number in modo che la raffle sia in stato CALCULATING
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ///////////////
    /// Check Upkeep
    ///////////////
    function testCheckUpkeepReturnsFalseIfHasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //Act
        (bool updatedNeeded, ) = raffle.checkUpKeep("");
        //Assert
        assert(!updatedNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen() public {
        //Arrane - va nel calculating state
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //Setta il timestamp in modo che la raffle sia in stato CALCULATING
        vm.warp(block.timestamp + interval + 1);
        //Setta il block number in modo che la raffle sia in stato CALCULATING
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        //Act
        (bool updatedNeeded, ) = raffle.checkUpKeep("");
        //Assert
        assert(updatedNeeded == false);
    }

    function testCheckUpkeepReturnFalseIfEnoughTimeIsPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.roll(block.number + 1);
        (bool updatedNeeded, ) = raffle.checkUpKeep("");
        //Assert
        assert(!updatedNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //Setta il timestamp in modo che la raffle sia in stato CALCULATING
        vm.warp(block.timestamp + interval + 1);
        //Setta il block number in modo che la raffle sia in stato CALCULATING
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        //Act
        (bool updatedNeeded, ) = raffle.checkUpKeep("");
        //Assert
        assert(updatedNeeded = true);
    }

    ///////////////
    /// Perform Upkeep
    ///////////////
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //Act - Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;
        //Act - Assert
        //We experct that the next function reverts with these paramenters
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpKeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier RaffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        RaffleEnteredAndTimePassed
    {
        //Act
        //Salva tutti i logs che possiamo vedere nella struct con getRecordLogs
        vm.recordLogs();
        raffle.performUpkeep(""); //Emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //tipo speciale fornito da foundry, all the events emitted
        bytes32 requestId = entries[1].topics[1]; //entries[0] sarebbe l'evento emesso da vfrCoordinatoi, il nostro è il numero. topic[0] si riferisce a tutto l'evento emesso

        Raffle.RaffleState rState = raffle.getRaffleState();
        assert(uint256(requestId) > 0); //così siamo sicuri che l'evento sia stato emesso
        assert(uint256(rState) == 1); //così siamo sicuri che lo stato sia stato aggiornato
    }

    /////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public RaffleEnteredAndTimePassed skipFork {
        // Arrange
        // Act / Assert
        vm.expectRevert("nonexistent request");
        // vm.mockCall could be used here...
        //Devo provare tutti i casi di requestId quindi uso un fuzz test - passo randomRequestId nella funzione
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        RaffleEnteredAndTimePassed
    {
        //Arrange
        uint256 additionalEntrance = 5; //vogliamo ulteriori 5 giocatori
        uint256 startingIndexing = 1; //Abbiamo un giocatore già registrato

        //Creo un loop per creare i giocatori e farli accedere alla raffle
        for (
            uint256 i = startingIndexing;
            i < startingIndexing + additionalEntrance;
            i++
        ) {
            //Creo gli address
            address player = address(uint160(i)); //equivalente a address(i)
            //Gli do degli ether
            hoax(player, STARTING_USER_BALANCE);
            //Lo faccio entrare nella raffle
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrance + 1);

        vm.recordLogs();
        raffle.performUpkeep(""); //Emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //tipo speciale fornito da foundry, all the events emitted
        bytes32 requestId = entries[1].topics[1]; //entries[0] sarebbe l'evento emesso da vfrCoordinatoi, il nostro è il numero. topic[0] si riferisce a tutto l'evento emesso

        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        //Vogliamo essere VRF Chainlink to get the number & pick the winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //Assert
        assert(uint256(raffle.getRaffleState()) == 0); //La raffle è in stato OPEN
        assert(raffle.getRecentWinner() != address(0)); //Abbiamo un vincitore
        assert(raffle.getLenghtOfPlayers() == 0); //Resettiamo la lista dei vincitori
        assert(previousTimeStamp < raffle.getLastTimeStamp()); //Aggiorniamo il timestamp

        //Verifico che vengano mandati i soldi al vincitore
        console.log(raffle.getRecentWinner().balance);
        console.log(STARTING_USER_BALANCE + prize);
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        );
    }
}
