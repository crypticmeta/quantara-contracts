// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

uint16 constant FEE_BPS_DENOMINATOR = 10_000;

contract FeeController {
    address public immutable feeRecipient;
    uint16 public immutable feeBps;

    error InvalidFeeTerms();

    constructor(address feeRecipient_, uint16 feeBps_) {
        if (feeRecipient_ == address(0) || feeBps_ > FEE_BPS_DENOMINATOR) revert InvalidFeeTerms();
        feeRecipient = feeRecipient_;
        feeBps = feeBps_;
    }
}
