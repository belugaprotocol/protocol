# @version 0.3.3

from vyper.interfaces import ERC20
from vyper.interfaces import ERC20Detailed

# Interfaces
interface IStrategy:
    def investedUnderlyingBalance() -> uint256: view

# Constants
VERSION: constant(String[12]) = "1.0.0"

# State variables
uint256Storage: HashMap[bytes32, uint256]
addressStorage: HashMap[bytes32, address]
boolStorage: HashMap[bytes32, bool]

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
rewardDistribution: public(HashMap[address, bool])
rewardTokens: public(DynArray[address, 10])
durationForToken: public(HashMap[address, uint256])
periodFinishForToken: public(HashMap[address, uint256])
rewardRateForToken: public(HashMap[address, uint256])
lastUpdateTimeForToken: public(HashMap[address, uint256])
rewardPerTokenStoredForToken: public(HashMap[address, uint256])
userRewardPerTokenPaidForToken: public(HashMap[address, HashMap[address, uint256]])
rewardsForToken: public(HashMap[address, HashMap[address, uint256]])
lastDepositTimestamp: public(HashMap[address, uint256])

# Events
event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event Withdraw:
    beneficiary: indexed(address)
    amount: uint256

event Deposit:
    beneficiary: indexed(address)
    amount: uint256

event Invest:
    amount: uint256

event StrategyAnnounced:
    newStrategy: address
    time: uint256

event StrategyChanged:
    newStrategy: address
    oldStrategy: address

event UpgradeAnnounce:
    newImplementation: address

event ExitFeeChangeQueued:
    newFee: uint256
    time: uint256

event ExitFeeChange:
    newFee: uint256
    oldFee: uint256

event RewardPaid:
    user: indexed(address)
    rewardToken: indexed(address)
    amount: uint256

event RewardInjection:
    rewardToken: indexed(address)
    rewardAmount: uint256

# Eternal Storage Pattern
@internal
def _setUint256(_key: String[32], _value: uint256):
    self.uint256Storage[keccak256(_abi_encode(_key))] = _value

@internal
def _setAddress(_key: String[32], _value: address):
    self.addressStorage[keccak256(_abi_encode(_key))] = _value

@internal
def _setBool(_key: String[32], _value: bool):
    self.boolStorage[keccak256(_abi_encode(_key))] = _value

@internal
@view
def _getUint256(_key: String[32]) -> uint256:
    return self.uint256Storage[keccak256(_abi_encode(_key))]

@internal
@view
def _getAddress(_key: String[32]) -> address:
    return self.addressStorage[keccak256(_abi_encode(_key))]

@internal
@view
def _getBool(_key: String[32]) -> bool:
    return self.boolStorage[keccak256(_abi_encode(_key))]

@internal
def _setTotalSupply(_value: uint256):
    self._setUint256("totalSupply", _value)

@internal
def _setStrategy(_value: address):
    self._setAddress("strategy", _value)

@internal
def _setUnderlying(_value: address):
    self._setAddress("underlying", _value)

@internal
def _setUnderlyingUnit(_value: uint256):
    self._setUint256("underlyingUnit", _value)

@internal
def _setFractionToInvestNumerator(_value: uint256):
    self._setUint256("fractionToInvestNumerator", _value)

@internal
def _setNextImplementation(_value: address):
    self._setAddress("nextImplementation", _value)

@internal
def _setNextImplementationTimestamp(_value: uint256):
    self._setUint256("nextImplementationTimestamp", _value)

@internal
def _setTimelockDelay(_value: uint256):
    self._setUint256("timelockDelay", _value)

@internal
def _setFutureStrategy(_value: address):
    self._setAddress("futureStrategy", _value)

@internal
def _setStrategyUpdateTime(_value: uint256):
    self._setUint256("strategyUpdateTime", _value)

@internal
def _setDepositMaturityTime(_value: uint256):
    self._setUint256("depositMaturityTime", _value)

@internal
def _setExitFee(_value: uint256):
    self._setUint256("exitFee", _value)

@internal
def _setNextExitFee(_value: uint256):
    self._setUint256("nextExitFee", _value)

@internal
def _setNextExitFeeTimestamp(_value: uint256):
    self._setUint256("nextExitFeeTimestamp", _value)

@internal
@view
def _totalSupply() -> uint256:
    return self._getUint256("totalSupply")

@external
@view
def totalSupply() -> uint256:
    return self._totalSupply()

@internal
@view
def _strategy() -> address:
    return self._getAddress("strategy")

@external
@view
def strategy() -> address:
    return self._strategy()

@internal
@view
def _underlying() -> address:
    return self._getAddress("underlying")

@external
@view
def underlying() -> address:
    return self._underlying()

@internal
@view
def _underlyingUnit() -> uint256:
    return self._getUint256("underlyingUnit")

@external
@view
def underlyingUnit() -> uint256:
    return self._underlyingUnit()

@internal
@view
def _fractionToInvestNumerator() -> uint256:
    return self._getUint256("fractionToInvestNumerator")

@external
@view
def fractionToInvestNumerator() -> uint256:
    return self._fractionToInvestNumerator()

@internal
@view
def _nextImplementation() -> address:
    return self._getAddress("nextImplementation")

@external
@view
def nextImplementation() -> address:
    return self._nextImplementation()

@internal
@view
def _nextImplementationTimestamp() -> uint256:
    return self._getUint256("nextImplementationTimestamp")

@external
@view
def nextImplementationTimestamp() -> uint256:
    return self._nextImplementationTimestamp()

@internal
@view
def _timelockDelay() -> uint256:
    return self._getUint256("timelockDelay")

