// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Marketplace is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    IERC20 public officialToken;
    AggregatorV3Interface internal priceFeed;

    event Withdrawal(address indexed provider, uint256 amount, uint256 usdEquivalent);

    // NOTE: the choice of sizes of uint has to be done carefully do allow the most efficient storage possible => See structs!
    uint256 internal value;
    // constant allow to save more gas
    uint8 public constant MAX_PROVIDERS = 200; // uint8 can contain 0-255, saving space where possible
    uint64 public minFee; // MAX fee allowed is 2^64-1, more than enough for any potential change, considering this is always gonna be in USD, using 6 deimals to give more control over decimals settings. 18 would be unnecessary
    // used also for generating a unique provider ID
    uint128 minPrice;
    uint8 public providerCounter; // different from Id cause the counter can decrement when a provider is removed and deleted
    uint128 public subscribersId;
    uint8 public providersId;
    address public token;

    // storing providers in this way implies looping over the keys to find duplicates, which is not efficient.
    // however, mapping keys to addresses would make the provider removal ineffiecient, as we would need to loop over the keys to find the address to remove.
    // mapping (address => bytes32[]) public providerKeys;
    mapping(uint8 => Provider) public providers;
    mapping(uint256 => Subscriber) public subscribers;
    mapping(bytes32 => uint8) public keyToProviderId;

    // NOTE: GAS OPTIMIZATION!
    // A struct in the storage can be packed, placing smaller data types together so they can fit in 1 word which is 32 bytes.
    // This is done by ordering the struct members by size, from largest to smallest. The reverse approach is also correct
    // NOTE: TRADEOFF: packing structs efficiently comes at the cost of readability!
    struct Provider {
        uint256 balance; // 32 bytes
        uint128 subscribersNumber; // could reduce to 128 // we don't need the subscriber ids, just the number of subscribers, otherwise a big array here could be too expensive and redundant // i need this data just to calculate the due amount
        uint64 fee; // 8 bytes
        uint8 id; // 1 byte
        bool isActive; // 1 byte
        address owner; // 20 bytes
    }

    // NOTE: GAS OPTIMIZATION! Same for above
    struct Subscriber {
        uint256 id; // 32 bytes
        uint256 balance; // 32 bytes
        address owner; // 20 bytes
        bool isPaused; // 1 byte
        uint8[] subscribedProviders; // unknown
    }

    modifier onlyProviderOwner(uint8 id) {
        require(msg.sender == providers[id].owner, "Only provider owner can call this function");
        _;
    }

    modifier onlySubscriptionOwner(uint128 id) {
        require(msg.sender == subscribers[id].owner, "Only subscriber owner can call this function");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @param _owner The owner of the contract
    /// @param _tokenAddress The address of the offical token to be used in the marketplace for paying the fees and monthly subscriptions
    /// @param _chainlinkAddress The address of the chainlink price feed to be used for fetching the token price
    function initialize(address _owner, address _tokenAddress, address _chainlinkAddress) public initializer {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_chainlinkAddress != address(0), "Invalid price feed address");
        // The contract need an owner to be able to perform administrative tasks, from more complex operations lie upgrading the contract to updating the min fee, etc..
        __Ownable_init(_owner);
        // The contract is upgradeable without the need of a proxy admin, keeping the things more simple. DOCS: https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol
        __UUPSUpgradeable_init();
        providerCounter = 0;
        // Using simple incremental ids to avoid duplicates
        subscribersId = 0;
        providersId = 0;
        // Hardcoding since requested from the specs
        minFee = 50 * 10 ** 6; // 50 USD in 6 decimals
        officialToken = IERC20(_tokenAddress);
        // initialize chainlink price feed
        priceFeed = AggregatorV3Interface(_chainlinkAddress);
    }

    /// @notice Register a new provider, they can register providing:
    /// @param key The key to be used to identify the provider and has to be unique
    function registerProvider(bytes32 key, uint64 fee) external {
        require(providerCounter < MAX_PROVIDERS, "Provider limit reached");
        require(keyToProviderId[key] == 0, "registration key already exists");
        int256 usdEquivalent = fetchTokenPriceFromChainlink();
        // TODO: here decimals have to be considered, the comparison has to happen between variables that use the same decimals setup
        require(uint256(fee) * uint256(usdEquivalent) >= minFee, "Fee too low");

        // if pre-validation checks are passing, we can proceed with the registration
        Provider storage provider = providers[providersId];
        provider.balance = 0;
        provider.owner = msg.sender;
        provider.id = providersId;
        provider.isActive = true;
        provider.fee = fee;
        provider.subscribersNumber = 0;

        // once the provider is registered, we can store the key and the id, so that the key cannot be used anymore
        keyToProviderId[key] = providersId;
        // increment the provider id
        providersId++;
        // increment the provider counter
        providerCounter++;
    }

    function deactivateProvider(uint8 id) external onlyProviderOwner(id) {
        providers[id].isActive = false;
    }

    function activateProvider(uint8 id) external onlyProviderOwner(id) {
        providers[id].isActive = true;
    }

    /// @notice Remove a provider from the marketplace and transfer the remaining balance to the owner
    /// @param id The id of the provider to be removed
    function removeProvider(uint8 id) external onlyProviderOwner(id) {
        // The modified 
        officialToken.transfer(msg.sender, providers[id].balance);
        // TODO: instead of deleting the logic could just decativate the provider; even tho deleting would free some storage, cause there is a gas refund
        delete providers[id];
        providerCounter--;
    }

    /// @notice Create a subcriber 
    function createSubscriber() external {
        Subscriber storage subscriber = subscribers[subscribersId];
        subscriber.id = subscribersId;
        subscriber.balance = 0;
        subscriber.owner = msg.sender;
        subscriber.isPaused = false;
        subscriber.subscribedProviders = new uint8[](0);

        subscribersId++;
    }

    /// @notice Register a new subscriber

    function registerSubscriber(uint128 id, uint8[] memory providersIds) external onlySubscriptionOwner(id) {
        require(providersIds.length < MAX_PROVIDERS, "Cannot register to more than available");
        require(subscribers[id].isPaused == false, "Cannot register if paused");
        require(subscribers[id].balance * uint256(fetchTokenPriceFromChainlink()) > 100, "Balance too low");

        // todo: REQUIRE: double check that the provider is active or exists - otherwise revert

        Subscriber storage subscriber = subscribers[subscribersId];
        subscriber.subscribedProviders = providersIds;

    }

    function getProviderState() public view returns (Provider memory) {
        return providers[providersId];
    }

    function getProviderCounter() public view returns (uint8) {
        return providerCounter;
    }

    function isProviderActive(uint8 id) public view returns (bool) {
        return providers[id].isActive;
    }

    function isSubscriberPaused(uint256 id) public view returns (bool) {
        return subscribers[id].isPaused;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function withdrawProviderFunds(uint8 id, uint256 amount) external onlyProviderOwner(id) {
        // only provider owner can withdraw funds
        require(providers[id].balance > 0, "No funds to withdraw");
        require(providers[id].balance >= amount, "Insufficient funds");
        officialToken.approve(msg.sender, amount); //todo: fix, this needs to approve the sender to move tokens from this contract
        officialToken.transfer(msg.sender, amount);
        providers[id].balance -= amount;
        uint256 usdEquivalent = amount * uint256(fetchTokenPriceFromChainlink());
        emit Withdrawal(msg.sender, amount, usdEquivalent);
    }

    // NOTE: decided not to put a modifier so that you can find any existent subscription ( and even if paused )
    function depositToSubscription(uint128 id, uint256 amount) external {
        officialToken.transferFrom(msg.sender, address(this), amount);
        subscribers[id].balance += amount;
    }

    function calculateProviderEarnings() external {
        // todo update provider balance
    }

    /// CAUTION: this function is not safe as it is, it should have more checks over decimals and over stale price data!
    /// @notice Fetch the token price from chainlink
    /// @return price The price of the token in USD
    function fetchTokenPriceFromChainlink() internal view returns (int256 price ) {
        // @TODO: no check for stale price data, known oracle problem, never trust third party data, especially oracles
        // Ideally also to take into account: When working with Oracle price feeds, developers must account for different price feeds having different decimal precision; it is an error to assume that every price feed will report prices using the same precision. Generally, non-ETH pairs report using 8 decimals, while ETH pairs report using 18 decimals.
        (, price,,,) = priceFeed.latestRoundData();
        return price / 10 ** 8; // from the chainlining docs, the price is returned with 8 decimals
    }

    function getSubscriberDepositValueUSD(uint256 subscriberId) external view returns (uint256) {
        // todo get subscriber deposit value in USD
    }
}
