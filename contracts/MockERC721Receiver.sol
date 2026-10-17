// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockERC721Receiver
/// @notice Test helper for `safeTransferFrom`: a contract recipient that can
///         be toggled between returning the correct ERC-721 receiver magic
///         value and returning a wrong value, so tests can cover both the
///         accepting and the `UnsafeRecipient` rejecting paths.
/// @dev Test-only contract — not part of the NFT implementation.
contract MockERC721Receiver {
    bool public accept = true;

    function setAccept(bool accept_) external {
        accept = accept_;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        return accept ? bytes4(0x150b7a02) : bytes4(0xdeadbeef);
    }
}
