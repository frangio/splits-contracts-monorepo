// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import { WebAuthn } from "@web-authn/WebAuthn.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

/**
 * @title Multi Signer Library
 * @author Splits
 */
library MultiSignerLib {
    /* -------------------------------------------------------------------------- */
    /*                                   STRUCTS                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Storage layout used by this contract.
    /// @dev Can allow up to 256 signers.
    /// @custom:storage-location erc7201:splits.storage.MultiSigner
    struct MultiSignerStorage {
        uint256 nonce;
        /// @dev Number of unique signatures required to validate a message signed by this contract.
        uint8 threshold;
        /// @dev number of signers
        uint8 signerCount;
        /// @dev signer bytes;
        mapping(uint8 => bytes) signers;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Thrown when a provided signer is neither 64 bytes long (for public key)
     *         nor a ABI encoded address.
     * @param signer The invalid signer.
     */
    error InvalidSignerBytesLength(bytes signer);

    /**
     * @notice Thrown if a provided signer is 32 bytes long but does not fit in an `address` type or if `signer` has
     * code.
     * @param signer The invalid signer.
     */
    error InvalidEthereumAddressOwner(bytes signer);

    /// @notice Thrown when threshold is greater than number of owners or when zero.
    error InvalidThreshold();

    /// @notice Thrown when number of signers is more than 256.
    error InvalidNumberOfSigners();

    /* -------------------------------------------------------------------------- */
    /*                                  FUNCTIONS                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Validates the list of `signers` and `threshold`.
     * @dev Throws error when number of signers is zero or greater than 255.
     * @dev Throws error if `threshold` is zero or greater than number of signers.
     * @param _signers abi encoded list of signers (passkey/eoa).
     * @param _threshold minimum number of signers required for approval.
     */
    function validateSigners(bytes[] calldata _signers, uint8 _threshold) internal view {
        if (_signers.length > 255 || _signers.length == 0) revert InvalidNumberOfSigners();

        uint8 numberOfSigners = uint8(_signers.length);

        if (numberOfSigners < _threshold || _threshold < 1) revert InvalidThreshold();

        bytes memory signer;

        for (uint8 i; i < numberOfSigners; i++) {
            signer = _signers[i];

            validateSigner(signer);
        }
    }

    /**
     * @notice Validates the signer.
     * @dev Throws error when length of signer is neither 32 or 64.
     * @dev Throws error if signer is invalid address or if address has code.
     */
    function validateSigner(bytes memory _signer) internal view {
        if (_signer.length != 32 && _signer.length != 64) {
            revert InvalidSignerBytesLength(_signer);
        }

        if (_signer.length == 32) {
            if (uint256(bytes32(_signer)) > type(uint160).max) revert InvalidEthereumAddressOwner(_signer);
            address eoa;
            assembly ("memory-safe") {
                eoa := mload(add(_signer, 32))
            }

            if (eoa.code.length > 0) revert InvalidEthereumAddressOwner(_signer);
        }
    }

    /**
     * @notice validates if the signature provided by the signer at `signerIndex` is valid for the hash.
     */
    function isValidSignature(
        bytes32 _hash,
        bytes memory _signer,
        bytes memory _signature
    )
        internal
        view
        returns (bool isValid)
    {
        if (_signer.length == 32) {
            isValid = isValidSignatureEOA(_hash, _signer, _signature);
        } else if (_signer.length == 64) {
            isValid = isValidSignaturePasskey(_hash, _signer, _signature);
        }
    }

    function isValidSignaturePasskey(
        bytes32 _hash,
        bytes memory _signer,
        bytes memory _signature
    )
        internal
        view
        returns (bool)
    {
        (uint256 x, uint256 y) = abi.decode(_signer, (uint256, uint256));

        WebAuthn.WebAuthnAuth memory auth = abi.decode(_signature, (WebAuthn.WebAuthnAuth));

        return WebAuthn.verify({ challenge: abi.encode(_hash), requireUV: false, webAuthnAuth: auth, x: x, y: y });
    }

    function isValidSignatureEOA(
        bytes32 _hash,
        bytes memory _signer,
        bytes memory _signature
    )
        internal
        view
        returns (bool)
    {
        address owner;
        assembly ("memory-safe") {
            owner := mload(add(_signer, 32))
        }

        return SignatureCheckerLib.isValidSignatureNow(owner, _hash, _signature);
    }
}
