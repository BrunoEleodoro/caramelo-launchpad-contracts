// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'solmate/tokens/ERC20.sol';

contract CustomERC20 is ERC20 {
    string public description;
    string public imageURL;

    constructor(
        string memory name,
        string memory symbol,
        string memory _description,
        string memory _imageURL,
        address initialAccount,
        uint256 initialBalance
    ) ERC20(name, symbol, 18) {
        description = _description;
        imageURL = _imageURL;
        _mint(initialAccount, initialBalance);
    }
}
