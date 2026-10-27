// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice ERC-721 receiver interface (for safe transfers).
interface IERC721Receiver {
    /// @notice Called by `safeTransferFrom` on the recipient contract.
    /// @dev Must return `IERC721Receiver.onERC721Received.selector` to
    ///      accept the token; any other return value (or a revert) makes
    ///      the whole transfer revert, so ownership rolls back.
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

/// @title MintableNFT
/// @notice A minimal, self-contained ERC-721 implementation (no external
///         imports) with a paid public mint, a fixed max supply, a
///         base-URI tokenURI scheme, ERC-2981 royalty reporting, and
///         owner/approved burning.
///         Written as a compact reference for how the ERC-721 standard
///         fits together: ownership and balances, approvals, transfers,
///         ERC-165 interface detection, and standardised royalties.
contract MintableNFT {
    // ----- Collection metadata -----
    string public name;
    string public symbol;
    uint256 public immutable maxSupply;
    uint256 public immutable mintPrice; // in wei
    string private _baseTokenURI;

    address public owner;
    uint256 private _nextTokenId; // token ids start at 0

    // ----- ERC-2981 royalties -----
    /// @notice Address that receives royalties on secondary sales.
    /// @dev Defaults to the contract owner; see `setRoyaltyInfo`.
    address public royaltyReceiver;
    /// @notice Royalty fee in basis points (1 bps = 0.01%, 10_000 = 100%).
    /// @dev Defaults to 0 (no royalty) until the owner configures one.
    uint256 public royaltyFeeBps;

    // ----- ERC-721 state -----
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // ----- ERC-721 events -----
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event RoyaltyInfoUpdated(address indexed receiver, uint256 feeBps);

    error NotOwner();
    error ZeroAddress();
    error TokenNotFound();
    error NotAuthorized();
    error ApprovalToOwner();
    error SoldOut();
    error WrongPrice();
    error NotContractOwner();
    error UnsafeRecipient();
    error InvalidRoyalty();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotContractOwner();
        _;
    }

