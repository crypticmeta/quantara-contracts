// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IClaimableSale {
    function claimFor(address buyer) external;
    function refundFor(address buyer) external;
}

contract ClaimManager {
    function claim(IClaimableSale sale) external {
        sale.claimFor(msg.sender);
    }

    function refund(IClaimableSale sale) external {
        sale.refundFor(msg.sender);
    }
}
