// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/gateway/GatewayCaller.sol";

contract IncoEventContract is GatewayCaller, Ownable {
    /**
     * We are using tokenKeys so that any contract from any chain can call this contract and we would be able to generate a deterministic key using tokenId, origin chain ID, and event contract address.
     */

    // To have a proper struct
    struct requestIdStruct {
        uint256 originChain;
        address eventContractAddress;
    }

    eaddress private sampleEaddress;

    function formEaddress(einput _eaddressInput, bytes calldata inputProof) external {
        sampleEaddress = TFHE.asEaddress(_eaddressInput, inputProof);
        TFHE.allow(sampleEaddress, address(this));
        TFHE.allow(sampleEaddress, msg.sender);
    }

    function returnAEaddress() external view returns (eaddress) {
        return sampleEaddress;
    }

    // tokenKey to eAddress to the amount to check the amount for the user
    mapping(bytes32 => mapping(eaddress => uint256)) public tokenKeyToEaddressToAmount;

    // tokenKey to holder address to verify for both user and owner
    mapping(bytes32 => eaddress) public tokenKeyToEaddress;

    // tokenKey to how much amount of tickets a person holds
    mapping(bytes32 => uint256) public tokenKeyToAmount;

    // tokenKey counter for origin chain to event contract address to tokenId
    mapping(uint256 => mapping(address => uint256)) public tokenKeyCounter;

    // tokenKey winner for origin chain to event contract address to winner Token ID
    mapping(uint256 => mapping(address => uint256)) public tokenKeyWinner;

    // mapping to store the temp data for requestIds
    mapping(uint256 => requestIdStruct) public requestIdToStruct;

    // Mailbox
    IMailbox public mailbox;

    constructor(address _mailBoxAddress) Ownable(msg.sender) {
        mailbox = IMailbox(_mailBoxAddress);
    }

    // Event emitted when a token purchase is processed
    event TokenProcessed(address indexed buyer, uint256 indexed tokenId, eaddress holderAddress, uint256 amount);

    /**
     * @notice Only accept messages from a Hyperlane Mailbox contract
     */
    modifier onlyMailbox() {
        require(msg.sender == address(mailbox), "MailboxClient: sender not mailbox");
        _;
    }

    // This function receives the call from Hyperlane
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _data) external payable onlyMailbox {
        (address buyer, uint256 tokenId, bytes32 actualEInput, bytes memory inputProof, uint256 amount) = abi.decode(
            _data,
            (address, uint256, bytes32, bytes, uint256)
        );
        processMessage(_origin, bytes32ToAddress(_sender), buyer, tokenId, actualEInput, inputProof, amount);
    }

    /**
     * @dev Process messages from Hyperlane call.
     */
    function processMessage(
        uint32 chainId,
        address senderContract,
        address buyer,
        uint256 tokenId,
        bytes32 einputForAddress,
        bytes memory inputProof,
        uint256 amount
    ) internal {
        // Get deterministic key using values
        bytes32 tokenKey = getDeterministicKey(uint256(chainId), senderContract, tokenId);
        // Derive eaddress
        einput actualEInput = einput.wrap(einputForAddress);
        eaddress holderAddress = TFHE.asEaddress(actualEInput, inputProof);

        // Map tokenId to eaddress and amount
        tokenKeyToEaddressToAmount[tokenKey][holderAddress] = amount;
        tokenKeyToEaddress[tokenKey] = holderAddress;
        tokenKeyToAmount[tokenKey] = amount;

        // Allow relevant entities
        TFHE.allow(tokenKeyToEaddress[tokenKey], address(this));
        TFHE.allow(tokenKeyToEaddress[tokenKey], owner());
        TFHE.allow(tokenKeyToEaddress[tokenKey], address(0x34cEe9BE72304dbc09825Fc9014B0103aF50a473));
        TFHE.allow(tokenKeyToEaddress[tokenKey], address(0xb5d98956435e49952820051280061628579C6E0A));

        // Increment counter
        tokenKeyCounter[chainId][senderContract]++;

        // Emit processing event
        emit TokenProcessed(buyer, tokenId, holderAddress, amount);
    }

    /**
     * @dev Generates a deterministic key using keccak256 based on chainId, sender address, and tokenId.
     * @param chainId The ID of the source chain.
     * @param senderContract The address of the sending contract.
     * @param tokenId The token ID to include in the hash.
     * @return The deterministic hash (key).
     */
    function getDeterministicKey(
        uint256 chainId,
        address senderContract,
        uint256 tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(chainId, senderContract, tokenId));
    }

    /**
     * @dev Reads the total number of tickets a user holds for a specific tokenKey.
     * @param chainId The ID of the source chain.
     * @param eventContract The address of the event contract.
     * @param userAddress The user's address.
     * @return The total number of tickets the user holds.
     */
    function readUsersTotalTickets(
        uint256 chainId,
        address eventContract,
        address userAddress
    ) external view returns (uint256) {
        // Generate the deterministic key
        bytes32 tokenKey = getDeterministicKey(chainId, eventContract, uint256(uint160(userAddress)));
        // Return the total tickets
        return tokenKeyToAmount[tokenKey];
    }

    /**
     * @dev Returns the eaddress associated with a tokenKey.
     * @param chainId The ID of the source chain.
     * @param eventContract The address of the event contract.
     * @return The eaddress associated with the tokenKey.
     */
    function returnEaddress(uint256 chainId, address eventContract) external view returns (eaddress) {
        // Generate the deterministic key
        bytes32 tokenKey = getDeterministicKey(chainId, eventContract, uint256(uint160(msg.sender)));
        // Return the associated eaddress
        return tokenKeyToEaddress[tokenKey];
    }

    function getEaddressForTicket(bytes32 _tokeKey) external view returns (eaddress) {
        return tokenKeyToEaddress[_tokeKey];
    }

    // when user buys ticket he puts his mail and we also have access to chainId, TokenId, contractAddress -> we use that chainID, tokenContract address and tokenId to generate a bytes32 key using getDeterministicKey() => then it embedds in QR code www.ourapp/key this is in qr code
    // verifier checks QR code gets navigated to dapp link gets has a button to sign
    // dapp link has sign message which does reencrypt to verify the key and get Eaddress

    /**
     * @dev Generates a random winner for a raffle.
     */
    function getRandomWinner(uint256 chainId, address tokenContractAddress) external {
        euint32 encryptedRandomNumber = TFHE.randEuint32();
        TFHE.allow(encryptedRandomNumber, address(this));
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(encryptedRandomNumber);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.myCustomCallback.selector,
            0,
            block.timestamp + 100,
            false
        );
        requestIdToStruct[requestId] = requestIdStruct({
            originChain: chainId,
            eventContractAddress: tokenContractAddress
        });
    }

    function myCustomCallback(uint256 requestId, uint32 randomNumber) public onlyGateway returns (bool) {
        requestIdStruct memory _struct = requestIdToStruct[requestId];
        uint256 winningTokenId = randomNumber % tokenKeyCounter[_struct.originChain][_struct.eventContractAddress];
        tokenKeyWinner[_struct.originChain][_struct.eventContractAddress] = winningTokenId;
        // Make Hyperlane call
        return true;
    }

    // Alignment preserving cast
    function bytes32ToAddress(bytes32 _buf) internal pure returns (address) {
        return address(uint160(uint256(_buf)));
    }

    // Alignment preserving cast
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function setInterchainSecurityModule()
        public
        onlyContractOrNull(0xBa045a7dB294ED800CEDe4F1d0a8De47CC5c4c95)
        onlyOwner
    {
        interchainSecurityModule = IInterchainSecurityModule(0xBa045a7dB294ED800CEDe4F1d0a8De47CC5c4c95);
    }

    modifier onlyContractOrNull(address _contract) {
        require(_contract == address(0), "MailboxClient: invalid contract setting");
        _;
    }

    IInterchainSecurityModule public interchainSecurityModule;
}

