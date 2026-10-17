# ERC-721 NFT Minting (Solidity + Hardhat)

[![test](https://github.com/madhu786/erc721-nft-minting/actions/workflows/test.yml/badge.svg)](https://github.com/madhu786/erc721-nft-minting/actions/workflows/test.yml)
![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?logo=solidity) ![Hardhat](https://img.shields.io/badge/Hardhat-2.x-666666?logo=hardhat) ![Ethers.js](https://img.shields.io/badge/Ethers.js-v6-3C3C3D) ![Node.js](https://img.shields.io/badge/Node.js-20-339933?logo=nodedotjs)

A **minimal ERC-721 implementation written from scratch** in Solidity — no
OpenZeppelin imports — with a paid public mint, a fixed max supply, and a
Hardhat test suite. It is a portfolio implementation built to show how the
ERC-721 standard actually fits together under the hood; it is not a production
deployment.

## What it does

- Deploys a named collection (`name`, `symbol`) with a fixed `maxSupply` and a
  fixed `mintPrice`.
- Anyone can mint the next token by paying exactly the mint price, until the
  supply cap is reached.
- Full ERC-721 surface: ownership, balances, single-token and operator
  approvals, `transferFrom`, `safeTransferFrom`, and `tokenURI` built from a
  base URI.
- ERC-165 `supportsInterface` so marketplaces and wallets recognize the
  contract as ERC-721 (+ metadata extension).
- The contract owner can withdraw accumulated mint proceeds.

## Features

- From-scratch ERC-721: no inherited code, every function visible in one file
- Sequential token IDs starting at 0, with a hard supply cap (`SoldOut`)
- Exact-price minting (`WrongPrice` on under/overpayment)
- `safeTransferFrom` performs the ERC-721 receiver check on contract recipients
- Per-token approvals cleared automatically on transfer
- Custom errors throughout; standard `Transfer` / `Approval` /
  `ApprovalForAll` events

## Design notes

- **State layout** mirrors the standard's shape: `tokenId → owner`,
  `owner → balance`, `tokenId → approved`, and `owner → operator → approved`
  mappings, plus a monotonic `_nextTokenId` counter that doubles as
  `totalSupply`.
- **Metadata** follows the usual convention: `tokenURI(id)` returns
  `baseURI + id`, so a host only needs one JSON file per token id under a
  single base (e.g. an IPFS folder).
- **Why write it by hand?** Production projects should use audited libraries
  such as OpenZeppelin. Implementing the standard directly is a learning and
  demonstration exercise: it makes the approval checks, the receiver handshake
  in `safeTransferFrom`, and the ERC-165 interface IDs explicit instead of
  inherited magic.
- **Test coverage** includes the edge cases a reviewer checks first:
  `ownerOf` / `tokenURI` / `getApproved` reverting on unminted ids, operator
  (`setApprovalForAll`) transfers, per-token approvals being cleared on
  transfer, the `safeTransferFrom` receiver handshake against both an
  accepting and a rejecting contract (`MockERC721Receiver`), and withdraw
  being restricted to the contract owner.
- **Known simplifications:** no enumerable extension, no royalty (ERC-2981)
  support, mint price and supply are immutable after deployment, and there is
  no per-wallet mint limit.

## Tech stack

- Solidity `^0.8.20` (self-contained, compiles standalone)
- Hardhat 2 + `@nomicfoundation/hardhat-toolbox`
- Tests: Mocha/Chai with Ethers.js v6

## How to run

```bash
npm install

# run the test suite
npx hardhat test

# compile only
npx hardhat compile

# deploy to a local node from the Hardhat console
npx hardhat node
```

Example deployment (Hardhat console):

```js
const MintableNFT = await ethers.getContractFactory("MintableNFT");
const nft = await MintableNFT.deploy(
  "My Collection", "MYC", 1000,
  ethers.parseEther("0.05"),
  "ipfs://<metadata-folder>/"
);
```

## Project structure

```
erc721-nft-minting/
├── contracts/
│   ├── MintableNFT.sol         # minimal ERC-721 + paid mint (self-contained)
│   └── MockERC721Receiver.sol  # test-only receiver (accept / reject modes)
├── test/
│   └── MintableNFT.test.js   # 20 cases: mint / supply / transfers / approvals
│                             # + edge cases (unminted ids, operator approvals,
│                             #   safe-transfer receiver handshake, withdraw)
├── hardhat.config.js
├── package.json
└── README.md
```

## Possible extensions

- Reveal mechanics and per-wallet mint limits
- ERC-2981 royalties and OpenZeppelin-based production variant
- A React + Ethers.js minting page with wallet connect and live supply counter

## License

MIT