@external
@view
def timelockDelay() -> uint256:
    return self._timelockDelay()

@internal
@view
def _futureStrategy() -> address:
    return self._getAddress("futureStrategy")

@external
@view
def futureStrategy() -> address:
    return self._futureStrategy()

@internal
@view
def _strategyUpdateTime() -> uint256:
    return self._getUint256("strategyUpdateTime")

@external
@view
def strategyUpdateTime() -> uint256:
    return self._strategyUpdateTime()

@internal
@view
def _depositMaturityTime() -> uint256:
    return self._getUint256("depositMaturityTime")

@external
@view
def depositMaturityTime() -> uint256:
    return self._depositMaturityTime()

@internal
@view
def _exitFee() -> uint256:
    return self._getUint256("exitFee")

@external
@view
def exitFee() -> uint256:
    return self._exitFee()

@internal
@view
def _nextExitFee() -> uint256:
    return self._getUint256("nextExitFee")

@external
@view
def nextExitFee() -> uint256:
    return self._nextExitFee()

@internal
@view
def _nextExitFeeTimestamp() -> uint256:
    return self._getUint256("nextExitFeeTimestamp")

@external
@view
def nextExitFeeTimestamp() -> uint256:
    return self._nextExitFeeTimestamp()

# ERC20 Interface

@internal
def _mint(_to: address, _value: uint256):
    assert _to != ZERO_ADDRESS
    self._setTotalSupply(self._totalSupply() + _value)
    self.balanceOf[_to] += _value
    log Transfer(ZERO_ADDRESS, _to, _value)

@internal
def _burn(_from: address, _value: uint256):
    self._setTotalSupply(self._totalSupply() - _value)
    self.balanceOf[_from] -= _value
    log Transfer(_from, ZERO_ADDRESS, _value)

@external
def transfer(_to: address, _value: uint256) -> bool:
    # Pretransfer hook.
    assert block.timestamp >= self.lastDepositTimestamp[msg.sender] + 8

    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    self.allowance[_from][msg.sender] -= _value
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

@external
def increaseAllowance(_spender: address, _value: uint256) -> bool:
    self.allowance[msg.sender][_spender] += _value
    return True

@external
def decreaseAllowance(_spender: address, _value: uint256) -> bool:
    self.allowance[msg.sender][_spender] -= _value
    return True

@external
@view
def name() -> String[32]:
    return "Placeholder"

@external
@view
def symbol() -> String[32]:
    return "HLD"

@external
@pure
def decimals() -> uint8:
    return 18

@internal
@view
def _underlyingBalanceInVault() -> uint256:
    return ERC20(self._underlying()).balanceOf(self)

@external
@view
def underlyingBalanceInVault() -> uint256:
    return self._underlyingBalanceInVault()

@internal
@view
def _underlyingBalanceWithInvestment() -> uint256:
    if self._strategy() == ZERO_ADDRESS:
        return self._underlyingBalanceInVault()
    return (self._underlyingBalanceInVault() + IStrategy(self._strategy()).investedUnderlyingBalance())

@external
@view
def underlyingBalanceWithInvestment() -> uint256:
    return self._underlyingBalanceWithInvestment()

@internal
@view
def _lastTimeRewardApplicable(_rewardToken: address) -> uint256:
    return min(block.timestamp, self.periodFinishForToken[_rewardToken])

@external
@view
def lastTimeRewardApplicable(_rewardToken: address) -> uint256:
    return self._lastTimeRewardApplicable(_rewardToken)

@internal
@view
def _rewardPerToken(_rewardToken: address) -> uint256:
    sup: uint256 = self._totalSupply()
    if sup == 0:
        return self.rewardPerTokenStoredForToken[_rewardToken]
    return self.rewardPerTokenStoredForToken[_rewardToken] + ((block.timestamp - self._lastTimeRewardApplicable(_rewardToken)) * self.rewardRateForToken[_rewardToken] * 1e18) / sup

@internal
@view
def _earned(_rewardToken: address, _account: address) -> uint256:
    return ((
                self.balanceOf[_account] * 
                    (self._rewardPerToken(_rewardToken) - self.userRewardPerTokenPaidForToken[_rewardToken][_account]))
            + self.rewardsForToken[_rewardToken][_account])

@internal
def _updateRewards(_account: address):
    for i in self.rewardTokens:
        rewardToken: address = self.rewardTokens[i]
        self.rewardPerTokenStoredForToken[rewardToken] = self._rewardPerToken(rewardToken)
        self.lastUpdateTimeForToken[rewardToken] = self._lastTimeRewardApplicable(rewardToken)
        if _account != ZERO_ADDRESS:
            self.rewardsForToken[rewardToken][_account] = self._earned(rewardToken, _account)
            self.userRewardPerTokenPaidForToken[rewardToken][_account] = self.rewardPerTokenStoredForToken[rewardToken]
        

@internal
def _deposit(_amount: uint256, _sender: address, _beneficiary: address):
    assert _amount > 0
    assert _beneficiary != ZERO_ADDRESS

    sup: uint256 = self._totalSupply()
    toMint: uint256 = 69
    if sup == 0:
        toMint = _amount
    else:
        toMint = (_amount * sup) / self._underlyingBalanceWithInvestment()
    self._mint(_beneficiary, toMint)
    self.lastDepositTimestamp[_beneficiary] = block.timestamp

    ERC20(self._underlying()).transferFrom(_sender, self, _amount)
    log Deposit(_beneficiary, _amount)

@external
def deposit(_amount: uint256):
    self._deposit(_amount, msg.sender, msg.sender)