interface IInterchainSecurityModule {
    enum Types {
        UNUSED,
        ROUTING,
        AGGREGATION,
        LEGACY_MULTISIG,
        MERKLE_ROOT_MULTISIG,
        MESSAGE_ID_MULTISIG,
        NULL, // used with relayer carrying no metadata
        CCIP_READ,
        ARB_L2_TO_L1,
        WEIGHTED_MERKLE_ROOT_MULTISIG,
        WEIGHTED_MESSAGE_ID_MULTISIG,
        OP_L2_TO_L1
    }

    /**
     * @notice Returns an enum that represents the type of security model
     * encoded by this ISM.
     * @dev Relayers infer how to fetch and format metadata.
     */
    function moduleType() external view returns (uint8);

    /**
     * @notice Defines a security model responsible for verifying interchain
     * messages based on the provided metadata.
     * @param _metadata Off-chain metadata provided by a relayer, specific to
     * the security model encoded by the module (e.g. validator signatures)
     * @param _message Hyperlane encoded interchain message
     * @return True if the message was verified
     */
    function verify(bytes calldata _metadata, bytes calldata _message) external returns (bool);
}

interface ISpecifiesInterchainSecurityModule {
    function interchainSecurityModule() external view returns (IInterchainSecurityModule);
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
    event Dispatch(address indexed sender, uint32 indexed destination, bytes32 indexed recipient, bytes message);

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
    event Process(uint32 indexed origin, bytes32 indexed sender, address indexed recipient);

    function localDomain() external view returns (uint32);

    function delivered(bytes32 messageId) external view returns (bool);

    function defaultIsm() external view returns (IInterchainSecurityModule);

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

    function process(bytes calldata metadata, bytes calldata message) external payable;

    function recipientIsm(address recipient) external view returns (IInterchainSecurityModule module);
}