    /// @notice Deploy a collection with a fixed supply cap and mint price.
    /// @dev `mintPrice` and `maxSupply` are immutable after deployment;
    ///      `royaltyReceiver` starts as the deployer with a 0 fee, so
    ///      royalties are opt-in via `setRoyaltyInfo`.
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 mintPrice_,
        string memory baseURI_
    ) {
        name = name_;
        symbol = symbol_;
        maxSupply = maxSupply_;
        mintPrice = mintPrice_;
        _baseTokenURI = baseURI_;
        owner = msg.sender;
        royaltyReceiver = msg.sender;
    }

    // ----- Minting -----

    /// @notice Mint one NFT to the caller for exactly `mintPrice`.
    function mint() external payable returns (uint256 tokenId) {
        if (_nextTokenId >= maxSupply) revert SoldOut();
        if (msg.value != mintPrice) revert WrongPrice();

        tokenId = _nextTokenId++;

        // Effects before the (implicit) interaction of recording ownership.
        _balances[msg.sender] += 1;
        _owners[tokenId] = msg.sender;

        emit Transfer(address(0), msg.sender, tokenId);
    }

    /// @notice Total tokens minted so far.
    /// @dev This counts mints, not circulating tokens: burning a token
    ///      removes its ownership but does not reuse its id or lower
    ///      this counter, so ids stay unique and monotonic.
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    /// @notice Burn `tokenId`, permanently removing it from circulation.
    /// @dev Caller must be the token owner, the per-token approved
    ///      address, or an operator of the owner — the same authorisation
    ///      as `transferFrom`. Clears the per-token approval, drops the
    ///      owner's balance, and emits `Transfer` to the zero address,
    ///      the standard burn signal. The id is never reused, and
    ///      `totalSupply` (a mint counter) is unchanged, so `ownerOf`,
    ///      `tokenURI`, `getApproved` and `royaltyInfo` all revert with
    ///      `TokenNotFound` for a burned id, exactly as for an unminted one.
    function burn(uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        if (
            msg.sender != tokenOwner &&
            msg.sender != _tokenApprovals[tokenId] &&
            !isApprovedForAll(tokenOwner, msg.sender)
        ) {
            revert NotAuthorized();
        }

        delete _tokenApprovals[tokenId];
        _balances[tokenOwner] -= 1;
        delete _owners[tokenId];

        emit Transfer(tokenOwner, address(0), tokenId);
    }

    /// @notice Withdraw the contract's ETH balance (mint proceeds) to the owner.
    /// @dev Only the deployer (`owner`) may call this; reverts with
    ///      `NotContractOwner` for any other caller. Uses a low-level call
    ///      and reverts if the transfer fails.
    function withdraw() external onlyOwner {
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    // ----- ERC-721 read functions -----

    /// @notice Count of tokens owned by `account`.
    /// @dev Reverts with `ZeroAddress` for the zero address, per ERC-721.
    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[account];
    }

    /// @notice Owner of `tokenId`.
    /// @dev Reverts with `TokenNotFound` if the token has not been minted.
    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenNotFound();
        return tokenOwner;
    }

    /// @notice Base URI + tokenId, per the ERC-721 metadata convention.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        ownerOf(tokenId); // reverts if the token does not exist
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId)));
    }

    /// @notice Single-token approved address for `tokenId`, or the zero
    ///         address if none. Reverts with `TokenNotFound` for unminted ids.
    function getApproved(uint256 tokenId) public view returns (address) {
        ownerOf(tokenId); // reverts if the token does not exist
        return _tokenApprovals[tokenId];
    }

    /// @notice Whether `operator` may manage all of `account`'s tokens.
    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    // ----- ERC-721 approvals -----

    /// @notice Approve `approved` to transfer `tokenId` once.
    /// @dev Caller must be the token owner or an operator of the owner.
    ///      Reverts with `ApprovalToOwner` if `approved` is the current owner
    ///      and with `NotAuthorized` if the caller may not approve.
    ///      The approval is cleared automatically on any transfer.
    function approve(address approved, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner && !isApprovedForAll(tokenOwner, msg.sender)) {
            revert NotAuthorized();
        }
        if (approved == tokenOwner) revert ApprovalToOwner();

        _tokenApprovals[tokenId] = approved;
        emit Approval(tokenOwner, approved, tokenId);
    }

    /// @notice Grant or revoke operator approval for all of the caller's tokens.
    /// @dev Emits `ApprovalForAll`. Operators can transfer and approve on
    ///      behalf of the owner until revoked.
    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // ----- ERC-721 transfers -----

    /// @notice Transfer `tokenId` from `from` to `to`.
    /// @dev Caller must be the owner, the per-token approved address, or an
    ///      operator. Reverts with `NotOwner` if `from` is not the current
    ///      owner and with `ZeroAddress` if `to` is the zero address.
    ///      Clears the per-token approval before moving ownership.
    function transferFrom(address from, address to, uint256 tokenId) public {
        address tokenOwner = ownerOf(tokenId);
        if (from != tokenOwner) revert NotOwner();
        if (to == address(0)) revert ZeroAddress();
        if (
            msg.sender != tokenOwner &&
            msg.sender != _tokenApprovals[tokenId] &&
            !isApprovedForAll(tokenOwner, msg.sender)
        ) {
            revert NotAuthorized();
        }

        // Clear the per-token approval and move ownership (effects first).
        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /// @notice Transfer `tokenId` and, if `to` is a contract, require it to
    ///         return the ERC-721 receiver magic value (see the 4-arg overload).
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    /// @notice Transfer `tokenId` with arbitrary `data` forwarded to the
    ///         recipient's `onERC721Received` handler (see the 3-arg
    ///         overload, which passes empty data). The receiver check
    ///         runs after the ownership move, so a rejecting recipient
    ///         reverts the whole transfer, including the balance updates.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        transferFrom(from, to, tokenId);

        // If the recipient is a contract, it must signal ERC-721 awareness.
        if (to.code.length > 0) {
            bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data);
            if (retval != IERC721Receiver.onERC721Received.selector) revert UnsafeRecipient();
        }
    }

    // ----- ERC-2981 royalties -----

    /// @notice Configure the default royalty for every token in the collection.
    /// @dev Only the contract owner may call this. `feeBps` is in basis
    ///      points and must not exceed 10_000 (100%). A non-zero fee
    ///      requires a non-zero `receiver`; setting `feeBps` to 0 disables
    ///      royalties regardless of the receiver. This contract only
    ///      *reports* royalties via `royaltyInfo` — marketplaces decide
    ///      whether to honour them, as ERC-2981 intends.
    /// @param receiver Address that should receive royalty payments.
    /// @param feeBps Royalty fee in basis points (e.g. 500 = 5%).
    function setRoyaltyInfo(address receiver, uint256 feeBps) external onlyOwner {
        if (feeBps > 10_000) revert InvalidRoyalty();
        if (feeBps > 0 && receiver == address(0)) revert ZeroAddress();
        royaltyReceiver = receiver;
        royaltyFeeBps = feeBps;
        emit RoyaltyInfoUpdated(receiver, feeBps);
    }

    /// @notice Royalty information for a sale of `tokenId` at `salePrice`.
    /// @dev Implements ERC-2981. Reverts with `TokenNotFound` for an
    ///      unminted id, consistent with `tokenURI` and `getApproved`.
    ///      The amount is `salePrice * royaltyFeeBps / 10_000`, rounded
    ///      down by integer division.
    /// @param tokenId Token being sold; must have been minted.
    /// @param salePrice Sale price the royalty is calculated from, in wei
    ///        (or the sale currency's smallest unit).
    /// @return receiver Address that should receive the royalty payment.
    /// @return royaltyAmount Amount owed to `receiver` for this sale.
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view returns (address receiver, uint256 royaltyAmount) {
        ownerOf(tokenId); // reverts if the token does not exist
        receiver = royaltyReceiver;
        royaltyAmount = (salePrice * royaltyFeeBps) / 10_000;
    }

    // ----- ERC-165 -----

    /// @notice ERC-165 interface detection: ERC-721 (0x80ac58cd), ERC-721
    ///         metadata (0x5b5e139f), ERC-2981 (0x2a55205a), and ERC-165
    ///         itself (0x01ffc9a7).
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x80ac58cd || // ERC-721
            interfaceId == 0x5b5e139f || // ERC-721 metadata
            interfaceId == 0x2a55205a || // ERC-2981 royalties
            interfaceId == 0x01ffc9a7; // ERC-165
    }

    // ----- Helpers -----

    /// @notice Decimal rendering of `value` (no leading zeros), used to
    ///         build `tokenURI` as `baseURI + tokenId` for multi-digit ids
    ///         as well as single-digit ones.
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
