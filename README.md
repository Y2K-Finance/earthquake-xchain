# earthquake-xchain

The cross-chain zapper lets users bridge then deposit to a Y2K vault or withdraw funds from the vault that was previously deposited via the zapper - on the fromChain. In addition, the fromChain zapper allows users to swap their tokens on UniswapV2, UniswapV3, Balancer, or Curve before they are bridged to be deposited.

Documentation & Audit folder: https://drive.google.com/drive/folders/1jdCNiZQ0Ns50on6IXSYKV3_q-l4MTpJA?usp=sharing

**QuickStart**

_Install Foundry_

- Forge/Foundryup: installed successfully if you can run forge --version
- Git: installed successfully if you can run git --version
- Install libs with forge update

_Testing_

- Configure the .env file (reference .env.example for required fields)
- Run forge test for tests
- Run forge coverage for test coverage
