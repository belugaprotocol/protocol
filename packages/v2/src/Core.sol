// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Ext} from "./interfaces/IERC20Ext.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";
import {JsonWriter} from "./lib/JsonWriter.sol";
import {BelugaProxy} from "./BelugaProxy.sol";
import {CoreStorage} from "./CoreStorage.sol";

/// @title Beluga Core Protocol
/// @author Chainvisions
/// @notice Core protocol contract for access control and harvests.

contract Core {
    using CoreStorage for CoreStorage.Layout;
    using JsonWriter for JsonWriter.Json;
    using SafeTransferLib for IERC20;

    // Structure for a vault deployment
    struct Deployment {
        address vault;
        address strategy;
        address strategyImpl;
    }

    /// @notice Numerator for percentage calculations.
    uint256 public constant NUMERATOR = 10000;

    /// @notice Emitted on a successful doHardWork.
    event SharePriceChangeLog(
        address indexed vault,
        address indexed strategy,
        uint256 oldSharePrice,
        uint256 newSharePrice,
        uint256 timestamp
    );

    /// @notice Emitted on a failed doHardWork on `batchDoHardWork()` calls.
    event FailedHarvest(address indexed vault);

    /// @notice Emitted on a successful rebalance on a vault.
    event VaultRebalance(address indexed vault);

    /// @notice Emitted on a failed rebalance on `batchRebalance()` calls.
    event FailedRebalance(address indexed vault);

    /// @notice Emitted when governance is transferred to a new address.
    event GovernanceTransferred(address prevGovernance, address newGovernance);

    /// @notice Emitted on vault deployment.
    event VaultDeployment(address vault, address strategy, string vaultType);

    /// @notice Used for limiting certain functions to governance only.
    modifier onlyGovernance {
        require(msg.sender == CoreStorage.layout().governance);
        _;
    }

    /// @notice Deploys and configures a new vault contract.
    /// @param _underlying The underlying token that the vault accepts.
    /// @param _exitFee The exit fee charged by the vault on early withdrawal.
    /// @param _bytecode The bytecode of the vault's strategy contract implementation.
    /// @param _deployAsMaximizer Whether or not to deploy the vault as a maximizer.
    /// @return The deployed contracts that are part of the vault.
    function deployVault(
        address _underlying,
        uint256 _exitFee,
        bytes memory _bytecode,
        bool _deployAsMaximizer
    ) public returns (Deployment memory) {
        require(CoreStorage.layout().keepers[msg.sender]);
        // Create a variable for the deployment metadata to return.
        Deployment memory deploymentData;

        // Deploy and initialize a new vault proxy.
        BelugaProxy proxy = new BelugaProxy(CoreStorage.layout().latestVaultImplementation);
        deploymentData.vault = address(proxy);
        IVault vaultProxy = IVault(address(proxy));
        vaultProxy.initializeVault(address(this), _underlying, 9999, true, _exitFee);

        // Deploy a new strategy contract.
        address strategyImpl = _create(_bytecode);
        BelugaProxy strategyProxy = new BelugaProxy(strategyImpl);
        (bool initStatus, ) = address(strategyProxy).call(abi.encodeWithSignature("initializeStrategy(address,address)", address(this), address(proxy)));
        require(initStatus, "VaultDeployer: Strategy initialization failed");
        deploymentData.strategy = address(strategyProxy);
        deploymentData.strategyImpl = strategyImpl;

        vaultProxy.setStrategy(address(strategyProxy));

        // Handle vault configuration.
        if(_deployAsMaximizer) {
            // Set the strategy as reward distribution on the vault.
            vaultProxy.addRewardDistribution(address(strategyProxy));

            // Fetch the reward token to add to the vault.
            (,bytes memory encodedReward) = address(strategyProxy).staticcall(abi.encodeWithSignature("targetVault()"));
            address vaultReward = abi.decode(encodedReward, (address));

            // Add the reward token to the vault with a reward duration of 1 hour.
            vaultProxy.addRewardToken(vaultReward, 900);
            CoreStorage.layout().whitelist[address(strategyProxy)] = true;
            CoreStorage.layout().feeExemptAddresses[address(strategyProxy)] = true;
        }

        CoreStorage.layout().registeredVaults.push(
            CoreStorage.RegistryData(
                _deployAsMaximizer == false ? CoreStorage.StrategyType.Autocompound : CoreStorage.StrategyType.Maximizer,
                address(proxy), 
                _underlying
            )
        );
        emit VaultDeployment(
            address(proxy),
            address(strategyProxy),
            _deployAsMaximizer == false ? "autocompounding" : "maximizer"
        );
        return deploymentData;
    }

    /// @notice Collects `_token` that is in the Controller.
    /// @param _token Token to salvage from the contract.
    /// @param _amount Amount of `_token` to salvage.
    function salvage(
        address _token,
        uint256 _amount
    ) external onlyGovernance {
        IERC20(_token).safeTransfer(CoreStorage.layout().governance, _amount);
    }

    /// @notice Salvages tokens from the specified strategy.
    /// @param _strategy Address of the strategy to salvage from.
    /// @param _token Token to salvage from `_strategy`.
    /// @param _amount Amount of `_token` to salvage from `_strategy`.
    function salvageStrategy(
        address _strategy,
        address _token,
        uint256 _amount
    ) external onlyGovernance {
        IStrategy(_strategy).salvage(CoreStorage.layout().governance, _token, _amount);
    }

    /// @notice Salvages multiple tokens from the Controller.
    /// @param _tokens Tokens to salvage.
    function salvageMultipleTokens(
        address[] memory _tokens
    ) external onlyGovernance {
        address _governance = CoreStorage.layout().governance;
        for(uint256 i; i < _tokens.length;) {
            IERC20 token = IERC20(_tokens[i]);
            token.safeTransfer(_governance, token.balanceOf(address(this)));
            unchecked { ++i; }
        }
    }

    /// @notice Converts `_tokenFrom` into Beluga's target tokens.
    /// @param _tokenFrom Token to convert from.
    /// @param _fee Performance fees to convert into the target tokens.
    function notifyFee(address _tokenFrom, uint256 _fee) external {
        CoreStorage.layout().lastHarvestTimestamp[msg.sender] = block.timestamp;
        IERC20 reserve = IERC20(CoreStorage.layout().reserveToken);
        // If the token is the reserve token, send it to the multisig.
        if(_tokenFrom == address(reserve)) {
            IERC20(_tokenFrom).safeTransferFrom(msg.sender, CoreStorage.layout().governance, _fee);
            return;
        }
        // Else, the token needs to be converted to wFTM.
        address[] memory targetRouteToReward = CoreStorage.layout().tokenConversionRoute[_tokenFrom][address(reserve)]; // Save to memory to save gas.
        if(targetRouteToReward.length > 1) {
            // Perform conversion if a route to wFTM from `_tokenFrom` is specified.
            IERC20(_tokenFrom).safeTransferFrom(msg.sender, address(this), _fee);
            uint256 feeAfter = IERC20(_tokenFrom).balanceOf(address(this)); // In-case the token has transfer fees.
            IUniswapV2Router02 targetRouter = IUniswapV2Router02(CoreStorage.layout().tokenConversionRouter[_tokenFrom][address(reserve)]);
            if(address(targetRouter) != address(0)) {
                // We can safely perform a regular swap.
                uint256 endAmount = _performSwap(targetRouter, IERC20(_tokenFrom), feeAfter, targetRouteToReward);

                // Calculate and distribute split.
                uint256 rebateAmount = (endAmount * CoreStorage.layout().rebateNumerator) / NUMERATOR;
                uint256 remainingAmount = (endAmount - rebateAmount);
                reserve.safeTransfer(tx.origin, rebateAmount);
                reserve.safeTransfer(CoreStorage.layout().governance, remainingAmount);
            } else {
                // Else, we need to perform a cross-dex liquidation.
                address[] memory targetRouters = CoreStorage.layout().tokenConversionRouters[_tokenFrom][address(reserve)];
                uint256 endAmount = _performMultidexSwap(targetRouters, _tokenFrom, feeAfter, targetRouteToReward);

                // Calculate and distribute split.
                uint256 rebateAmount = (endAmount * CoreStorage.layout().rebateNumerator) / NUMERATOR;
                uint256 remainingAmount = (endAmount - rebateAmount);
                reserve.safeTransfer(tx.origin, rebateAmount);
                reserve.safeTransfer(CoreStorage.layout().governance, remainingAmount);
            }
        } else {
            // Else, leave the funds in the Controller.
            return;
        }
    }

    /// @notice Simulates a harvest on a vault. Meant to be called statically.
    /// @param _vault Vault to simulate a harvest on.
    /// @return bounty Bounty for harvesting the vault.
    /// @return gasUsed Gas used to harvest.
    function simulateHarvest(
        address _vault
    ) external returns (uint256 bounty, uint256 gasUsed) {
        uint256 initialReserve = IERC20(CoreStorage.layout().reserveToken).balanceOf(tx.origin);
        uint256 initialGas = gasleft();
        doHardWork(_vault);
        gasUsed = initialGas - gasleft();
        bounty = IERC20(CoreStorage.layout().reserveToken).balanceOf(tx.origin) - initialReserve;
    }

    /// @notice Fetches the last harvest on a specific vault.
    /// @return Timestamp of the vault's most recent harvest.
    function fetchLastHarvestForVault(address _vault) external view returns (uint256) {
        return CoreStorage.layout().lastHarvestTimestamp[IVault(_vault).strategy()];
    }

    /// @notice Lists all registered vaults.
    /// @return All vaults registered on the protocol in JSON format.
    function registry() external view returns (string[] memory) {
        CoreStorage.RegistryData[] memory registeredVaults = CoreStorage.layout().registeredVaults;
        string[] memory vaults = new string[](registeredVaults.length);
        for(uint256 i; i < vaults.length;) {
            CoreStorage.RegistryData memory vault = registeredVaults[i];
            JsonWriter.Json memory writer;
            string memory tokenSymbol;
            bool isRegularToken;
            {
                try IUniswapV2Pair(vault.underlyingAddress).token0() {
                    isRegularToken = false;
                } catch {
                    isRegularToken = true;
                }
            }

            // Construct token symbol.
            if(isRegularToken) {
                string memory symbol = IERC20Ext(vault.underlyingAddress).symbol();
                tokenSymbol = vault.strategyType == CoreStorage.StrategyType.Autocompound ? string.concat("b", symbol) : string.concat(symbol, " Maximizer");
            } else {
                string memory symbol = string.concat(
                    string.concat(
                        IERC20Ext(IUniswapV2Pair(vault.underlyingAddress).token0()).symbol(), 
                        string.concat(
                            "-", IERC20Ext(IUniswapV2Pair(vault.underlyingAddress).token1()).symbol()
                        )
                    ),
                    " LP"
                );
                tokenSymbol = vault.strategyType == CoreStorage.StrategyType.Autocompound ? string.concat("b", symbol) : string.concat(symbol, " Maximizer");
            }

            writer.writeStartObject();
            writer.writeStringProperty("name", tokenSymbol);
            writer.writeAddressProperty("address", vault.vaultAddress);
            writer.writeAddressProperty("underlyingAddress", vault.underlyingAddress);
            writer.writeStringProperty("strategyType", vault.strategyType == CoreStorage.StrategyType.Autocompound ? "autocompound" : "maximizer");
            writer.writeEndObject();

            vaults[i] = writer.value;
            unchecked { ++i; }
        }

        return vaults;
    }

    /// @notice Fetches the storage value of the profitsharing numerator.
    /// @return Numerator for vault performance fees.
    function profitSharingNumerator() external view returns (uint256) {
        return CoreStorage.layout().profitSharingNumerator;
    }

    /// @notice Fetches the pure value of the profitsharing denominator.
    /// @return Denominator for vault performance fees.
    function profitSharingDenominator() external pure returns (uint256) {
        return NUMERATOR;
    }

    /// @notice Provides backwards compatability with existing contracts.
    /// @return The address of the core protocol.
    function governance() external view returns (address) {
        return address(this);
    }

    /// @notice Provides backwards compatability with existing contracts.
    /// @return The address of the core protocol.
    function controller() external view returns (address) {
        return address(this);
    }

    /// @notice Fetches whether or not a contract is whitelisted.
    /// @param _contract Contract to check whitelisting for.
    /// @return Whether or not the contract is whitelisted.
    function whitelist(address _contract) external view returns (bool) {
        return CoreStorage.layout().whitelist[_contract];
    }

    /// @notice Fetches whether or not a contract is exempt from penalties.
    /// @param _contract Contract to check exemption for.
    /// @return Whether or not the contract is exempt.
    function feeExemptAddresses(address _contract) external view returns (bool) {
        return CoreStorage.layout().feeExemptAddresses[_contract];
    }

    /// @notice Fetches whether or not a contract is whitelisted (old method).
    /// @param _contract Contract to check whitelisting for.
    /// @return Whether or not the contract is whitelisted.
    function greyList(address _contract) external view returns (bool) {
        return CoreStorage.layout().greyList[_contract];
    }

    /// @notice Fetches the governance address from storage.
    /// @return Protocol governance address.
    function protocolGovernance() external view returns (address) {
        return CoreStorage.layout().governance;
    }

    /// @notice Performs doHardWork on a desired vault.
    /// @param _vault Address of the vault to doHardWork on.
    function doHardWork(address _vault) public {
        uint256 prevSharePrice = IVault(_vault).getPricePerFullShare();
        IVault(_vault).doHardWork();
        uint256 sharePriceAfter = IVault(_vault).getPricePerFullShare();
        emit SharePriceChangeLog(
            _vault,
            IVault(_vault).strategy(),
            prevSharePrice,
            sharePriceAfter,
            block.timestamp
        );
    }

    /// @notice Performs doHardWork on vaults in batches.
    /// @param _vaults Array of vaults to doHardWork on.
    function batchDoHardWork(address[] memory _vaults) public {
        for(uint256 i = 0; i < _vaults.length; i++) {
            uint256 prevSharePrice = IVault(_vaults[i]).getPricePerFullShare();
            // We use the try/catch pattern to allow us to spot an issue in one of our vaults
            // while still being able to harvest the rest.
            try IVault(_vaults[i]).doHardWork() {
                uint256 sharePriceAfter = IVault(_vaults[i]).getPricePerFullShare();
                emit SharePriceChangeLog(
                    _vaults[i],
                    IVault(_vaults[i]).strategy(),
                    prevSharePrice,
                    sharePriceAfter,
                    block.timestamp
                );
            } catch {
                emit FailedHarvest(_vaults[i]);
            }
        }
    }

    /// @notice Silently performs a doHardWork (does not emit any events).
    function silentDoHardWork(address _vault) public {
        IVault(_vault).doHardWork();
    }

    /// @notice Adds a contract to the whitelist.
    /// @param _whitelistedAddress Address of the contract to whitelist.
    function addToWhitelist(address _whitelistedAddress) public onlyGovernance {
        CoreStorage.layout().whitelist[_whitelistedAddress] = true;
    }

    /// @notice Removes a contract from the whitelist.
    /// @param _whitelistedAddress Address of the contract to remove.
    function removeFromWhitelist(address _whitelistedAddress) public onlyGovernance {
        CoreStorage.layout().whitelist[_whitelistedAddress] = false;
    }

    /// @notice Exempts an address from deposit maturity and exit fees.
    /// @param _feeExemptedAddress Address to exempt from fees.
    function addFeeExemptAddress(address _feeExemptedAddress) public onlyGovernance {
        CoreStorage.layout().feeExemptAddresses[_feeExemptedAddress] = true;
    }

    /// @notice Removes an address from fee exemption
    /// @param _feeExemptedAddress Address to remove from fee exemption.
    function removeFeeExemptAddress(address _feeExemptedAddress) public onlyGovernance {
        CoreStorage.layout().feeExemptAddresses[_feeExemptedAddress] = false;
    }

    /// @notice Adds a list of addresses to the whitelist.
    /// @param _toWhitelist Addresses to whitelist.
    function batchWhitelist(address[] memory _toWhitelist) public onlyGovernance {
        for(uint256 i; i < _toWhitelist.length;) {
            CoreStorage.layout().whitelist[_toWhitelist[i]] = true;
            unchecked { ++i; }
        }
    }

    /// @notice Exempts a list of addresses from Beluga exit penalties.
    /// @param _toExempt Addresses to exempt.
    function batchExempt(address[] memory _toExempt) public onlyGovernance {
        for(uint256 i; i < _toExempt.length;) {
            CoreStorage.layout().feeExemptAddresses[_toExempt[i]] = true;
            unchecked { ++i; }
        }
    }

    /// @notice Adds an address to the legacy whitelist mechanism.
    /// @param _greyListedAddress Address to whitelist.
    function addToGreyList(address _greyListedAddress) public onlyGovernance {
        CoreStorage.layout().greyList[_greyListedAddress] = true;
    }

    /// @notice Removes an address from the legacy whitelist mechanism.
    /// @param _greyListedAddress Address to remove from whitelist.
    function removeFromGreyList(address _greyListedAddress) public onlyGovernance {
        CoreStorage.layout().greyList[_greyListedAddress] = false;
    }

    /// @notice Sets the numerator for protocol performance fees.
    /// @param _profitSharingNumerator New numerator for fees.
    function setProfitSharingNumerator(uint256 _profitSharingNumerator) public onlyGovernance {
        CoreStorage.layout().profitSharingNumerator  = _profitSharingNumerator;
    }

    /// @notice Sets the percentage of fees that are to be used for gas rebates.
    /// @param _rebateNumerator Percentage to use for buybacks.
    function setRebateNumerator(uint256 _rebateNumerator) public onlyGovernance {
        require(_rebateNumerator <= NUMERATOR, "FeeRewardForwarder: New numerator is higher than the denominator");
        CoreStorage.layout().rebateNumerator = _rebateNumerator;
    }

    /// @notice Sets the address of the reserve token.
    /// @param _reserveToken Reserve token for the protocol to collect.
    function setReserveToken(address _reserveToken) public onlyGovernance {
        CoreStorage.layout().reserveToken = _reserveToken;
    }

    /// @notice Adds a token to the list of transfer fee tokens.
    /// @param _transferFeeToken Token to add to the list.
    function addTransferFeeToken(address _transferFeeToken) public onlyGovernance {
        CoreStorage.layout().transferFeeTokens[_transferFeeToken] = true;
    }

    /// @notice Removes a token from the transfer fee tokens list.
    /// @param _transferFeeToken Address of the transfer fee token.
    function removeTransferFeeToken(address _transferFeeToken) public onlyGovernance {
        CoreStorage.layout().transferFeeTokens[_transferFeeToken] = false;
    }

    /// @notice Adds a keeper to the contract.
    /// @param _keeper Keeper to add to the contract.
    function addKeeper(address _keeper) public onlyGovernance {
        CoreStorage.layout().keepers[_keeper] = true;
    }

    /// @notice Removes a keeper from the contract.
    /// @param _keeper Keeper to remove from the contract.
    function removeKeeper(address _keeper) public onlyGovernance {
        CoreStorage.layout().keepers[_keeper] = false;
    }

    /// @notice Sets the route for token conversion.
    /// @param _tokenFrom Token to convert from.
    /// @param _tokenTo Token to convert to.
    /// @param _route Route used for conversion.
    function setTokenConversionRoute(
        address _tokenFrom,
        address _tokenTo,
        address[] memory _route
    ) public onlyGovernance {
        CoreStorage.layout().tokenConversionRoute[_tokenFrom][_tokenTo] = _route;
    }

    /// @notice Sets the router for token conversion.
    /// @param _tokenFrom Token to convert from.
    /// @param _tokenTo Token to convert to.
    /// @param _router Target router for the swap.
    function setTokenConversionRouter(
        address _tokenFrom,
        address _tokenTo,
        address _router
    ) public onlyGovernance {
        CoreStorage.layout().tokenConversionRouter[_tokenFrom][_tokenTo] = _router;
    }

    /// @notice Sets the routers used for token conversion.
    /// @param _tokenFrom Token to convert from.
    /// @param _tokenTo Token to convert to.
    /// @param _routers Target routers for the swap.
    function setTokenConversionRouters(
        address _tokenFrom,
        address _tokenTo,
        address[] memory _routers
    ) public onlyGovernance {
        CoreStorage.layout().tokenConversionRouters[_tokenFrom][_tokenTo] = _routers;
    }

    /// @notice Sets the pending governance address.
    /// @param _governance New governance address.
    function setGovernance(address _governance) public onlyGovernance {
        CoreStorage.layout().pendingGovernance = _governance;
    }

    /// @notice Transfers governance from the current to the pending.
    function acceptGovernance() public onlyGovernance {
        address prevGovernance = CoreStorage.layout().governance;
        address newGovernance = CoreStorage.layout().pendingGovernance;
        require(msg.sender == newGovernance);
        CoreStorage.layout().governance = newGovernance;
        CoreStorage.layout().pendingGovernance = address(0);
        emit GovernanceTransferred(prevGovernance, newGovernance);
    }

    function _performSwap(
        IUniswapV2Router02 _router,
        IERC20 _tokenFrom,
        uint256 _amount,
        address[] memory _route
    ) internal returns (uint256 endAmount) {
        _tokenFrom.safeApprove(address(_router), 0);
        _tokenFrom.safeApprove(address(_router), _amount);
        if(!CoreStorage.layout().transferFeeTokens[address(_tokenFrom)]) {
            uint256[] memory amounts = _router.swapExactTokensForTokens(_amount, 0, _route, address(this), (block.timestamp + 600));
            endAmount = amounts[amounts.length - 1];
        } else {
            _router.swapExactTokensForTokensSupportingFeeOnTransferTokens(_amount, 0, _route, address(this), (block.timestamp + 600));
            endAmount = IERC20(_route[_route.length - 1]).balanceOf(address(this));
        }
    }

    function _performMultidexSwap(
        address[] memory _routers,
        address _tokenFrom,
        uint256 _amount,
        address[] memory _route
    ) internal returns (uint256 endAmount) {
        for(uint256 i = 0; i < _routers.length; i++) {
            // Create swap route.
            address swapRouter = _routers[i];
            address[] memory conversionRoute = new address[](2);
            conversionRoute[0] = _route[i];
            conversionRoute[1] = _route[i+1];

            // Fetch balances.
            address routeStart = conversionRoute[0];
            uint256 routeStartBalance;
            if(routeStart == _tokenFrom) {
                routeStartBalance = _amount;
            } else {
                routeStartBalance = IERC20(routeStart).balanceOf(address(this));
            }
            
            // Perform swap.
            if(conversionRoute[1] != _route[_route.length - 1]) {
                _performSwap(IUniswapV2Router02(swapRouter), IERC20(routeStart), routeStartBalance, conversionRoute);
            } else {
                endAmount = _performSwap(IUniswapV2Router02(swapRouter), IERC20(routeStart), routeStartBalance, conversionRoute);
            }
        }
    }

    function _create(bytes memory _bytecode) internal returns (address deployed) {
        assembly {
            deployed := create(0, add(_bytecode, 0x20), mload(_bytecode))
        }
    }
}