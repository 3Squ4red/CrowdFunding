# Crowd Funding
A consensus-based crowd-fund contract, capable of handling multiple creators, each with multiple 'projects'.

Every project will have following fields: *Title*, *Description*, *Minimum contribution*, *Target amount*, *Raised amount*, *Target reached*, *Contributions* and *Spend requests*. The creator will have to provide the first 4 fields while creating a project.

Anyone, besides the project creator can contribute to a project - for which they'd need the project creators' address and the project index.
While contributing, if on adding the contribution amount, the raised amount exceeds the target amount of that project, that contributor will get a refund. In other words, at no point in time, the raised amount of a project will exceed it's target amount.

After contributing to a project, a contributor will also be allowed to withdraw his money back **until** the project has not met it's target.

ONLY after the target of a project is reached, it's creator will be allowed to request for funds. Each of those requests will have: Amount, Receiver, Purpose, Approvers, Spent (a boolean value showing if this request is completed).
The contributors will then decide whether to approve such a spending request or not. Only the requests which have MORE than 50% of the contributors' approval, will be 'spent' by the project's creator.

By NOT directly transferring the contributions to the project creator and asking for the contributor's approval before spending their money, fraud cases could be prevented to some extent.

### How to run
1. Clone the repo
```
git clone https://github.com/bytecode-velocity/CrowdFunding.git
```
2. Change directory
```
cd CrowdFunding
```
3. Install the packages
```
npm install
```
4. Run the tests
```
npx hardhat test test/crowdFunding.test.js
```
5. Or deploy it locally
```
npx hardhat run scripts/deploy.js
```
