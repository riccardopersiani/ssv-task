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

An approach where you would just switch from month to hour will significantly increase the number of transactions and so the gas costs. Also the number of updates of these complex and heavy struct would be higher.

However, the process can definitely be improved and be more precise: actually, a really interesting approach would be to use an asset streaming strategy that allows providers and subscribers to pay and get paid by the second.
How can this be accomplished? There are some tokens like DAIx (SuperFluid) - that are also USD pegged - that rebalance and they can allow to create second-by-second token transfers.
This approach would make the subscriber pay for the services exactly for the specific amount of time that it uses it, enabling very interesting use cases.
Using a USD-pegged token like DAIx provides stability against price volatility, ensuring consistent costs for subscribers and predictable revenue for providers.
It's important to notice that the way this streaming service is designed it will not make the fee go higher. Also, if I am not wrong, some payments also could occur off-chain.

One good improvement regarding the usage of USD-pegged amount, would be that we could get rid of the oracle, which is always a fragile/heavy/dangerous component.
However, there could be a case where the USD-pegged token loses its peg, so there would need to be some mechanics to block the token/system from the admin side or allow the support/switch of another alternative USD-pegged token.

