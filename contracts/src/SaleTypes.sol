// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

enum SaleKind {
    FixedPrice,
    FairLaunchFCFS,
    FairLaunchProRata
}

enum SaleOutcome {
    Pending,
    Successful,
    Failed
}

struct SaleTerms {
    SaleKind kind;
    uint256 inventory;
    uint256 price;
    uint64 start;
    uint64 end;
    uint256 minContribution;
    uint256 maxContribution;
    uint256 softCap;
    uint256 hardCap;
}

struct SaleSetup {
    address token;
    address creator;
    address claimManager;
    uint16 feeBps;
    address feeRecipient;
    uint256 projectId;
    string projectName;
    string description;
}

struct SaleSummary {
    address token;
    address creator;
    uint256 totalRaised;
    uint256 totalAllocated;
    SaleOutcome outcome;
    uint256 createdBlock;
    uint16 feeBps;
    address feeRecipient;
    string projectName;
    string description;
    uint256 projectId;
}
