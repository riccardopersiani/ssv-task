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

    // GAS OPTIMIZATION!
    // NOTE: the choice of sizes of variables (uint, bytes, struct) has to be done carefully,
    // to allow the most efficient storage possible!

    // CONSTANTS allow to save more gas
    uint8 public constant MAX_PROVIDERS = 200; // using uint8 can contain 0-255, saving space where possible
    uint8 public constant MINIMUN_DEPOSIT = 100;
    uint8 public constant MINIMUM_FEE = 50;

    uint64 public subscribersId; // NOTE: uint32 would have been reasonable but decided to use 64 in case the service become ultra popular and to avoid the infamous youtube video counter issue ( 32 bit overflow )!
    uint8 public providersId; // 0-255 is enough for the providers with cap to 200
    address public token; // the official token address to be used in the marketplace

    bool isUpgradable; // Flag to lock the contract and prevent further upgrades

    // ID -> Provider
    mapping(uint8 => Provider) public providers;
    // ID -> Subscriber
    mapping(uint64 => Subscriber) public subscribers;
    // Key -> Provider ID
    mapping(bytes32 => uint8) public keyToProviderId;

    // NOTE: GAS OPTIMIZATION!
    // A struct in the storage can be packed by placing smaller data types together so they can fit in 1 word/slot (which is 32 bytes).
    // This is done by ordering the struct members by size, from largest to smallest. The reverse approach is also correct.
    // NOTE: TRADEOFF: packing structs efficiently comes at the cost of readability as you can see!
    struct Provider {
        uint256 balance; // 32 bytes
        uint256 earnings; // 32 bytes
        uint256 lastWithdrawTime; // Last time the provider withdrew
        uint256 fee; // 32 bytes
        uint64 subscribersNumber; // could reduce to 128 // we don't need the subscriber ids, just the number of subscribers, otherwise a big array here could be too expensive and redundant // i need this data just to calculate the due amount
        uint8 id; // 1 byte
        bool isActive; // 1 byte
        address owner; // 20 bytes
    }

    // NOTE: GAS OPTIMIZATION! Same for above
    struct Subscriber {
        uint256 balance; // 32 bytes
        uint8[] subscribedProviders; // Up to 200 providers, the length slot + 1 byte per each provider
        bool isPaused; // 1 byte
        uint64 id; // 8 bytes
        address owner; // 20 bytes
    }

    // NOTE: Serves 2 puposes, check that the sender is the owner of the provider and that the provider exists
    modifier onlyProviderOwner(uint8 id) {
        require(msg.sender == providers[id].owner, "Only provider owner can call this function");
        _;
    }

    // NOTE: Serves 2 puposes, check that the sender is the owner of the provider and that the subscirption exists
    modifier onlySubscriptionOwner(uint64 id) {
        require(msg.sender == subscribers[id].owner, "Only subscriber owner can call this function");
        _;
    }

    /// NOTE: common pattern used to prevent the contract from being initialized outside of a proxy context.
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
        // NOTE: Using simple incremental ids to avoid duplicates and using them as counters too. Us
        subscribersId = 0;
        providersId = 0;
        officialToken = IERC20(_tokenAddress);
        // Initialize chainlink price feed with right Chainlink address depending on the network
        priceFeed = AggregatorV3Interface(_chainlinkAddress);
        // The contract is upgradable by default
        isUpgradable = true;
    }

    /// @notice Locks the contract to prevent further upgrades permanently
    function lockUpgradeability() external onlyOwner {
        isUpgradable = false;
    }

    /// @dev Authorize an upgrade if the contract is upgradeable
    /// @param newImplementation The address of the new contract implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(isUpgradable, "Contract is locked and cannot be upgraded");
    }

    /// @notice Register a new provider, they can register providing:
    /// @param key The key to be used to identify the provider and has to be unique
    /// @param fee The monthly fee the provider wants to charge for the service
    function registerProvider(bytes32 key, uint256 fee) external {
        // FROM THE SPECS: There is also a maximum limit on the number of Providers that can be registered (200).
        require(providersId <= MAX_PROVIDERS, "Provider limit reached");
        // FROM THE SPECS: The system prevents a Provider from registering using the same key more than once.
        require(keyToProviderId[key] == 0, "registration key already exists");
        int256 usdEquivalent = fetchTokenPriceFromChainlink();
        // FROM THE SPECS: The system should check that the minimum fee amount is worth at least $50 based on the current token price from Chainlink.
        // TODO: here decimals have to be considered, the comparison has to happen between variables that use the same decimals setup.
        require(fee * uint256(usdEquivalent) >= MINIMUM_FEE, "Fee too low");

        // Increment the provider id / counter; the first provider will have id 1
        providersId++;

        // If pre-validation checks have passed, we can proceed with the registration
        Provider storage provider = providers[providersId];
        provider.balance = 0;
        provider.earnings = 0;
        provider.owner = msg.sender;
        provider.id = providersId;
        provider.isActive = true;
        provider.fee = fee;
        provider.subscribersNumber = 0;
        // Starts the 30 days countdown for withdrawing the earnings
        provider.lastWithdrawTime = block.timestamp;

        // Once the provider is registered, we can store the key and the id, so that the key cannot be used anymore!
        // FROM THE EMAIL: the verification of their uniqueness is done on the contract side.
        keyToProviderId[key] = providersId;
    }

    // FROM THE EMAIL: On the second question, this is up to your implementation. 
    // An inactive provider doesn't provide services (like pausing it) but can resume operations later. A removed provider can not be reactivated later.
    
    // JUSTIFYING THE CHOSEN APPROACH: both approaches have pros and cons; not deleting providers means that more storage is gonna be used; 
    // however, re-activating an inactive provider is a cheaper and more appealing feature to offer than create-delete-recreate a Provider.
    // Also deleting could led to loss of earnings not withdrawn. 

    /// @notice Remove a provider from the marketplace and transfer the remaining balance to the owner
    /// FROM THE SPECS: Providers can be removed from the system, but only by their respective owners.
    /// @param id The id of the provider to be removed
    function removeProvider(uint8 id) external onlyProviderOwner(id) {
        // If no balance, just deactivate the provider
        if (providers[id].balance > 0) {
            // FROM THE SPECS: The balance held in the contract is returned to the owner upon removal.
            officialToken.transfer(msg.sender, providers[id].balance);
        }
        providers[id].isActive = false;
    }

    // GAS OPTIMIZATION: using calldata for the dynamic array
    /// @notice Register a new subscriber
    /// @param providersIds The ids of the providers the subscriber wants to subscribe to
    /// @param depositAmount The amount of tokens to be deposited to the subscription
    function registerSubscriber(uint8[] memory providersIds, uint256 depositAmount) external {
        require(providersIds.length < MAX_PROVIDERS, "Cannot register to more than available");
        require(
            removeTokenDecimals(depositAmount) * uint256(fetchTokenPriceFromChainlink()) > 100,
            "Initial deposit too low"
        );

        officialToken.transferFrom(msg.sender, address(this), depositAmount);

        subscribersId++;

        Subscriber storage subscriber = subscribers[subscribersId];
        subscriber.id = subscribersId;
        subscriber.balance = depositAmount;
        subscriber.owner = msg.sender;
        subscriber.isPaused = false;
        subscriber.subscribedProviders = providersIds;

        for (uint8 i = 0; i < providersIds.length; i++) {
            providers[providersIds[i]].subscribersNumber++;
        }

        // todo: could
    }

    function changeProviderState(uint8 id, bool newState) external onlyOwner {
        providers[id].isActive = newState;
    }



    

    function getProviderState(uint8 id)
        public
        view
        returns (uint64 subscribersNumber, uint256 fee, address owner, uint256 balance, bool isActive)
    {
        return (
            providers[id].subscribersNumber,
            providers[id].fee,
            providers[id].owner,
            providers[id].balance,
            providers[id].isActive
        );
    }

    function getProviderCounter() public view returns (uint8) {
        return providersId;
    }

    /// @notice Get the provider status
    /// @param id The id of the provider
    function isProviderActive(uint8 id) public view returns (bool) {
        return providers[id].isActive;
    }

    /// @notice Get the subscriber status
    /// @param id The id of the subscriber
    function isSubscriberPaused(uint64 id) public view returns (bool) {
        return subscribers[id].isPaused;
    }

    /// @notice Withdraw the provider funds into the balance, then the owners can move them out of the contract as they wish
    // obviously there would need to be a proper function to move also the balance of the owner our the contract
    function withdrawProviderFunds(uint8 id) external onlyProviderOwner(id) {
        // Check if a month has passed since the last withdrawal
        require(block.timestamp >= providers[id].lastWithdrawTime + 30 days, "Withdrawal is monthly limited");
        // perform the earnings calculation if the month has passed since the last withdrawal
        uint256 amount = providers[id].subscribersNumber * providers[id].fee;

        require(amount > 0, "Insufficient funds to withdraw");

        // TODO: adjust the proper units dealing with decimals
        uint256 usdEquivalent = amount * uint256(fetchTokenPriceFromChainlink());
        emit Withdrawal(msg.sender, amount, usdEquivalent);
    }

    // NOTE: decided not to put a modifier so that you can find any existent subscription ( and even if paused )
    function depositToSubscription(uint64 id, uint256 amount) external {
        officialToken.transferFrom(msg.sender, address(this), amount);
        subscribers[id].balance += amount;
    }

    /// CAUTION: this function is not safe as it is, it should have more checks over decimals and over stale price data!
    // Assuming for simplicity that decimals returned are 8
    /// @notice Fetch the token price from chainlink
    /// @return price The price of the token in USD
    function fetchTokenPriceFromChainlink() internal view returns (int256 price) {
        // @TODO: no check for stale price data, known oracle problem, never trust third party data, especially oracles
        // Ideally also to take into account: When working with Oracle price feeds, developers must account for different price feeds having different decimal precision; it is an error to assume that every price feed will report prices using the same precision. Generally, non-ETH pairs report using 8 decimals, while ETH pairs report using 18 decimals.
        (, price,,,) = priceFeed.latestRoundData();
        return price / 10 ** 8; // from the chainlining docs, the price is returned with 8 decimals
    }

    // GAS OPTIMIZATION: using pure for this helper
    // Ideally should be restircted to internal, but for testing purposes, it is public
    // Assuming for simplicity that token decimals are 18, obviously this is not always the case
    function removeTokenDecimals(uint256 amount) public pure returns (uint256) {
        return amount / (10 ** 18);
    }

    function getSubscriberDepositValueUSD(uint256 subscriberId) external view returns (uint256) {
        // todo get subscriber deposit value in USD
    }

    // TODO
    // there needs to be a method for the provider to transfer the balance out of the contract
    // officialToken.approve(msg.sender, amount); //todo: fix, this needs to approve the sender to move tokens from this contract
    // officialToken.transfer(msg.sender, amount);
    // providers[id].balance -= amount;

    // TODO
    // subscribers could cheat and pause before they have to pay the subscripion
}
