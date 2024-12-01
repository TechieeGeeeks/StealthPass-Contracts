// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OriginEventContract is Ownable {
    
    uint256 public tokenId;
    address public paymentToken; // Address of USDC or other accepted currency
    IMailbox public mailBox; // Hyperlane message router
    address public incoContractAddress;
    uint32 public constant incoDomain = 21097; // Destination chain domain
    string public tokenUri;
    uint256 public raffleAmount; // Amount reserved for raffle
    uint256 public cost;

    struct TokenPurchase {
        bytes32 actualEInput; // Encrypted input provided by the user
        uint256 amount; // Amount of tokens purchased
    }

    // tokenId => actualEInput => amount
    mapping(uint256 => mapping(bytes32 => uint256))
        public tokenIdToAddressToAmount;
    mapping(uint256 => uint256) public tokenIdToToAmount;

    function setIncoContract(address _newIncoContractAddress) external{
        incoContractAddress = _newIncoContractAddress;
    }

    event TokenPurchased(
        address indexed buyer,
        uint256 indexed tokenId,
        bytes32 actualEInput,
        bytes inputProof,
        uint256 amount
    );

    constructor(
        address _paymentToken,
        address _mailBoxAddress,
        uint256 _raffleAmount,
        address _incoContractAddress,
        uint256 _cost
    ) Ownable(msg.sender) {
        paymentToken = _paymentToken;
        mailBox = IMailbox(_mailBoxAddress);
        tokenUri = "uri";
        raffleAmount = _raffleAmount; // Initialize the raffle amount
        incoContractAddress = _incoContractAddress;
        cost = _cost;
    }

    /**
     * @dev User purchases a token by providing an encrypted input and proof.
     */
    function purchaseToken(
        bytes32 actualEInput,
        bytes memory inputProof,
        uint256 amount
    ) external payable {
        // Verify user has given approval and sufficient balance
        require(
            IERC20(paymentToken).allowance(msg.sender, address(this)) >= cost * amount,
            "Insufficient allowance"
        );

        // Transfer payment tokens from the user to the contract
        IERC20(paymentToken).transferFrom(msg.sender, address(this), cost * amount);

        // Store actualEInput in mapping
        tokenIdToAddressToAmount[tokenId][actualEInput] = amount;

        // Emit purchase event
        emit TokenPurchased(
            msg.sender,
            tokenId,
            actualEInput,
            inputProof,
            amount
        );
        tokenId++;

        // Prepare message for Hyperlane
        bytes memory message = abi.encode(
            msg.sender,
            tokenId,
            actualEInput,
            inputProof,
            amount
        );

        // Send message to Inco chain
        uint256 fee = mailBox.quoteDispatch(
            incoDomain,
            addressToBytes32(incoContractAddress),
            message
        );
        mailBox.dispatch{value: fee}(
            incoDomain,
            addressToBytes32(incoContractAddress),
            message
        );
    }

    /**
     * @dev Allows the owner to update the raffle amount.
     * @param newRaffleAmount The new amount reserved for the raffle.
     */
    function updateRaffleAmount(uint256 newRaffleAmount) external onlyOwner {
        raffleAmount = newRaffleAmount;
    }

    // alignment preserving cast
    function bytes32ToAddress(bytes32 _buf) internal pure returns (address) {
        return address(uint160(uint256(_buf)));
    }

    // alignment preserving cast
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}

interface IMailbox {
    // ============ Events ============
    /**
     * @notice Emitted when a new message is dispatched via Hyperlane
     * @param sender The address that dispatched the message
     * @param destination The destination domain of the message
     * @param recipient The message recipient address on `destination`
     * @param message Raw bytes of message
     */
    event Dispatch(
        address indexed sender,
        uint32 indexed destination,
        bytes32 indexed recipient,
        bytes message
    );

    /**
     * @notice Emitted when a new message is dispatched via Hyperlane
     * @param messageId The unique message identifier
     */
    event DispatchId(bytes32 indexed messageId);

    /**
     * @notice Emitted when a Hyperlane message is processed
     * @param messageId The unique message identifier
     */
    event ProcessId(bytes32 indexed messageId);

    /**
     * @notice Emitted when a Hyperlane message is delivered
     * @param origin The origin domain of the message
     * @param sender The message sender address on `origin`
     * @param recipient The address that handled the message
     */
    event Process(
        uint32 indexed origin,
        bytes32 indexed sender,
        address indexed recipient
    );

    function localDomain() external view returns (uint32);

    function delivered(bytes32 messageId) external view returns (bool);

    function latestDispatchedId() external view returns (bytes32);

    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external payable returns (bytes32 messageId);

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external view returns (uint256 fee);

    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata body,
        bytes calldata defaultHookMetadata
    ) external payable returns (bytes32 messageId);

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata defaultHookMetadata
    ) external view returns (uint256 fee);

    function process(bytes calldata metadata, bytes calldata message)
        external
        payable;
}
