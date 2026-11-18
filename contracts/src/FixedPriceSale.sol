// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Sale} from "./Sale.sol";
import {SaleKind, SaleSetup, SaleTerms} from "./SaleTypes.sol";

contract FixedPriceSale is Sale {
    constructor(SaleSetup memory setup, SaleTerms memory terms) Sale(setup, terms) {
        if (terms.kind != SaleKind.FixedPrice) revert InvalidTerms();
    }
}
