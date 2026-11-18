# Quantara contracts

Solidity contracts for public token launches on QMS Testnet. Anyone with a funded testnet wallet can create a fixed-supply ERC-20 token, publish a sale, and participate in public launches. The application is available at [usequantara.com](https://usequantara.com/).

| Contract | Responsibility |
| --- | --- |
| `LaunchFactory` | Registers projects, publishes sales, and maintains the public launch directory. |
| `TokenFactory` | Creates fixed-supply ERC-20 tokens and records their creators. |
| `FixedPriceSale` | Sells pre-funded token inventory at a fixed price. |
| `FairLaunch` | Supports first-come allocation and pro-rata allocation at settlement. |
| `Sale` | Enforces contribution limits, settlement, claims, refunds, and withdrawals. |
| `FeeController` | Stores the deployment's immutable fee recipient and fee rate. |
| `ClaimManager` | Forwards claims and refunds for callers. |
| `FairLaunchDeployer` | Deploys fair-launch sales for the factory. |
| `SaleTypes` | Defines shared sale terms, setup, and state representations. |

## Build and test

Install [Foundry](https://getfoundry.sh/introduction/installation/) and Node.js with npm. From the repository root, run the following commands.

```bash
npm ci --ignore-scripts
npm run build
npm test
```

The project pins OpenZeppelin Contracts 5.4.0 and Solidity 0.8.30. Foundry compiles for Prague with the optimizer enabled for 200 runs, via IR, and no metadata bytecode hash. The Foundry configuration and source paths match the QMS Testnet deployment build. Tests cover token supply conservation, fixed-price and fair-launch allocation, decimal rounding, contribution bounds, settlement, claims, refunds, and withdrawals.

## QMS Testnet deployment

The [deployment manifest](deployments/qms-testnet.json) records the chain identity, compiler settings, contract addresses, token addresses, sale terms, transaction hashes, and QMSScan source links.

| Setting | Value |
| --- | --- |
| Chain ID | `19480` |
| RPC | `https://rpc.testnet.qms.finance` |
| Explorer | [QMSScan](https://testnet.qmsscan.io/) |
| Launch factory | `0x8ca708730ea4bbe57c706cd8edf65ac91f5757f2` |
| Token factory | `0x63F2F329E7d16c24a1E4C9CAb5BB4Fcd4A604F3A` |

Sales accept native test QMS and escrow their token inventory when published. Each sale fixes its price or allocation mode, inventory, window, contribution limits, caps, and fee terms at deployment. Participants claim allocations after successful settlement or collect eligible refunds after failed settlement. The recorded factory uses a 1% service fee on successful sales.

QMSScan reports partial source matches for the recorded contracts. This repository preserves the compiler configuration used for those deployments. QMS Testnet can reset, so confirm the chain identity and addresses against the manifest before using them. Test assets have no monetary value.

For network configuration and RPC behavior, see the [QMS developer documentation](https://docs.qms.finance/for-developers/network-and-rpc/).

## License

The Quantara Solidity files declare the MIT license. See [LICENSE](LICENSE). OpenZeppelin dependencies retain their upstream license.
