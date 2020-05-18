<p  align="center"><img  src="https://i.imgur.com/ZvVG2b1.png"  width="250px"/></p>

<h1  align="center">Gelato - The easiest way to build automated ethereum dapps</h1>

<p  align="center">

<a  href="https://circleci.com/gh/gelatodigital/gelato-V1"  alt="circleCI">

<img  src="https://circleci.com/gh/gelatodigital/gelato-V1.svg?style=shield&circle-token=d72f3799a6ac81e89e2e0f9a29f7633baef8252b">

</a>

<a  href="https://coveralls.io/github/gelatodigital/gelato-V1"  alt="coverals">

<img  src="https://coveralls.io/repos/github/gelatodigital/gelato-V1/badge.svg?t=esHbYY">

</a>

<a  href="https://codechecks.io"  alt="codeChecks">

<img  src="https://raw.githubusercontent.com/codechecks/docs/master/images/badges/badge-default.svg?sanitize=true">

</a>

</p>

---

# Setup

```
git clone https://github.com/gelatodigital/gelato-V1.git

cd gelato-V1

yarn install

npx buidler compile
```

Create an .env file and store the following 5 environment variables.
Use your own private keys for USER_PK and PROVIDER_PK and your own infura id, these are simply example values).
DEV_MNEMONIC and MAINNET_MNEMONIC must be provided but can remain like in the example below:

```
USER_PK="040494B9430949583848949031094390493983E8943D983948934898A898C892"
PROVIDER_PK="743878AB348983298EB238938293892C983984989FD834894898989A89382392"
INFURA_ID="a489898712dd89312393898cf9032398"
DEV_MNEMONIC="test test test test test test test test test test test test test test test test"
MAINNET_MNEMONIC="test test test test test test test test test test test test test test test test"
```

**Make sure to put .env in .gitignore!**

# Documentation🍦

## What is Gelato?

Gelato is a tool that enables web3 developers to build automated dapps on Ethereum. Think of Gelato as enabling you to use `If This, Then That` for smart contracts. It allows for the combination of arbitrary conditions with arbitrary actions on-chain, which will be executed on behalf of your users by a network of relay nodes.

## Who is gelato for?

Developers who want to build cool automated dapps, without having to worry about running the required underlying relay node infrastructure.

## What is an automated dapp?

**Example #1:** Swap 100 DAI to ETH on Uniswap every week

**Example #2:** Automatically refinance my loan between multiple lending protocols to always get the highest yield

A **regular dapp** like uniswap.exchange requires users to interact with it manually by sending transactions every time they want to swap tokens. Users that want to sell 100 DAI every week on uniswap have to manually do it every week.

An **automated dapp** would require users to send a transaction only once and will send other transactions on the users behalf in the future when certain pre-defined conditions are met. Users that want to sell 100 day every every on uniswap would only have to send one transactions and every week 100 DAI will automatically be sold.

## How gelato works:

At its core, gelato gives developers **(providers)** access to a network of relay nodes **(executors),** which execute certain transactions **(actions)** on behalf of their **users**, if certain predefined **conditions** are met.

Everyone can access these executors and give them arbitrary instructions, which they will execute in exactly the manner they were told to do. Executors never have custody of users funds, they simply initiate the transaction. Funds are always kept either by the user's wallet or their personal smart contract wallet (proxy contract).

Each user deploys and approves their personal smart contract wallet (proxy contract) to move funds on their behalf. Then they can submit tasks to gelato which will initiate certain transactions in the future.

The only thing executors require before executing a transaction, is that they will be compensated for their execution cost. This is accomplished by certain parties depositing ETH on gelato. Gelato will calculate how much gas was consumed and what the current gas price is and will pay the executor for its accomplished work using the formula: **consumed gas \* current gas price**.

Gelato works together with Chainlink to provide users with constantly updated, fair gas prices. That way you can always be sure that executors are not charging gas prices that are too high.

Who pays the executors you might ask? Having to ask end-users to deposit some ETH on gelato before their transactions get executed still sounded like bad UX to us, that is why we introduced the concept of **providers**.

## Providers:

Providers are special actors that deposit ETH on gelato in order to pay for their users transactions. In most cases, providers are dapp developers that want to offer cool automated dapps to their customers, without requiring them to pre-deposit ETH.

Providers have the ability to define exactly what kind of tasks users can ask executors to conduct on their behalf. They can define:

