// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FairLaunch} from "./FairLaunch.sol";
import {SaleSetup, SaleTerms} from "./SaleTypes.sol";

/// @dev Separates Fair Launch creation code from LaunchFactory to fit the EVM code size limit.
contract FairLaunchDeployer {
    address public immutable factory = msg.sender;

    error Unauthorized();

    function deploy(SaleSetup calldata setup, SaleTerms calldata terms) external returns (address sale) {
        if (msg.sender != factory) revert Unauthorized();
        return address(new FairLaunch(setup, terms));
    }
}
