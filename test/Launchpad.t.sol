// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Launchpad.sol";
import "../src/LaunchpadToken.sol";
import "../src/Gauge.sol";
import "../src/LpHolder.sol";
import "../src/ConstantProductCurve.sol";

contract LaunchpadTest is Test {
    Launchpad public launchpad;
    LaunchpadToken public tokenImpl;
    Gauge public gaugeImpl;
    LpHolder public lpHolder;
    ConstantProductCurve public curve;

    address public deployer;
    address public user1;
    address public user2;
    address public treasury;
    address public feeReceiver;

    // Uniswap V2 addresses (replace with actual testnet addresses if needed)
    address constant UNISWAP_V2_ROUTER =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function setUp() public {
        deployer = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        treasury = address(0x3);
        feeReceiver = address(0x4);

        vm.startPrank(deployer);

        tokenImpl = new LaunchpadToken();
        gaugeImpl = new Gauge(
            IUniswapV2Router02(UNISWAP_V2_ROUTER),
            IUniswapV2Factory(UNISWAP_V2_FACTORY),
            IWETH(WETH),
            feeReceiver
        );
        lpHolder = new LpHolder(deployer);
        curve = new ConstantProductCurve();

        launchpad = new Launchpad(
            address(tokenImpl),
            address(gaugeImpl),
            address(curve),
            treasury, // Use the new treasury address
            address(lpHolder),
            feeReceiver, // feeReceiver
            0.01 ether, // creationCost
            0.01e18, // boosterFraction (1%)
            IUniswapV2Router02(UNISWAP_V2_ROUTER),
            IUniswapV2Factory(UNISWAP_V2_FACTORY),
            IWETH(WETH)
        );
        launchpad.setGaugeFees(
            Gauge.FeeParameters({
                buyFee: 0.01e18, // 1% buy fee
                sellFee: 0.01e18 // 1% sell fee
            })
        );

        launchpad.setBondingCurveFraction(0.8e18); // 80% of token supply used in bonding curve

        vm.stopPrank();

        vm.deal(treasury, 1 ether);
        vm.deal(feeReceiver, 1 ether);
    }

    function testCreateToken() public {
        vm.startPrank(user1);
        vm.deal(user1, 1 ether);

        LaunchpadToken.TokenConfig memory tokenConfig = LaunchpadToken
            .TokenConfig({
                name: "Test Token",
                symbol: "TEST",
                initialSupply: 1000000 * 1e18 // 1 million tokens
            });

        LaunchpadToken.TokenMetadataConfig
            memory metadataConfig = LaunchpadToken.TokenMetadataConfig({
                ipfsHash: "",
                website: "",
                twitter: "",
                telegram: "",
                description: "A test token",
                metadata: ""
            });

        Gauge.CurveParameters memory curveParameters = Gauge.CurveParameters({
            yMin: 0.0001 ether, // Minimum price
            yMax: 0.01 ether // Maximum price
        });

        Launchpad.AutoSnipeConfig memory snipeConfig = Launchpad
            .AutoSnipeConfig({
                minAmountOut: 1000 * 1e18 // Minimum 1000 tokens
            });

        (LaunchpadToken newToken, Gauge newGauge) = launchpad
            .createLaunchpadToken{value: 0.02 ether}(
            tokenConfig,
            metadataConfig,
            snipeConfig,
            curveParameters
        );
        // Verify that the feeReceiver is set correctly
        assertEq(newGauge.feeReceiver(), feeReceiver);
        assertEq(newToken.name(), "Test Token");
        assertEq(newToken.symbol(), "TEST");
        assertEq(newToken.totalSupply(), 1000000 * 1e18);

        address gaugeAddress = launchpad.tokenToGauge(address(newToken));
        assertEq(gaugeAddress, address(newGauge));

        vm.stopPrank();
    }

    function testBuyAndSellTokens() public {
        // First, create a token
        testCreateToken();

        address tokenAddress = launchpad.getAllTokens()[0];
        LaunchpadToken token = LaunchpadToken(tokenAddress);
        Gauge gauge = Gauge(launchpad.tokenToGauge(tokenAddress));

        vm.startPrank(user2);
        vm.deal(user2, 1 ether);

        // Buy tokens
        uint256 buyAmount = 1000 * 1e18; // 1000 tokens
        (uint256 actualBuyAmount, uint256 ethCost) = launchpad
            .quoteBuyExactTokens(tokenAddress, buyAmount);
        launchpad.buyExactTokens{value: ethCost}(tokenAddress, actualBuyAmount);

        assertEq(token.balanceOf(user2), actualBuyAmount);

        // Sell tokens
        uint256 sellAmount = 500 * 1e18; // 500 tokens
        uint256 ethBeforeSell = user2.balance;
        token.approve(address(launchpad), sellAmount);
        launchpad.sellExactTokens(tokenAddress, sellAmount, 0); // 0 minAmountOut for simplicity

        assertEq(gauge.feeReceiver(), feeReceiver);
        assertEq(token.balanceOf(user2), actualBuyAmount - sellAmount);
        assertTrue(user2.balance > ethBeforeSell);

        vm.stopPrank();
    }

    function testGaugeClosable() public {
        testCreateToken();

        address tokenAddress = launchpad.getAllTokens()[0];
        Gauge gauge = Gauge(launchpad.tokenToGauge(tokenAddress));

        // Buy almost all available tokens
        uint256 availableTokens = gauge.tokenTarget() - gauge.tokenPurchased();
        uint256 buyAmount = availableTokens - 1e18; // Leave 1 token unbought

        vm.startPrank(user2);
        vm.deal(user2, 100 ether);

        (uint256 actualBuyAmount, uint256 ethCost) = launchpad
            .quoteBuyExactTokens(tokenAddress, buyAmount);
        launchpad.buyExactTokens{value: ethCost}(tokenAddress, actualBuyAmount);

        assertFalse(gauge.gaugeClosable());

        // Buy the last token
        launchpad.buyExactTokens{value: 1 ether}(tokenAddress, 1e18);
        assertEq(gauge.feeReceiver(), feeReceiver);
        assertTrue(gauge.gaugeClosable());

        vm.stopPrank();
    }

    function testLaunchPool() public {
        testCreateToken();

        address tokenAddress = launchpad.getAllTokens()[0];
        LaunchpadToken token = LaunchpadToken(tokenAddress);
        Gauge gauge = Gauge(launchpad.tokenToGauge(tokenAddress));

        // Buy all available tokens
        uint256 availableTokens = gauge.tokenTarget() - gauge.tokenPurchased();

        vm.startPrank(user2);
        vm.deal(user2, 100 ether);

        (uint256 actualBuyAmount, uint256 ethCost) = launchpad
            .quoteBuyExactTokens(tokenAddress, availableTokens);
        launchpad.buyExactTokens{value: ethCost}(tokenAddress, actualBuyAmount);

        vm.stopPrank();

        // Ensure all tokens are purchased
        assertEq(
            gauge.tokenPurchased(),
            gauge.tokenTarget(),
            "Not all tokens purchased"
        );

        // Ensure the gauge is closable
        assertTrue(gauge.gaugeClosable(), "Gauge is not closable");

        // Check the ETH balance of the Gauge
        uint256 gaugeEthBalance = address(gauge).balance;
        emit log_named_uint("Gauge ETH balance", gaugeEthBalance);

        // Launch the pool through the Launchpad contract
        vm.prank(address(this)); // Use the test contract address, which should be the owner of the Launchpad

        try launchpad.launchPool(tokenAddress) returns (address poolAddress) {
            assertTrue(
                poolAddress != address(0),
                "Pool address should not be zero"
            );
            assertEq(gauge.pool(), poolAddress, "Pool address mismatch");
            assertFalse(
                gauge.gaugeActive(),
                "Gauge should not be active after launch"
            );
        } catch Error(string memory reason) {
            emit log(reason);
            assertTrue(false, string.concat("LaunchPool failed: ", reason));
        } catch Panic(uint256 errorCode) {
            emit log_named_uint("Panic code", errorCode);
            assertTrue(
                false,
                string.concat(
                    "LaunchPool failed with Panic code: ",
                    vm.toString(errorCode)
                )
            );
        } catch (bytes memory lowLevelData) {
            string memory decodedError = abi.decode(lowLevelData, (string));
            emit log(decodedError);
            assertTrue(
                false,
                string.concat("LaunchPool failed with error: ", decodedError)
            );
        }
    }

    function assertETHBalanceChange(
        address account,
        uint256 expectedChange,
        function() internal txFunc
    ) internal {
        uint256 balanceBefore = account.balance;
        txFunc();
        uint256 balanceAfter = account.balance;
        assertEq(
            balanceAfter,
            balanceBefore + expectedChange,
            "Unexpected ETH balance change"
        );
    }
}
