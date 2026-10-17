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

describe("MintableNFT — edge cases", function () {
  let nft;
  let owner, alice, bob;

  async function deploy(maxSupply = 10) {
    const MintableNFT = await ethers.getContractFactory("MintableNFT");
    return MintableNFT.deploy("Portfolio Pets", "PPET", maxSupply, PRICE, BASE_URI);
  }

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    nft = await deploy();
  });

  it("reverts ownerOf / tokenURI / getApproved for an unminted token", async function () {
    await expect(nft.ownerOf(99)).to.be.revertedWithCustomError(nft, "TokenNotFound");
    await expect(nft.tokenURI(99)).to.be.revertedWithCustomError(nft, "TokenNotFound");
    await expect(nft.getApproved(99)).to.be.revertedWithCustomError(nft, "TokenNotFound");
  });

  it("reverts balanceOf for the zero address", async function () {
    await expect(nft.balanceOf(ethers.ZeroAddress)).to.be.revertedWithCustomError(nft, "ZeroAddress");
  });

  it("rejects minting with an overpayment as well as underpayment", async function () {
    await expect(
      nft.connect(alice).mint({ value: PRICE + 1n })
    ).to.be.revertedWithCustomError(nft, "WrongPrice");
    await expect(
      nft.connect(alice).mint({ value: 0 })
    ).to.be.revertedWithCustomError(nft, "WrongPrice");
  });

  it("rejects approving the current owner and approving as a stranger", async function () {
    await nft.connect(alice).mint({ value: PRICE });
    await expect(
      nft.connect(alice).approve(alice.address, 0)
    ).to.be.revertedWithCustomError(nft, "ApprovalToOwner");
    await expect(
      nft.connect(bob).approve(bob.address, 0)
    ).to.be.revertedWithCustomError(nft, "NotAuthorized");
  });

  it("lets an operator transfer via setApprovalForAll and emits ApprovalForAll", async function () {
    await nft.connect(alice).mint({ value: PRICE });
    await expect(nft.connect(alice).setApprovalForAll(bob.address, true))
      .to.emit(nft, "ApprovalForAll")
      .withArgs(alice.address, bob.address, true);
    expect(await nft.isApprovedForAll(alice.address, bob.address)).to.equal(true);
    await nft.connect(bob).transferFrom(alice.address, bob.address, 0);
    expect(await nft.ownerOf(0)).to.equal(bob.address);
    // Revoking restores the default.
    await nft.connect(alice).setApprovalForAll(bob.address, false);
    expect(await nft.isApprovedForAll(alice.address, bob.address)).to.equal(false);
  });

  it("clears the per-token approval on transfer", async function () {
    await nft.connect(alice).mint({ value: PRICE });
    await nft.connect(alice).approve(bob.address, 0);
    expect(await nft.getApproved(0)).to.equal(bob.address);
    await nft.connect(alice).transferFrom(alice.address, owner.address, 0);
    expect(await nft.getApproved(0)).to.equal(ethers.ZeroAddress);
  });

  it("reverts transferFrom with a wrong from address or a zero recipient", async function () {
    await nft.connect(alice).mint({ value: PRICE });
    await expect(
      nft.connect(alice).transferFrom(bob.address, alice.address, 0)
    ).to.be.revertedWithCustomError(nft, "NotOwner");
    await expect(
      nft.connect(alice).transferFrom(alice.address, ethers.ZeroAddress, 0)
    ).to.be.revertedWithCustomError(nft, "ZeroAddress");
  });

  it("safeTransferFrom works to an EOA and to an accepting contract", async function () {
    const Mock = await ethers.getContractFactory("MockERC721Receiver");
    const receiver = await Mock.deploy();
    await nft.connect(alice).mint({ value: PRICE });
    await nft.connect(alice).mint({ value: PRICE });
    await nft.connect(alice)["safeTransferFrom(address,address,uint256)"](alice.address, bob.address, 0);
    expect(await nft.ownerOf(0)).to.equal(bob.address);
    await nft.connect(alice)["safeTransferFrom(address,address,uint256)"](alice.address, await receiver.getAddress(), 1);
    expect(await nft.ownerOf(1)).to.equal(await receiver.getAddress());
  });

  it("safeTransferFrom reverts with UnsafeRecipient for a rejecting contract", async function () {
    const Mock = await ethers.getContractFactory("MockERC721Receiver");
    const receiver = await Mock.deploy();
    await receiver.setAccept(false);
    await nft.connect(alice).mint({ value: PRICE });
    await expect(
      nft.connect(alice)["safeTransferFrom(address,address,uint256)"](alice.address, await receiver.getAddress(), 0)
    ).to.be.revertedWithCustomError(nft, "UnsafeRecipient");
    // The transfer is rolled back: Alice still owns the token.
    expect(await nft.ownerOf(0)).to.equal(alice.address);
  });

  it("restricts withdraw to the owner and pays out the mint proceeds", async function () {
    await nft.connect(alice).mint({ value: PRICE });
    await expect(nft.connect(alice).withdraw()).to.be.revertedWithCustomError(nft, "NotContractOwner");
    await expect(nft.connect(owner).withdraw()).to.changeEtherBalances(
      [owner, nft],
      [PRICE, -PRICE]
    );
  });

  it("reports the metadata and ERC-165 interface ids via ERC-165", async function () {
    expect(await nft.supportsInterface("0x5b5e139f")).to.equal(true);
    expect(await nft.supportsInterface("0x01ffc9a7")).to.equal(true);
  });
});
