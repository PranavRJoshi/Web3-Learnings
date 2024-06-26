// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

// Before we start coding, we need to figure out what the contracts will do
// Enter the lottery (pay some amount)
// Pick a random winner (verifiably random)
// Winner to be selected every X minutes ---> completely automated
// Chainlink Oracle ---> Randomness, Automated execution (Chainlink keepers)

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

error Raffle__NotEnoughETHEntered();
error Raffle__TransferredFailed();
error Raffle__NotOpen();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

/** @title A sample Raffle / Lottery contract
  * @author MONKE
  * @notice This contract is for creating an untamperable decentralized smart contract
  * @dev This contract implements Chainlink VRF v2 and Chainlink Automation
  */

contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
	/* Type Declarations */
	enum RaffleState { OPEN, CALCULATING }

	/* State Variables */
	uint256 private immutable i_entranceFee;
	address payable[] private s_players; // These addresses are made payable as one of them will eventually win the raffle and the money is transferred to their account
	bytes32 private immutable i_gasLane;
	uint64 private immutable i_subscriptionId;
	uint32 private immutable i_callbackGasLimit;
	uint16 private constant REQUEST_CONFIRMATIONS = 3;	
	uint32 private constant NUM_WORDS = 1;
	
	/* Lottery/Raffle Variables */
	address private s_recentWinner;
	RaffleState private s_raffleState;
	uint256 private s_lastTimeStamp;
	uint256 private immutable i_interval;

	VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
	
	constructor(address vrfCoordinatorV2, uint256 entranceFee, bytes32 gasLane, uint64 subscriptionId, uint32 callbackGasLimit, uint256 interval) VRFConsumerBaseV2(vrfCoordinatorV2) {
		i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
		i_entranceFee = entranceFee;
		i_gasLane = gasLane;
		i_subscriptionId = subscriptionId;
		i_callbackGasLimit = callbackGasLimit;
		s_raffleState = RaffleState.OPEN;
		s_lastTimeStamp = block.timestamp;
		i_interval = interval;
	}

	event RaffleEnter(address indexed player);
	event RequestedRaffleWinner(uint256 indexed requestId);
	event WinnerPicked(address indexed winner);

	/* Functions */
	function enterLottery() public payable{
		// one pre-requisite to enter the waffle is
		// to have msg.value >= entranceFee
		if (msg.value < i_entranceFee) {
			revert Raffle__NotEnoughETHEntered();
		} if (s_raffleState != RaffleState.OPEN) {
			revert Raffle__NotOpen();
		}
		s_players.push(payable(msg.sender));
		// just having msg.sender will not work as the declaration of s_players
		// is an array of addresses that are payable, hence we typecast it
		emit RaffleEnter(msg.sender);
		
	}
	
	/**
	* @dev This is the function that the Chainlink keeper/automation nodes call
	* they look for the `upkeepNeeded` to return true
	* The following should be true in order to return true
	* 1. Our time interval should have passed
	* 2. The lottery should have at least 1 player, and have some ETH
	* 3. Our subscription is funded with LINK
	* 4. The lottery should be in an "open" state
	*/
	function checkUpkeep(bytes memory /*checkData*/) public view override returns (bool upkeepNeeded, bytes memory /* performData */) {
		bool isOpen = (RaffleState.OPEN == s_raffleState);
		bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
		bool hasPlayers = (s_players.length > 0);
		bool hasBalance = address(this).balance > 0;
		
		upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
	}

	function performUpkeep(bytes calldata /* performData */) external {
		(bool upkeepNeeded, ) = checkUpkeep("");
		if (!upkeepNeeded) {
			revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
		}	
		// previously called the requestRandomWinner() function
		// To pick a random winner
		// we first need to request the random number
		// once we get it, we need to do something with it 
		// overall, it is a two step process
		s_raffleState = RaffleState.CALCULATING;
		uint256 requestId = i_vrfCoordinator.requestRandomWords(
			i_gasLane,
            		i_subscriptionId,
            		REQUEST_CONFIRMATIONS,
			i_callbackGasLimit,
            		NUM_WORDS
		);
		emit RequestedRaffleWinner(requestId);
	}

	function fulfillRandomWords(uint256 /*requestId*/, uint256[] memory randomWords) internal override {
		// This is the modulo operation used to determine the winner
		uint256 indexOfWinner = randomWords[0] % s_players.length;
		address payable recentWinner = s_players[indexOfWinner];
		s_recentWinner = recentWinner;
		s_raffleState = RaffleState.OPEN;
		s_lastTimeStamp = block.timestamp;
		s_players = new address payable[](0);
		// sending the balance collected in the contract to the winner
		(bool success, ) = recentWinner.call{ value: address(this).balance }("");
		if (!success) {
			revert Raffle__TransferredFailed();
		}
		emit WinnerPicked(recentWinner);
	}	

	/* View and Pure functions */
	function getEntranceFee() public view returns (uint256) {
		return i_entranceFee;
	}
	
	function getPlayer(uint256 index) public view returns (address) {
		return s_players[index];
	}

	function getRecentWinner() public view returns (address) {
		return s_recentWinner;
	}
	
	function getRaffleState() public view returns (RaffleState) {
		return s_raffleState;
	}

	function getNumWords() public pure returns (uint256) {
		return NUM_WORDS; // since the data of NUM_WORDS is not stored in storage but rather in the bytecode itself, it need not be declared view
	}

	function getNumberOfPlayers() public view returns (uint256) {
		return s_players.length;
	}

	function getLatestTimeStamp() public view returns (uint256) {
		return s_lastTimeStamp;
	}

	function getRequestConfirmations() public pure returns (uint256) {
		return REQUEST_CONFIRMATIONS;
	}

	function getInterval() public view returns (uint256) {
		return i_interval;
	}
}
