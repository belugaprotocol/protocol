// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IUpgradeSource} from "./interfaces/IUpgradeSource.sol";
import {BaseUpgradeabilityProxy} from "./lib/BaseUpgradeabilityProxy.sol";

/// @title Beluga Proxy
/// @author Chainvisions
/// @notice Proxy for Beluga's contracts.

contract BelugaProxy is BaseUpgradeabilityProxy {

    constructor(address _impl) {
        _setImplementation(_impl);
    }

    /**
    * The main logic. If the timer has elapsed and there is a schedule upgrade,
    * the governance can upgrade the contract
    */
    function upgrade() external {
        (bool should, address newImplementation) = IUpgradeSource(address(this)).shouldUpgrade();
        require(should, "Beluga Proxy: Upgrade not scheduled");
        _upgradeTo(newImplementation);

        // The finalization needs to be executed on itself to update the storage of this proxy
        // it also needs to be invoked by the governance, not by address(this), so delegatecall is needed
        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSignature("finalizeUpgrade()")
        );

        require(success, "Beluga Proxy: Issue when finalizing the upgrade");
    }

    function implementation() external view returns (address) {
        return _implementation();
    }
}