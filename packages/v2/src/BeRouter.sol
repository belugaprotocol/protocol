// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IAssetAnchor} from "./interfaces/IAssetAnchor.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

/// @title Beluga BeRouter
/// @author Chainvisions
/// @notice Contract used for aggregating beToken deposits.

contract BeRouter {
    using SafeTransferLib for IERC20;
    using SafeTransferLib for IVault;

    /// @notice Address with control over the router.
    address public controller;

    /// @notice Anchor pool for a specific beToken.
    mapping(IVault => IAssetAnchor) public anchorForWrapper;

    constructor() {
        controller = msg.sender;
    }

    /// @notice Deposits into a beToken.
    /// @param _beToken beToken to deposit into.
    /// @param _amountIn Amount of tokens to deposit into the token.
    function depositToBeToken(
        IVault _beToken, 
        uint256 _amountIn
    ) external {
        require(tx.origin == msg.sender, "Must be tx.origin");
        IAssetAnchor _anchor = anchorForWrapper[_beToken];
        IERC20 _base = IERC20(_anchor.base());
        
        // Transfer base tokens in.
        _base.safeTransferFrom(msg.sender, address(this), _amountIn);

        // Check if we can completely use the anchor.
        uint256 totalBeAssets = ((_beToken.balanceOf(address(_anchor))) * 98) / 100;
        if(totalBeAssets >= _amountIn) {
            // In this case, we can completely use the anchor.
            _anchor.swapToPegged(_amountIn);
        } else {
            // In the case of insufficient pegged tokens then we must
            // swap as much as possible for the pegged asset and deposit the rest.
            _anchor.swapToPegged(totalBeAssets);
            _beToken.deposit(_amountIn - totalBeAssets);
        }

        _beToken.safeTransfer(msg.sender, _beToken.balanceOf(address(this)));
    }

    /// @notice Sets the anchor for a specific beToken.
    /// @param _beToken Vault to set the anchor for.
    /// @param _anchor Anchor of the specified beToken.
    function setAnchorForBeToken(
        IVault _beToken,
        IAssetAnchor _anchor
    ) external {
        require(msg.sender == controller, "Not controller");
        anchorForWrapper[_beToken] = _anchor;

        // Setup approvals.
        IERC20 base = IERC20(_anchor.base());
        base.safeApprove(address(_anchor), type(uint256).max);
        base.safeApprove(address(_beToken), type(uint256).max);
    }
}