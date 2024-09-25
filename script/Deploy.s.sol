// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Launchpad.sol";
import "../src/LaunchpadToken.sol";
import "../src/Gauge.sol";
import "../src/LpHolder.sol";
import "../src/ConstantProductCurve.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "Invalid PRIVATE_KEY: missing hex prefix (0x)");

        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        address feeReceiver = address(0xbDf433bB8CBF4140AE30B7Adef1614a7a1ce9776);
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        // Deploy LaunchpadToken implementation
        LaunchpadToken tokenImpl = new LaunchpadToken();
        console.log("LaunchpadToken implementation deployed to:", address(tokenImpl));

        // Deploy Gauge implementation
        Gauge gaugeImpl = new Gauge(
            IUniswapV2Router02(0x56A364f7355765f9d0457ee131aBFA06D7cb2e73), // Uniswap V2 Router
            IUniswapV2Factory(0xCEaB4e71463c643B7E5776D14995D8015e1Fa14b), // Uniswap V2 Factory
            IWETH(0x2911a1AB18546cb501628Be8625C7503a2A7DB54), // WETH
            feeReceiver // Fee receiver (set to deployer for now)
        );
        console.log("Gauge implementation deployed to:", address(gaugeImpl));

        // Deploy LpHolder
        LpHolder lpHolder = new LpHolder(feeReceiver); // Fee receiver (set to deployer for now)
        console.log("LpHolder deployed to:", address(lpHolder));

        // Deploy ConstantProductCurve
        ConstantProductCurve curve = new ConstantProductCurve();
        console.log("ConstantProductCurve deployed to:", address(curve));

        // Deploy Launchpad
        Launchpad launchpad = new Launchpad(
            address(tokenImpl),
            address(gaugeImpl),
            address(curve),
            deployer, // Treasury (set to deployer for now)
            address(lpHolder), // LP receiver
            feeReceiver, // Fee receiver (set to deployer for now)
            0.01 ether, // Creation cost (0.01 ETH)
            0.01e18, // Booster fraction (1%)
            IUniswapV2Router02(0x56A364f7355765f9d0457ee131aBFA06D7cb2e73), // Uniswap V2 Router
            IUniswapV2Factory(0xCEaB4e71463c643B7E5776D14995D8015e1Fa14b), // Uniswap V2 Factory
            IWETH(0x2911a1AB18546cb501628Be8625C7503a2A7DB54) // WETH
        );
        console.log("Launchpad deployed to:", address(launchpad));

        launchpad.setGaugeFees(Gauge.FeeParameters({
            buyFee: 0.01e18, // 1% buy fee
            sellFee: 0.01e18 // 1% sell fee
        }));
        console.log("Launchpad gauge fees set");

        launchpad.setBondingCurveFraction(0.8e18); // 80% of token supply used in bonding curve
        console.log("Launchpad bonding curve fraction set");

        // Example of creating a new token (you may want to move this to a separate script)
        LaunchpadToken.TokenConfig memory tokenConfig = LaunchpadToken.TokenConfig({
            name: "Example Token",
            symbol: "EXT",
            initialSupply: 1000000 * 1e18 // 1 million tokens
        });

        LaunchpadToken.TokenMetadataConfig memory metadataConfig = LaunchpadToken.TokenMetadataConfig({
            ipfsHash: "",
            website: "",
            twitter: "",
            telegram: "",
            description: "An example token",
            metadata: ""
        });

        Gauge.CurveParameters memory curveParameters = Gauge.CurveParameters({
            yMin: 0.0001 ether, // Minimum price
            yMax: 0.01 ether    // Maximum price
        });

        Launchpad.AutoSnipeConfig memory snipeConfig = Launchpad.AutoSnipeConfig({
            minAmountOut: 1000 * 1e18 // Minimum 1000 tokens
        });

        (LaunchpadToken newToken, Gauge newGauge) = launchpad.createLaunchpadToken{value: 0.01 ether}(
            tokenConfig,
            metadataConfig,
            snipeConfig,
            curveParameters
        );

        console.log("New token created at:", address(newToken));
        console.log("New gauge created at:", address(newGauge));

        vm.stopBroadcast();
    }
}