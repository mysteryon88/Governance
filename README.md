## Governer

A research into the practical uses and interconnections in DAO. 

Will help beginners to understand how Governer and ERC20 voting works.

```sh
forge test 
```

## Contracts

- MyGovernor
    - Inherits the OZ library and the `Governer` contract
    - Used to control and monitor voting
        - `GovernorCountingSimple` allows you to set up a simple "for, against, abstain" vote
- Token
    - Ordinary `ERC20` contract
    - Inherits `ERC20Votes` for voting
- TimeLock
    - Contract, to enter the wait time before executing the winning `proposal`
- Treasury
    - Proposal contract
    - In its place could be anything
    - The address of this contract is `target`, and the function selector is `calldata`
    - `owner` - timelock

## References
- [Governance](https://docs.openzeppelin.com/contracts/5.x/api/governance)
- [How to set up on-chain governance](https://docs.openzeppelin.com/contracts/5.x/governance)
