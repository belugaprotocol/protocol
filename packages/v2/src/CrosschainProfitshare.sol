// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";
import {Cast} from "./lib/Cast.sol";
import {CrosschainRootState} from "./CrosschainRootState.sol";

/// @title Crosschain Profitshare
/// @author Chainvisions
/// @notice Crosschain profitsharing vault for BELUGA staking.

contract CrosschainProfitshare {
    using Cast for uint256;
    using SafeTransferLib for IERC20;

    /// @notice Structure for storing balances.
    struct Balance {
        uint128 nativeStake;    // Amount of BELUGA staked on the current chain.
        uint128 appendedStake;  // Amount of BELUGA staked from other chains.
    }

    /// @notice BELUGA token contract.
    IERC20 public immutable BELUGA_TOKEN;

    /// @notice CrosschainRootState contract for fetching merkle roots.
    CrosschainRootState public immutable ROOT_STATE;

    /// @notice User balances.
    mapping(address => Balance) public balance;

    /// @notice Emitted on a cross-chain deposit.
    /// @param depositor Profitshare depositor
    /// @param sourceChain Chain ID from where the deposit was relayed from
    /// @param sourceRoot Merkle root of the source chain for verifying the deposit.
    /// @param proof Merkle proof supplied by the depositor for relaying
    /// @param amount Amount of tokens deposited by the depositor
    event CrosschainDeposit(
        address indexed depositor,
        uint256 sourceChain,
        bytes32 sourceRoot,
        bytes32[] proof,
        uint256 amount
    );

    /// @notice Emitted on a cross-chain withdrawal.
    /// @param depositor Profitshare depositor
    /// @param sourceChain Chain ID from where the withdrawal was relayed from
    /// @param sourceRoot Merkle root of the source chain for verifying the withdrawal.
    /// @param proof Merkle proof supplied by the depositor for relaying
    /// @param amount Amount of tokens withdrawn by the depositor.
    event CrosschainWithdrawal(
        address indexed depositor,
        uint256 sourceChain,
        bytes32 sourceRoot,
        bytes32[] proof,
        uint256 amount
    );

    constructor(IERC20 _beluga, CrosschainRootState _rootState) {
        BELUGA_TOKEN = _beluga;
        ROOT_STATE = _rootState;
    }

    /// @notice Deposits tokens into the profitshare.
    /// @param _proof Merkle proof supplied for relaying.
    /// @param _amount Amount of tokens to deposit.
    function deposit(bytes32[] calldata _proof, uint256 _amount) external {
        // TODO: Update rewards.
        balance[msg.sender].nativeStake += _amount.u128();

        // Transfer BELUGA tokens and emit relay request.
        BELUGA_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        (bytes32 root, ) = ROOT_STATE.rootForChain(block.chainid);
        emit CrosschainDeposit(msg.sender, block.chainid, root, _proof, _amount);
    }
    
    /// @notice Withdraws tokens from the profitshare.
    /// @param _proof Merkle proof supplied for relaying.
    /// @param _amount Amount of tokens to withdraw.
    function withdraw(bytes32[] calldata _proof, uint256 _amount) external {
        Balance memory _balance = balance[msg.sender];
        require(_amount <= _balance.nativeStake, "Cannot withdraw over stake");

        // Update stake.
        _balance.nativeStake -= _amount.u128();
        balance[msg.sender] = _balance;

        // Transfer tokens and emit relay request.
        BELUGA_TOKEN.safeTransfer(msg.sender, _amount);
        (bytes32 root, ) = ROOT_STATE.rootForChain(block.chainid);
        emit CrosschainWithdrawal(msg.sender, block.chainid, root, _proof, _amount);
    }

    /// @notice Relays a deposit from another chain onto the current.
    /// @param _depositor Depositor to append the deposit to.
    /// @param _sourceChain Chain ID from where the deposit was relayed from.
    /// @param _sourceRoot Merkle root of the source chain for verifying the deposit.
    /// @param _proof Merkle proof for verifying the deposit.
    /// @param _amount Amount of tokens deposited.
    function appendCrosschainDeposit(
        address _depositor,
        uint256 _sourceChain,
        bytes32 _sourceRoot,
        bytes32[] calldata _proof,
        uint256 _amount
    ) external {
        balance[_depositor].appendedStake += _amount.u128();
    }

    /// @notice Relays a withdrawal from another chain onto the current.
    /// @param _depositor Depositor to append the withdrawal to.
    /// @param _sourceChain Chain ID from where the withdrawal was relayed from.
    /// @param _sourceRoot Merkle root of the source chain for verifying the deposit.
    /// @param _proof Merkle proof for verifying the withdrawal.
    /// @param _amount Amount of tokens withdrawn.
    function appendCrosschainWithdrawal(
        address _depositor,
        uint256 _sourceChain,
        bytes32 _sourceRoot,
        bytes32[] calldata _proof,
        uint256 _amount
    ) external {
        balance[_depositor].appendedStake -= _amount.u128();
    }
}