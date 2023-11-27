// Sources flattened with hardhat v2.17.1 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev ERC20 token interface.
interface IERC20 {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Gets the total amount of tokens stored by the contract.
    /// @return Amount of tokens.
    function totalSupply() external view returns (uint256);

    /// @dev Gets remaining number of tokens that the `spender` can transfer on behalf of `owner`.
    /// @param owner Token owner.
    /// @param spender Account address that is able to transfer tokens on behalf of the owner.
    /// @return Token amount allowed to be transferred.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @dev Mints tokens.
    /// @param account Account address.
    /// @param amount Token amount.
    function mint(address account, uint256 amount) external;

    /// @dev Burns tokens.
    /// @param amount Token amount to burn.
    function burn(uint256 amount) external;
}


// File lib/fx-portal/contracts/FxChild.sol
// IStateReceiver represents interface to receive state
interface IStateReceiver {
    function onStateReceive(uint256 stateId, bytes calldata data) external;
}

// IFxMessageProcessor represents interface to process message
interface IFxMessageProcessor {
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes calldata data) external;
}

/**
 * @title FxChild child contract for state receiver
 */
contract FxChild is IStateReceiver {
    address public fxRoot;

    event NewFxMessage(address rootMessageSender, address receiver, bytes data);

    function setFxRoot(address _fxRoot) external {
        require(fxRoot == address(0x0));
        fxRoot = _fxRoot;
    }

    function onStateReceive(uint256 stateId, bytes calldata _data) external override {
        require(msg.sender == address(0x0000000000000000000000000000000000001001), "Invalid sender");
        (address rootMessageSender, address receiver, bytes memory data) = abi.decode(_data, (address, address, bytes));
        emit NewFxMessage(rootMessageSender, receiver, data);
        IFxMessageProcessor(receiver).processMessageFromRoot(stateId, rootMessageSender, data);
    }
}


// File lib/fx-portal/contracts/tunnel/FxBaseChildTunnel.sol
// IFxMessageProcessor represents interface to process message

/**
 * @notice Mock child tunnel contract to receive and send message from L2
 */
abstract contract FxBaseChildTunnel is IFxMessageProcessor {
    // MessageTunnel on L1 will get data from this event
    event MessageSent(bytes message);

    // fx child
    address public fxChild;

    // fx root tunnel
    address public fxRootTunnel;

    constructor(address _fxChild) {
        fxChild = _fxChild;
    }

    // Sender must be fxRootTunnel in case of ERC20 tunnel
    modifier validateSender(address sender) {
        require(sender == fxRootTunnel, "FxBaseChildTunnel: INVALID_SENDER_FROM_ROOT");
        _;
    }

    // set fxRootTunnel if not set already
    function setFxRootTunnel(address _fxRootTunnel) external virtual {
        require(fxRootTunnel == address(0x0), "FxBaseChildTunnel: ROOT_TUNNEL_ALREADY_SET");
        fxRootTunnel = _fxRootTunnel;
    }

    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes calldata data) external override {
        require(msg.sender == fxChild, "FxBaseChildTunnel: INVALID_SENDER");
        _processMessageFromRoot(stateId, rootMessageSender, data);
    }

    /**
     * @notice Emit message that can be received on Root Tunnel
     * @dev Call the internal function when need to emit message
     * @param message bytes message that will be sent to Root Tunnel
     * some message examples -
     *   abi.encode(tokenId);
     *   abi.encode(tokenId, tokenMetadata);
     *   abi.encode(messageType, messageData);
     */
    function _sendMessageToRoot(bytes memory message) internal {
        emit MessageSent(message);
    }

    /**
     * @notice Process message received from Root Tunnel
     * @dev function needs to be implemented to handle message as per requirement
     * This is called by onStateReceive function.
     * Since it is called via a system call, any event will not be emitted during its execution.
     * @param stateId unique state id
     * @param sender root message sender
     * @param message bytes message that was sent from Root Tunnel
     */
    function _processMessageFromRoot(uint256 stateId, address sender, bytes memory message) internal virtual;
}


// File contracts/bridges/FxERC20ChildTunnel.sol
/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @title FxERC20ChildTunnel - Smart contract for the L2 token management part
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract FxERC20ChildTunnel is FxBaseChildTunnel {
    event FxDepositERC20(address indexed childToken, address indexed rootToken, address from, address indexed to, uint256 amount);
    event FxWithdrawERC20(address indexed rootToken, address indexed childToken, address from, address indexed to, uint256 amount);

    // Child token address
    address public immutable childToken;
    // Root token address
    address public immutable rootToken;

    /// @dev FxERC20ChildTunnel constructor.
    /// @param _fxChild Fx Child contract address.
    /// @param _childToken L2 token address.
    /// @param _rootToken Corresponding L1 token address.
    constructor(address _fxChild, address _childToken, address _rootToken) FxBaseChildTunnel(_fxChild) {
        // Check for zero addresses
        if (_fxChild == address(0) || _childToken == address(0) || _rootToken == address(0)) {
            revert ZeroAddress();
        }

        childToken = _childToken;
        rootToken = _rootToken;
    }

    /// @dev Deposits tokens on L2 in order to obtain their corresponding bridged version on L1.
    /// @notice Destination address is the same as the sender address.
    /// @param amount Token amount to be deposited.
    function deposit(uint256 amount) external {
        _deposit(msg.sender, amount);
    }

    /// @dev Deposits tokens on L2 in order to obtain their corresponding bridged version on L1 by a specified address.
    /// @param to Destination address on L1.
    /// @param amount Token amount to be deposited.
    function depositTo(address to, uint256 amount) external {
        // Check for the address to deposit tokens to
        if (to == address(0)) {
            revert ZeroAddress();
        }

        _deposit(to, amount);
    }

    /// @dev Receives the token message from L1 and transfers L2 tokens to a specified address.
    /// @param sender FxERC20RootTunnel contract address from L1.
    /// @param message Incoming bridge message.
    function _processMessageFromRoot(
        uint256 /* stateId */,
        address sender,
        bytes memory message
    ) internal override validateSender(sender) {
        // Decode incoming message from root: (address, address, uint96)
        address from;
        address to;
        // The token amount is limited to be no bigger than 2^96 - 1
        uint96 amount;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Offset 20 bytes for the address from (160 bits)
            from := mload(add(message, 20))
            // Offset 20 bytes for the address to (160 bits)
            to := mload(add(message, 40))
            // Offset 12 bytes of amount (96 bits)
            amount := mload(add(message, 52))
        }

        // Transfer decoded amount of tokens to a specified address
        IERC20(childToken).transfer(to, amount);

        emit FxWithdrawERC20(rootToken, childToken, from, to, amount);
    }

    /// @dev Deposits tokens on L2 to get their representation on L1 by a specified address.
    /// @param to Destination address on L1.
    /// @param amount Token amount to be deposited.
    function _deposit(address to, uint256 amount) internal {
        // Check for the non-zero amount
        if (amount == 0) {
            revert ZeroValue();
        }

        // Deposit tokens on an L2 bridge contract (lock)
        IERC20(childToken).transferFrom(msg.sender, address(this), amount);

        // Encode message for root: (address, address, uint96)
        bytes memory message = abi.encodePacked(msg.sender, to, uint96(amount));
        // Send message to root
        _sendMessageToRoot(message);

        emit FxDepositERC20(childToken, rootToken, msg.sender, to, amount);
    }
}
