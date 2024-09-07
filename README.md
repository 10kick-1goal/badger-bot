# BadgerBot NFT Staking Project

This project implements a BadgerBot NFT staking system with smart contracts for NFT minting, staking, and reward distribution.

## Prerequisites

-   Node.js (v18.0.0 or later)
-   npm (v6.0.0 or later)
-   Hardhat
-   Ethereum wallet with testnet ETH (for deployment)

## Setup

1. Clone the repository:

    ```
    git clone https://github.com/ProjectBadgerBot/Staking-Token.git
    cd Staking-Token
    ```

2. Install dependencies:

    ```
    npm install
    ```

3. Create a `.env` file in the root directory with the following variables:
    ```
    PRIVATE_KEY=<your-ethereum-private-key>
    SEPOLIA_RPC_URL=<your-sepolia-rpc-url>
    MAINNET_RPC_URL=<your-mainnet-rpc-url>
    ETHERSCAN_API_KEY=<your-etherscan-api-key>
    TEST_BASE_URI=<your-test-base-uri>
    ```

## Compilation

Compile the smart contracts:

## Deployment

### Sepolia Testnet

To deploy the contracts to the Sepolia testnet:

1. Make sure you have enough Sepolia ETH in your wallet.

2. Run the deployment script:

    ```
    npx hardhat run scripts/deployBadgerBotContracts.js --network sepolia
    ```

3. Note down the deployed contract addresses for future reference.

### Mainnet Deployment

To deploy the contracts to the Ethereum mainnet:

1. Ensure you have sufficient ETH in your wallet to cover deployment costs and gas fees.

2. Update your `.env` file with the mainnet RPC URL:

    ```
    MAINNET_RPC_URL=<your-mainnet-rpc-url>
    ```

3. Run the deployment script with the mainnet network:

    ```
    npx hardhat run scripts/deployBadgerBotContracts.js --network mainnet
    ```

4. Note down the deployed contract addresses for future reference.

5. Verify the contracts on Etherscan (if not done automatically):
    ```
    npx hardhat verify --network mainnet <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGUMENTS>
    ```

**Important:** Before deploying to mainnet, ensure all contracts have been thoroughly tested and audited. Mainnet deployments involve real value and cannot be undone.

## Configuration

After deployment, you may need to configure the contracts:

1. The deployment script automatically sets the staking contract address in the BadgerBotPool contract.
2. Add whitelist addresses to the BadgerBotPool contract using the `addToWhitelist` function.
3. Set up initial parameters for the BadgerBotStakingContract using the setter functions provided.

You can create custom scripts to interact with the deployed contracts and set these configurations.

## Testing

Run the test suite:

## Verification

The contracts are automatically verified on Etherscan after deployment if running on the Sepolia network.

## Important Notes

-   The `BadgerBotStakingContract` interacts with the `BadgerBotPool` contract. Make sure both are deployed and properly linked.
-   Review and adjust the constants in the contracts (e.g., MIN_DEPOSIT, MAX_DEPOSIT, TEAM_SHARE) before deployment to production.
-   The project uses OpenZeppelin contracts. Make sure to review their documentation for any updates or security considerations.

## Contract Addresses

After deployment, update this section with the deployed contract addresses:

-   BadgerBotPool: [Contract Address]
-   BadgerBotStakingContract: [Contract Address]

## Security

-   Always use safe math operations to prevent overflows.
-   Implement access control properly using the Ownable pattern.
-   Consider getting a professional audit before deploying to mainnet with real value.

## License

This project is licensed under the MIT License.
