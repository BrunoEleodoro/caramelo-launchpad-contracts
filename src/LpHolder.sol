// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV2Pair } from "./external/IUniswapV2Pair.sol";

/**
 * @title   LP Holder
 * @notice  Permanently locks and collects fees from UniV3 LP positions
 */
contract LpHolder is ERC721Holder, Ownable {
    

    ////////////////////////////////////////////////////////////////////////////////
    // STATE
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Receives fees collected from UniV3 LP positions
    address public feeReceiver;

    ////////////////////////////////////////////////////////////////////////////////
    // CONSTRUCTION AND INITIALIZATION
    ////////////////////////////////////////////////////////////////////////////////

    
    constructor(address _feeReceiver) Ownable(msg.sender) {
        if (_feeReceiver == address(0)) revert LpHolder__ZeroAddress();
        feeReceiver = _feeReceiver;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // FEE MANAGEMENT
    ////////////////////////////////////////////////////////////////////////////////

     /**
     * @notice  Collect fees from UniV2 LP positions
     * @param   pairs    Array of Uniswap V2 pair addresses
     */
    function collectFees(address[] calldata pairs) external {
        if (pairs.length == 0) revert LpHolder__ZeroLength();

        for (uint256 i = 0; i < pairs.length; i++) {
            IUniswapV2Pair pair = IUniswapV2Pair(pairs[i]);
            pair.sync(); // Update reserves and collect fees
            uint256 balance = pair.balanceOf(address(this));
            if (balance > 0) {
                pair.transfer(feeReceiver, balance);
            }
        }
    }

     /**
     * @notice  Sweep tokens from the contract
     * @param   token   Token to sweep
     */
    function sweep(address token) external onlyOwner {
        IERC20(token).transfer(feeReceiver, IERC20(token).balanceOf(address(this)));
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ADMINISTRATION
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Set the fee receiver
     * @param   _feeReceiver    New fee receiver
     */
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        if (_feeReceiver == address(0)) revert LpHolder__ZeroAddress();
        emit FeeReceiverSet(_feeReceiver, feeReceiver);
        feeReceiver = _feeReceiver;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////////

    event FeeReceiverSet(address newFeeReceiver, address oldFeeReceiver);

    ////////////////////////////////////////////////////////////////////////////////
    // ERRORS
    ////////////////////////////////////////////////////////////////////////////////

    error LpHolder__ZeroAddress();
    error LpHolder__ZeroLength();
}
