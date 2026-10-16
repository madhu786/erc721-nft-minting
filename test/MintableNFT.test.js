const { expect } = require("chai");
const { ethers } = require("hardhat");

const PRICE = ethers.parseEther("0.05");
const BASE_URI = "ipfs://example-collection/";

describe("MintableNFT", function () {
  let nft;
  let owner, alice, bob;

  async function deploy(maxSupply = 3) {
    const MintableNFT = await ethers.getContractFactory("MintableNFT");
    return MintableNFT.deploy("Portfolio Pets", "PPET", maxSupply, PRICE, BASE_URI);
  }

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    nft = await deploy();
  });

  it("exposes collection metadata", async function () {
    expect(await nft.name()).to.equal("Portfolio Pets");
    expect(await nft.symbol()).to.equal("PPET");
    expect(await nft.maxSupply()).to.equal(3);
    expect(await nft.mintPrice()).to.equal(PRICE);
    expect(await nft.totalSupply()).to.equal(0);
  });

  it("mints a token for the exact mint price", async function () {
    await expect(nft.connect(alice).mint({ value: PRICE }))
      .to.emit(nft, "Transfer")
      .withArgs(ethers.ZeroAddress, alice.address, 0);

    expect(await nft.ownerOf(0)).to.equal(alice.address);
    expect(await nft.balanceOf(alice.address)).to.equal(1);
    expect(await nft.totalSupply()).to.equal(1);
  });

  it("builds tokenURI from the base URI and token id", async function () {
    await nft.connect(alice).mint({ value: PRICE });
    expect(await nft.tokenURI(0)).to.equal(BASE_URI + "0");
  });

  it("rejects minting with the wrong price", async function () {
    await expect(
      nft.connect(alice).mint({ value: ethers.parseEther("0.01") })
    ).to.be.revertedWithCustomError(nft, "WrongPrice");
  });

  it("enforces the max supply cap", async function () {
    await nft.connect(alice).mint({ value: PRICE });
    await nft.connect(alice).mint({ value: PRICE });
    await nft.connect(bob).mint({ value: PRICE });

    await expect(
      nft.connect(bob).mint({ value: PRICE })
    ).to.be.revertedWithCustomError(nft, "SoldOut");
  });

  it("transfers a token between accounts", async function () {
    await nft.connect(alice).mint({ value: PRICE });

    await nft.connect(alice).transferFrom(alice.address, bob.address, 0);

    expect(await nft.ownerOf(0)).to.equal(bob.address);
    expect(await nft.balanceOf(alice.address)).to.equal(0);
    expect(await nft.balanceOf(bob.address)).to.equal(1);
  });

  it("blocks transfers from non-owners without approval", async function () {
    await nft.connect(alice).mint({ value: PRICE });

    await expect(
      nft.connect(bob).transferFrom(alice.address, bob.address, 0)
    ).to.be.revertedWithCustomError(nft, "NotAuthorized");
  });

  it("lets an approved account transfer the token", async function () {
    await nft.connect(alice).mint({ value: PRICE });
    await nft.connect(alice).approve(bob.address, 0);

    expect(await nft.getApproved(0)).to.equal(bob.address);
    await nft.connect(bob).transferFrom(alice.address, bob.address, 0);
    expect(await nft.ownerOf(0)).to.equal(bob.address);
  });

  it("reports ERC-721 via ERC-165", async function () {
    expect(await nft.supportsInterface("0x80ac58cd")).to.equal(true);
    expect(await nft.supportsInterface("0xffffffff")).to.equal(false);
  });
});
