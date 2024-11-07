// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployMarketplace} from "../script/DeployMarketplace.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Marketplace} from "../src/Marketplace.sol";

contract DeployAndUpgradeTest is StdCheats, Test {
    DeployMarketplace public deployMarketplace;
    address public OWNER = address(1);

    function setUp() public {
        console.log('Starting test setup'); 
        deployMarketplace = new DeployMarketplace();
    }

    function testMarketplaceWorks() public {
        address proxyAddress = deployMarketplace.deployMarketplace();
        uint256 expectedCounter = 0;
        assertEq(expectedCounter, Marketplace(proxyAddress).getProviderCounter());
    }
}
