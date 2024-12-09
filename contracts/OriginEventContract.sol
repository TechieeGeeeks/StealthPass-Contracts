// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BettingGame is ERC721, Ownable {
    struct Bet {
        uint256 amount; // Maximum betting amount
        string hostTwitter; // Host's Twitter handle
        bytes encryptedKey; // Encrypted key
        address host; // Address of the host
        bool active; // Whether the bet is active
        uint256 endTime; // The bet will be closed on this time
        string url;
    }

    struct UsersHistoricalBets {
        uint256 amount;
        address userAddress;
        string emailAddress;
        string twitter;
    }

    address public agentAddress;

    uint256 public betCounter = 0;
    mapping(uint256 => Bet) public bets;
    mapping(uint256 => UsersHistoricalBets[]) public userBets; // Multiple bets per bet ID

    event BetCreated(uint256 betId, uint256 amount, string hostTwitter, address host);
    event BetActivated(uint256 betId, string tokenURI);
    event BetPlaced(uint256 betId, address bettor, string bettorTwitter, string bettorEmail);
    event BetClosed(uint256 betId, address winner, string winnerTwitter, string winnerEmail, uint256 actualAmount);

    modifier onlyAgent() {
        require(msg.sender == agentAddress, "Only the agent can call this function");
        _;
    }

    constructor(address _agentAddress) ERC721("BetNFT", "BFT") Ownable(msg.sender) {
        agentAddress = _agentAddress;
    }

    // Host a new bet
    function hostBet(
        uint256 amount,
        uint256 timeToEnd,
        string memory hostTwitter,
        bytes memory encryptedKey
    ) public payable {
        require(msg.value >= amount, "Insufficient ETH for hosting the bet");
        require(timeToEnd > block.timestamp, "End time must be in the future");

        bets[betCounter] = Bet({
            amount: amount,
            hostTwitter: hostTwitter,
            encryptedKey: encryptedKey,
            host: msg.sender,
            active: false, // Bet is not active until secured
            endTime: timeToEnd,
            url: ""
        });

        emit BetCreated(betCounter, amount, hostTwitter, msg.sender);

        betCounter++;
    }

    // Secure a bet: Mint NFT with URI from the AI agent and activate the bet
    function secureBet(uint256 betId, string memory tokenURI) external onlyOwner {
        Bet storage bet = bets[betId];
        require(!bet.active, "Bet is already active");

        // Mint NFT to the contract address to ensure ownership
        _safeMint(address(this), betId);

        bet.active = true;
        bet.url = tokenURI;

        emit BetActivated(betId, tokenURI);
    }

    // Place a bet
    function placeBet(uint256 betId, string memory bettorTwitter, string memory bettorEmail) public payable {
        Bet storage bet = bets[betId];
        require(bet.active, "Bet is not active");
        require(msg.value > 0, "Must place a bet with ETH");
        require(block.timestamp < bet.endTime, "Betting time has expired");

        userBets[betId].push(
            UsersHistoricalBets({
                amount: msg.value,
                userAddress: msg.sender,
                emailAddress: bettorEmail,
                twitter: bettorTwitter
            })
        );

        emit BetPlaced(betId, msg.sender, bettorTwitter, bettorEmail);
    }

    // Close the bet when the agent provides the actual amount
    function closeBetWhenTimeEnds(uint256 betId, uint256 actualAmount) public onlyAgent {
        Bet storage bet = bets[betId];
        require(bet.active, "Bet is already closed or inactive");
        require(block.timestamp >= bet.endTime, "Betting period is not over");

        // Determine the winner with the closest bet
        address winner;
        string memory winnerTwitter;
        string memory winnerEmail;
        uint256 closestDifference = type(uint256).max;

        for (uint256 i = 0; i < userBets[betId].length; i++) {
            UsersHistoricalBets memory userBet = userBets[betId][i];
            uint256 difference = actualAmount > userBet.amount
                ? actualAmount - userBet.amount
                : userBet.amount - actualAmount;

            if (difference < closestDifference) {
                closestDifference = difference;
                winner = userBet.userAddress;
                winnerTwitter = userBet.twitter;
                winnerEmail = userBet.emailAddress;
            }
        }

        require(winner != address(0), "No valid bets placed");

        bet.active = false;

        // Transfer NFT to the winner
        safeTransferFrom(address(this), winner, betId);
        payable(winner).transfer(bet.amount);

        // Calculate and distribute funds
        uint256 totalFunds = address(this).balance;
        uint256 platformFee = (totalFunds * 10) / 100;
        uint256 profit = totalFunds - bet.amount - platformFee;

        if (profit > 0) {
            payable(bet.host).transfer(profit);
        }

        payable(owner()).transfer(platformFee);

        emit BetClosed(betId, winner, winnerTwitter, winnerEmail, actualAmount);
    }
}
