// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FixedSupplyToken is ERC20 {
    uint8 private immutable tokenDecimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address[] memory recipients,
        uint256[] memory amounts
    ) ERC20(name_, symbol_) {
        tokenDecimals = decimals_;
        for (uint256 index; index < recipients.length; ++index) {
            _mint(recipients[index], amounts[index]);
        }
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
}

contract TokenFactory {
    mapping(address token => bool known) public isToken;

    error InvalidTokenTerms();
    error InvalidAllocation();

    event TokenCreated(
        address indexed creator, address indexed token, string name, string symbol, uint8 decimals, uint256 supply
    );

    function createToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 supply,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (address token) {
        if (
            bytes(name).length == 0 || bytes(name).length > 64 || bytes(symbol).length == 0 || bytes(symbol).length > 12
                || decimals > 36 || supply == 0
        ) revert InvalidTokenTerms();
        if (recipients.length == 0 || recipients.length != amounts.length) revert InvalidAllocation();

        uint256 unallocated = supply;
        for (uint256 index; index < recipients.length; ++index) {
            uint256 amount = amounts[index];
            if (recipients[index] == address(0) || amount == 0 || amount > unallocated) {
                revert InvalidAllocation();
            }
            unallocated -= amount;
        }
        if (unallocated != 0) revert InvalidAllocation();

        token = address(new FixedSupplyToken(name, symbol, decimals, recipients, amounts));
        isToken[token] = true;
        emit TokenCreated(msg.sender, token, name, symbol, decimals, supply);
    }
}