1. what kind of condition will be tracked

2. what kind of actions will be executed on behalf of the user

3. what type of users they accept in the first place, which can use the provider’s funds to pay for pay for future transactions

#### Why would a provider pay for their users transaction fees on gelato?

Because a provider has many possibilities to create interesting business models on top of gelato. For example, if a provider enables users to swap DAI to ETH on uniswap every 2 days, then a fee could be applied for each executed transaction that retains 0.5% of the sold tokens and sends them to the provider.

This way, users do not have to prepay ETH on gelato and providers get compensated / rewarded for paying the transaction fees on behalf of users, all without having to do the heavy lifting of running the underlying infrastructure.

Hence you can think of gelato as pay as you go execution service for developers to create user-friendly automated dapps.

# Getting started as a provider

Check if the account linked to your `PROVIDER_PK` has sufficient ETH for the network you want to test on.
You Rinkeby ETH [here](https://faucet.rinkeby.io/).

## How to become a gelato provider

In order to use gelato, a provider has to do the following steps. **Note:** Gelato is only on rinkeby as of now.

#### 1. Add some balance (ETH) to gelato

To top up your gelato balance by 1 ETH (we recommend not less, as gas prices are quite high atm (14.05.20), run:

    npx buidler gelato-providefunds 1 --network rinkeby

If you would like to withdraw your funds later, simply run (not now)

    npx buidler gelato-unprovidefunds 1 --network rinkeby

#### 2. Assign your provider to the gelato executor network

This enables that an executor can execute the transactions on behalf of your users.

```
npx builder gelato-assign-executor --network rinkeby
```

#### 3. Define who can submit tasks and use the providers funds by whitelisting a proxy module

A user in the gelato system is represented by a proxy contract. A proxy contract is a smart contract account, which is fully owned by a certain user and which conducts certain actions on behalf of the user when specific conditions are fulfilled.

There are several proxy smart contracts out there developers are using. We build gelato to be fully proxy agnostic, so you can use whatever proxy contract standard you like with it. Examples of proven proxy contracts are for example the Gnosis Safe or DsProxy. We also created a tailor made Gelato User Proxy, which boasts native functionalities unique to the gelato protocol.

Let’s say you want your users to only be allowed to submit tasks with Gelato User Proxies. To enable these users to use you as a provider with a Gelato User Proxy, run:

    npx builder gelato-add-provider-module GelatoUserProxy --network rinkeby

Now you enabled every user that has a gelato user proxy to be a potential customer of yours. When you start integrating Gelato in your UI, you can deploy a proxy for first time users and have them start using your service, all in one transaction, using the GelatoUserProxyFactory.

#### 4. Define what kind of Tasks users can submit with you being the provider (whitelist a Task Spec).

You can think of the gelato executors as bots that accept submitted tasks from your users and that execute them according to what the user specified. You as the provider have the power to define in advance what type of condition and what type of actions (combined called a Task) the user's are allowed to ask executors to execute on their behalf.

This is done to ensure that you can always integrate a sustainable business model within Tasks, that compensate you as the provider for your incurred transcation fees on gelato.

**Whitelisting the actual Task Spec:**

Before any user can submit a task with yourself marked as the provider to gelato, you must have whitelisted (provided) a blueprint or specification of the Task the user is allowed to submit first. To whitelist a so-called _TaskSpec_, you have to instantiate it in a `.js` file.

You can see an example of how this is done by checking out `./src/demo/task.spec.example.js`, which defines a _TaskSpec_ that is a blueprint for a Task users can submit that transfers a selected Token from the user's wallet to a given destination address every X minutes, N times.

To checkout how a **TaskSpec** object looks like, run the script that returns the above mentioned example:

```
npx builder gelato-return-taskpec-example --network rinkeby
```

To whitelist this example TaskSpec and enable users to submit tasks that follow its specification, run:

```
npx buidler gelato-whitelist-taskspec example --network rinkeby
```

That’s it from a providers point of view in terms of what you have to do on the gelato cli to enable users to submit tasks on gelato with you being their provider! 🍦

Now let's see how your user's can submit a task that matches your TaskSpec

# Getting started as a user - How to instruct gelato to execute the example Task

**Note:** The example code discussed in this chapter is found here: `src/demo/automated_dapps/task.dapp.example.js`.
This code would normally be located in your UI that interfaces with your user and enables them to use your automated dapp (which is in essence a whitelisted Task Spec on gelato)

### Example: Automatically transfer 1 DAI every 2 minutes to a given destination address:

#### 1. Make sure you have completed the Setup and have a user account funded with ETH.

Check if the account linked to your `USER_PK` has sufficient ETH for the network you want to test on.
You can get some Rinkeby ETH [here](https://faucet.rinkeby.io/).

#### 2. Get some rinkeby DAI.

You can get some from [Compound's Rinkeby UI](https://app.compound.finance/) by going on Supply DAI => Withdraw => Faucet

#### 3. Get the proxy address of your user account.

Run:

```
npx builder gelato-predict-gelato-proxy-address --network rinkeby
```

**=>** your proxy address e.g. 0x35dE7aCAd63E30B22C3305ac0e3fb8438697D0Fb

#### 4. Approve the user's proxy contract to transfer 5 DAI in total on the user's behalf (using rinkeby DAI address here)

```
npx builder gelato-approve-erc20 0x5592ec0cfb4dbc12d3ab100b257153436a1f0fea 5000000000000000000 $YOUR_PROXY_ADDRESS --network rinkeby
```

#### 5. Make sure you as a provider has whitelisted the example TaskSpec. To check, run:

```
npx builder gelato-check-if-provided --taskspecname example --network rinkeby
```

If it is not whitelisted by your provider, run:

```
npx buidler gelato-whitelist-taskspec example --network rinkeby
```

#### 6. Run the following script to start the automatic process of transferring 1 DAI to a given destination address every 2 minutes (120 seconds), 5 times in a row (total of 5 DAI):

```
npx builder gelato-example-dapp --sendtoken 0x5592ec0cfb4dbc12d3ab100b257153436a1f0fea --destination 0x518eAa8f962246bCe2FA49329Fe998B66d67cbf8 --amount 1000000000000000000 --secondsdelta 120 --cycles 5 --network rinkeby
```

Once the transaction, which calls the `submitTaskCycle()` function on GelatoCore using your user's gelato user proxy contract, is mined, gelato will monitor the specified condition, and when it is fulfilled, an executor will execute the example task on behalf of your user. Your provider account balance will be deducted by the consumed gas amount \* current gas price.

Now watch your account on [Etherscan](https://rinkeby.etherscan.io/) and observe that tokens are being transferred out of the user’s account every 2 minutes like magic ✨

5 Tasks and hence transactions will be executed in total. This is because we inputted `--cycles 5`. If we want to enable users to have this task executed for ever, we would simply input `--cycles 5`, though make sure you have a sufficient provider balance before you do that ;).

# Whitelist your own custom TaskSpec as a provider

This is where it becomes interesting and you can become creative. With gelato, you can combine arbitrary conditions (e.g. if price of ETH/\$ on Uniswap) with arbitrary actions (e.g. refinance by loan from lending protocol A to B) and combine them in a new **TaskSpec**, which you simply have to whitelist once on gelato. After it is whitelisted, users can submit the corresponding tasks and can enjoy amazing automation features!

If this still feels to tricky for you, feel free to reach out to us, we're more than happy to help you out!

## Whitelist your own custom Task Spec:

#### 1. Create a file which returns your Task Spec

run:

```
touch ./src/demo/task_specs/task.spec.nameOfYourTaskSpec.js
```

and follow the example of `./src/demo/task.spec.example.js` to instantiate and return a TaskSpec object.

Make sure that you name the task returning your TaskSpec correctly like: `"gelato-return-taskpec-example"`. An example would be `“gelato-return-taskpec-time-based-uniswap-trade`.

#### 2. Add the path to your TaskSpec to the Tasks Spec collection file

When you are done, add the path to your Task Spec file to `src/demo/task_specs/collection.tasks.specs.js`

#### 3. Whitelist your TaskSpec on gelato

To whitelist your _TaskSpec_ so that users can submit corresponding _Tasks_, run:

```
npx buidler gelato-whitelist-taskspec time-based-uniswap-trade --network rinkeby
```

That's it, now users can submit tasks that follow your Task Spec guideline!

# Instruct gelato to execute a task based on your providers custom TaskSpec as a user

Now that you whitelisted a TaskSpec on gelato, users can submit Tasks with you being marked as the provider who will pay for transaction fees. Let’s see how that would look like:

### Thing to keep in mind:

Before enabling users to submit tasks with you being listed as the provider, you should make sure that:

a) The task to be submitted is indeed whitelisted by the provider (you). To check if you provided the examaple Task Script, run:

```
npx builder gelato-check-if-provided --taskspecname nameOfYourTaskSpec --network rinkeby --log
```

b) Your provider balance is sufficiently funded. To check that, run

```
npx buidler gelato-check-if-provider-liquid --network rinkeby
```

c) Your users have sufficient ERC20 allowance if you plan on using the users proxy contract as a “light-proxy”. Check out the commands in the example above if you need a refresher.

**Note:** Users always have to submit tasks through their proxy contracts and never through their EOAs, otherwise it won’t work.

To try out your submitting the newly whitelisted TaskSpec, follow these steps:

#### 1. Create a file which will contain the code that instantiates and submits the Task

run:

```
touch ./src/demo/task_specs/task.spec.nameOfYourTaskSpec.js
```

and follow the example of `src/demo/automated_dapps/task.dapp.example.js` to instantiate and return a TaskSpec object.

#### 2. Add the path to your script which submits the Task to the Dapp collection file

Path of collection file `src/demo/automated_dapps/collection.tasks.demo.dapps.js`

#### 3. Execute your new script to submit the task with your users proxy account

Instead of `...params` you probably need some params that define what the user inputs. Check out the example demo scipts above for inspiration.

```
npx builder gelato-nameOfYourTaskSpec ...params --network rinkeby
```

That's it!

## Further technical details:

#### What is a Task?

**A Task is an object which consists of several parts:**

#### Gelato Provider

- addr (address) => The address of the provider who is paying for the transaction. This will be the address you used to deposit ETH on gelato

* module (address) => The address of the provider module which verifies the type of proxy contract allowed to access the providers services. In our previous example, this would be the address returned by `gelato-add-provider-module`

#### Conditions (A list of several individual conditions, each consisting of)

- inst (address): The address of the condition that will be called. An example of this would be gelato’s time condition, which compares the current timestamp `block.timestamp` with another timestamp, which when being equal or greater indicating that the condition is fulfilled

* data (bytes): Encoded data of the function that will be called on the condition. Note: Every condition in gelato must have a function called `ok`, which when fulfilled returns “OK”.

#### Actions (A list of several individual actions, each consisting of)

- addr (address): The address of the action you would like to call. This could be e.g. the address of uniswap or the address of a smart contract script that you want your users proxy to delegate call into

* data (bytes): Encoded data of the function that will be called on the action contract.

- operation (uint256): If the proxy should .call (0) or .delegatecall (1) into the action. If you don't know the difference, read [this](https://ethereum.stackexchange.com/questions/3667/difference-between-call-callcode-and-delegatecall)

* value: (uint256): If ETH should be send to an action or not (only possible if .call is chosen in operation)

- termsOkCheck (bool): Used for gelato actions that enable providers to verify the inputted action payload. If marked as true, gelato will call a special `termsOk` function on the respective action before execution, which needs to return `"OK"` in order for execution to proceed

---

#### What is a light-proxy?

A light-proxy never really holds the funds after a transaction is conducted, it only acts as a transfer agent. For example, if your user submits a task to swap 100 DAI to ETH on uniswap every day, then all DAI will remain in your users EOA and the proxy will simply get an allowance (e.g. infinite allowance) to transfer the tokens out of your users actual wallet. Now when the condition is met, the proxy will transfer the funds from the users EOA to itself, will swap on uniswap and send the funds back atomically in one transaction.

To enable the proxy to do so, it requires an approval by the account of the user that holds the funds (e.g. the Nano Ledger, Metamask or another wallet).

On the other hand, a heavy-proxy will keep custody of the funds after the action is conducted. In such a scenario, users if they want to swap 1000 DAI over the next 10 days every day, will transfer 1000 DAI to their proxy right now, which will then conduct the swap for them in the next 10 days. Heavy proxies are meant to always keep the funds of users.

---

## Need help?

Let us know in our Telegram Chat if you have any issues, we are more than happy to help you get going and even provide you feedback on your idea for an automated dapp (we built quite a lot ourselves)!

Let’s build the next generation of etherem dapps, fully automated, together.

Reach out to us in our official [Telegram Community Chat](http://tiny.cc/gelatotelegtram)
