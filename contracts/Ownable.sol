// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

contract Ownable {
    address payable public immutable owner;

    constructor() {
        owner = payable(msg.sender);
    }

    error NotInvokedByOwner();
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotInvokedByOwner();
        _;
    }
}
