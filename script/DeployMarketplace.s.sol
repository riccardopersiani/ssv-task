// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract DeployMarketplace is Script {
    address OWNER = makeAddr("Owner");
    Marketplace marketplace;
    AggregatorV3Interface priceFeed = AggregatorV3Interface(0x48731cF7e84dc94C5f84577882c14Be11a5B7456);
    uint256 goerliFork;

    function run() external returns (address) {
        address proxy = deployMarketplace();
        return proxy;
    }

    function deployMarketplace() public returns (address) {
        vm.startBroadcast();

        marketplace = new Marketplace();
        ERC1967Proxy proxy = new ERC1967Proxy(address(marketplace), "");
        IERC20 WETH = IERC20(0x4200000000000000000000000000000000000006);

        Marketplace(address(proxy)).initialize(
            OWNER, address(WETH), address(0x48731cF7e84dc94C5f84577882c14Be11a5B7456)
        );
        vm.stopBroadcast();
        return address(proxy);
    }

    function setUp() public {
        goerliFork = vm.createFork("https://mc-12.p123yippy.com/12ase525c5012");
        vm.selectFork(goerliFork);

        address proxy = deployMarketplace();
        console.log(proxy);
    }
}
