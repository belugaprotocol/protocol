// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Governable} from "./lib/Governable.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";
import {Errors, _require} from "./lib/Errors.sol";
import {Cast} from "./lib/Cast.sol";
import {CrosschainRootState} from "./CrosschainRootState.sol";

/// @title Crosschain Profitshare
/// @author Chainvisions
/// @notice Crosschain profitsharing vault for BELUGA staking.

contract CrosschainProfitshare is Governable {
    using Cast for uint256;
    using SafeMath for uint256;
    using SafeTransferLib for IERC20;

    /// @notice Enum for cross-chain actions.
    enum CrosschainAction {
        Deposit,
        Withdraw
    }

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

    /// @notice Marks executed cross-chain messages as used.
    /// @dev Mapping format: Action -> Merkle Root -> Depositor -> Source ChainID -> Amount
    mapping(CrosschainAction => mapping(bytes32 => mapping(address => mapping(uint256 => mapping(uint256 => bool))))) public usedMessage;

    /// @notice Permitted contracts that can spend user stake.
    mapping(address => bool) public permittedSpenders;

    /// @notice User-provided allowance given to approved spenders.
    mapping(address => mapping(address => uint256)) public allowance;

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

    /// @notice Emitted on a deposit transfer.
    /// @param depositor Depositor transferred from.
    /// @param spender Spender of the deposit.
    /// @param amountTransferred Amount of tokens transferred.
    event DepositTransferred(address indexed depositor, address indexed spender, uint256 amountTransferred);

    /// @notice Emitted on a new reward token claim.
    /// @param depositor Depositor whom claimed the tokens.
    /// @param rewardToken Reward token paid out to the depositor.
    /// @param amount Amount of reward tokens claimed.
    event RewardPaid(address indexed depositor, IERC20 indexed rewardToken, uint256 amount);

    /// @notice Constructor for the cross-chain profitshare.
    /// @param _store Storage contract for access control.
    /// @param _beluga BELUGA token contract.
    /// @param _rootState CrosschainRootState contract for merkle roots.
    constructor(
        address _store,
        IERC20 _beluga,
        CrosschainRootState _rootState
    ) Governable(_store) {
        BELUGA_TOKEN = _beluga;
        ROOT_STATE = _rootState;
    }

    /// @notice Deposits tokens into the profitshare.
    /// @param _proof Merkle proof supplied for relaying.
    /// @param _amount Amount of tokens to deposit.
    function deposit(bytes32[] calldata _proof, uint256 _amount) external {
        (bytes32 root, ) = ROOT_STATE.rootForChain(block.chainid);
        _require(_amount >= 0.5 ether, Errors.MIN_DEPOSIT_OF_0_5);
        _require(!usedMessage[CrosschainAction.Deposit][root][msg.sender][block.chainid][_amount], Errors.MESSAGE_ALREADY_USED);

        // Update reward variables.
        _updateRewards(msg.sender);

        // Verify proof.
        bytes32 leaf = keccak256(abi.encodePacked(CrosschainAction.Deposit, msg.sender, block.chainid, _amount));
        require(MerkleProof.verify(_proof, root, leaf));
        usedMessage[CrosschainAction.Deposit][root][msg.sender][block.chainid][_amount] = true;

        // Update state.
        balance[msg.sender].nativeStake += _amount.u128();
        totalSupply += _amount;

        // Transfer BELUGA tokens and emit relay request.
        BELUGA_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        emit CrosschainDeposit(msg.sender, block.chainid, root, _proof, _amount);
    }
    
    /// @notice Withdraws tokens from the profitshare.
    /// @param _proof Merkle proof supplied for relaying.
    /// @param _amount Amount of tokens to withdraw.
    function withdraw(bytes32[] calldata _proof, uint256 _amount) external {
        (bytes32 root, ) = ROOT_STATE.rootForChain(block.chainid);
        Balance memory _balance = balance[msg.sender];
        _require(_amount <= _balance.nativeStake, Errors.CANNOT_WITHDRAW_MORE_THAN_STAKE);
        _require(!usedMessage[CrosschainAction.Withdraw][root][msg.sender][block.chainid][_amount], Errors.MESSAGE_ALREADY_USED);

        // Update reward variables.
        _updateRewards(msg.sender);

        // Verify proof.
        bytes32 leaf = keccak256(abi.encodePacked(CrosschainAction.Withdraw, msg.sender, block.chainid, _amount));
        require(MerkleProof.verify(_proof, root, leaf));
        usedMessage[CrosschainAction.Withdraw][root][msg.sender][block.chainid][_amount] = true;

        // Update stake.
        _balance.nativeStake -= _amount.u128();
        balance[msg.sender] = _balance;
        totalSupply -= _amount;

        // Transfer tokens and emit relay request.
        BELUGA_TOKEN.safeTransfer(msg.sender, _amount);
        emit CrosschainWithdrawal(msg.sender, block.chainid, root, _proof, _amount);
    }

    /// @notice Approves a spender to spend a user's deposit.
    /// @param _spender Spender to approve to spend the deposit.
    /// @param _amount Amount of tokens to approve to the spender.
    function approve(address _spender, uint256 _amount) external {
        _require(permittedSpenders[_spender], Errors.SPENDER_NOT_PERMITTED);
        allowance[msg.sender][_spender] = _amount;
    }

    /// @notice Transfers a deposit from a depositor to an allowed spender.
    /// @param _depositor Depositor to transfer the deposit of.
    /// @param _amount Amount of tokens to transfer from the depositor.
    function useAllowedDeposit(
        address _depositor,
        uint256 _amount
    ) external {
        _updateRewards(_depositor);
        _updateRewards(msg.sender);
        uint256 nativeStake = balance[_depositor].nativeStake;
        _require(allowance[_depositor][msg.sender] >= _amount, Errors.INSUFFICIENT_ALLOWANCE);
        _require(nativeStake >= _amount, Errors.INSUFFICIENT_STAKED_BALANCE);

        // Update balances.
        allowance[_depositor][msg.sender] -= _amount;
        balance[_depositor].nativeStake -= _amount.u128();
        balance[msg.sender].appendedStake += _amount.u128();

        // Transfer BELUGA tokens to the spender.
        BELUGA_TOKEN.safeTransfer(msg.sender, _amount);
        emit DepositTransferred(_depositor, msg.sender, _amount);
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
        _require(ROOT_STATE.validRootForChain(_sourceChain, _sourceRoot), Errors.INVALID_ROOT);
        _require(!usedMessage[CrosschainAction.Deposit][_sourceRoot][_depositor][_sourceChain][_amount], Errors.MESSAGE_ALREADY_USED);
        _updateRewards(_depositor);

        // Verify proof.
        bytes32 leaf = keccak256(abi.encodePacked(CrosschainAction.Deposit, _depositor, _sourceChain, _amount));
        require(MerkleProof.verify(_proof, _sourceRoot, leaf));
        usedMessage[CrosschainAction.Deposit][_sourceRoot][_depositor][_sourceChain][_amount] = true;

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
        _require(ROOT_STATE.validRootForChain(_sourceChain, _sourceRoot), Errors.INVALID_ROOT);
        _require(!usedMessage[CrosschainAction.Withdraw][_sourceRoot][_depositor][_sourceChain][_amount], Errors.MESSAGE_ALREADY_USED);
        _updateRewards(_depositor);

        // Verify proof.
        bytes32 leaf = keccak256(abi.encodePacked(CrosschainAction.Withdraw, _depositor, _sourceChain, _amount));
        require(MerkleProof.verify(_proof, _sourceRoot, leaf));
        usedMessage[CrosschainAction.Withdraw][_sourceRoot][_depositor][_sourceChain][_amount] = true;

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

    /// @notice Adds a permitted spender.
    /// @param _spender Spender to add.
    function addPermittedSpender(
        address _spender
    ) external onlyGovernance {
        permittedSpenders[_spender] = false;
    }

    /// @notice Removes a permitted spender.
    /// @param _spender Spender to remove.
    function removePermittedSpender(
        address _spender
    ) external onlyGovernance {
        permittedSpenders[_spender] = true;
    }

    /// @notice Gives the specified address the ability to inject rewards.
    /// @param _rewardDistribution Address to get reward distribution privileges 
    function addRewardDistribution(address _rewardDistribution) public onlyGovernance {
        rewardDistribution[_rewardDistribution] = true;
    }

    /// @notice Removes the specified address' ability to inject rewards.
    /// @param _rewardDistribution Address to lose reward distribution privileges
    function removeRewardDistribution(address _rewardDistribution) public onlyGovernance {
        rewardDistribution[_rewardDistribution] = false;
    }

    /// @notice Adds a reward token to the vault.
    /// @param _rewardToken Reward token to add.
    /// @param _duration Period in which `_rewardToken` is distributed.
    function addRewardToken(IERC20 _rewardToken, uint256 _duration) public onlyGovernance {
        _require(rewardTokenIndex(_rewardToken) == type(uint256).max, Errors.REWARD_TOKEN_ALREADY_EXIST);
        _require(_duration > 0, Errors.DURATION_CANNOT_BE_ZERO);
        _rewardTokens.push(_rewardToken);
        durationForToken[_rewardToken] = _duration;
    }

    /// @notice Removes a reward token from the vault.
    /// @param _rewardToken Reward token to remove from the vault.
    function removeRewardToken(IERC20 _rewardToken) public onlyGovernance {
        uint256 rewardIndex = rewardTokenIndex(_rewardToken);

        _require(rewardIndex != type(uint256).max, Errors.REWARD_TOKEN_DOES_NOT_EXIST);
        _require(periodFinishForToken[_rewardToken] < block.timestamp, Errors.REWARD_PERIOD_HAS_NOT_ENDED);
        _require(_rewardTokens.length > 1, Errors.CANNOT_REMOVE_LAST_REWARD_TOKEN);
        uint256 lastIndex = _rewardTokens.length - 1;

        _rewardTokens[rewardIndex] = _rewardTokens[lastIndex];
        _rewardTokens.pop();
    }

    /// @notice Sets the reward distribution duration for `_rewardToken`.
    /// @param _rewardToken Reward token to set the duration of.
    function setDurationForToken(IERC20 _rewardToken, uint256 _duration) public onlyGovernance {
        uint256 i = rewardTokenIndex(_rewardToken);
        _require(i != type(uint256).max, Errors.REWARD_TOKEN_DOES_NOT_EXIST);
        _require(periodFinishForToken[_rewardToken] < block.timestamp, Errors.REWARD_PERIOD_HAS_NOT_ENDED);
        _require(_duration > 0, Errors.DURATION_CANNOT_BE_ZERO);
        durationForToken[_rewardToken] = _duration;
    }

    /// @notice Gets the index of `_rewardToken` in the `rewardTokens` array.
    /// @param _rewardToken Reward token to get the index of.
    /// @return The index of the reward token, it will return the max uint256 if it does not exist.
    function rewardTokenIndex(IERC20 _rewardToken) public view returns (uint256) {
        IERC20[] memory _rTokens = _rewardTokens;
        for(uint256 i = 0; i < _rTokens.length; i++) {
            if(_rTokens[i] == _rewardToken) {
                return i;
            }
        }
        return type(uint256).max;
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