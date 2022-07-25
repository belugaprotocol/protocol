// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

library CoreStorage {
    enum StrategyType {
        Autocompound,
        Maximizer
    }

    struct RegistryData {
        StrategyType strategyType;
        address vaultAddress;
        address underlyingAddress;
    }

    struct Layout {
        address governance;
        address pendingGovernance;
        uint256 profitSharingNumerator;
        uint256 rebateNumerator;
        address reserveToken;
        address latestVaultImplementation;

        RegistryData[] registeredVaults;
        mapping(address => bool) whitelist;
        mapping(address => bool) feeExemptAddresses;
        mapping(address => bool) greyList;
        mapping(address => bool) keepers;
        mapping(address => uint256) lastHarvestTimestamp;
        mapping(address => bool) transferFeeTokens;
        mapping(address => mapping(address => address[])) tokenConversionRoute;
        mapping(address => mapping(address => address)) tokenConversionRouter;
        mapping(address => mapping(address => address[])) tokenConversionRouters;
    }

    function layout() internal pure returns (Layout storage l) {
        assembly {
            l.slot := 0xcde5d6681cd66b99988b4e3d60bae2ea05fc7abf248cc30b7469951d43b482c3
        }
    }
}