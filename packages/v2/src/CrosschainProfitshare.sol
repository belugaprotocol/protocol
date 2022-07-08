// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";
import {Cast} from "./lib/Cast.sol";
import {CrosschainRootState} from "./CrosschainRootState.sol";

/// @title Crosschain Profitshare
/// @author Chainvisions
/// @notice Crosschain profitsharing vault for BELUGA staking.

contract CrosschainProfitshare {
    using Cast for uint256;
    using SafeMath for uint256;
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

    /// @notice Total tokens staked in the profitshare.
    uint256 public totalSupply;

    /// @notice User balances.
    mapping(address => Balance) public balance;

    /// @notice Reward tokens rewarded by the vault.
    IERC20[] private _rewardTokens;

    /// @notice Addresses permitted to inject rewards into the vault.
    mapping(address => bool) public rewardDistribution;

    /// @notice Reward duration for a specific reward token.
    mapping(IERC20 => uint256) public durationForToken;

    /// @notice Time when rewards for a specific reward token ends.
    mapping(IERC20 => uint256) public periodFinishForToken;

    /// @notice The amount of rewards distributed per second for a specific reward token.
    mapping(IERC20 => uint256) public rewardRateForToken;

    /// @notice The last time reward variables updated for a specific reward token.
    mapping(IERC20 => uint256) public lastUpdateTimeForToken;

    /// @notice Stored rewards per bToken for a specific reward token.
    mapping(IERC20 => uint256) public rewardPerTokenStoredForToken;

    /// @notice The amount of rewards per bToken of a specific reward token paid to the user.
    mapping(IERC20 => mapping(address => uint256)) public userRewardPerTokenPaidForToken;

    /// @notice The pending reward tokens for a user.
    mapping(IERC20 => mapping(address => uint256)) public rewardsForToken;

    /// @notice Emitted on a cross-chain deposit.
    /// @param depositor Profitshare depositor.
    /// @param sourceChain Chain ID from where the deposit was relayed from.
    /// @param sourceRoot Merkle root of the source chain for verifying the deposit.
    /// @param proof Merkle proof supplied by the depositor for relaying.
    /// @param amount Amount of tokens deposited by the depositor.
    event CrosschainDeposit(
        address indexed depositor,
        uint256 sourceChain,
        bytes32 sourceRoot,
        bytes32[] proof,
        uint256 amount
    );

    /// @notice Emitted on a cross-chain withdrawal.
    /// @param depositor Profitshare depositor.
    /// @param sourceChain Chain ID from where the withdrawal was relayed from.
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

    /// @notice Emitted on a new reward token claim.
    /// @param depositor Depositor whom claimed the tokens.
    /// @param rewardToken Reward token paid out to the depositor.
    /// @param amount Amount of reward tokens claimed.
    event RewardPaid(address indexed depositor, IERC20 indexed rewardToken, uint256 amount);

    constructor(IERC20 _beluga, CrosschainRootState _rootState) {
        BELUGA_TOKEN = _beluga;
        ROOT_STATE = _rootState;
    }

    /// @notice Deposits tokens into the profitshare.
    /// @param _proof Merkle proof supplied for relaying.
    /// @param _amount Amount of tokens to deposit.
    function deposit(bytes32[] calldata _proof, uint256 _amount) external {
        // Update reward variables.
        _updateRewards(msg.sender);

        // Verify proof.
        // TODO: Add verification code.

        // Update state.
        balance[msg.sender].nativeStake += _amount.u128();
        totalSupply += _amount;

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
        
        // Update reward variables.
        _updateRewards(msg.sender);

        // Verify proof.
        // TODO: Add verification code.

        // Update stake.
        _balance.nativeStake -= _amount.u128();
        balance[msg.sender] = _balance;
        totalSupply -= _amount;

        // Transfer tokens and emit relay request.
        BELUGA_TOKEN.safeTransfer(msg.sender, _amount);
        (bytes32 root, ) = ROOT_STATE.rootForChain(block.chainid);
        emit CrosschainWithdrawal(msg.sender, block.chainid, root, _proof, _amount);
    }

    /// @notice Claims rewards from the profitshare.
    function getReward() external {
        _updateRewards(msg.sender);
        IERC20[] memory _rTokens = _rewardTokens;
        for(uint256 i; i < _rTokens.length;) {
            _getReward(_rTokens[i]);
            unchecked { ++i; }
        }
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
        _updateRewards(_depositor);

        // Verify proof.
        // TODO: Add verification code.

        // Append deposit to the user.
        balance[_depositor].appendedStake += _amount.u128();
        totalSupply += _amount;
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
        _updateRewards(_depositor);

        // Verify proof.
        // TODO: Add verification code.

        // Append withdrawal to the user.
        balance[_depositor].appendedStake -= _amount.u128();
        totalSupply -= _amount;
    }

    /// @notice Returns all reward tokens on the PS.
    /// @return All tokens rewarded by the profitshare.
    function rewardTokens() external view returns (IERC20[] memory) {
        return (_rewardTokens);
    }

    /// @notice Fetches a depositors full stake in the PS.
    /// @param _depositor Depositor to fetch the stake of.
    /// @return Total stake of the depositor.
    function balanceOf(
        address _depositor
    ) external view returns (uint256) {
        Balance memory _balance = balance[_depositor];
        return (_balance.nativeStake + _balance.appendedStake);
    }

    /// @notice Gets the last time rewards for a token were applicable.
    /// @return The last time rewards were applicable.
    function lastTimeRewardApplicable(IERC20 _rewardToken) public view returns (uint256) {
        return Math.min(block.timestamp, periodFinishForToken[_rewardToken]);
    }

    /// @notice Gets the amount of rewards per bToken for a specified reward token.
    /// @param _rewardToken Reward token to get the amount of rewards for.
    /// @return Amount of `_rewardToken` per bToken.
    function rewardPerToken(IERC20 _rewardToken) public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStoredForToken[_rewardToken];
        }
        return
            rewardPerTokenStoredForToken[_rewardToken].add(
                lastTimeRewardApplicable(_rewardToken)
                    .sub(lastUpdateTimeForToken[_rewardToken])
                    .mul(rewardRateForToken[_rewardToken])
                    .mul(1e18)
                    .div(totalSupply)
            );
    }

    /// @notice Gets the user's earnings by reward token address.
    /// @param _rewardToken Reward token to get earnings from.
    /// @param _account Address to get the earnings of.
    function earned(IERC20 _rewardToken, address _account) public view returns (uint256) {
        Balance memory _balance = balance[_account];
        return
            uint256(_balance.nativeStake + _balance.appendedStake)
                .mul(rewardPerToken(_rewardToken).sub(userRewardPerTokenPaidForToken[_rewardToken][_account]))
                .div(1e18)
                .add(rewardsForToken[_rewardToken][_account]);
    }

    function _updateRewards(address _account) internal {
        IERC20[] memory _rTokens = _rewardTokens;
        for(uint256 i = 0; i < _rTokens.length; i++ ) {
            IERC20 rewardToken = _rTokens[i];
            rewardPerTokenStoredForToken[rewardToken] = rewardPerToken(rewardToken);
            lastUpdateTimeForToken[rewardToken] = lastTimeRewardApplicable(rewardToken);
            if (_account != address(0)) {
                rewardsForToken[rewardToken][_account] = earned(rewardToken, _account);
                userRewardPerTokenPaidForToken[rewardToken][_account] = rewardPerTokenStoredForToken[rewardToken];
            }
        }
    }

    function _getReward(IERC20 _rewardToken) internal {
        uint256 rewards = earned(_rewardToken, msg.sender);
        if(rewards > 0) {
            rewardsForToken[_rewardToken][msg.sender] = 0;
            IERC20(_rewardToken).safeTransfer(msg.sender, rewards);
            emit RewardPaid(msg.sender, _rewardToken, rewards);
        }
    }
}