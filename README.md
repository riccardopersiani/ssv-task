# SSV Task

# Bonus Section 

## Balance Management:

Currently, the contract operates monthly, meaning that
subscribers need to deposit at least two months' worth of fees when they register.
Could this process be improved or made more precise? Consider whether allowing
subscribers to pay for services on a daily or even hourly basis would be more
eﬃcient. How could such a feature be implemented?
How would you modify the system to allow subscribers to deposit a USD-pegged
amount rather than a specific token amount? What challenges might this introduce?

### Comment:

An update where the sub payment would switch from monthly to hourly will significantly increase the number of transactions/operations and so the gas costs. Also the number of updates of the structs would be higher.

However, the process can definitely be improved and be more precise: actually, a really interesting approach would be to use an asset streaming strategy that allows providers and subscribers to pay and get paid by the second.
How can this be accomplished? There are some tokens like DAIx (SuperFluid) - that are also USD-pegged - that can rebalance continuously and they can allow to create second-by-second token transfers.
This approach would make the subscriber pay for the services exactly for the specific amount of time that it uses it.
In addition, using a USD-pegged token like DAIx provides stability against price volatility, ensuring consistent costs for subscribers and predictable revenue for providers.
It's important to notice that the way this streaming service is designed it will not make the fee go higher.

One good improvement regarding the integration of a USD-pegged amount, would be getting rid of the oracle, which is always a fragile/heavy/dangerous component.
However, there could be a case where the USD-pegged token loses its peg, so there would need to be mechanics to block the token/system from the admin side or allow the support/switch of another alternative USD-pegged token.

## System Scalability:

The current system restricts the maximum number of providers
to 200. How could this system be changed to become more scalable and remove
such a limitation? Are there changes to the data structures or other modifications
that would allow the system to handle a theoretically unlimited number of providers?

### Comment:

Optimization always needs to be a priority while writing Solidity.
In order to be more scalable the focus has to be on data structures, storage optimization and more efficient lookup.
First of all, there are some limits given by the EVM itself, starting from the MAX types used for ids 2^256 (theoretically infinite when it comes to ids), to the amount of storage, to the amount of gas that can be used in a transaction which is ultimately limited by the **block gas limit of 30 million units** ( and knowingly these looping over arrays of unknown size may lead to reach this amount and to DoS ). A good fact is that there is no limit to storage technically. Packing the strategy properly needs to be mandatory.
When the number grows the usage of loop should be forbidden because is too expensive and as said may let to DOS. The usage of some tree structure could be explored to save some data when they need to be ordered in a certain way. Every optimization possible should be tried: even use uncheck block when possible and optimize code with YUL would be the best, trying to save some bytes.
I would consider freeing storage slot in this scenario (with `delete`). Also using bytes32 is cheaper than using string; and switching for **mappings over arrays** especially in cases where data sets are huge or with direct access. However, for smaller data sets or when iteration is key, arrays can be a practical choice, like done in the current project.

A good approach would be to explore moving some of operations off-chain, maybe using events that of course still participate to the consensus mechanics of the EVM.

## Changing Provider Fees: 

Currently, providers set their fees upon registration. What if
a provider needs to change their fee after registration? How can the system ensure
that the correct amount is charged to subscribers, mainly if the fee change occurs
partway through a billing cycle? Consider how such a feature could be implemented
while maintaining fairness for both providers and subscribers.

### Comment

Allowing a fee change with immediate effect would be to dangerous, due to malicious providers that could drain completely the funds of the subscribers, that by changing one second before withdrawing. 

A safer approach could be to use a new field called `uint256 nextFee`, that would need to stay set for a while - let's say at least 15 days - before becoming effective as `fee`. 
The provider could - after the days are passed - then apply the fee in the middle of the billing cycle; the fact that it would need to be submitted several days before becoming effective would give subscribers more time to notice the changes.
The provider could still act maliciously here and hope that some subscribers would not notice the fee change setting a very high fee. Setting a MAX FEE also would be useful to contain malicious behaviours. 

Another approach would be do deactivate the subscriber when a fee is set higher, and keep them unpaused when the fee is set lower. Then the subscriber would need to register (or upause) to the provider again ( in this case it would need a status for every single provider). However, this will come at the cost of the subscriber that has to do an additional operation.

Generally, regarding the partway during the billing cycle, this looks quite complex, indeed it requires more calculations and data saved. In fact, when a provider changes their fee in the middle of a billing cycle, the contract should also calculate a prorated charge for the old rate up to the point of the change and apply the new rate for the remainder of the cycle.

