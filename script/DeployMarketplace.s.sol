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

contract MockPriceFeed is AggregatorV3Interface {
    int256 private _price;

    constructor(int256 initialPrice) {
        _price = initialPrice;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _price, block.timestamp, block.timestamp, 0);
    }

    // Other required functions from AggregatorV3Interface can be empty stubs if unused
    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 0, 0, 0, 0);
    }
}

contract DeployMarketplace is Script {
    address OWNER = makeAddr("Owner");
    Marketplace public marketplace;
    AggregatorV3Interface public priceFeed;
    uint256 goerliFork;

    function run() external returns (address) {
        address proxy = deployMarketplace();
        return proxy;
    }

    function deployMarketplace() public returns (address) {
        vm.startBroadcast();

        priceFeed = new MockPriceFeed(2000 * 10 ** 8); // 2000 USD per WETH with 18 decimals

        marketplace = new Marketplace();
        ERC1967Proxy proxy = new ERC1967Proxy(address(marketplace), "");
        IERC20 WETH = IERC20(0x4200000000000000000000000000000000000006);

        Marketplace(address(proxy)).initialize(OWNER, address(WETH), address(priceFeed));
        vm.stopBroadcast();
        return address(proxy);
    }

    // function setUp() public {
    //     goerliFork = vm.createFork("https://mc-12.p123yippy.com/12ase525c5012");
    //     vm.selectFork(goerliFork);

    //     address proxy = deployMarketplace();
    //     console.log(proxy);
    // }
}
