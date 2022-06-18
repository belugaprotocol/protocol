// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

/// @title BAI Storage
/// @author Chainvisions
/// @notice Diamond storage logic for Beluga's BAI stablecoin.

library BaiStorage {

    /// @notice Storage structure for BAI collaterals.
    struct Collateral {
        // Minting/collateral state.
        uint128 totalMinted;
        uint128 mintCap;
        mapping(address => uint256) userBorrowDebt;
        mapping(address => uint256) userCollateralSupply;

        // Reward state.
        uint32 duration;
        uint32 periodFinish;
        uint32 lastUpdateTime;
        uint128 rewardRate;
        uint128 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewardsForToken;
    }

    /// @notice Storage structure for BAI TWAPs.
	struct Pair {
        bool lastIsA;
		bool initialized;
        uint32 updateA;
		uint32 updateB;
		uint256 priceCumulativeA;
		uint256 priceCumulativeB;
	}

    /// @notice Diamond storage layout for BAI.
    struct Layout {
        /// @notice Collateral state for each token supported.
        mapping(address => Collateral) collateralForToken;
    }

    function layout() internal pure returns (Layout storage l) {
        assembly {
            // We hardcode this slot to use less bytecode
            // and save a small amount of gas not needing an MSTORE.
            l.slot := 0xe4d42545ba2db98532654131d0afb50300a4608429cf6b57199f590b2c4a3f57
        }
    }
}