// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CustomERC20.sol";
import "./external/IUniswapV2Factory.sol";
import "./external/IUniswapV2Router02.sol";

contract MemeCoinFactory {
    address public uniswapRouter;
    address public uniswapFactory;
    address public WETH;

    event CoinCreated(address indexed token, address indexed pair);

    constructor(address _uniswapRouter, address _uniswapFactory, address _WETH) {
        uniswapRouter = _uniswapRouter;
        uniswapFactory = _uniswapFactory;
        WETH = _WETH;
    }

    function createMemeCoin(
        string memory name,
        string memory symbol,
        string memory description,
        string memory imageURL,
        uint256 initialSupply
    ) external payable returns (address token, address pair) {
        // Deploy new ERC20 token
        CustomERC20 newToken = new CustomERC20(
            name,
            symbol,
            description,
            imageURL,
            address(this),
            initialSupply
        );
        token = address(newToken);

        // Approve tokens for the router
        newToken.approve(uniswapRouter, initialSupply);

        // Add liquidity to Uniswap
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);
        router.addLiquidityETH{value: msg.value}(
            token,
            initialSupply,
            0,
            0,
            msg.sender,
            block.timestamp + 1200
        );

        // Get the pair address
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapFactory);
        pair = factory.getPair(token, WETH);

        emit CoinCreated(token, pair);
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
