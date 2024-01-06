// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "solmate/tokens/ERC20.sol";
import "solmate/auth/Owned.sol";

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract LinkInu is ERC20, Owned, CCIPReceiver {
    address public ccipRouter;
    bytes public ccipExtraArgs;

    mapping(uint64 => bool) public supportedChainSelectors;

    event BridgeStart(
        uint64 destinationChainSelector,
        address sender,
        address receiver,
        uint256 amount,
        bytes32 messageId
    );

    event BridgeEnd(
        uint64 sourceChainSelector,
        address sender,
        address receiver,
        uint256 amount,
        bytes32 messageId
    );

    struct BridgeData {
        address sender;
        address receiver;
        uint256 amount;
    }

    constructor(
        address router
    ) ERC20("Link Inu", "LINKU", 18) Owned(msg.sender) CCIPReceiver(router) {
        ccipRouter = router;
        _mint(msg.sender, 69_420_000_000 * 1e18);
    }

    function setSupportedChainSelector(
        uint64 chainSelector,
        bool supported
    ) external onlyOwner {
        supportedChainSelectors[chainSelector] = supported;
    }

    function setExtraArgs(bytes calldata extraArgs) external onlyOwner {
        ccipExtraArgs = extraArgs;
    }

    function bridge(
        uint64 destinationChainSelector,
        uint256 amount,
        address receiver
    ) external payable {
        require(
            supportedChainSelectors[destinationChainSelector],
            "Unsupported chain selector"
        );

        BridgeData memory bridgeData = BridgeData({
            sender: msg.sender,
            receiver: receiver,
            amount: amount
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(bridgeData),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: ccipExtraArgs,
            feeToken: address(0)
        });

        uint256 fee = IRouterClient(ccipRouter).getFee(
            destinationChainSelector,
            message
        );

        bytes32 messageId = IRouterClient(ccipRouter).ccipSend{value: fee}(
            destinationChainSelector,
            message
        );

        _burn(msg.sender, amount);

        emit BridgeStart(
            destinationChainSelector,
            msg.sender,
            receiver,
            amount,
            messageId
        );
    }

    function estimateBridgeFee(
        uint64 destinationChainSelector,
        uint256 amount,
        address receiver
    ) external view returns (uint256) {
        BridgeData memory bridgeData = BridgeData({
            sender: msg.sender,
            receiver: receiver,
            amount: amount
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(bridgeData),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: ccipExtraArgs,
            feeToken: address(0)
        });

        return
            IRouterClient(ccipRouter).getFee(destinationChainSelector, message);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        require(
            abi.decode(message.sender, (address)) == address(this),
            "Invalid sender"
        );

        require(
            supportedChainSelectors[message.sourceChainSelector],
            "Unsupported chain selector"
        );

        BridgeData memory bridgeData = abi.decode(message.data, (BridgeData));

        _mint(bridgeData.receiver, bridgeData.amount);

        emit BridgeEnd(
            message.sourceChainSelector,
            bridgeData.sender,
            bridgeData.receiver,
            bridgeData.amount,
            message.messageId
        );
    }
}
