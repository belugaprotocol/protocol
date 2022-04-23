# @version 0.3.3

from vyper.interfaces import ERC20

interface CToken:
    def mint(_value: uint256) -> uint256: nonpayable
    def redeem(_value: uint256) -> uint256: nonpayable
    def redeemUnderlying(_value: uint256): nonpayable

interface LiquidityGauge:
    def deposit(_value: uint256): nonpayable
    def withdraw(_value: uint256): nonpayable

# Unpacked, we don't have to care about size /---/
struct AtlantisPool:
    # Addresses
    supplyCToken: address
    liquidityGauge: address

    # Reward logic
    duration: uint256
    periodFinish: uint256
    rewardRate: uint256
    lastUpdate: uint256
    rewardPerTokenStored: uint256


# ETERNAL STORAGE STATE
uint256Storage: HashMap[bytes32, uint256]
addressStorage: HashMap[bytes32, address]
boolStorage: HashMap[bytes32, bool]

# NON PRIMITIVE STATE VARIABLES
validDepositToken: public(HashMap[address, bool])
tokenAtlantisPool: public(HashMap[address, AtlantisPool])
atlanteanCTokens: public(HashMap[address, uint256])

event AtlantisDeposit:
    depositor: indexed(address)
    token: indexed(address)
    amount: uint256

event AtlantisWithdrawal:
    user: indexed(address)
    token: indexed(address)
    amountInCToken: uint256

# ETERNAL STORAGE LOGIC

@internal
def _set_uint256(key: String[32], val: uint256):
    self.uint256Storage[keccak256(_abi_encode(key))] = val

@internal
def _set_address(key: String[32], val: address):
    self.addressStorage[keccak256(_abi_encode(key))] = val

@internal
def _set_bool(key: String[32], val: bool):
    self.boolStorage[keccak256(_abi_encode(key))] = val

@view
@internal
def _get_uint256(key: String[32]) -> uint256:
    return self.uint256Storage[keccak256(_abi_encode(key))]

@view
@internal
def _get_address(key: String[32]) -> address:
    return self.addressStorage[keccak256(_abi_encode(key))]

@view
@internal
def _get_bool(key: String[32]) -> bool:
    return self.boolStorage[keccak256(_abi_encode(key))]

# Getters and setters#

@internal
@view
def _nextImplementation() -> address:
    return self._get_address("nextImplementation")

@external
@view
def nextImplementation() -> address:
    return self._nextImplementation()

@internal
@view
def _nextImplementationTimestamp() -> uint256:
    return self._get_uint256("nextImplementationTimestamp")

@external
@view
def nextImplementationTimestamp() -> uint256:
    return self._nextImplementationTimestamp()

@internal
def _set_next_implementation(val: address):
    self._set_address("nextImplementation", val)

@internal
def _set_next_implementation_timestamp(val: uint256):
    self._set_uint256("nextImplementationTimestamp", val)

@internal
def _set_upgrade_timelock(val: uint256):
    self._set_uint256("upgradeTimelock", val)

# SafeTransferLib

@internal
def safeTransfer(token: address, to: address, amount: uint256):
    """
    Safely transfer tokens with failure detection
    """
    res: Bytes[32] = raw_call(
        token,
        concat(
            method_id("transfer(address,uint256)"),
            convert(to, bytes32),
            convert(amount, bytes32)
        ),
        max_outsize=32
    )
    if len(res) > 0:
        assert convert(res, bool)

@internal
def safeApprove(token: address, toApprove: address, amount: uint256):
    """
    Safely add allowance on a token with checks for reversions
    """
    res: Bytes[32] = raw_call(
        token,
        concat(
            method_id("approve(address,uint256)"),
            convert(toApprove, bytes32),
            convert(amount, bytes32)
        ),
        max_outsize=32
    )
    if len(res) > 0:
        assert convert(res, bool)

@internal
def safeTransferFrom(token: address, addressFrom: address, to: address, amount: uint256):
    """
    Safely transfer tokens from a contract with checks for reversions
    """
    res: Bytes[32] = raw_call(
        token,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(addressFrom, bytes32),
            convert(to, bytes32),
            convert(amount, bytes32)
        ),
        max_outsize=32
    )

    if len(res) > 0:
        assert convert(res, bool)

# ATLANTIS LOGIC

@external
@nonreentrant('lock')
def deposit(token: address, amount: uint256):
    # Check pool validity and fetch the pool.
    assert self.validDepositToken[token], "Atlantis: Invalid deposit token"
    _pool: AtlantisPool = self.tokenAtlantisPool[token]

    # Transfer initial tokens.
    assert amount > 0, "Atlantis: Cannot deposit zero"
    self.safeTransferFrom(token, msg.sender, self, amount)

    # Supply tokens to the gauge.
    self.safeApprove(token, _pool.supplyCToken, 0)
    self.safeApprove(token, _pool.supplyCToken, amount)
    assert CToken(_pool.supplyCToken).mint(amount) == 0, "Atlantis: CToken mint failed"

    cTokens: uint256 = ERC20(_pool.supplyCToken).balanceOf(self)
    self.atlanteanCTokens[msg.sender] = cTokens

    self.safeApprove(_pool.supplyCToken, _pool.liquidityGauge, 0)
    self.safeApprove(_pool.supplyCToken, _pool.liquidityGauge, cTokens)
    LiquidityGauge(_pool.liquidityGauge).deposit(cTokens)

    # TODO: Handle VeManager deposit

    log AtlantisDeposit(msg.sender, token, amount)

@external
@nonreentrant('lock')
def withdraw(token: address, amountCToken: uint256):
    assert self.atlanteanCTokens[msg.sender] >= amountCToken, "Atlantis: Cannot withdraw over deposit"
    _pool: AtlantisPool = self.tokenAtlantisPool[token]

    # TODO: Handle VeManager withdrawal

    # Withdraw tokens from the liquidity gauge and redeem the cTokens.
    tknsInPrev: uint256 = ERC20(token).balanceOf(self)
    LiquidityGauge(_pool.liquidityGauge).withdraw(amountCToken)
    assert CToken(_pool.supplyCToken).redeem(amountCToken) == 0, "Atlantis: CToken redemption failed"
    
    tknsIn: uint256 = ERC20(token).balanceOf(self) - tknsInPrev # Just for the sake of safety.
    self.safeTransfer(token, msg.sender, tknsIn)

    log AtlantisWithdrawal(msg.sender, token, amountCToken)
