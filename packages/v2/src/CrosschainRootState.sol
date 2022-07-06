// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

/// @title Crosschain Root State
/// @author Chainvisions
/// @notice Contract for storing chain merkle roots.

contract CrosschainRootState {

    /// @notice Structure for storing root data.
    struct Root {
        bytes32 root;
        uint256 lastUpdate;
    }

    /// @notice Keepers responsible for posting roots.
    mapping(address => bool) public keeper;

    /// @notice Roots for each chain.
    mapping(uint256 => Root) public rootForChain;

    /// @notice Emitted when the root of a chain is updated.
    event RootUpdated(uint256 indexed chainId, bytes32 newRoot);

    constructor() {
        keeper[msg.sender] = true;
    }

    /// @notice Posts a new root for a chain.
    /// @param _chainId Chain ID of the chain to post the root of.
    /// @param _root Root of the chain to post.
    function postRootForChain(uint256 _chainId, bytes32 _root) external {
        require(keeper[msg.sender], "Must be a keeper");
        rootForChain[_chainId] = Root(_root, block.timestamp);
        emit RootUpdated(_chainId, _root);
    }
}