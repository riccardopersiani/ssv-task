// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployMarketplace} from "../script/DeployMarketplace.s.sol";

import {Test} from "forge-std/Test.sol";

import {console} from "forge-std/console.sol";

import {Marketplace} from "../src/Marketplace.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract DeployAndUpgradeTest is Test {
    DeployMarketplace public deployMarketplace;
    address OWNER = makeAddr("Owner");
    address proxyAddress;
    Marketplace marketplace;
    uint8[] public providersIds;
    IWETH WETH = IWETH(0x4200000000000000000000000000000000000006);

    uint256 baseFork;

    function setUp() public {
        vm.label(OWNER, "Owner");
        vm.label(address(WETH), "WETH");
        vm.label(proxyAddress, "Proxy Marketplace");

        deployMarketplace = new DeployMarketplace();
        proxyAddress = deployMarketplace.deployMarketplace();
        marketplace = Marketplace(proxyAddress);
    }

    function testMarketplaceWorks() public view {
        uint8 expectedCounter = 0;

        assertEq(expectedCounter, marketplace.providersId());
    }

    function testRemoveTokenDecimals() public view {
        uint8 expectedValue = 10;

        assertEq(expectedValue, marketplace.removeTokenDecimals(10 * 10 ** 18));
    }

    function testRegisterAndRemoveProvider() public {
        vm.startPrank(OWNER);
        bytes32 key = "test";
        uint256 providerFee = 100 * 10 ** 18; // 100 LINK
        uint8 expectedCounter = 0;
        assertEq(expectedCounter, marketplace.providersId());
        marketplace.registerProvider(key, providerFee);

        assertEq(1, marketplace.providersId());

        uint8 expectedId = marketplace.keyToProviderId(key);
        assertEq(expectedId, 1);

        (uint256 subscribersNumber, uint256 fee, address owner, uint256 balance, bool isActive) =
            marketplace.getProviderState(1);

        assertEq(subscribersNumber, 0);
        assertEq(fee, providerFee);
        assertEq(owner, address(OWNER));
        assertEq(balance, 0);
        assertEq(isActive, true);

        vm.expectRevert("Only provider owner can call this function");
        marketplace.removeProvider(2);

        assertEq(true, marketplace.isProviderActive(1));
        marketplace.removeProvider(1);
        assertEq(false, marketplace.isProviderActive(1));

        vm.stopPrank();
    }

    function testRegisterProviderAndSubscriber() public {
        vm.startPrank(OWNER);
        bytes32 key = "test";
        uint256 providerFee = 100 * 10 ** 18; // 100 LINK
        uint8 expectedCounter = 0;
        assertEq(expectedCounter, marketplace.providersId());
        marketplace.registerProvider(key, providerFee);

        assertEq(1, marketplace.providersId());

        uint8 expectedId = marketplace.keyToProviderId(key);
        assertEq(expectedId, 1);

        (uint256 subscribersNumber, uint256 fee, address owner, uint256 balance, bool isActive) =
            marketplace.getProviderState(1);

        assertEq(subscribersNumber, 0);
        assertEq(fee, providerFee);
        assertEq(owner, address(OWNER));
        assertEq(balance, 0);
        assertEq(isActive, true);

        // vm.deal(OWNER, 10 ether);

        // WETH.deposit{value: 1 ether}();

        // WETH.approve(address(marketplace), 1 ether);
        // providersIds = [1];
        // marketplace.registerSubscriber(providersIds, 1 ether);

        // assertEq(false, marketplace.isSubscriberPaused(1));

        vm.stopPrank();
    }
}
